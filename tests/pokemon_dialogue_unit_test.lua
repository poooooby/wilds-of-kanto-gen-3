-- lib/pokemon_dialogue.lua: the dialogue portrait loader reads portraits from the sprite atlas first
-- (they ship packed in atlas shards, with no file of their own) and falls back to a plain image load.
-- Run: lua tests/pokemon_dialogue_unit_test.lua
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

local newImageCalls, filters = {}, {}
love = {
  image = {
    newImageData = function(w, h)
      local id = { w = w, h = h }
      function id:paste() end
      return id
    end,
  },
  graphics = {
    newImage = function(x)
      newImageCalls[#newImageCalls + 1] = x
      local img = { source = x }
      function img:setFilter(a, b) filters[#filters + 1] = a .. "/" .. b end
      return img
    end,
  },
}

local Atlas = V.require("sprite_atlas")
local Dialogue = V.require("pokemon_dialogue")
local load = Dialogue._loadPortraitImage
check(type(load) == "function", "the portrait loader is exposed for tests")

local INDEX = [[{"version":1,"families":{"pmd":{"index":"assets/atlas/pmd.json","dirs":[],"prefixes":["assets/pmdcollab/portraits/"]}}}]]
local FAMILY = [[{"version":1,"family":"pmd","shards":[{"file":"assets/atlas/pmd_0.png","w":40,"h":80}],
  "dirs":{"assets/pmdcollab/portraits/025/normal":{"happy.png":[0,0,0,40,40],"normal.png":[0,0,40,40,40]}}}]]
local files = { ["assets/atlas/index.json"] = INDEX, ["assets/atlas/pmd.json"] = FAMILY }

local A = {
  image = function(path) return { engineImage = path } end,
  imageData = function(path) return {} end,
  exists = function() return false end,
}
Atlas._reset()
local ok = Atlas.install({ path = "mods/wilds_of_kanto_gen3" }, {
  read = function(rel) return files[rel] end,
  imageData = function(path) return { tag = path, paste = function() end } end,
  Assets = A,
})
eq(ok, true, "atlas installed for the test")

-- an atlased portrait: cut from the shard, never loaded as a file
local base = "mods/wilds_of_kanto_gen3/assets/pmdcollab/portraits/025/normal/"
local img = load(base .. "happy.png")
check(img ~= nil, "atlased portrait loads")
check(type(newImageCalls[1]) == "table" and newImageCalls[1].w == 40 and newImageCalls[1].h == 40,
  "it is built from a 40x40 slice, not from a file path")
eq(filters[#filters], "nearest/nearest", "nearest filter is applied like before")
local again = load(base .. "happy.png")
check(again == img, "the same portrait is served from the atlas cache on the next dialogue")
eq(#newImageCalls, 1, "no second Image was created")

-- a path the atlas does not have: plain image load, as before
local fallbackPath = "mods/wilds_of_kanto_gen3/assets/pmdcollab/portraits/025/normal/angry.png"
local plain = load(fallbackPath)
check(plain ~= nil, "a non-atlas portrait still loads")
eq(newImageCalls[#newImageCalls], fallbackPath, "it goes to love.graphics.newImage with the path")
eq(filters[#filters], "nearest/nearest", "nearest filter on the fallback too")

-- guards
eq(load(nil), nil, "nil path")
eq(load(""), nil, "empty path")
local saved = love.graphics.newImage
love.graphics.newImage = nil
eq(load(base .. "normal.png"), nil, "no image API -> nil")
love.graphics.newImage = saved

-- no atlas at all (repo checkout): the loader behaves exactly as before
Atlas._reset()
local n = #newImageCalls
local direct = load(base .. "happy.png")
check(direct ~= nil, "without an atlas the file path is loaded")
eq(newImageCalls[n + 1], base .. "happy.png", "without an atlas newImage gets the path")

if failures > 0 then
  io.stderr:write(string.format("\n%d failure(s)\n", failures))
  os.exit(1)
end
print("all passed")
