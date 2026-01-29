-- ICEYTEK CONTROLLER NODE -- TEK-OS

-- Colours
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

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local CONFIG_FILE = "controller.cfg"
local STATE_FILE = "state.txt"
local VERSION_FILE = "controller_version.txt"
local DEFAULT_VERSION = "0.0.0.0"
local DEFAULT_MAINFRAME_ID = nil
local REDSTONE_SIDE = "back"

local function readVersion()
  if fs.exists(VERSION_FILE) then
    local f = fs.open(VERSION_FILE, "r")
    local v = f.readAll()
    f.close()
    if v and v ~= "" then
      return v
    end
  end
  return DEFAULT_VERSION
end

local function writeVersion(v)
  local f = fs.open(VERSION_FILE, "w")
  f.write(v)
  f.close()
end

local VERSION = readVersion()
writeVersion(VERSION)

-- Boot splash (controller)
textutils.slowPrint("^^^^TEK-OS(R) CONTROL NODE^^^^")
print("")
print("")
os.sleep(0.2)
textutils.slowPrint("COPYRIGHT 2025 ICEYTEK(R)")
os.sleep(0.2)
textutils.slowPrint("CONTROL BUS ONLINE")
os.sleep(0.2)
textutils.slowPrint("EXEC VERSION 41.10")
os.sleep(0.2)
write(fs.getFreeSpace("/") .. " ")
textutils.slowPrint("BYTES FREE")
os.sleep(0.2)
textutils.slowPrint("LOAD ROM(C): DEITRIX 303")

for i = 1, 6 do
  print("")
  os.sleep(0.05)
end

-- Open modem (lock until detected)
local function waitForModem()
  while true do
    for _, s in ipairs(rs.getSides()) do
      if peripheral.getType(s) == "modem" then
        rednet.open(s)
        return true
      end
    end
    term.clear()
    term.setCursorPos(1, 2)
    term.setTextColor(colors.red)
    printCentered("SECURITY LOCKOUT")
    term.setTextColor(colours.lime)
    printCentered("NO MODEM DETECTED")
    printCentered("CONNECT A MODEM TO CONTINUE")
    sleep(1)
  end
end

waitForModem()

local function readConfig()
  if fs.exists(CONFIG_FILE) then
    local f = fs.open(CONFIG_FILE, "r")
    local raw = f.readAll()
    f.close()
    local t = textutils.unserialize(raw)
    if type(t) == "table" then
      return t
    end
  end
  return nil
end

local function writeConfig(cfg)
  local f = fs.open(CONFIG_FILE, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

local function setupWizard()
  term.clear()
  term.setCursorPos(1, 2)
  printCentered("CONTROL SETUP")
  print("")
  write("Control Name: ")
  local name = trim(read())
  write("Category (Doors/Lights/Machines/etc): ")
  local category = trim(read())
  write("Admin Only? (y/n): ")
  local a = trim(read()):lower()
  local adminOnly = (a == "y" or a == "yes")
  local mainframeId
  while not mainframeId do
    write("Mainframe ID: ")
    local m = trim(read())
    mainframeId = tonumber(m)
  end
  local cfg = {
    id = os.getComputerID(),
    name = name,
    category = category,
    adminOnly = adminOnly,
    mainframeId = mainframeId
  }
  writeConfig(cfg)
  return cfg
end

local cfg = readConfig()
if not cfg then
  cfg = setupWizard()
end
if not cfg.mainframeId then
  cfg.mainframeId = setupWizard().mainframeId
end

local MAINFRAME_ID = cfg.mainframeId

local function readState()
  if fs.exists(STATE_FILE) then
    local f = fs.open(STATE_FILE, "r")
    local v = f.readAll()
    f.close()
    return v == "1"
  end
  return false
end

local function writeState(state)
  local f = fs.open(STATE_FILE, "w")
  f.write(state and "1" or "0")
  f.close()
end

local active = readState()
redstone.setOutput(REDSTONE_SIDE, active)

local function register()
  rednet.send(cfg.mainframeId, {
    type = "controller_register",
    id = cfg.id,
    name = cfg.name,
    category = cfg.category,
    adminOnly = cfg.adminOnly,
    active = active
  })
end

local function sendStatus()
  rednet.send(cfg.mainframeId, {
    type = "controller_status",
    id = cfg.id,
    name = cfg.name,
    category = cfg.category,
    adminOnly = cfg.adminOnly,
    active = active
  })
end

local function checkForUpdate()
  rednet.send(cfg.mainframeId, { type = "controller_version_check", version = VERSION })
  local _, reply = rednet.receive(3)
  if type(reply) ~= "table" or reply.type ~= "controller_version_info" then
    return
  end
  if reply.version ~= VERSION then
    rednet.send(cfg.mainframeId, { type = "controller_update_request" })
    local _, payload = rednet.receive(5)
    if type(payload) == "table" and payload.type == "controller_update_payload" and payload.content then
      local f = fs.open("startup.lua", "w")
      f.write(payload.content)
      f.close()
      writeVersion(payload.version or reply.version)
      os.reboot()
    end
  end
end

checkForUpdate()
register()

local lastHeartbeat = os.clock()

while true do
  local id, msg = rednet.receive(1)
  if type(msg) == "table" then
    if msg.type == "controller_set" then
      active = not not msg.state
      redstone.setOutput(REDSTONE_SIDE, active)
      writeState(active)
      sendStatus()
    elseif msg.type == "controller_toggle" then
      active = not active
      redstone.setOutput(REDSTONE_SIDE, active)
      writeState(active)
      sendStatus()
    elseif msg.type == "controller_status_request" then
      sendStatus()
    end
  end

  if os.clock() - lastHeartbeat > 30 then
    sendStatus()
    lastHeartbeat = os.clock()
  end
end
