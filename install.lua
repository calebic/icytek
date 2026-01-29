-- ICEYTEK INSTALLER -- TEK-OS

term.setPaletteColour(colours.black, 0x000F1C)
term.setPaletteColour(colours.lime, 0x0DDA85)
term.setPaletteColour(colours.green, 0x0AA86A)
term.setPaletteColour(colours.cyan, 0x39E6D3)
term.setPaletteColour(colours.lightGrey, 0x8FD9C8)
term.setPaletteColour(colours.orange, 0xFFB347)
term.setPaletteColour(colours.red, 0xFF4C4C)
term.setBackgroundColor(colours.black)
term.setTextColour(colours.lime)
shell.run("clear")

local function printCentered(text, y)
  local w, _ = term.getSize()
  local x = math.floor((w - #text) / 2) + 1
  if y then term.setCursorPos(x, y) else term.setCursorPos(x, select(2, term.getCursorPos())) end
  write(text)
end

local function drawFrame()
  local w, h = term.getSize()
  term.setBackgroundColor(colours.black)
  term.setTextColour(colours.green)
  term.setCursorPos(1, 1)
  write(string.rep("=", w))
  term.setCursorPos(1, 2)
  write(string.rep("-", w))
  term.setCursorPos(1, h - 1)
  write(string.rep("-", w))
  term.setCursorPos(1, h)
  write(string.rep("=", w))
end

local function drawHeader()
  local w, _ = term.getSize()
  term.setTextColour(colours.cyan)
  printCentered("ICYTEK INSTALLATION CONSOLE", 1)
  term.setTextColour(colours.lightGrey)
  local tag = "TEK-OS DISTRIBUTION NODE"
  term.setCursorPos(w - #tag + 1, 2)
  write(tag)
end

local function drawFooter(text)
  local w, h = term.getSize()
  term.setTextColour(colours.lightGrey)
  term.setCursorPos(2, h - 1)
  term.clearLine()
  write(text or "W/S MOVE  ENTER SELECT  Q EXIT")
  term.setTextColour(colours.green)
  term.setCursorPos(2, h)
  term.clearLine()
  write("READY >")
end

local function drawScanlines()
  local w, h = term.getSize()
  term.setTextColour(colours.green)
  for y = 4, h - 2, 2 do
    term.setCursorPos(1, y)
    write(string.rep(".", w))
  end
end

local function bootSplash()
  local w, h = term.getSize()
  term.clear()
  drawFrame()
  term.setTextColour(colours.cyan)
  printCentered("TEK-OS VAULTLINK BOOT", 4)
  term.setTextColour(colours.lightGrey)
  printCentered("ESTABLISHING SECURE LINK...", 6)
  term.setTextColour(colours.lime)
  for i = 1, 3 do
    term.setCursorPos(2, 8 + i)
    write("SYSCHK-" .. i .. " OK")
    sleep(0.08)
  end
  term.setTextColour(colours.orange)
  printCentered("LOADING MODULES", 12)
  for i = 1, w - 6 do
    term.setCursorPos(3, 14)
    write(string.rep("=", i))
    sleep(0.01)
  end
  term.setTextColour(colours.lime)
  printCentered("READY", h - 3)
  sleep(0.4)
end

local function flicker()
  local w, h = term.getSize()
  for i = 1, 8 do
    local y = math.random(4, h - 2)
    local x = math.random(1, w - 3)
    term.setTextColour(colours.green)
    term.setCursorPos(x, y)
    write("..")
  end
end

local function promptLine(label, default)
  local _, h = term.getSize()
  term.setCursorPos(1, h - 1)
  term.clearLine()
  write(label)
  local v = read()
  if v == "" and default ~= nil then
    return default
  end
  return v
end

local function sanitizeBase(base)
  if base:sub(-1) == "/" then
    return base:sub(1, -2)
  end
  return base
end

local function download(url, dest)
  if fs.exists(dest) then
    fs.delete(dest)
  end
  return shell.run("wget", url, dest)
end

local function writeConfig(path, tbl)
  local f = fs.open(path, "w")
  f.write(textutils.serialize(tbl))
  f.close()
end

local function drawMenu(options, selected)
  term.clear()
  drawFrame()
  drawHeader()
  drawScanlines()

  local w, h = term.getSize()
  term.setTextColour(colours.orange)
  printCentered("VAULTLINK INSTALLER v76.3", 3)

  local startY = 6
  local boxWidth = math.min(w - 8, 34)
  local boxX = math.floor((w - boxWidth) / 2) + 1

  for i, opt in ipairs(options) do
    local y = startY + (i - 1) * 2
    term.setCursorPos(boxX, y)
    if i == selected then
      term.setBackgroundColor(colours.lime)
      term.setTextColour(colours.black)
      write("> " .. opt .. string.rep(" ", boxWidth - #opt - 3))
    else
      term.setBackgroundColor(colours.black)
      term.setTextColour(colours.lime)
      write("  " .. opt .. string.rep(" ", boxWidth - #opt - 2))
    end
  end

  term.setBackgroundColor(colours.black)
  term.setTextColour(colours.lime)
  drawFooter("W/S MOVE  ENTER SELECT  Q EXIT")
end

local MAINFRAME_URL = "https://raw.githubusercontent.com/calebic/icytek/refs/heads/main/Mainframe/startup.lua"
local TERMINAL_URL = "https://raw.githubusercontent.com/calebic/icytek/refs/heads/main/Computer%20Terminal/startup.lua"
local WIRELESS_URL = "https://raw.githubusercontent.com/calebic/icytek/refs/heads/main/Wireless%20Terminal/startup.lua"
local CONTROLLER_URL = "https://raw.githubusercontent.com/calebic/icytek/refs/heads/main/Controller/startup.lua"

local function installMainframe()
  if fs.exists("pairing.txt") then
    fs.delete("pairing.txt")
  end
  return shell.run("wget", MAINFRAME_URL, "startup.lua")
end

local function installClient()
  local mf = tonumber(promptLine("Mainframe ID [18]: ", "18"))
  if not shell.run("wget", TERMINAL_URL, "startup.lua") then
    return false
  end
  local requireLogin = promptLine("Require login each boot? (y/n): ", "y")
  local cfg = {
    mainframeId = mf,
    requireLogin = (requireLogin:lower() ~= "n")
  }
  writeConfig("tekos.cfg", cfg)
  return true
end

local function installPocket()
  if not shell.run("wget", WIRELESS_URL, "startup.lua") then
    return false
  end
  local id = tonumber(promptLine("Mainframe ID [18]: ", "18"))
  local cfg = { mainframeId = id }
  writeConfig("tekos.cfg", cfg)
  return true
end

local function installController()
  if not shell.run("wget", CONTROLLER_URL, "startup.lua") then
    return false
  end
  local name = promptLine("Control Name: ", "")
  local category = promptLine("Category (Doors/Lights/Machines/etc): ", "")
  local admin = promptLine("Admin Only? (y/n): ", "n")
  local mainframeId = tonumber(promptLine("Mainframe ID [18]: ", "18"))
  local function readSide(label, default)
    local valid = { back = true, bottom = true, top = true, right = true, left = true, front = true }
    while true do
      local v = promptLine(label .. " [" .. default .. "]: ", default):lower()
      if valid[v] then
        return v
      end
    end
  end
  local outputSide = readSide("Output Side", "back")
  local inputSide
  repeat
    inputSide = readSide("Input Side", "front")
  until inputSide ~= outputSide
  local cfg = {
    id = os.getComputerID(),
    name = name,
    category = category,
    adminOnly = (admin:lower() == "y" or admin:lower() == "yes"),
    mainframeId = mainframeId,
    outputSide = outputSide,
    inputSide = inputSide
  }
  writeConfig("controller.cfg", cfg)
  return true
end

local options = {
  "Install Mainframe",
  "Install Terminal Computer",
  "Install Terminal Wireless",
  "Install Controller",
  "Exit"
}

local selected = 1
bootSplash()
while true do
  drawMenu(options, selected)
  flicker()
  local _, key = os.pullEvent("key")
  if key == keys.w then
    selected = selected - 1
    if selected < 1 then selected = #options end
  elseif key == keys.s then
    selected = selected + 1
    if selected > #options then selected = 1 end
  elseif key == keys.q then
    term.clear()
    return
  elseif key == keys.enter or key == keys.numPadEnter then
    if options[selected] == "Exit" then
      term.clear()
      return
    end

    local base
    term.clear()
    printCentered("INSTALLING...")

    local ok = false
    if selected == 1 then
      ok = installMainframe()
    elseif selected == 2 then
      ok = installClient()
    elseif selected == 3 then
      ok = installPocket()
    elseif selected == 4 then
      ok = installController()
    end

    term.clear()
    if ok then
      printCentered("INSTALL COMPLETE")
      printCentered("REBOOTING...")
      sleep(1)
      os.reboot()
    else
      printCentered("INSTALL FAILED")
      sleep(2)
    end
  end
end
