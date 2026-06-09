-- Meeting Light: white/tinted fill on chosen screen(s) while the camera is in use
-- (Zoom / Teams / Google Meet, including in a browser). Camera-on is the signal
-- that catches browser meetings too.
--
-- Controls live in a menu bar item (💡). "Adjust light…" opens a slider panel for
-- warmth (color temperature) + brightness, with live preview on the real monitor.
--
-- macOS Sequoia notes:
--   * Hammerspoon's wallpaper GETTER is unreliable on 15.x, so the original wallpaper
--     is captured & restored via AppleScript. Hammerspoon detects the camera, generates
--     the fill image (hs.canvas), and SETS it on the target displays.

local home    = os.getenv("HOME")
local hsDir   = home .. "/.hammerspoon"
local snapPath = hsDir .. "/wallpaper_snapshot.lua"
local setPath  = hsDir .. "/meeting_light_settings.lua"

-- ===== User config (safe to tweak) =====
local CONFIG = {
  defaultKelvin     = 4500,   -- starting warmth in Kelvin (warm 2700 .. cool 6500)
  defaultBrightness = 100,    -- starting brightness percent
  warmthMin     = 2700, warmthMax     = 6500,
  brightnessMin = 10,   brightnessMax = 100,
}

-- Forward declarations (functions reference each other / the menu / the panel).
local rebuildMenu, update, fullReconcile, openPanel

local snapshot = nil  -- { [desktopIndex] = "/path" }
local settings = { enabled = true, kelvin = CONFIG.defaultKelvin, brightness = CONFIG.defaultBrightness, whiteDisplays = {} }
local menubar  = nil
local panel    = nil
local panelBackup = nil

-- ---------- helpers ----------
local function fileExists(p) local f=io.open(p,"r"); if f then f:close(); return true end; return false end
local function escapeAS(s)   return (s:gsub("\\","\\\\"):gsub('"','\\"')) end
local function screenName(s) return s:name() or ("Display " .. tostring(s:id())) end
local function isPrimary(s)  return s:id() == hs.screen.primaryScreen():id() end
local function clamp(x,lo,hi) if x<lo then return lo elseif x>hi then return hi else return x end end

-- A fill image is one of ours: white.png (legacy) or any mlfill_*.png.
local function isFillPath(p)
  local base = p:match("[^/]+$") or p
  return base == "white.png" or base:find("^mlfill_") ~= nil
end

-- ---------- color (color temperature -> RGB, Tanner Helland approximation) ----------
local function kelvinToRGB(kelvin)
  local t = kelvin / 100
  local r, g, b
  if t <= 66 then
    r = 255
    g = 99.4708025861 * math.log(t) - 161.1195681661
    if t <= 19 then b = 0 else b = 138.5177312231 * math.log(t - 10) - 305.0447927307 end
  else
    r = 329.698727446 * ((t - 60) ^ -0.1332047592)
    g = 288.1221695283 * ((t - 60) ^ -0.0755148492)
    b = 255
  end
  return { clamp(r,0,255), clamp(g,0,255), clamp(b,0,255) }
end

local function currentRGB()
  local rgb = kelvinToRGB(settings.kelvin or 4500)
  local f = (settings.brightness or 100) / 100
  return { math.floor(rgb[1]*f+0.5), math.floor(rgb[2]*f+0.5), math.floor(rgb[3]*f+0.5) }
end

-- Render the current color to an image file and return its file:// URL.
-- We ALTERNATE between two filenames so the path always changes — otherwise
-- macOS caches the wallpaper by path and won't reload it when only the bytes change.
local fillToggle = 0
local function materializeFillURL()
  fillToggle = 1 - fillToggle
  local path = hsDir .. "/mlfill_live" .. fillToggle .. ".png"
  local rgb = currentRGB()
  local c = hs.canvas.new({ x = 0, y = 0, w = 256, h = 256 })
  c[1] = {
    type = "rectangle", action = "fill",
    frame = { x = "0%", y = "0%", w = "100%", h = "100%" },
    fillColor = { red = rgb[1]/255, green = rgb[2]/255, blue = rgb[3]/255, alpha = 1 },
  }
  local img = c:imageFromCanvas()
  if img then img:saveToFile(path) end
  c:delete()
  return "file://" .. path
end

-- ---------- persistence ----------
local function loadSnapshot()
  local ok, data = pcall(dofile, snapPath)
  if ok and type(data) == "table" then snapshot = data end
end
local function saveSnapshot()
  if not snapshot then return end
  local f = io.open(snapPath, "w"); if not f then return end
  f:write("return {\n")
  for i, p in pairs(snapshot) do f:write(string.format("  [%d] = %q,\n", i, p)) end
  f:write("}\n"); f:close()
end

local function loadSettings()
  local ok, data = pcall(dofile, setPath)
  if ok and type(data) == "table" then
    if type(data.enabled) == "boolean" then settings.enabled = data.enabled end
    if type(data.kelvin) == "number" then settings.kelvin = data.kelvin end
    if type(data.brightness) == "number" then settings.brightness = data.brightness end
    if not data.kelvin and type(data.warmth) == "string" then           -- migrate old presets
      local map = { cool=6500, daylight=5500, neutral=4500, warm=3500, warmer=2900 }
      settings.kelvin = map[data.warmth] or CONFIG.defaultKelvin
    end
    if type(data.whiteDisplays) == "table" then settings.whiteDisplays = data.whiteDisplays end
  end
end
local function saveSettings()
  local f = io.open(setPath, "w"); if not f then return end
  f:write(string.format("return {\n  enabled = %s,\n  kelvin = %d,\n  brightness = %d,\n  whiteDisplays = {\n",
    tostring(settings.enabled), math.floor(settings.kelvin or 4500), math.floor(settings.brightness or 100)))
  for name in pairs(settings.whiteDisplays) do f:write(string.format("    [%q] = true,\n", name)) end
  f:write("  },\n}\n"); f:close()
end

-- ---------- AppleScript wallpaper get/set (reliable on Sequoia) ----------
local function getAllWallpapers()
  local ok, result = hs.osascript.applescript([[
    set out to ""
    tell application "System Events"
      repeat with d in desktops
        set out to out & (picture of d) & linefeed
      end repeat
    end tell
    return out
  ]])
  if not ok or type(result) ~= "string" then return nil end
  local list = {}
  for line in result:gmatch("[^\r\n]+") do list[#list + 1] = line end
  return list
end
local function restoreAll(snap)
  for i, p in pairs(snap) do
    hs.osascript.applescript(string.format(
      'tell application "System Events" to set picture of desktop %d to "%s"', i, escapeAS(p)))
  end
end
local function listHasFill(list)
  for _, p in ipairs(list) do if isFillPath(p) then return true end end
  return false
end

-- ---------- screens / camera ----------
local function targetScreens()
  local out = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    if settings.whiteDisplays[screenName(s)] then out[#out + 1] = s end
  end
  return out
end
local function cameraInUse()
  for _, cam in ipairs(hs.camera.allCameras()) do if cam:isInUse() then return true end end
  return false
end

-- ---------- core actions ----------
local function applyFillToTargets()
  local img = materializeFillURL()
  for _, s in ipairs(targetScreens()) do s:desktopImageURL(img) end
end
local function captureIfClean()
  local cur = getAllWallpapers()
  if cur and not listHasFill(cur) then snapshot = cur; saveSnapshot() end  -- never memorize a fill
end
local function restoreFromSnapshot() if snapshot then restoreAll(snapshot) end end

function fullReconcile()
  restoreFromSnapshot()
  if settings.enabled and cameraInUse() then applyFillToTargets() end
  rebuildMenu()
end

function update()
  if not settings.enabled then
    restoreFromSnapshot()
  elseif cameraInUse() then
    captureIfClean(); applyFillToTargets()
  else
    local cur = getAllWallpapers()
    if cur and listHasFill(cur) then restoreFromSnapshot()
    elseif cur then snapshot = cur; saveSnapshot() end
  end
  rebuildMenu()
end

-- ---------- smooth on-screen preview (canvas overlay; no wallpaper writes) ----------
-- Used only while the slider panel is open, so dragging is smooth (a canvas color
-- change is instant, with none of the crossfade animation a wallpaper change triggers).
local previewOverlays = {}  -- [screenId] = hs.canvas

local function previewColor()
  local rgb = currentRGB()
  return { red = rgb[1]/255, green = rgb[2]/255, blue = rgb[3]/255, alpha = 1 }
end

local function showPreview()
  local color = previewColor()
  local wanted = {}
  for _, s in ipairs(targetScreens()) do
    local id = s:id(); wanted[id] = true
    local cv = previewOverlays[id]
    if not cv then
      cv = hs.canvas.new(s:fullFrame())
      cv:level(hs.canvas.windowLevels.overlay)
      cv:canvasMouseEvents(false, false, false, false)
      cv[1] = { type = "rectangle", action = "fill",
                frame = { x = "0%", y = "0%", w = "100%", h = "100%" }, fillColor = color }
      previewOverlays[id] = cv
      cv:show()
    else
      cv[1].fillColor = color; cv:show()
    end
  end
  for id, cv in pairs(previewOverlays) do
    if not wanted[id] then cv:delete(); previewOverlays[id] = nil end
  end
end

local function updatePreviewColor()
  local color = previewColor()
  for _, cv in pairs(previewOverlays) do cv[1].fillColor = color end
end

local function hidePreview()
  for id, cv in pairs(previewOverlays) do cv:delete(); previewOverlays[id] = nil end
end

-- ---------- slider panel (live preview) ----------
local function panelHTML()
  local html = [[
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
 body{font-family:-apple-system,system-ui;margin:0;padding:16px;background:#1e1e1e;color:#eee;-webkit-user-select:none;}
 h2{margin:0 0 4px;font-size:15px;font-weight:600;}
 .hint{font-size:11px;color:#888;margin-bottom:10px;}
 #sw{height:64px;border-radius:8px;border:1px solid #444;margin:10px 0 4px;}
 .row{margin:14px 0;}
 label{display:flex;justify-content:space-between;font-size:12px;margin-bottom:6px;color:#bbb;}
 label b{color:#fff;font-weight:600;}
 input[type=range]{width:100%;accent-color:#0a84ff;}
 .btns{display:flex;gap:8px;margin-top:18px;}
 button{flex:1;padding:9px;border-radius:6px;border:none;font-size:13px;cursor:pointer;}
 .done{background:#0a84ff;color:#fff;} .cancel{background:#3a3a3a;color:#ddd;}
</style></head><body>
 <h2>Meeting fill light</h2>
 <div class="hint">Preview shows live on your selected screen.</div>
 <div id="sw"></div>
 <div class="row"><label>Warmth <b id="kv"></b></label>
   <input id="k" type="range" min="__KMIN__" max="__KMAX__" step="50"></div>
 <div class="row"><label>Brightness <b id="bv"></b></label>
   <input id="b" type="range" min="__BMIN__" max="__BMAX__" step="1"></div>
 <div class="btns">
   <button class="cancel" onclick="send('cancel')">Cancel</button>
   <button class="done" onclick="send('done')">Done</button>
 </div>
<script>
 const k=document.getElementById('k'),b=document.getElementById('b');
 const kv=document.getElementById('kv'),bv=document.getElementById('bv'),sw=document.getElementById('sw');
 k.value=__KELVIN__; b.value=__BRIGHT__;
 function k2rgb(t){t/=100;let r,g,bb;
  if(t<=66){r=255;g=99.4708025861*Math.log(t)-161.1195681661;bb=(t<=19)?0:138.5177312231*Math.log(t-10)-305.0447927307;}
  else{r=329.698727446*Math.pow(t-60,-0.1332047592);g=288.1221695283*Math.pow(t-60,-0.0755148492);bb=255;}
  const c=x=>Math.max(0,Math.min(255,Math.round(x)));return[c(r),c(g),c(bb)];}
 function paint(){const rgb=k2rgb(+k.value),f=(+b.value)/100;
  const r=Math.round(rgb[0]*f),g=Math.round(rgb[1]*f),bb=Math.round(rgb[2]*f);
  sw.style.background='rgb('+r+','+g+','+bb+')';kv.textContent=k.value+'K';bv.textContent=b.value+'%';}
 let pending=false;
 function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;post('change');},80);}
 function post(t){window.webkit.messageHandlers.ml.postMessage({type:t,kelvin:+k.value,brightness:+b.value});}
 function send(t){post(t);}
 k.oninput=()=>{paint();schedule();};b.oninput=()=>{paint();schedule();};
 paint();
</script></body></html>]]
  html = html:gsub("__KELVIN__", tostring(math.floor(settings.kelvin or CONFIG.defaultKelvin)))
  html = html:gsub("__BRIGHT__", tostring(math.floor(settings.brightness or CONFIG.defaultBrightness)))
  html = html:gsub("__KMIN__", tostring(CONFIG.warmthMin)):gsub("__KMAX__", tostring(CONFIG.warmthMax))
  html = html:gsub("__BMIN__", tostring(CONFIG.brightnessMin)):gsub("__BMAX__", tostring(CONFIG.brightnessMax))
  return html
end

function openPanel()
  if panel then panel:show():bringToFront(true); return end
  captureIfClean()  -- make sure we have a clean wallpaper for after the meeting
  panelBackup = { kelvin = settings.kelvin, brightness = settings.brightness }
  showPreview()     -- smooth on-screen preview; does NOT touch the wallpaper

  local function finish(save)
    local p = panel; panel = nil
    if not save then
      settings.kelvin = panelBackup.kelvin
      settings.brightness = panelBackup.brightness
    end
    hidePreview()
    saveSettings()
    if p then p:delete() end
    fullReconcile()   -- writes the wallpaper ONCE (only if a meeting is active)
  end

  local uc = hs.webview.usercontent.new("ml")
  uc:setCallback(function(msg)
    -- msg.body may be a table OR a JSON string depending on WebKit/HS version.
    local b = msg.body
    if type(b) == "string" then b = hs.json.decode(b) or {} end
    if type(b) ~= "table" then b = {} end
    if b.type == "change" then
      if tonumber(b.kelvin) then settings.kelvin = tonumber(b.kelvin) end
      if tonumber(b.brightness) then settings.brightness = tonumber(b.brightness) end
      updatePreviewColor()                 -- instant, smooth — no wallpaper write
    elseif b.type == "done" then finish(true)
    elseif b.type == "cancel" then finish(false) end
  end)

  local W, H = 380, 360
  local sf = hs.screen.primaryScreen():frame()
  panel = hs.webview.new({ x = sf.x + (sf.w - W)/2, y = sf.y + (sf.h - H)/2, w = W, h = H },
                         { developerExtrasEnabled = false }, uc)
  panel:windowStyle(hs.webview.windowMasks.titled + hs.webview.windowMasks.closable + hs.webview.windowMasks.utility)
  panel:windowTitle("Meeting Light")
  panel:allowTextEntry(true)
  panel:windowCallback(function(action)
    if action == "closing" and panel then finish(true) end  -- red-button close = keep
  end)
  panel:html(panelHTML())
  panel:show():bringToFront(true)
end

-- ---------- menu bar icon (template images: monochrome, adapts to light/dark) ----------
local ICON_ON, ICON_IDLE, ICON_OFF

local function bulbImage(filled, slash)
  local s = 22
  local k = { red = 0, green = 0, blue = 0, alpha = 1 }  -- color is ignored once template = true
  local c = hs.canvas.new({ x = 0, y = 0, w = s, h = s })
  -- glass
  c[#c + 1] = { type = "circle", center = { x = s * 0.5, y = s * 0.43 }, radius = s * 0.24,
                action = filled and "fill" or "stroke", fillColor = k, strokeColor = k, strokeWidth = 1.7 }
  -- base
  c[#c + 1] = { type = "rectangle", frame = { x = s * 0.42, y = s * 0.63, w = s * 0.16, h = s * 0.16 },
                roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
                action = filled and "fill" or "stroke", fillColor = k, strokeColor = k, strokeWidth = 1.7 }
  if slash then
    c[#c + 1] = { type = "segments", coordinates = { { x = s * 0.15, y = s * 0.15 }, { x = s * 0.85, y = s * 0.85 } },
                  action = "stroke", strokeColor = k, strokeWidth = 2 }
  end
  local img = c:imageFromCanvas()
  c:delete()
  if img then img:template(true) end
  return img
end

local function buildIcons()
  local ok = pcall(function()
    ICON_ON   = bulbImage(true,  false)   -- camera live: filled bulb
    ICON_IDLE = bulbImage(false, false)   -- enabled, waiting: outline bulb
    ICON_OFF  = bulbImage(false, true)    -- paused: outline + slash
  end)
  if not ok then ICON_ON, ICON_IDLE, ICON_OFF = nil, nil, nil end
end

-- ---------- menu bar ----------
function rebuildMenu()
  if not menubar then return end
  local active = settings.enabled and cameraInUse()
  local icon = (not settings.enabled) and ICON_OFF or (active and ICON_ON or ICON_IDLE)
  if icon then
    menubar:setIcon(icon); menubar:setTitle("")
  else  -- fallback if template images couldn't be built
    menubar:setTitle(not settings.enabled and "🌙" or (active and "⚪" or "💡"))
  end

  local items = {}
  items[#items+1] = { title = settings.enabled and "✓ Auto-white during meetings" or "Auto-white during meetings",
                      fn = function() settings.enabled = not settings.enabled; saveSettings(); fullReconcile() end }
  items[#items+1] = { title = "-" }
  items[#items+1] = { title = "White these screens:", disabled = true }
  for _, s in ipairs(hs.screen.allScreens()) do
    local name = screenName(s)
    items[#items+1] = {
      title = name .. (isPrimary(s) and "  (main)" or "  (secondary)"),
      checked = settings.whiteDisplays[name] == true,
      fn = function()
        if settings.whiteDisplays[name] then settings.whiteDisplays[name] = nil
        else settings.whiteDisplays[name] = true end
        saveSettings(); fullReconcile()
      end,
    }
  end
  items[#items+1] = { title = "-" }
  items[#items+1] = { title = string.format("Adjust light…  (%dK · %d%%)",
                        math.floor(settings.kelvin or 4500), math.floor(settings.brightness or 100)),
                      fn = function() openPanel() end }
  items[#items+1] = { title = "-" }
  items[#items+1] = { title = cameraInUse() and "● Camera in use" or "○ Camera idle", disabled = true }
  items[#items+1] = { title = "-" }
  items[#items+1] = { title = "Save current wallpaper as default", fn = function()
      local cur = getAllWallpapers()
      if cur and not listHasFill(cur) then snapshot = cur; saveSnapshot(); hs.alert.show("Wallpaper saved as default")
      else hs.alert.show("Can't save while a screen is lit — end the meeting first") end end }
  items[#items+1] = { title = "Restore wallpaper now", fn = function() restoreFromSnapshot(); rebuildMenu() end }
  items[#items+1] = { title = "-" }
  items[#items+1] = { title = "Reload config", fn = function() hs.reload() end }
  menubar:setMenu(items)
end

-- ---------- watchers ----------
local function watch(cam)
  cam:setPropertyWatcherCallback(function() update() end)
  cam:startPropertyWatcher()
end
for _, cam in ipairs(hs.camera.allCameras()) do watch(cam) end
hs.camera.setWatcherCallback(function(cam, change) if change == "Added" then watch(cam) end end)
hs.camera.startWatcher()
hs.screen.watcher.new(update):start()

-- ---------- startup ----------
hs.autoLaunch(true)
hs.pathwatcher.new(hsDir .. "/", function(files)
  for _, f in ipairs(files) do
    if f:sub(-4) == ".lua" and not f:find("wallpaper_snapshot") and not f:find("meeting_light_settings") then
      hs.reload(); return
    end
  end
end):start()

loadSnapshot()
loadSettings()
if not fileExists(setPath) then
  for _, s in ipairs(hs.screen.allScreens()) do
    if not isPrimary(s) then settings.whiteDisplays[screenName(s)] = true end
  end
  saveSettings()
end

menubar = hs.menubar.new()
buildIcons()
require("hs.ipc")

MeetingLight = {
  update = update, reconcile = fullReconcile, openPanel = openPanel,
  status = function()
    local n = 0; for _ in pairs(previewOverlays) do n = n + 1 end
    return hs.inspect({ settings=settings, cameraInUse=cameraInUse(), rgb=currentRGB(), previewOverlays=n })
  end,
}

update()
hs.alert.show("Meeting Light ready — see the menu bar")
