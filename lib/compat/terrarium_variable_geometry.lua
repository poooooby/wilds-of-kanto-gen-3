-- In-memory compatibility adapter: TERRARIUM SpriteBillboards.mesh
-- consumes Wilds / Gen1Recomp variable SpriteDef geometry.
--
-- Terrarium (manifest id TERRARIUM, a Dramatic Shape Voxel Mod fork,
-- inspected 1.35.0-beta) exposes exports.lib = V with V.require — the same
-- public SpriteBillboards / Voxel3D / VoxelState contract as Battle Art,
-- Potato, Dramaless, and Stadium2. lib/SpriteBillboards.lua still hardcodes
-- 16px frames (fy = frame * 16). Wilds wraps mesh() and re-points
-- shadowQuad so body, occlusion silhouette, and sprite-mesh shadows agree.
-- Terrarium source is not copied and is not patched on disk.
--
-- Pivot: billboard / caster matrices apply T(-8,0,0), same convention as
-- Battle Art. Variable quads land the SpriteDef anchor on that pivot.
local V = ...
local Factory = V.require("compat/voxel_sprite_billboards_adapter")

return Factory.create({
  providerId = "TERRARIUM",
  displayName = "Terrarium",
  failLog = "Terrarium variable geometry unavailable; using Classic",
  okInstalled = "Terrarium variable geometry: adapter installed",
  okNative = "Terrarium variable geometry: native",
})
