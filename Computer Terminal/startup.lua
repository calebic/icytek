-- ICEYTEK STATION TERMINAL -- TEK-OS

-- Colours
term.setPaletteColour(colours.black, 0x000F1C)
term.setPaletteColour(colours.lime, 0x0DDA85)
term.setBackgroundColor(colours.black)
term.setTextColour(colours.lime)
shell.run("clear")

-- Centered print
local function printCentered(text)
  local w, _ = term.getSize()
  term.setCursorPos(math.floor((w - #text) / 2) + 1, select(2, term.getCursorPos()))
  print(text)
end

-- Versioning
local VERSION_FILE = "version.txt"
local DEFAULT_VERSION = "0.0.0.0"
local CONFIG_FILE = "tekos.cfg"

local function loadConfig()
  if fs.exists(CONFIG_FILE) then
    local f = fs.open(CONFIG_FILE, "r")
    local raw = f.readAll()
    f.close()
    local t = textutils.unserialize(raw)
    if type(t) == "table" then
      return t
    end
  end
  return {}
end

local cfg = loadConfig()

local function writeTekosConfig(mainframeId, requireLogin)
  local f = fs.open(CONFIG_FILE, "w")
  f.write(textutils.serialize({
    mainframeId = mainframeId,
    requireLogin = requireLogin
  }))
  f.close()
end

if not cfg.mainframeId then
  textutils.slowPrint("^^^^TEK-OS(R) SETUP^^^^")
  write("Mainframe ID: ")
  local inputId = tonumber(read())
  if inputId then
    cfg.mainframeId = inputId
  end
  if not cfg.mainframeId then
    cfg.mainframeId = 13
  end
  if cfg.requireLogin == nil then
    cfg.requireLogin = true
  end
  writeTekosConfig(cfg.mainframeId, cfg.requireLogin)
end

local MAINFRAME_ID = cfg.mainframeId or 13
local REQUIRE_LOGIN_EACH_BOOT = (cfg.requireLogin ~= false)

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

-- Username (set after update check)
local username = "GUEST"
local isAdmin = false

local function login()
  if fs.exists("user.txt") and not REQUIRE_LOGIN_EACH_BOOT then
    local f = fs.open("user.txt", "r")
    username = f.readAll()
    f.close()
  else
    textutils.slowPrint("^^^^TEK-OS(R) V" .. VERSION .. "^^^^")
    write("Enter User: ")
    username = read()
    if not REQUIRE_LOGIN_EACH_BOOT then
      local f = fs.open("user.txt", "w")
      f.write(username)
      f.close()
      os.reboot()
    end
  end
end

-- Boot splash (client)
textutils.slowPrint("^^^^TEK-OS(R) V" .. VERSION .. "^^^^")
print("")
print("")
os.sleep(0.2)
textutils.slowPrint("COPYRIGHT 2025 ICEYTEK(R)")
os.sleep(0.2)
textutils.slowPrint("LOADER V1.1")
os.sleep(0.2)
textutils.slowPrint("EXEC VERSION 41.10")
os.sleep(0.2)
textutils.slowPrint("64K RAM SYSTEM")
os.sleep(0.2)
write(fs.getFreeSpace("/") .. " ")
textutils.slowPrint("BYTES FREE")
os.sleep(0.2)
textutils.slowPrint("NO HOLOTAPE FOUND")
os.sleep(0.2)
textutils.slowPrint("LOAD ROM(1): DEITRIX 303")

local function scroll()
  os.sleep(0.05)
  print("")
  os.sleep(0.05)
  print("")
  os.sleep(0.05)
  print("")
  os.sleep(0.05)
  print("")
end

scroll() scroll() scroll() scroll()
print("Initializing...")
scroll() scroll()
os.sleep(1)

for i = 1, 10 do
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

-- Version check / update
local function checkForUpdate()
  rednet.send(MAINFRAME_ID, { type = "version_check", user = username, client_version = VERSION })
  local _, reply = rednet.receive(3)

  if type(reply) ~= "table" or reply.type ~= "version_info" then
    return false
  end

  if reply.version ~= VERSION then
    term.clear()
    term.setCursorPos(1, 2)
    printCentered("UPDATE REQUIRED")
    printCentered("LOCAL:  " .. VERSION)
    printCentered("REMOTE: " .. reply.version)

    rednet.send(MAINFRAME_ID, { type = "update_request", user = username })
    local _, payload = rednet.receive(5)

    if type(payload) == "table" and payload.type == "update_payload" and payload.content then
      local f = fs.open("startup.lua", "w")
      f.write(payload.content)
      f.close()
      writeVersion(payload.version or reply.version)
      printCentered("UPDATE APPLIED")
      sleep(1)
      os.reboot()
    else
      -- If no payload exists, just sync version to mainframe and continue.
      writeVersion(reply.version)
      VERSION = reply.version
      printCentered("VERSION SYNCED")
      sleep(1)
    end
  end

  return true
end

checkForUpdate()

login()

-- Handshake
rednet.send(MAINFRAME_ID, "[Station:" .. username .. "] handshake")
local _, reply = rednet.receive(5)

local permissions = {}
if reply then
  local data = textutils.unserialize(reply)
  if data and data.type == "permissions" then
    permissions = data.commands
    isAdmin = data.isAdmin or false
  else
    printCentered("ACCESS DENIED")
    sleep(3)
    return
  end
else
  printCentered("NO MAINFRAME RESPONSE")
  sleep(3)
  return
end

-- UI helpers
local tabs = { "MAIN", "CTRL", "DATA" }
local currentTab = 1
local selection = 1
local ctrlPage = "root"
local controllerCache = {}

local function drawTabs()
  local w, _ = term.getSize()
  term.setCursorPos(1, 1)
  term.clearLine()
  term.setCursorPos(1, 1)
  write("<A>")
  term.setCursorPos(w - 2, 1)
  write("<D>")
  local line = ""
  for i, t in ipairs(tabs) do
    if i == currentTab then
      line = line .. "[" .. t .. "] "
    else
      line = line .. t .. " "
    end
  end
  local start = math.floor((w - #line) / 2) + 1
  if start < 5 then start = 5 end
  if start + #line - 1 > w - 4 then
    start = w - #line - 3
  end
  if start < 5 then start = 5 end
  term.setCursorPos(start, 1)
  write(line)

  term.setCursorPos(1, 2)
  term.clearLine()
  write(string.rep("-", w))
end

local function drawFooter()
  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.clearLine()
  local left = "ICYTEK"
  local right = "USER: " .. username
  term.setCursorPos(1, h)
  write(left)
  term.setCursorPos(w - #right + 1, h)
  write(right)
end

local function promptInput(prompt)
  local _, h = term.getSize()
  term.setCursorPos(1, h - 1)
  term.clearLine()
  write(prompt)
  return read()
end

local function waitForReply(timeout)
  local deadline = os.clock() + timeout
  while os.clock() < deadline do
    local remaining = deadline - os.clock()
    local id, msg = rednet.receive(remaining)
    if id == MAINFRAME_ID then
      return msg
    end
  end
  return nil
end

local function showNotice(text)
  local _, h = term.getSize()
  term.clear()
  term.setCursorPos(1, math.floor(h / 2))
  printCentered(text or "No response")
  sleep(2)
end

local drawUI

local function refreshControllers()
  rednet.send(MAINFRAME_ID, { type = "controller_list", user = username, refresh = true })
  local reply = waitForReply(3)
  if type(reply) == "table" and reply.type == "controller_list" then
    controllerCache = reply.controllers or {}
  end
end

local function getCategories()
  local set = {}
  for _, c in ipairs(controllerCache) do
    set[c.category or "Unsorted"] = true
  end
  local list = {}
  for name, _ in pairs(set) do
    table.insert(list, name)
  end
  table.sort(list)
  return list
end

local function getControllersForCategory(category)
  local adminList = {}
  local normalList = {}
  for _, c in ipairs(controllerCache) do
    if (c.category or "Unsorted") == category then
      if c.adminOnly then
        table.insert(adminList, c)
      else
        table.insert(normalList, c)
      end
    end
  end
  table.sort(adminList, function(a, b) return a.name < b.name end)
  table.sort(normalList, function(a, b) return a.name < b.name end)
  return adminList, normalList
end

local function getMenuItems()
  local tab = tabs[currentTab]
  if tab == "MAIN" then
    local items = {}
    for _, cmd in ipairs(permissions) do
      if cmd == "status" then
        table.insert(items, {
          label = "[Request Status]",
          action = function()
            rednet.send(MAINFRAME_ID, "[Station:" .. username .. "] status")
            local resp = waitForReply(3)
            showNotice(resp or "No response")
          end
        })
      elseif cmd == "whoami" then
        table.insert(items, {
          label = "[Who Am I]",
          action = function()
            rednet.send(MAINFRAME_ID, "[Station:" .. username .. "] who am i")
            local resp = waitForReply(3)
            showNotice(resp or "No response")
          end
        })
      elseif cmd == "message" then
        table.insert(items, {
          label = "[Send Message]",
          action = function()
            local msg = promptInput("Message > ")
            if msg and msg ~= "" then
              rednet.send(MAINFRAME_ID, "[Station:" .. username .. "] " .. msg)
              local resp = waitForReply(3)
              showNotice(resp or "Sent")
            end
          end
        })
      end
    end
    table.insert(items, {
      label = "[Logout]",
      action = function()
        if fs.exists("user.txt") then
          fs.delete("user.txt")
        end
        showNotice("LOGGED OUT")
        os.reboot()
      end
    })
    if #items == 0 then
      table.insert(items, { label = "No permissions" })
    end
    return items
  elseif tab == "DATA" then
    return {
      { label = "Version: " .. VERSION },
      { label = "Mainframe ID: " .. MAINFRAME_ID },
    }
  elseif tab == "CTRL" then
    if ctrlPage == "root" then
      local items = {}
      local categories = getCategories()
      for _, name in ipairs(categories) do
        table.insert(items, { label = "[" .. name .. "]", action = function() ctrlPage = name; selection = 1 end })
      end
      if #items == 0 then
        table.insert(items, { label = "No controllers" })
      end
      return items
    else
      local items = {
        { label = "[Back]", action = function() ctrlPage = "root"; selection = 1 end }
      }
      local adminList, normalList = getControllersForCategory(ctrlPage)
      if isAdmin and #adminList > 0 then
        table.insert(items, { label = "-- ADMIN CONTROLS --" })
        for _, c in ipairs(adminList) do
          table.insert(items, {
            label = "[" .. c.name .. "]",
            status = c.active and "ACTIVE" or "INACTIVE",
            action = function()
              rednet.send(MAINFRAME_ID, { type = "controller_toggle", name = c.name, category = c.category, user = username })
              showNotice("Command sent")
              refreshControllers()
            sleep(0.2)
            refreshControllers()
            drawUI()
            end
          })
        end
        table.insert(items, { label = "--------------------" })
      end
      for _, c in ipairs(normalList) do
        table.insert(items, {
          label = "[" .. c.name .. "]",
          status = c.active and "ACTIVE" or "INACTIVE",
            action = function()
            rednet.send(MAINFRAME_ID, { type = "controller_toggle", name = c.name, category = c.category, user = username })
            showNotice("Command sent")
            refreshControllers()
            sleep(0.2)
            refreshControllers()
            drawUI()
          end
        })
      end
      if #adminList == 0 and #normalList == 0 then
        table.insert(items, { label = "No devices" })
      end
      return items
    end
  end
  return {}
end

local function drawMenu()
  term.setCursorPos(1, 3)
  term.clearLine()
  if tabs[currentTab] == "CTRL" and ctrlPage ~= "root" then
    printCentered(ctrlPage:upper())
  else
    printCentered(tabs[currentTab])
  end

  local items = getMenuItems()
  local startRow = 4
  local w, _ = term.getSize()

  for i = 1, 10 do
    term.setCursorPos(1, startRow + i - 1)
    term.clearLine()
  end

  for i, item in ipairs(items) do
    term.setCursorPos(2, startRow + i - 1)
    if i == selection then
      term.setBackgroundColor(colours.lime)
      term.setTextColor(colours.black)
    else
      term.setBackgroundColor(colours.black)
      term.setTextColor(colours.lime)
    end

    local label = item.label or ""
    if item.status then
      local status = item.status
      term.write(label)
      term.setCursorPos(w - #status - 1, startRow + i - 1)
      term.write(status)
    else
      term.write(label)
    end
  end

  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.lime)
end

drawUI = function()
  term.clear()
  drawTabs()
  drawMenu()
  drawFooter()
end

local function moveSelection(delta)
  local items = getMenuItems()
  if #items == 0 then
    selection = 1
    return
  end
  selection = selection + delta
  if selection < 1 then selection = #items end
  if selection > #items then selection = 1 end
end

local function activateSelection()
  local items = getMenuItems()
  local item = items[selection]
  if item and item.action then
    item.action()
  end
end

-- UI loop
refreshControllers()

while true do
  drawUI()
  local _, key = os.pullEvent("key")
  if key == keys.a then
    currentTab = currentTab - 1
    if currentTab < 1 then currentTab = #tabs end
    selection = 1
    ctrlPage = "root"
  elseif key == keys.d then
    currentTab = currentTab + 1
    if currentTab > #tabs then currentTab = 1 end
    selection = 1
    ctrlPage = "root"
  elseif key == keys.w then
    moveSelection(-1)
  elseif key == keys.s then
    moveSelection(1)
  elseif key == keys.enter or key == keys.numPadEnter then
    activateSelection()
  elseif key == keys.r then
    refreshControllers()
  end
end




