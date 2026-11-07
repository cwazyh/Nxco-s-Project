--[[
  Universal loader for liquid-glass-ui repo.
  Loads every file in the repo through a single loadstring.
  
  Usage:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/cwazyh/liquid-glass-ui/main/GUI/loader.lua"))()
--]]

local base = "https://raw.githubusercontent.com/cwazyh/liquid-glass-ui/main"

-- Load files in dependency order
local files = {
  "GUI/UI.lua",
}

for _, rel in ipairs(files) do
  local url = base .. "/" .. rel
  print("[loader] fetching " .. url)
  local ok, res = pcall(function()
    return loadstring(game:HttpGet(url))()
  end)
  if not ok then
    warn("[loader] failed to load " .. rel .. ": " .. tostring(res))
  else
    print("[loader] loaded " .. rel)
  end
end