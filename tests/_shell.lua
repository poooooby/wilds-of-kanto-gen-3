-- Portable process helpers for the test suite: they behave the same under Windows cmd.exe and POSIX sh, so a test can
-- shell out to Python without heredocs, /dev/null or /tmp. Load with: local Shell = dofile("tests/_shell.lua")
local Shell = {}

Shell.isWindows = package.config:sub(1, 1) == "\\"

--- A writable temp directory, with forward slashes (Python and Lua both accept them on Windows).
function Shell.tmpDir()
  local dir = os.getenv("TEMP") or os.getenv("TMPDIR") or os.getenv("TMP") or "/tmp"
  return (dir:gsub("\\", "/"))
end

--- Run a command in the repo root. Returns ok (exit status 0), then stdout+stderr.
-- The status is read from a marker so it works on Lua 5.1 / LuaJIT, where io.popen():close() reports nothing useful.
function Shell.run(cmd)
  local f = io.popen(cmd .. " 2>&1 && echo __WILDS_OK__ || echo __WILDS_FAIL__", "r")
  if not f then return false, "io.popen unavailable" end
  local out = f:read("*a") or ""
  f:close()
  local ok = out:find("__WILDS_OK__", 1, true) ~= nil
  out = out:gsub("%s*__WILDS_OK__%s*$", ""):gsub("%s*__WILDS_FAIL__%s*$", "")
  return ok, out
end

local interpreter
--- The Python launcher that works here: python3, python, or py -3. nil when there is none.
function Shell.pythonCmd()
  if interpreter ~= nil then return interpreter or nil end
  for _, cmd in ipairs({ "python3", "python", "py -3" }) do
    if Shell.run(cmd .. " --version") then
      interpreter = cmd
      return cmd
    end
  end
  interpreter = false
  return nil
end

--- Run a Python source string (written to a temp file). Returns ok, output.
function Shell.python(source)
  local py = Shell.pythonCmd()
  if not py then return false, "no python interpreter found" end
  math.randomseed(os.time() + math.floor((os.clock() * 1000) % 100000))
  local path = string.format("%s/wilds_test_%d_%d.py", Shell.tmpDir(), os.time(), math.random(1, 1000000))
  local f = assert(io.open(path, "w"))
  f:write(source)
  f:close()
  local ok, out = Shell.run(py .. ' "' .. path .. '"')
  os.remove(path)
  return ok, out
end

--- Run a repo Python script (path relative to the repo root) with optional extra arguments. Returns ok, output.
function Shell.pythonFile(script, args)
  local py = Shell.pythonCmd()
  if not py then return false, "no python interpreter found" end
  return Shell.run(py .. " " .. script .. (args and (" " .. args) or ""))
end

return Shell
