-- Shared in-memory SpriteBillboards.mesh wrap for Voxel forks that expose
-- the same public module table Battle Art does: exports.lib.require.
--
-- Battle Art keeps its own adapter (lib/compat/battle_art_variable_geometry.lua)
-- and is not routed through this factory. Potato / Dramaless / Stadium2 use
-- this so their wrap contract stays aligned without touching the known-good
-- Battle Art path.
--
-- Wilds does NOT copy VoxelScene, shaders, camera, or mesher code.
-- Vanilla 16×16 defs call the original mesh() unchanged.
-- shadowBlob() is never wrapped (Potato low-end contact shadow).
local V = ...
local DebugLog = V.require("debug_log")

local Factory = {}

local INSET_U = 0.02
local INSET_V = 0.05
-- Dramatic Shape-family billboard / caster matrices apply T(-8, 0, 0).
local PIVOT_X = 8

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

--- spec:
---   providerId, displayName
---   failLog, okInstalled, okNative  (DEV log strings)
function Factory.create(spec)
  spec = spec or {}
  local Adapter = {}
  Adapter.PROVIDER_ID = spec.providerId
  Adapter.FAIL_LOG = spec.failLog
    or (tostring(spec.displayName or "Voxel")
      .. " variable geometry unavailable; using Classic")

  local _state = "idle" -- idle | installed | native | failed | absent
  local _reason = nil
  local _loggedFail = false
  local _loggedOk = false
  local _origMesh = nil
  local _origInvalidate = nil
  local _origShadowQuad = nil
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
    if DebugLog and DebugLog.info then
      DebugLog.info(mod, "%s", msg)
    end
  end

  local function logOk(mod, detail)
    if _loggedOk then return end
    _loggedOk = true
    local msg
    if _state == "native" then
      msg = spec.okNative
        or (tostring(spec.displayName or "Voxel") .. " variable geometry: native")
    else
      msg = spec.okInstalled
        or (tostring(spec.displayName or "Voxel")
          .. " variable geometry: adapter installed")
    end
    if DebugLog and DebugLog.info then
      DebugLog.info(mod, "%s", msg)
    end
  end

  function Adapter.findProvider(mod)
    if not mod or type(mod.find) ~= "function" then return nil end
    local ok, hit = pcall(mod.find, mod, Adapter.PROVIDER_ID)
    if ok and hit then return hit end
    return nil
  end

  function Adapter.reset()
    if _wrappedTable and _origMesh then
      _wrappedTable.mesh = _origMesh
      if _origShadowQuad ~= nil then
        _wrappedTable.shadowQuad = _origShadowQuad
      else
        _wrappedTable.shadowQuad = _origMesh
      end
      if _origInvalidate then
        _wrappedTable.invalidate = _origInvalidate
      end
      _wrappedTable._wildsVariableGeometryWrapped = nil
    end
    _state = "idle"
    _reason = nil
    _loggedFail = false
    _loggedOk = false
    _origMesh = nil
    _origInvalidate = nil
    _origShadowQuad = nil
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

  -- displayWidth/displayHeight/displayAnchorX/displayAnchorY let a caller
  -- request a billboard quad SMALLER or LARGER than the real frameWidth/
  -- frameHeight/anchorX/anchorY. They default to the real values, so every
  -- existing caller (Battle Art, Potato, Dramaless, Stadium2, non-native
  -- Terrarium) is unaffected unless it sets them. Unlike a 2D canvas scale,
  -- this changes only the 3D quad's world-space size (Adapter.localQuad);
  -- Adapter.uvRect always slices the texture from the real frameWidth/
  -- frameHeight, so every source pixel is still sampled at native
  -- resolution — no resampling of the underlying image.
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
      -- different pixel column per frame (HGSS_SPRITES hit this at
      -- 0.6x/0.7x scales), which looks like the card pinching or
      -- stretching across the walk cycle. Only when a display override is
      -- actually set — otherwise this would round every plain (no
      -- override) real size too, for every caller that never opted in.
      dw = math.floor(dw + 0.5)
      dh = math.floor(dh + 0.5)
    end
    -- Default anchor: derive from the (already-quantized) display size as
    -- an exact proportion of the real anchor, rather than independently
    -- rounding a separately-computed anchor value. Two things break
    -- otherwise: (1) most species have ay == fh (anchor flush with the
    -- frame bottom) — but a species with real transparent padding below
    -- its feet (e.g. Onix: anchorY=36, frameHeight=38) needs that same 2px
    -- gap preserved at the display size, or its ground contact point
    -- shifts and it visibly floats/sinks. (2) for a centered real anchor
    -- (ax == fw/2, true for most species on X), deriving dax from the
    -- quantized dw guarantees dax == dw/2 exactly, however dw rounds —
    -- independently rounding dax can land it off-center by up to half a
    -- pixel when dw quantizes to an odd number, and since facing left/right
    -- mirrors the quad around the pivot, an off-center quad shifts one way
    -- when mirrored and the other way when not: too close facing one
    -- direction, too far facing the other. A fractional result here (e.g.
    -- dax = 10.5) is fine — a stable fractional offset never causes jitter,
    -- only a per-frame *varying* one does, which is what the dw/dh
    -- quantization above already prevents.
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

  function Adapter.localQuad(fw, fh, ax, ay)
    local x0 = PIVOT_X - ax
    local x1 = x0 + fw
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

  local function providerIsNative(ds)
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
    local x0, y0, x1, y1 = Adapter.localQuad(dw, dh, dax, day)
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
    _origShadowQuad = SpriteBillboards.shadowQuad
    _Voxel3D = Voxel3D
    _Assets = Assets
    _varMeshes = {}
    _wrappedTable = SpriteBillboards
    SpriteBillboards.mesh = wrappedMesh
    -- Re-point shadowQuad so solid / occlusion silhouette share geometry.
    -- Potato's dedicated shadowBlob() is a different function and is left
    -- on the table untouched.
    if type(SpriteBillboards.shadowQuad) == "function" then
      SpriteBillboards.shadowQuad = wrappedMesh
    end
    SpriteBillboards.invalidate = wrappedInvalidate
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
      local ds = Adapter.findProvider(mod)
      if not ds then
        _state = "absent"
        _reason = "provider_absent"
        return
      end
      local native, nativeWhy = providerIsNative(ds)
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
end

return Factory
