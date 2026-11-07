--[[
  Universal loader for Nxco's Project repo.
  Auto-discovers ALL .lua files in the repo via the GitHub API and loads them.
  
  Usage:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/cwazyh/Nxco-s-Project/main/loader.lua"))()
  
  New files: Just add any .lua file to the repo and it will auto-load on next run.
--]]

local REPO_OWNER = "cwazyh"
local REPO_NAME  = "Nxco-s-Project"
local BASE_API   = "https://api.github.com/repos/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/contents/"
local BASE_RAW   = "https://raw.githubusercontent.com/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/main/"

-- Recursively collect all .lua file paths from the repo
local function listLuaFiles(path, out)
  path = path or ""
  local url = BASE_API .. path .. "?ref=main"
  local ok, body = pcall(function() return game:HttpGet(url) end)
  if not ok or not body or body == "" then
    warn("[loader] failed to list " .. path)
    return
  end
  local data
  ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
  if not ok or type(data) ~= "table" then
    warn("[loader] bad JSON listing " .. path)
    return
  end
  for _, item in ipairs(data) do
    if item.type == "dir" then
      listLuaFiles(item.path, out)
    elseif item.type == "file" and item.name:match("%.lua$") then
      table.insert(out, item.path)
    end
  end
end

local files = {}
listLuaFiles("", files)

-- Sort: GUI first, then everything else alphabetically
table.sort(files, function(a, b)
  local aGui = a:match("^GUI/") ~= nil
  local bGui = b:match("^GUI/") ~= nil
  if aGui ~= bGui then return aGui end
  return a < b
end)

print("[loader] discovered " .. #files .. " lua file(s)")

for _, rel in ipairs(files) do
  local url = BASE_RAW .. rel
  print("[loader] fetching " .. url)
  local ok, res = pcall(function()
    return loadstring(game:HttpGet(url))()
  end)
  if not ok then
    warn("[loader] failed: " .. rel .. " — " .. tostring(res))
  else
    print("[loader] loaded: " .. rel)
  end
end