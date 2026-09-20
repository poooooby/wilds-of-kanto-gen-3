-- lib/sprite_atlas.lua: serving per-species sprite sheets from atlas shards under their original paths.
-- Run: lua tests/sprite_atlas_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local modules = {}
local V = { mod = {}, path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

-- ---------------------------------------------------------------- fixtures
local DIR = "assets/wilds_generated/true_size/hgss"
local OTHER_DIR = "assets/wilds_generated/water_runtime/swimming"

local ROOT_INDEX = [[{"version":1,"families":{
  "hgss":{"index":"assets/atlas/hgss.json","dirs":["assets/wilds_generated/true_size/hgss"]},
  "swim":{"index":"assets/atlas/swim.json","dirs":["assets/wilds_generated/water_runtime/swimming"]}}}]]
local HGSS_INDEX = [[{"version":1,"family":"hgss",
  "shards":[{"file":"assets/atlas/hgss_0.png","w":32,"h":300},{"file":"assets/atlas/hgss_1.png","w":32,"h":200}],
  "dirs":{"assets/wilds_generated/true_size/hgss":{
    "001-normal.png":[0,0,0,32,100],"001-shiny.png":[0,0,100,32,100],"002-normal.png":[0,0,200,20,100],
    "003-normal.png":[1,0,0,32,200]}}}]]
local SWIM_INDEX = [[{"version":1,"family":"swim",
  "shards":[{"file":"assets/atlas/swim_0.png","w":16,"h":96}],
  "dirs":{"assets/wilds_generated/water_runtime/swimming":{"001-normal.png":[0,0,0,16,96]}}}]]

local files, decodes, released, pastes, newImages = {}, {}, {}, {}, 0
local love_ = nil

local function resetWorld()
  files = {
    ["assets/atlas/index.json"] = ROOT_INDEX,
    ["assets/atlas/hgss.json"] = HGSS_INDEX,
    ["assets/atlas/swim.json"] = SWIM_INDEX,
  }
  decodes, released, pastes, newImages = {}, {}, {}, 0
  love = {
    image = {
      newImageData = function(w, h)
        local id = { w = w, h = h }
        function id:paste(src, dx, dy, sx, sy, sw, sh)
          pastes[#pastes + 1] = { from = src.tag, dx = dx, dy = dy, sx = sx, sy = sy, sw = sw, sh = sh }
        end
        return id
      end,
    },
    graphics = { newImage = function(id) newImages = newImages + 1; return { image = true, data = id } end },
  }
end

local function newAssets()
  local calls = { image = {}, imageData = {}, exists = {}, registered = 0 }
  local A = {
    image = function(path) calls.image[#calls.image + 1] = path; return { real = path } end,
    imageData = function(path) calls.imageData[#calls.imageData + 1] = path; return { realData = path } end,
    exists = function(path) calls.exists[#calls.exists + 1] = path; return false end,
    register = function(hooks)
      calls.registered = calls.registered + 1
      calls.hooks = hooks
      calls.invalidator = type(hooks) == "table" and hooks.invalidate or hooks
    end,
  }
  return A, calls
end

local function shardLoader(path)
  decodes[#decodes + 1] = path
  return { tag = path, release = function() released[#released + 1] = path end }
end

local Atlas
local function fresh(opts)
  opts = opts or {}
  resetWorld()
  modules.sprite_atlas = nil
  Atlas = V.require("sprite_atlas")
  Atlas._reset()
  if opts.maxBytes then Atlas.MAX_SHARD_BYTES = opts.maxBytes end
  local A, calls = newAssets()
  local mod = { path = "mods/wilds_of_kanto_gen3" }
  local ok, why = Atlas.install(mod, {
    read = function(rel) return files[rel] end,
    imageData = shardLoader,
    Assets = A,
  })
  return A, calls, ok, why
end

local P = "mods/wilds_of_kanto_gen3/" .. DIR

-- ---------------------------------------------------------------- install
do
  resetWorld()
  files = {}
  modules.sprite_atlas = nil
  Atlas = V.require("sprite_atlas"); Atlas._reset()
  local A, calls = newAssets()
  local origImage = A.image
  local ok, why = Atlas.install({ path = "mods/x" }, { read = function(rel) return files[rel] end, Assets = A })
  eq(ok, false, "install: no atlas index -> false")
  eq(why, "no atlas index", "install: reason")
  check(A.image == origImage, "install: engine Assets untouched without an atlas")
  eq(Atlas.installed(), false, "install: not installed")
  check(Atlas.has(P .. "/001-normal.png") == false, "has: false without an atlas")
  check(Atlas.image(P .. "/001-normal.png") == nil, "image: nil without an atlas")
end

do
  resetWorld()
  files["assets/atlas/index.json"] = "{ not json"
  modules.sprite_atlas = nil
  Atlas = V.require("sprite_atlas"); Atlas._reset()
  local A = newAssets()
  local ok = Atlas.install({ path = "mods/x" }, { read = function(rel) return files[rel] end, Assets = A })
  eq(ok, false, "install: corrupt index -> false")
  files["assets/atlas/index.json"] = '{"version":2,"families":{}}'
  ok = Atlas.install({ path = "mods/x" }, { read = function(rel) return files[rel] end, Assets = A })
  eq(ok, false, "install: unsupported version -> false")
  files["assets/atlas/index.json"] = '{"version":1,"families":{}}'
  ok = Atlas.install({ path = "mods/x" }, { read = function(rel) return files[rel] end, Assets = A })
  eq(ok, false, "install: no families -> false")
end

do
  local A, calls, ok = fresh()
  eq(ok, true, "install: ok with an index")
  eq(Atlas.installed(), true, "install: installed")
  eq(calls.registered, 1, "install: registers an Assets invalidator")
  local wrapped = A.image
  local ok2 = Atlas.install({ path = "mods/wilds_of_kanto_gen3" }, {
    read = function(rel) return files[rel] end, imageData = shardLoader, Assets = A,
  })
  eq(ok2, true, "install: second call ok")
  check(A.image == wrapped, "install: idempotent (Assets not wrapped twice)")
  eq(calls.registered, 1, "install: invalidator registered once")
end

-- ---------------------------------------------------------------- path mapping / exists
do
  local A, calls = fresh()
  local rels = {
    P .. "/001-normal.png",                      -- mods/<folder>/assets/...
    DIR .. "/001-normal.png",                    -- bare assets/...
    "./" .. DIR .. "/001-normal.png",
    ((P .. "/001-normal.png"):gsub("/", "\\")),  -- backslashes
  }
  for _, path in ipairs(rels) do
    check(A.exists(path) == true, "exists: served from the atlas (" .. path .. ")")
  end
  check(A.exists("mods/other_mod/" .. DIR .. "/001-normal.png") == true, "exists: any mods/<folder>/ prefix maps to the key")
  eq(#calls.exists, 0, "exists: atlas hits never reach the engine")
  eq(A.exists(P .. "/999-normal.png"), false, "exists: an unindexed sprite falls through")
  eq(#calls.exists, 1, "exists: the fall-through reached the original")
  eq(A.exists("assets/other/thing.png"), false, "exists: an unrelated path falls through")
  eq(A.exists(nil), false, "exists: nil path is safe")
  check(Atlas.has(P .. "/001-normal.png") and not Atlas.has(P .. "/999-normal.png"), "has: hit and miss")
  check(not Atlas.has("assets/atlas/hgss_0.png"), "has: shard files themselves are not sprites")
end

-- ---------------------------------------------------------------- image serving
do
  local A, calls = fresh()
  local img = A.image(P .. "/001-normal.png")
  check(img and img.image == true, "image: an atlased path returns a new Image")
  eq(#calls.image, 0, "image: the engine loader is not called for an atlased sprite")
  eq(newImages, 1, "image: one Image created")
  eq(#decodes, 1, "image: the shard is decoded once")
  eq(decodes[1], "mods/wilds_of_kanto_gen3/assets/atlas/hgss_0.png", "image: shard path resolved under the mod")
  eq(#pastes, 1, "image: one slice")
  eq(pastes[1].sx, 0, "slice: x")
  eq(pastes[1].sy, 0, "slice: y")
  eq(pastes[1].sw, 32, "slice: width")
  eq(pastes[1].sh, 100, "slice: height")
  eq(img.data.w, 32, "slice: image data is sprite-sized (w)")
  eq(img.data.h, 100, "slice: image data is sprite-sized (h)")

  local again = A.image(P .. "/001-normal.png")
  check(again == img, "image: cached (same object on the second request)")
  eq(newImages, 1, "image: no second Image")
  eq(#pastes, 1, "image: no second slice")

  local shiny = A.image(P .. "/001-shiny.png")
  check(shiny ~= img and shiny.image == true, "image: a second sprite from the same shard")
  eq(#decodes, 1, "image: same shard is not decoded again")
  eq(pastes[2].sy, 100, "slice: second sprite's y offset")
  local narrow = A.image(P .. "/002-normal.png")
  eq(narrow.data.w, 20, "slice: sprites narrower than the shard keep their own width")
  eq(pastes[3].sy, 200, "slice: third sprite's y offset")

  local other = A.image(P .. "/003-normal.png")
  check(other and other.image == true, "image: a sprite in the next shard")
  eq(#decodes, 2, "image: the next shard decodes on demand")
  eq(decodes[2], "mods/wilds_of_kanto_gen3/assets/atlas/hgss_1.png", "image: next shard path")

  local miss = A.image("assets/not/atlased.png")
  eq(miss.real, "assets/not/atlased.png", "image: a non-atlas path falls through with the same argument")
  eq(#calls.image, 1, "image: fall-through reached the engine loader")
  local st = Atlas.stats()
  eq(st.shardDecodes, 2, "stats: shard decodes")
  eq(st.slices, 4, "stats: slices")
  eq(st.cachedShards, 2, "stats: cached shards")
  eq(st.hits, 1, "stats: cache hits")
end

-- ---------------------------------------------------------------- imageData copies
do
  local A, calls = fresh()
  local a = A.imageData(P .. "/001-normal.png")
  local b = A.imageData(P .. "/001-normal.png")
  check(a ~= b, "imageData: a fresh copy every call (callers mutate it)")
  eq(a.w, 32, "imageData: sprite sized")
  eq(#pastes, 2, "imageData: two slices")
  eq(#decodes, 1, "imageData: one shard decode")
  eq(#calls.imageData, 0, "imageData: atlas hits never reach the engine")
  local real = A.imageData("assets/not/atlased.png")
  eq(real.realData, "assets/not/atlased.png", "imageData: a non-atlas path falls through")
end

-- ---------------------------------------------------------------- separate families
do
  local A = fresh()
  local swim = A.image("assets/wilds_generated/water_runtime/swimming/001-normal.png")
  check(swim and swim.image == true, "families: a second family is served too")
  eq(decodes[#decodes], "mods/wilds_of_kanto_gen3/assets/atlas/swim_0.png", "families: its own shard")
end

-- ---------------------------------------------------------------- source mode (real files present)
do
  resetWorld()
  for _, n in ipairs({ "001-normal", "001-shiny", "002-normal", "003-normal" }) do
    files[DIR .. "/" .. n .. ".png"] = "real png bytes"
  end
  modules.sprite_atlas = nil
  Atlas = V.require("sprite_atlas"); Atlas._reset()
  local A, calls = newAssets()
  Atlas.install({ path = "mods/wilds_of_kanto_gen3" }, {
    read = function(rel) return files[rel] end, imageData = shardLoader, Assets = A,
  })
  check(not Atlas.has(P .. "/001-normal.png"), "source mode: a family whose files exist on disk is not served from the atlas")
  local img = A.image(P .. "/001-normal.png")
  eq(img.real, P .. "/001-normal.png", "source mode: the engine loads the real file")
  eq(#decodes, 0, "source mode: no shard is decoded")
  check(Atlas.has("assets/wilds_generated/water_runtime/swimming/001-normal.png"), "source mode: other families are unaffected")
end

-- ---------------------------------------------------------------- corrupt family index
do
  local A, calls = fresh()
  files["assets/atlas/hgss.json"] = "not json at all"
  Atlas.invalidate()
  -- the family index is read lazily, so corrupt it before first use in a fresh install
  A, calls = fresh()
  files["assets/atlas/hgss.json"] = "not json at all"
  check(not Atlas.has(P .. "/001-normal.png"), "corrupt family index: nothing is served")
  local img = A.image(P .. "/001-normal.png")
  eq(img.real, P .. "/001-normal.png", "corrupt family index: falls through to the engine")
  local ok = pcall(A.exists, P .. "/001-normal.png")
  check(ok, "corrupt family index: exists() does not throw")
end

-- ---------------------------------------------------------------- shard LRU
do
  -- hgss shards are 32x300 and 32x200 RGBA = 38,400 and 25,600 bytes
  local A = fresh({ maxBytes = 40000 })
  A.image(P .. "/001-normal.png")            -- shard 0 (38,400)
  eq(#released, 0, "lru: nothing evicted yet")
  A.image(P .. "/003-normal.png")            -- shard 1 (25,600) -> over the cap, shard 0 goes
  eq(#released, 1, "lru: the least recently used shard is released")
  eq(released[1], "mods/wilds_of_kanto_gen3/assets/atlas/hgss_0.png", "lru: it was shard 0")
  eq(Atlas.stats().evictions, 1, "lru: eviction counted")
  A.image(P .. "/001-shiny.png")             -- shard 0 again: decoded again, shard 1 goes
  eq(#decodes, 3, "lru: an evicted shard decodes again on demand")
  check(A.image(P .. "/001-normal.png") ~= nil, "lru: cached small Images survive shard eviction")
  eq(#decodes, 3, "lru: cached Images need no shard")
end

-- ---------------------------------------------------------------- release (engine session end)
do
  local A, calls = fresh()
  local img = A.image(P .. "/001-normal.png")
  local freed = 0
  function img.release() freed = freed + 1 end
  check(type(calls.hooks) == "table" and type(calls.hooks.release) == "function", "release: registered as an Assets release hook")
  calls.hooks.release()
  eq(freed, 1, "release: cached Images are released")
  eq(#released, 1, "release: decoded shards are released")
  eq(Atlas.stats().cachedShards, 0, "release: nothing stays cached")
  check(A.image(P .. "/001-normal.png") ~= img, "release: later requests rebuild from the atlas")
end

-- ---------------------------------------------------------------- invalidate
do
  local A, calls = fresh()
  local first = A.image(P .. "/001-normal.png")
  calls.invalidator()
  local second = A.image(P .. "/001-normal.png")
  check(first ~= second, "invalidate: the Assets invalidator drops cached images")
  eq(#decodes, 2, "invalidate: and decoded shards")
end

-- ---------------------------------------------------------------- prefix families (PMD portraits)
do
  resetWorld()
  local PMD = "assets/pmdcollab/portraits"
  files["assets/atlas/index.json"] = [[{"version":1,"families":{
    "pmd":{"index":"assets/atlas/pmd.json","dirs":[],"prefixes":["assets/pmdcollab/portraits/"]},
    "hgss":{"index":"assets/atlas/hgss.json","dirs":["assets/wilds_generated/true_size/hgss"]}}}]]
  files["assets/atlas/pmd.json"] = [[{"version":1,"family":"pmd",
    "shards":[{"file":"assets/atlas/pmd_0.png","w":40,"h":120}],
    "dirs":{"assets/pmdcollab/portraits/001/normal":{"happy.png":[0,0,0,40,40],"normal.png":[0,0,40,40,40]},
            "assets/pmdcollab/portraits/001/shiny":{"normal.png":[0,0,80,40,40]}}}]]
  modules.sprite_atlas = nil
  Atlas = V.require("sprite_atlas"); Atlas._reset()
  local A, calls = newAssets()
  local ok = Atlas.install({ path = "mods/wilds_of_kanto_gen3" }, {
    read = function(rel) return files[rel] end, imageData = shardLoader, Assets = A,
  })
  eq(ok, true, "prefix family: install ok with a dirs-less family")
  local base = "mods/wilds_of_kanto_gen3/" .. PMD
  check(A.exists(base .. "/001/normal/happy.png") == true, "prefix family: a portrait under the prefix is served")
  check(Atlas.has(PMD .. "/001/shiny/normal.png"), "prefix family: nested <dex>/<variant>/ directories resolve")
  local img = A.image(base .. "/001/normal/normal.png")
  check(img and img.image == true, "prefix family: image() returns a sliced Image")
  eq(pastes[1].sy, 40, "prefix family: slice y offset")
  eq(pastes[1].sw, 40, "prefix family: slice width")
  eq(pastes[1].sh, 40, "prefix family: slice height")
  eq(decodes[1], "mods/wilds_of_kanto_gen3/assets/atlas/pmd_0.png", "prefix family: shard path")
  A.image(base .. "/001/shiny/normal.png")
  eq(#decodes, 1, "prefix family: portraits of one species share a shard decode")
  eq(A.exists(base .. "/001/normal/angry.png"), false, "prefix family: an unindexed file under the prefix falls through")
  eq(A.exists(base .. "/999/normal/happy.png"), false, "prefix family: an unindexed directory under the prefix falls through")
  eq(A.exists("mods/wilds_of_kanto_gen3/assets/pmdcollab/other/x.png"), false, "prefix family: outside the prefix falls through")
  eq(A.exists("mods/wilds_of_kanto_gen3/assets/pmdcollab/CREDITS.txt"), false, "prefix family: sibling files are not portraits")
  check(A.exists("mods/wilds_of_kanto_gen3/" .. DIR .. "/001-normal.png") == true, "prefix family: an exact-dir family still works beside it")
end

do
  -- source mode also applies to prefix families
  resetWorld()
  files["assets/atlas/index.json"] = [[{"version":1,"families":{
    "pmd":{"index":"assets/atlas/pmd.json","dirs":[],"prefixes":["assets/pmdcollab/portraits/"]}}}]]
  files["assets/atlas/pmd.json"] = [[{"version":1,"family":"pmd",
    "shards":[{"file":"assets/atlas/pmd_0.png","w":40,"h":40}],
    "dirs":{"assets/pmdcollab/portraits/001/normal":{"happy.png":[0,0,0,40,40]}}}]]
  files["assets/pmdcollab/portraits/001/normal/happy.png"] = "real png bytes"
  modules.sprite_atlas = nil
  Atlas = V.require("sprite_atlas"); Atlas._reset()
  local A = newAssets()
  Atlas.install({ path = "mods/wilds_of_kanto_gen3" }, {
    read = function(rel) return files[rel] end, imageData = shardLoader, Assets = A,
  })
  check(not Atlas.has("assets/pmdcollab/portraits/001/normal/happy.png"), "prefix family: real files on disk win (source mode)")
end

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
