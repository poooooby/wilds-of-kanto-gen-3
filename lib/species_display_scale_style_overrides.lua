-- Per-style Voxel display-scale overrides (dex -> { style = scale }).
-- Layered on top of the shared base table in species_display_scale.lua:
-- SpeciesGeometry.displayScale(dex, style) checks here FIRST for that exact
-- dex+style pair, and only falls back to the shared base scale when this
-- table has no entry for it.
--
-- style is whatever lib/config.lua's sprite_style option holds, e.g.
-- "pokemmo" (HGSS) or "followers" (Poke Followers/GSC).
--
-- Use this when one style's art for a species is proportioned differently
-- enough from the others that the shared base scale looks wrong for it.
-- Most species/styles need no entry at all here.
--
-- Example:
--   [6] = { pokemmo = 0.9 }, -- Charizard: tune just the HGSS/PokeMMO style
return {
--  [6] = { pokemmo = 0.9 }
}
