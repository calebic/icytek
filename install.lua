-- ICEYTEK INSTALLER -- TEK-OS

term.setPaletteColour(colours.black, 0x000F1C)
term.setPaletteColour(colours.lime, 0x0DDA85)
term.setBackgroundColor(colours.black)
term.setTextColour(colours.lime)
shell.run("clear")

local function printCentered(text)
  local w, _ = term.getSize()
  term.setCursorPos(math.floor((w - #text) / 2) + 1, select(2, term.getCursorPos()))
  print(text)
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
  term.setCursorPos(1, 2)
  printCentered("ICEYTEK INSTALLER")
  printCentered("TEK-OS DISTRIBUTION")
  print("")
  for i, opt in ipairs(options) do
    if i == selected then
      term.setBackgroundColor(colours.lime)
      term.setTextColour(colours.black)
    else
      term.setBackgroundColor(colours.black)
      term.setTextColour(colours.lime)
    end
    term.setCursorPos(4, 4 + i)
    write(opt)
  end
  term.setBackgroundColor(colours.black)
  term.setTextColour(colours.lime)

  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.clearLine()
  write("W/S: Move  ENTER: Select")
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
  local pair = promptLine("Pairing Code: ", "")
  while pair == "" do
    pair = promptLine("Pairing Code (required): ", "")
  end
  local cfg = {
    id = os.getComputerID(),
    name = name,
    category = category,
    adminOnly = (admin:lower() == "y" or admin:lower() == "yes"),
    mainframeId = mainframeId,
    pair = pair
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
while true do
  drawMenu(options, selected)
  local _, key = os.pullEvent("key")
  if key == keys.w then
    selected = selected - 1
    if selected < 1 then selected = #options end
  elseif key == keys.s then
    selected = selected + 1
    if selected > #options then selected = 1 end
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
