-- In-memory compatibility adapter: Battle Art Gen2 Voxel SpriteBillboards.mesh
-- consumes Wilds / Gen1Recomp variable SpriteDef geometry.
--
-- Battle Art Gen2 ships under a genuinely separate mod id from the Gen1 fork
-- (BATTLE_ART_VOXEL_FORK, see lib/compat/battle_art_variable_geometry.lua) —
-- own manifest.json id, same exports.lib.require("SpriteBillboards") contract,
-- but a real behavioral difference: Gen2 added SpriteBillboards.halfWidth(def)
-- (def.frameWidth/2, or 16 for "big doll" sheets like Snorlax/Lapras) so its
-- own world-space mirror/placement (billboardMatrix/casterMatrix in its
-- VoxelScene.lua) centres non-16-wide sheets correctly. The Gen1 fork has no
-- such function and always assumes a fixed 8. Keeping Gen1 and Gen2 as
-- separate files (rather than one adapter branching on which fork is active)
-- means each file only ever has to be correct for the ONE contract it targets.
--
-- Wilds does NOT copy VoxelScene, shaders, camera, or mesher code.
-- Vanilla 16×16 defs call the original mesh() unchanged.
local V = ...
local DebugLog = V.require("debug_log")

local Adapter = {}

Adapter.BATTLE_ART_GEN2_ID = "BATTLE_ART_VOXEL_GEN2"
Adapter.FAIL_LOG =
  "Battle Art Gen2 variable sprite adapter unavailable; using Classic Voxel geometry."

local INSET_U = 0.02
local INSET_V = 0.05
-- Fallback pivot only for a def SpriteBillboards.halfWidth cannot resolve
-- (missing frameWidth) or before install (no wrapped table yet) -- matches
-- Gen2's own halfWidth() fallback of 8. See Adapter.mirrorPivotX.
local PIVOT_X = 8

local _state = "idle" -- idle | installed | native | failed | absent
local _reason = nil
local _loggedFail = false
local _origMesh = nil
local _origInvalidate = nil
local _origHalfWidth = nil
local _varMeshes = {}
local _wrappedTable = nil
local _Voxel3D = nil
local _Assets = nil

local function logFail(mod, why)
  if _loggedFail then return end
  _loggedFail = true
  local msg = Adapter.FAIL_LOG
  if why and why ~= "" then
    msg = msg .. " (" .. tostring(why) .. ")"
  end
  if DebugLog and DebugLog.warn then
    DebugLog.warn(mod, "%s", msg)
  elseif mod and mod.log and mod.log.warn then
    mod.log:warn("[WildsOfKanto][WARN] %s", msg)
  end
end

local function logOk(mod, detail)
  if DebugLog and DebugLog.info then
    DebugLog.info(mod, "Battle Art Gen2 variable sprite adapter installed (%s)",
      tostring(detail or "mesh wrap"))
  end
end

function Adapter.findBattleArt(mod)
  if not mod or type(mod.find) ~= "function" then return nil end
  local ok, hit = pcall(mod.find, mod, Adapter.BATTLE_ART_GEN2_ID)
  if ok and hit then return hit end
  return nil
end

function Adapter.reset()
  if _wrappedTable and _origMesh then
    _wrappedTable.mesh = _origMesh
    _wrappedTable.shadowQuad = _origMesh
    if _origInvalidate then
      _wrappedTable.invalidate = _origInvalidate
    end
    if _origHalfWidth then
      _wrappedTable.halfWidth = _origHalfWidth
    end
    _wrappedTable._wildsVariableGeometryWrapped = nil
  end
  _state = "idle"
  _reason = nil
  _loggedFail = false
  _origMesh = nil
  _origInvalidate = nil
  _origHalfWidth = nil
  _varMeshes = {}
  _wrappedTable = nil
  _Voxel3D = nil
  _Assets = nil
end

function Adapter.isInstalled()
  return _state == "installed" or _state == "native"
end

function Adapter.isSupported()
  return Adapter.isInstalled()
end

function Adapter.supportsVariableGeometry()
  return _state == "installed" or _state == "native"
end

function Adapter.supportReason()
  return _reason
end

function Adapter.state()
  return _state
end

--- True when the def needs a non-16×16 card (or a non-default anchor).
function Adapter.needsVariableGeometry(def)
  if type(def) ~= "table" then return false end
  local fw = tonumber(def.frameWidth)
  local fh = tonumber(def.frameHeight)
  local ax = tonumber(def.anchorX)
  local ay = tonumber(def.anchorY)
  local dw = tonumber(def.displayWidth)
  local dh = tonumber(def.displayHeight)
  local dax = tonumber(def.displayAnchorX)
  local day = tonumber(def.displayAnchorY)
  if fw == nil and fh == nil and ax == nil and ay == nil
      and dw == nil and dh == nil and dax == nil and day == nil then
    return false
  end
  fw = fw or 16
  fh = fh or 16
  if ax == nil then ax = fw / 2 end
  if ay == nil then ay = fh end
  dw = dw or fw
  dh = dh or fh
  if dax == nil then dax = dw / 2 end
  if day == nil then day = dh end
  if fw == 16 and fh == 16 and ax == 8 and ay == 16
      and dw == 16 and dh == 16 and dax == 8 and day == 16 then
    return false
  end
  return fw > 0 and fh > 0 and dw > 0 and dh > 0
end

-- displayWidth/displayHeight/displayAnchorX/displayAnchorY let a caller
-- request a billboard quad SMALLER or LARGER than the real frameWidth/
-- frameHeight/anchorX/anchorY, defaulting to the real values so every
-- existing caller is unaffected unless it sets them. uvRect always slices
-- the texture from the real frameWidth/frameHeight, so every source pixel
-- is still sampled at native resolution — no resampling of the underlying
-- image. Mirrors lib/compat/voxel_sprite_billboards_adapter.lua's
-- resolveGeometry (Battle Art predates and is not routed through that
-- shared factory, so it needs the same decoupling applied separately here).
function Adapter.resolveGeometry(def)
  local fw = tonumber(def.frameWidth) or 16
  local fh = tonumber(def.frameHeight) or 16
  local ax = tonumber(def.anchorX)
  local ay = tonumber(def.anchorY)
  if ax == nil then ax = fw / 2 end
  if ay == nil then ay = fh end
  local dw = tonumber(def.displayWidth) or fw
  local dh = tonumber(def.displayHeight) or fh
  local dax = tonumber(def.displayAnchorX)
  local day = tonumber(def.displayAnchorY)
  local hasDisplay = def.displayWidth ~= nil or def.displayHeight ~= nil
    or def.displayAnchorX ~= nil or def.displayAnchorY ~= nil
  if hasDisplay then
    -- Quantize SIZE only (never a separately-computed anchor) to whole
    -- pixels: a fractional quad extent makes the rasterizer sample a
    -- different pixel column per frame, which looks like the card
    -- pinching or stretching across the walk cycle. Only when a display
    -- override is actually set — otherwise this would round every plain
    -- (no override) real size too, for every caller that never opted in.
    dw = math.floor(dw + 0.5)
    dh = math.floor(dh + 0.5)
  end
  -- Default anchor: derive from the (already-quantized) display size as an
  -- exact proportion of the real anchor, rather than independently
  -- rounding a separately-computed anchor value. Two things break
  -- otherwise: (1) most species have ay == fh (anchor flush with the frame
  -- bottom) — but a species with real transparent padding below its feet
  -- (e.g. Onix: anchorY=36, frameHeight=38) needs that same 2px gap
  -- preserved at the display size, or its ground contact point shifts and
  -- it visibly floats/sinks. (2) for a centered real anchor (ax == fw/2,
  -- true for most species on X), deriving dax from the quantized dw
  -- guarantees dax == dw/2 exactly, however dw rounds — independently
  -- rounding dax can land it off-center by up to half a pixel when dw
  -- quantizes to an odd number, and since facing left/right mirrors the
  -- quad around the pivot, an off-center quad shifts one way when
  -- mirrored and the other way when not: too close facing one direction,
  -- too far facing the other. A fractional result here (e.g. dax = 10.5)
  -- is fine — a stable fractional offset never causes jitter, only a
  -- per-frame *varying* one does, which the dw/dh quantization prevents.
  if dax == nil then
    dax = (fw ~= 0) and (ax * (dw / fw)) or (dw / 2)
  elseif hasDisplay then
    dax = math.floor(dax + 0.5)
  end
  if day == nil then
    day = (fh ~= 0) and (ay * (dh / fh)) or dh
  elseif hasDisplay then
    day = math.floor(day + 0.5)
  end
  return fw, fh, ax, ay, dw, dh, dax, day
end

function Adapter.cacheKey(def, frame, fw, fh, ax, ay, dw, dh, dax, day)
  return table.concat({
    tostring(def.image),
    tostring(frame or 0),
    tostring(fw),
    tostring(fh),
    tostring(ax),
    tostring(ay),
    tostring(dw),
    tostring(dh),
    tostring(dax),
    tostring(day),
  }, "#")
end

--- The X pivot Battle Art Gen2's OWN world-space placement (billboardMatrix /
--- casterMatrix in its VoxelScene.lua) will mirror and translate around for
--- this def: querying it live (rather than re-deriving fw/2 ourselves)
--- guarantees we always mirror around EXACTLY the pivot Battle Art itself
--- will use. The table's halfWidth is OUR OWN wrappedHalfWidth once
--- installed (see wrapBillboards) -- Gen2's native halfWidth(def) =
--- def.frameWidth/2 is designed for genuine multi-cell "big doll" sprites
--- (Snorlax/Lapras) where art width IS footprint width, and wrongly applies
--- the same rule to any def with a non-nil frameWidth -- including Wilds'
--- True Size sprites, which are always single-cell footprint (visual only)
--- regardless of how wide their art is (Onix's real frameWidth is 35, but
--- it still occupies exactly one cell). Using the native, un-wrapped
--- def.frameWidth/2 for those made mirrored and unmirrored placement
--- internally CONSISTENT with each other, but consistently centered on the
--- sprite's own ART width instead of its CELL -- fixing the direction-
--- dependent jump while introducing a direction-INDEPENDENT offset in both
--- cases (confirmed live: switching to a fixed PIVOT_X=8 quad, still using
--- Gen2's unwrapped native halfWidth for placement, fixed the down/up case
--- but left/right remained wrong -- the number that matters for placement
--- is Gen2's own halfWidth(def), not anything our quad alone can control).
function Adapter.mirrorPivotX(def)
  if _wrappedTable and type(_wrappedTable.halfWidth) == "function" then
    local ok, half = pcall(_wrappedTable.halfWidth, def)
    if ok and type(half) == "number" then
      return half
    end
  end
  return PIVOT_X
end

--- Local-space quad that lands the SpriteDef anchor on Battle Art's mirror
--- pivot (see Adapter.mirrorPivotX). Returns x0,y0,x1,y1 (bottom-left /
--- top-right in Y-up mesh space).
function Adapter.localQuad(fw, fh, ax, ay, pivotX)
  local x0 = (pivotX or PIVOT_X) - ax
  local x1 = x0 + fw
  -- 2D anchorY is measured down from the top of the frame. Mesh Y is up
  -- from the feet pivot: top = anchorY, bottom = anchorY - frameHeight.
  local y0 = ay - fh
  local y1 = ay
  return x0, y0, x1, y1
end

function Adapter.uvRect(fw, fh, frame, iw, ih)
  local fy = (tonumber(frame) or 0) * fh
  if fy + fh > ih then
    return nil, "frame_overflow"
  end
  local u0 = INSET_U / iw
  local u1 = (fw - INSET_U) / iw
  local v0 = (fy + INSET_V) / ih
  local v1 = (fy + fh - INSET_V) / ih
  return u0, v0, u1, v1, fy
end

local function sourceLooksNative(src)
  if type(src) ~= "string" or src == "" then return false end
  local usesGeometry = src:find("getPoseGeometry", 1, true)
    or src:find("getFrameGeometry", 1, true)
    or src:find("frameWidth", 1, true)
  local fixed16 = src:find("frame %*% 16", 1)
    or src:find("frame * 16", 1, true)
    or src:find("{ 16, 16, 0", 1, true)
  return usesGeometry and not fixed16
end

local function battleArtIsNative(ds)
  if ds.exports and (ds.exports.variableSpriteGeometry == true
      or ds.exports.supportsVariableSizeSprites == true
      or ds.exports.supportsVariableSpriteGeometry == true) then
    return true, "exports_flag"
  end
  if type(ds.read) == "function" then
    local ok, data = pcall(ds.read, ds, "lib/SpriteBillboards.lua")
    if ok and sourceLooksNative(data) then
      return true, "sprite_billboards_geometry_api"
    end
  end
  return false, nil
end

local function getImageSize(imagePath)
  if _Assets and type(_Assets.image) == "function" then
    local ok, img = pcall(_Assets.image, imagePath)
    if ok and img and type(img.getDimensions) == "function" then
      return img:getDimensions()
    end
  end
  return nil, nil
end

local function buildVariableCard(def, frame)
  local fw, fh, ax, ay, dw, dh, dax, day = Adapter.resolveGeometry(def)
  local iw, ih = getImageSize(def.image)
  if not iw or not ih or iw <= 0 or ih <= 0 then
    return nil, "image_unavailable"
  end
  local u0, v0, u1, v1, _fy = Adapter.uvRect(fw, fh, frame, iw, ih)
  if not u0 then
    return nil, v0 or "frame_overflow"
  end
  local pivotX = Adapter.mirrorPivotX(def)
  local x0, y0, x1, y1 = Adapter.localQuad(dw, dh, dax, day, pivotX)
  local verts = {
    { x0, y0, 0, u0, v1, 1 }, { x1, y0, 0, u1, v1, 1 },
    { x1, y1, 0, u1, v0, 1 }, { x0, y1, 0, u0, v0, 1 },
  }
  local indices = {}
  _Voxel3D.pushQuad(indices, 0)
  local mesh = _Voxel3D.newMesh(verts, indices)
  if not mesh then
    return nil, "newMesh_nil"
  end
  return mesh
end

local function wrappedMesh(def, frame)
  if type(def) ~= "table" or type(def.image) ~= "string" then
    return _origMesh(def, frame)
  end
  if not Adapter.needsVariableGeometry(def) then
    return _origMesh(def, frame)
  end
  local fw, fh, ax, ay, dw, dh, dax, day = Adapter.resolveGeometry(def)
  local key = Adapter.cacheKey(def, frame, fw, fh, ax, ay, dw, dh, dax, day)
  if _varMeshes[key] == nil then
    local ok, meshOrErr = pcall(buildVariableCard, def, frame)
    if ok and meshOrErr then
      _varMeshes[key] = meshOrErr
    else
      _varMeshes[key] = false
    end
  end
  if _varMeshes[key] then
    return _varMeshes[key]
  end
  return _origMesh(def, frame)
end

local function wrappedInvalidate()
  _varMeshes = {}
  if _origInvalidate then
    return _origInvalidate()
  end
end

-- Mirrors Gen2's own SpriteBillboards.lua isBigDef(def) EXACTLY (def.big, or
-- one of its three hardcoded big-doll ids) -- deliberately NOT inferred from
-- what the native halfWidth happens to numerically return. A real single-
-- cell species can have frameWidth==32 (Charizard does), which makes
-- native halfWidth(def) return 16 via the ORDINARY frameWidth/2 branch, the
-- exact same number isBigDef's dedicated branch also returns for a genuine
-- big doll -- two different code paths landing on one shared number. Only
-- checking the def's own fields (as Gen2 itself does) tells them apart;
-- checking the OUTPUT cannot, and previously misclassified Charizard as a
-- big doll purely because 32/2 happens to equal 16.
local function looksLikeBigDoll(def)
  if not def then return false end
  if def.big then return true end
  local id = def.id or ""
  return id == "SPRITE_BIG_SNORLAX"
    or id == "SPRITE_BIG_LAPRAS"
    or id == "SPRITE_BIG_DOLL"
end

-- Gen2's own halfWidth(def) = def.frameWidth/2 for ANY def with a non-nil
-- frameWidth, assuming that means a multi-cell "big doll" sprite (art width
-- == footprint width). That's wrong for Wilds' True Size sprites, which
-- always keep a single-cell footprint no matter how wide their art is
-- (Onix: frameWidth=35, Charizard: frameWidth=32, both still one cell).
-- Defer to the native answer for defs we don't manage AND for genuine big
-- dolls (looksLikeBigDoll) -- only override for OUR OWN single-cell
-- variable-geometry defs, where the correct placement pivot is the vanilla
-- single-cell constant, not half the art width.
local function wrappedHalfWidth(def)
  if looksLikeBigDoll(def) then
    return (_origHalfWidth and _origHalfWidth(def)) or 16
  end
  if Adapter.needsVariableGeometry(def) then
    return PIVOT_X
  end
  return (_origHalfWidth and _origHalfWidth(def)) or PIVOT_X
end

local function wrapBillboards(SpriteBillboards, Voxel3D, Assets)
  if SpriteBillboards._wildsVariableGeometryWrapped then
    return true, "already_wrapped"
  end
  if type(SpriteBillboards.mesh) ~= "function" then
    return false, "SpriteBillboards.mesh missing"
  end
  if not Voxel3D or type(Voxel3D.newMesh) ~= "function"
      or type(Voxel3D.pushQuad) ~= "function" then
    return false, "Voxel3D.newMesh/pushQuad missing"
  end
  _origMesh = SpriteBillboards.mesh
  _origInvalidate = SpriteBillboards.invalidate
  _origHalfWidth = SpriteBillboards.halfWidth
  _Voxel3D = Voxel3D
  _Assets = Assets
  _varMeshes = {}
  _wrappedTable = SpriteBillboards
  SpriteBillboards.mesh = wrappedMesh
  -- shadowQuad is assigned as an alias at Battle Art load time; re-point it
  -- so solid / shadow / occlusion silhouette share the same geometry.
  SpriteBillboards.shadowQuad = wrappedMesh
  SpriteBillboards.invalidate = wrappedInvalidate
  if type(_origHalfWidth) == "function" then
    -- Same table VoxelScene's drawEntity/drawShadow/drawGhost read
    -- halfWidth from -- this is what actually makes Battle Art's OWN
    -- placement matrix agree with our quad, not just our quad agree with
    -- itself. See Adapter.mirrorPivotX / wrappedHalfWidth for why.
    SpriteBillboards.halfWidth = wrappedHalfWidth
  end
  SpriteBillboards._wildsVariableGeometryWrapped = true
  if Assets and type(Assets.register) == "function" then
    pcall(Assets.register, wrappedInvalidate)
  end
  return true, "wrapped_mesh"
end

function Adapter.install(mod)
  if _state == "installed" or _state == "native" then
    return true, _reason
  end
  if _state == "failed" then
    return false, _reason
  end

  local ok, err = pcall(function()
    local ds = Adapter.findBattleArt(mod)
    if not ds then
      _state = "absent"
      _reason = "battle_art_absent"
      return
    end
    local native, nativeWhy = battleArtIsNative(ds)
    if native then
      _state = "native"
      _reason = nativeWhy
      return
    end
    local lib = ds.exports and ds.exports.lib
    if not (lib and type(lib.require) == "function") then
      error("exports.lib.require missing")
    end
    local okSB, SpriteBillboards = pcall(lib.require, "SpriteBillboards")
    if not (okSB and type(SpriteBillboards) == "table") then
      error("SpriteBillboards module missing")
    end
    local okV3, Voxel3D = pcall(lib.require, "Voxel3D")
    if not (okV3 and type(Voxel3D) == "table") then
      error("Voxel3D module missing")
    end
    local Assets = nil
    local okA, A = pcall(require, "src.render.Assets")
    if okA and type(A) == "table" then Assets = A end
    local wrapped, why = wrapBillboards(SpriteBillboards, Voxel3D, Assets)
    if not wrapped then
      error(why or "wrap failed")
    end
    _state = "installed"
    _reason = why
  end)

  if not ok then
    _state = "failed"
    _reason = tostring(err)
    logFail(mod, _reason)
    return false, _reason
  end
  if _state == "absent" then
    return false, _reason
  end
  if _state == "failed" then
    logFail(mod, _reason)
    return false, _reason
  end
  logOk(mod, _reason)
  return true, _reason
end

return Adapter
