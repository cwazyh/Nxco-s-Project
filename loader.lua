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

local function fetch(url)
  -- Try game:HttpGet first
  local ok, res = pcall(function() return game:HttpGet(url) end)
  if ok and res and type(res) == "string" and #res > 0 then
    return res
  end
  -- Try HttpService:GetAsync
  local ok2, res2 = pcall(function()
    return game:GetService("HttpService"):GetAsync(url)
  end)
  if ok2 and res2 and type(res2) == "string" and #res2 > 0 then
    return res2
  end
  return nil
end

-- Recursively collect all .lua file paths from the repo
local function listLuaFiles(path, out)
  path = path or ""
  local url = BASE_API .. path .. "?ref=main"
  local body = fetch(url)
  if not body then
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
  local body = fetch(url)
  if not body or #body == 0 then
    warn("[loader] empty response: " .. rel)
    goto continue
  end
  -- Print first 80 chars for debugging
  print("[loader] body sample: " .. body:sub(1, 80))
  local ok, res = pcall(function()
    return loadstring(body)()
  end)
  if not ok then
    warn("[loader] failed: " .. rel .. " — " .. tostring(res))
  else
    print("[loader] loaded: " .. rel)
  end
  ::continue::
end