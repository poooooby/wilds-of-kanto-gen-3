-- Unown letter forms (Gold). Unown is one species with 26 letters; the engine reads the letter off the DVs
-- (src/core/gen2/Unown.lua: letterFromDVs, 1 = A .. 26 = Z). Our HGSS/PokeMMO art has one sheet per letter
-- (assets/enhanced_overworld/followsprites/201-b-n[-NN].png: no suffix = A, -01 = B .. -25 = Z), which the build bakes
-- as extra "form assets" with ids 60001..60025 (tools/unown_forms.py) so every id-keyed part of the sprite pipeline
-- (runtime sheets, True Size packs, the atlas) serves them unchanged. 60000+ never collides with a real species
-- (1..1025) or a dex-expansion form (30001..50248).
--
-- A form is the number in the file suffix (1..25); nil means the base art (letter A, or any non-Unown).
local UnownForms = {}

UnownForms.SPECIES = "UNOWN"
UnownForms.BASE_DEX = 201
UnownForms.FORM_BASE = 60000
UnownForms.FORM_COUNT = 25 -- B..Z; Gold has no "!" / "?"

--- Letter number (1 = A .. 26 = Z) -> form 1..25, or nil for A / anything out of range.
function UnownForms.formForLetter(letter)
  local n = tonumber(letter)
  if not n or math.floor(n) ~= n then return nil end
  if n < 2 or n > UnownForms.FORM_COUNT + 1 then return nil end
  return n - 1
end

--- Form 1..25 -> letter number 2..26 (nil when out of range).
function UnownForms.letterForForm(form)
  local n = tonumber(form)
  if not n or math.floor(n) ~= n or n < 1 or n > UnownForms.FORM_COUNT then return nil end
  return n + 1
end

--- Form asset id (60001..60025) for a form, or nil.
function UnownForms.assetId(form)
  local n = tonumber(form)
  if not n or math.floor(n) ~= n or n < 1 or n > UnownForms.FORM_COUNT then return nil end
  return UnownForms.FORM_BASE + n
end

function UnownForms.isFormId(id)
  local n = tonumber(id)
  return n ~= nil and math.floor(n) == n
    and n > UnownForms.FORM_BASE and n <= UnownForms.FORM_BASE + UnownForms.FORM_COUNT
end

--- 60003 -> 201 (the species whose art/scale the form shares); any other id comes back unchanged.
function UnownForms.baseId(id)
  if UnownForms.isFormId(id) then return UnownForms.BASE_DEX end
  return id
end

--- Form asset id for `dex` (an asset id) wearing `form`, or nil when this is not Unown or the form is not a letter B..Z.
function UnownForms.formAssetId(dex, form)
  if tonumber(dex) ~= UnownForms.BASE_DEX then return nil end
  return UnownForms.assetId(form)
end

return UnownForms
