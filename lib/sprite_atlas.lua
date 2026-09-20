-- Sprite atlases: serve per-species sprite sheets from a few shard PNGs, under their ORIGINAL paths.
--
-- The release ZIP used to carry ~15,000 tiny sheet PNGs (one per species, style and variant). tools/generate_sprite_atlases.py
-- packs each family into a few single-column shard PNGs plus a JSON index (assets/atlas/index.json, one <family>.json per family),
-- and scripts/build-mod.py --atlas ships those instead of the per-file sheets. This module makes the game unaware of that:
--
--   * install() wraps the engine's central image loader (src.render.Assets: image / imageData / exists), so a request for
--     `mods/<folder>/assets/wilds_generated/true_size/hgss/025-normal.png` is answered from the atlas when the file is not
--     on disk, and every other path falls straight through to the original function. SpriteRenderer, the Voxel mods'
--     SpriteBillboards (both go through Assets.image) and the palette recolor bake (Assets.imageData) are untouched.
--   * A sprite is cut out of its decoded shard into an ordinary small image the first time it is asked for, so the engine
--     still sees one small image per sprite and draws exactly as before. Only the shards holding sprites in use are decoded,
--     kept in a byte-capped LRU.
--   * With no atlas (a repo checkout, or a --no-atlas build) install() does nothing. A family whose real files exist on disk is
--     skipped too ("source mode"), so a stale atlas can never shadow freshly generated sheets during development.
--
-- Not a shared GPU atlas on purpose: SpriteRenderer assumes every sheet starts at x=0 (topHalf / oamRow quads,
-- getFrameGeometry, recolor baking), so drawing from an atlas offset would mean patching engine internals other mods share.
local V = ...

local SpriteAtlas = {}

SpriteAtlas.ROOT_INDEX = "assets/atlas/index.json"
SpriteAtlas.MAX_SHARD_BYTES = 96 * 1024 * 1024 -- decoded shard cache cap (RGBA, w*h*4)

local state

local function newState()
  return {
    mod = nil, deps = nil,
    dirToFamily = {},   -- sprite directory -> family name
    prefixes = {},      -- { prefix, family } for families that own every directory under a prefix
    familyMeta = {},    -- family name -> { index = rel }
    families = {},      -- family name -> loaded index (or false when unusable)
    shards = {},        -- "family#n" -> { data, bytes, tick }
    shardBytes = 0,
    tick = 0,
    images = {},        -- sprite rel -> Image
    stats = { shardDecodes = 0, shardDecodeMs = 0, slices = 0, sliceMs = 0, evictions = 0, hits = 0 },
  }
end

-- ------------------------------------------------------------------ helpers
local function nowMs()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() * 1000 end
  return os.clock() * 1000
end

local function tryRequire(name)
  local ok, m = pcall(require, name)
  if ok then return m end
  return nil
end

local function assetPath(mod, rel)
  if mod and mod.assets and type(mod.assets.path) == "function" then
    local ok, p = pcall(mod.assets.path, mod.assets, rel)
    if ok and type(p) == "string" and p ~= "" then return p end
  end
  if mod and type(mod.path) == "string" and mod.path ~= "" and mod.path ~= "." then
    return mod.path .. "/" .. rel
  end
  return rel
end

local function readMod(rel)
  if not state then return nil end
  local reader = state.deps and state.deps.read
  if reader then
    local ok, data = pcall(reader, rel)
    return ok and data or nil
  end
  local mod = state.mod
  if not mod or type(mod.read) ~= "function" then return nil end
  local ok, data = pcall(mod.read, mod, rel)
  if ok and type(data) == "string" and data ~= "" then return data end
  return nil
end

local function decodeJson(raw)
  local ok, Json = pcall(function() return V.require("json_decode") end)
  if not (ok and Json and type(Json.decode) == "function") then return nil end
  local okDec, value = pcall(Json.decode, raw)
  if okDec and type(value) == "table" then return value end
  return nil
end

--- Repo-relative key (`assets/...`) for a path the engine or our code may use, or nil when it cannot be a mod asset.
local function relOf(path)
  if type(path) ~= "string" or path == "" then return nil end
  local p = (path:gsub("\\", "/"))
  local modPath = state and state.mod and state.mod.path
  if type(modPath) == "string" and modPath ~= "" and modPath ~= "." then
    local prefix = (modPath:gsub("\\", "/")) .. "/"
    if p:sub(1, #prefix) == prefix then return p:sub(#prefix + 1) end
  end
  local rel = p:match("^mods/[^/]+/(assets/.+)$") or p:match("^%./(assets/.+)$")
  if rel then return rel end
  if p:sub(1, 7) == "assets/" then return p end
  return nil
end

-- ------------------------------------------------------------------ index
local function loadFamily(name)
  local fam = state.families[name]
  if fam ~= nil then return fam or nil end
  local meta = state.familyMeta[name]
  local raw = meta and readMod(meta.index)
  local idx = raw and decodeJson(raw) or nil
  if not (idx and type(idx.shards) == "table" and type(idx.dirs) == "table") then
    state.families[name] = false
    return nil
  end
  idx.name = name
  -- Source mode: if a sprite this family covers exists as a real file, the family is not served from the atlas.
  local sourceMode = false
  for dir, files in pairs(idx.dirs) do
    for fname in pairs(files) do
      if readMod(dir .. "/" .. fname) ~= nil then sourceMode = true end
      break
    end
    if sourceMode then break end
  end
  idx.sourceMode = sourceMode
  state.families[name] = idx
  return idx
end

--- The index entry { shard, x, y, w, h } (shard 0-based) for a path, and its family, or nil.
local function lookup(path)
  if not state then return nil end
  local rel = relOf(path)
  if not rel then return nil end
  local dir, fname = rel:match("^(.*)/([^/]+)$")
  if not dir then return nil end
  local famName = state.dirToFamily[dir]
  if not famName then
    for _, p in ipairs(state.prefixes) do
      if dir:sub(1, #p[1]) == p[1] then famName = p[2] break end
    end
  end
  if not famName then return nil end
  local fam = loadFamily(famName)
  if not fam or fam.sourceMode then return nil end
  local entry = fam.dirs[dir] and fam.dirs[dir][fname]
  if type(entry) ~= "table" then return nil end
  return fam, entry, rel
end

-- ------------------------------------------------------------------ shard cache (LRU)
local function evictIfNeeded(keep)
  while state.shardBytes > SpriteAtlas.MAX_SHARD_BYTES do
    local oldestKey, oldest
    for key, sh in pairs(state.shards) do
      if key ~= keep and (not oldest or sh.tick < oldest.tick) then oldestKey, oldest = key, sh end
    end
    if not oldestKey then return end
    state.shards[oldestKey] = nil
    state.shardBytes = state.shardBytes - oldest.bytes
    state.stats.evictions = state.stats.evictions + 1
    if oldest.data and type(oldest.data.release) == "function" then pcall(oldest.data.release, oldest.data) end
  end
end

local function shardData(fam, shardIndex)
  local key = fam.name .. "#" .. tostring(shardIndex)
  state.tick = state.tick + 1
  local sh = state.shards[key]
  if sh then
    sh.tick = state.tick
    return sh.data
  end
  local meta = fam.shards[shardIndex + 1]
  if type(meta) ~= "table" or type(meta.file) ~= "string" then return nil end
  local t0 = nowMs()
  local loader = state.deps.imageData
  local ok, data = pcall(loader, assetPath(state.mod, meta.file))
  if not ok or not data then return nil end
  local ms = nowMs() - t0
  local bytes = (tonumber(meta.w) or 0) * (tonumber(meta.h) or 0) * 4
  state.shards[key] = { data = data, bytes = bytes, tick = state.tick }
  state.shardBytes = state.shardBytes + bytes
  state.stats.shardDecodes = state.stats.shardDecodes + 1
  state.stats.shardDecodeMs = state.stats.shardDecodeMs + ms
  if state.deps.log then
    state.deps.log(("[Atlas] decoded %s (%dx%d) in %.1f ms"):format(meta.file, meta.w or 0, meta.h or 0, ms))
  end
  evictIfNeeded(key)
  return data
end

-- ------------------------------------------------------------------ public reads
--- true when `path` is served from the atlas (indexed, family not in source mode).
function SpriteAtlas.has(path)
  return lookup(path) ~= nil
end

local function sliceData(fam, entry)
  local data = shardData(fam, entry[1])
  if not data then return nil end
  local w, h = entry[4], entry[5]
  local t0 = nowMs()
  local ok, out = pcall(function()
    local id = love.image.newImageData(w, h)
    id:paste(data, 0, 0, entry[2], entry[3], w, h)
    return id
  end)
  if not ok or not out then return nil end
  state.stats.slices = state.stats.slices + 1
  state.stats.sliceMs = state.stats.sliceMs + (nowMs() - t0)
  return out
end

--- Fresh ImageData for an atlased path (a new copy every call: callers such as the recolor bake mutate it), or nil.
function SpriteAtlas.imageData(path)
  local fam, entry = lookup(path)
  if not fam then return nil end
  return sliceData(fam, entry)
end

--- Cached small Image for an atlased path, or nil when the path is not in the atlas.
function SpriteAtlas.image(path)
  local fam, entry, rel = lookup(path)
  if not fam then return nil end
  local img = state.images[rel]
  if img then
    state.stats.hits = state.stats.hits + 1
    return img
  end
  local id = sliceData(fam, entry)
  if not id then return nil end
  local ok, made = pcall(love.graphics.newImage, id)
  if not ok or not made then return nil end
  state.images[rel] = made
  return made
end

--- Counters for debug logs / the dev overlay.
function SpriteAtlas.stats()
  local out = {}
  if not state then return out end
  for k, v in pairs(state.stats) do out[k] = v end
  out.shardBytes = state.shardBytes
  out.cachedShards = 0
  for _ in pairs(state.shards) do out.cachedShards = out.cachedShards + 1 end
  return out
end

--- Drop every cached image and decoded shard (engine hot reload / Assets.invalidate).
function SpriteAtlas.invalidate()
  if not state then return end
  state.images = {}
  state.shards = {}
  state.shardBytes = 0
end

--- Free the GPU images and decoded shards (the engine's session end: Assets.releaseSession), then forget them.
function SpriteAtlas.release()
  if not state then return end
  for _, img in pairs(state.images) do
    if type(img) == "table" and type(img.release) == "function" then pcall(img.release, img) end
  end
  for _, sh in pairs(state.shards) do
    if sh.data and type(sh.data.release) == "function" then pcall(sh.data.release, sh.data) end
  end
  SpriteAtlas.invalidate()
end

function SpriteAtlas.installed()
  return state ~= nil and state.installed == true
end

-- ------------------------------------------------------------------ install
--- Load the index and wrap the engine's Assets loader. Returns true, or false plus a reason (no atlas is a normal
-- "false": the game keeps using the per-file sheets). `deps` = { read, imageData, Assets, log } is injectable for tests.
function SpriteAtlas.install(mod, deps)
  deps = deps or {}
  local previous = state
  state = newState()
  state.mod = mod
  state.deps = deps
  if not deps.imageData then
    deps.imageData = function(path)
      local A = deps.Assets or tryRequire("src.render.Assets")
      -- Prefer the ORIGINAL loader: a shard path is never an atlased sprite, but this keeps the call cheap and recursion-free.
      local orig = A and A._wildsSpriteAtlas and A._wildsSpriteAtlas.imageData or (A and A.imageData)
      if type(orig) == "function" then return orig(path) end
      return love.image.newImageData(path)
    end
  end

  local raw = readMod(SpriteAtlas.ROOT_INDEX)
  if not raw then
    state = previous
    return false, "no atlas index"
  end
  local root = decodeJson(raw)
  if not (root and root.version == 1 and type(root.families) == "table") then
    state = previous
    return false, "unsupported atlas index"
  end
  local any = false
  for name, meta in pairs(root.families) do
    if type(meta) == "table" and type(meta.index) == "string"
       and (type(meta.dirs) == "table" or type(meta.prefixes) == "table") then
      state.familyMeta[name] = { index = meta.index }
      for _, dir in ipairs(meta.dirs or {}) do
        state.dirToFamily[dir] = name
        any = true
      end
      for _, prefix in ipairs(meta.prefixes or {}) do
        if type(prefix) == "string" and prefix ~= "" then
          state.prefixes[#state.prefixes + 1] = { prefix, name }
          any = true
        end
      end
    end
  end
  table.sort(state.prefixes, function(a, b) return #a[1] > #b[1] end) -- longest prefix wins
  if not any then
    state = previous
    return false, "empty atlas index"
  end

  local Assets = deps.Assets or tryRequire("src.render.Assets")
  if not (type(Assets) == "table" and type(Assets.image) == "function") then
    state = previous
    return false, "engine Assets unavailable"
  end

  if not Assets._wildsSpriteAtlas then
    local orig = { image = Assets.image, imageData = Assets.imageData, exists = Assets.exists }
    Assets._wildsSpriteAtlas = orig
    Assets.image = function(path)
      local img = SpriteAtlas.image(path)
      if img then return img end
      return orig.image(path)
    end
    if type(orig.imageData) == "function" then
      Assets.imageData = function(path)
        local id = SpriteAtlas.imageData(path)
        if id then return id end
        return orig.imageData(path)
      end
    end
    if type(orig.exists) == "function" then
      Assets.exists = function(path)
        if SpriteAtlas.has(path) then return true end
        return orig.exists(path)
      end
    end
    if type(Assets.register) == "function" then
      -- The table form also lets the engine free our images at session end (Assets.releaseSession).
      pcall(Assets.register, {
        invalidate = function() SpriteAtlas.invalidate() end,
        release = function() SpriteAtlas.release() end,
      })
    end
  end
  state.installed = true
  return true
end

--- Test / tooling hook: forget everything (does not unwrap the engine functions).
function SpriteAtlas._reset()
  state = nil
end

return SpriteAtlas
