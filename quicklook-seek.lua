-- quicklook-seek: seek Quick Look videos with the left/right arrow keys.
-- Loaded from ~/.hammerspoon/init.lua.
--
--   ← / →        seek by M.step seconds (default 5)
--   ⇧← / ⇧→      seek by M.bigStep seconds (default 30)
--
-- Keys only get intercepted while a Quick Look panel with a video/audio
-- timeline is open; otherwise they pass through (so arrowing between
-- images, PDFs, etc. still works).

local M = {}

M.step = 5
M.bigStep = 30

local LEFT, RIGHT = hs.keycodes.map["left"], hs.keycodes.map["right"]

local function attr(el, name)
  local ok, v = pcall(function() return el:attributeValue(name) end)
  if ok then return v end
end

-- The Quick Look panel shows up as a window with subrole "Quick Look" in the
-- host app (Finder, or whichever app opened it).
local function quickLookWindow()
  local app = hs.application.frontmostApplication()
  if not app then return nil end
  for _, w in ipairs(attr(hs.axuielement.applicationElement(app), "AXWindows") or {}) do
    if attr(w, "AXSubrole") == "Quick Look" then return w end
  end
end

local function findTimeline(el, depth)
  depth = depth or 0
  if depth > 6 then return nil end
  if attr(el, "AXRole") == "AXSlider" and attr(el, "AXDescription") == "timeline" then return el end
  for _, kid in ipairs(attr(el, "AXChildren") or {}) do
    local r = findTimeline(kid, depth + 1)
    if r then return r end
  end
end

-- When a key is held down, the slider's reported value can lag behind the
-- value we just set, so keep stepping from our last target for a moment.
local last = { slider = nil, target = nil, at = 0 }

local function seek(delta)
  local win = quickLookWindow()
  if not win then return false end
  local slider = findTimeline(win)
  if not slider then return false end

  local now = hs.timer.secondsSinceEpoch()
  local base
  if last.slider == slider and last.target and now - last.at < 0.4 then
    base = last.target
  else
    base = attr(slider, "AXValue")
  end
  if type(base) ~= "number" then return false end

  local lo = attr(slider, "AXMinValue") or 0
  local hi = attr(slider, "AXMaxValue") or math.huge
  local target = math.max(lo, math.min(hi, base + delta))
  pcall(function() slider:setAttributeValue("AXValue", target) end)
  last.slider, last.target, last.at = slider, target, now
  return true
end

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local code = e:getKeyCode()
  if code ~= LEFT and code ~= RIGHT then return false end

  -- Only plain or shift-modified arrows; leave ⌘/⌥/⌃ combos alone.
  -- (Arrow keys always carry the fn flag, so that's ignored.)
  local flags = e:getFlags()
  if flags.cmd or flags.alt or flags.ctrl then return false end

  local amount = flags.shift and M.bigStep or M.step
  local delta = code == LEFT and -amount or amount
  return seek(delta) -- true swallows the key; false lets it through
end)
M.tap:start()

-- macOS disables an event tap if a callback is ever too slow; turn it back on.
M.watchdog = hs.timer.doEvery(5, function()
  if not M.tap:isEnabled() then M.tap:start() end
end)

M.seek = seek

-- Debug helper: dump the accessibility tree of Finder / Quick Look windows.
function M.probe(path)
  local out = {}
  local function describe(el)
    local parts = {}
    for _, n in ipairs({ "AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXIdentifier",
                         "AXValue", "AXMinValue", "AXMaxValue" }) do
      local v = attr(el, n)
      if v ~= nil and v ~= "" then
        local s = type(v) == "userdata" and "<el>" or tostring(v)
        if #s > 80 then s = s:sub(1, 80) .. "…" end
        parts[#parts + 1] = n:sub(3) .. "=" .. s
      end
    end
    return table.concat(parts, " ")
  end
  local function dump(el, depth)
    if depth > 30 then return end
    out[#out + 1] = string.rep("  ", depth) .. describe(el)
    for _, kid in ipairs(attr(el, "AXChildren") or {}) do dump(kid, depth + 1) end
  end
  for _, app in ipairs(hs.application.runningApplications()) do
    local bid = app:bundleID() or ""
    if bid == "com.apple.finder" or bid:lower():find("quicklook") then
      out[#out + 1] = ("=== %s (%s)"):format(app:name(), bid)
      for _, win in ipairs(attr(hs.axuielement.applicationElement(app), "AXWindows") or {}) do dump(win, 1) end
    end
  end
  path = path or (os.getenv("HOME") .. "/Documents/code/personal/quicklook-seek/ql-tree.txt")
  local f = assert(io.open(path, "w"))
  f:write(table.concat(out, "\n"), "\n")
  f:close()
  return path
end

return M
