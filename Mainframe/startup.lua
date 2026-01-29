-- ICEYTEK MAINFRAME -- TEK-OS

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

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Versioning
local VERSION_FILE = "version.txt"
local CONTROLLER_VERSION_FILE = "controller_version.txt"
local DEFAULT_VERSION = "3.2.0.0"

local function readVersion(path)
  if fs.exists(path) then
    local f = fs.open(path, "r")
    local v = f.readAll()
    f.close()
    if v and v ~= "" then
      return v
    end
  end
  return DEFAULT_VERSION
end

local function writeVersion(path, v)
  local f = fs.open(path, "w")
  f.write(v)
  f.close()
end

local function bumpVersion(v)
  local a, b, c, d = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then
    return v
  end
  d = tostring(tonumber(d) + 1)
  return table.concat({ a, b, c, d }, ".")
end

local VERSION = readVersion(VERSION_FILE)
writeVersion(VERSION_FILE, VERSION)

local CONTROLLER_VERSION = readVersion(CONTROLLER_VERSION_FILE)
writeVersion(CONTROLLER_VERSION_FILE, CONTROLLER_VERSION)

-- Boot splash (mainframe)
textutils.slowPrint("^^^^TEK-OS(R) V" .. VERSION .. "^^^^")
print("")
print("")
os.sleep(0.2)
textutils.slowPrint("COPYRIGHT 2025 ICEYTEK(R)")
os.sleep(0.2)
textutils.slowPrint("MAINFRAME LOADER V2.1")
os.sleep(0.2)
textutils.slowPrint("EXEC VERSION 41.10")
os.sleep(0.2)
textutils.slowPrint("CORE BUS ONLINE")
os.sleep(0.2)
write(fs.getFreeSpace("/") .. " ")
textutils.slowPrint("BYTES FREE")
os.sleep(0.2)
textutils.slowPrint("SECURE REDNET STACK")
os.sleep(0.2)
textutils.slowPrint("LOAD ROM(0): DEITRIX 303")

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
print("Initializing mainframe...")
scroll() scroll()
os.sleep(1)

for i = 1, 10 do
  print("")
  os.sleep(0.05)
end

-- Username (admin)
local username
if fs.exists("user.txt") then
  local f = fs.open("user.txt", "r")
  username = f.readAll()
  f.close()
else
  write("Enter Admin User: ")
  username = read()
  local f = fs.open("user.txt", "w")
  f.write(username)
  f.close()
  os.reboot()
end
username = trim(username)

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

-- Logs
local logLines = {}
local function logLine(s)
  table.insert(logLines, os.date("%H:%M:%S") .. " " .. s)
  if #logLines > 50 then
    table.remove(logLines, 1)
  end
end

-- Users
local users = {}
local function addUser(name)
  if not name or name == "" then return end
  if not users[name] then
    users[name] = { lastSeen = os.date("%H:%M:%S") }
    logLine("User registered: " .. name)
  else
    users[name].lastSeen = os.date("%H:%M:%S")
  end
end

-- Controllers
local CONTROLLERS_FILE = "controllers.txt"
local controllers = {}

local function saveControllers()
  local f = fs.open(CONTROLLERS_FILE, "w")
  f.write(textutils.serialize(controllers))
  f.close()
end

local function broadcastControllerUpdate(c)
  if not c then return end
  rednet.broadcast({
    type = "controller_status_update",
    id = c.id,
    name = c.name,
    category = c.category,
    adminOnly = c.adminOnly,
    active = c.active
  })
end

local function loadControllers()
  if fs.exists(CONTROLLERS_FILE) then
    local f = fs.open(CONTROLLERS_FILE, "r")
    local raw = f.readAll()
    f.close()
    local t = textutils.unserialize(raw)
    if type(t) == "table" then
      controllers = t
    end
  end
end

local function upsertController(c)
  if not c or not c.id then return end
  controllers[c.id] = controllers[c.id] or {}
  for k, v in pairs(c) do
    controllers[c.id][k] = v
  end
  controllers[c.id].lastSeen = os.date("%H:%M:%S")
  saveControllers()
  broadcastControllerUpdate(controllers[c.id])
end

local function requestControllerStatus()
  for id, _ in pairs(controllers) do
    rednet.send(id, { type = "controller_status_request" })
  end
end

local function listControllers(isAdmin)
  local list = {}
  for _, c in pairs(controllers) do
    if isAdmin or not c.adminOnly then
      table.insert(list, {
        id = c.id,
        name = c.name,
        category = c.category,
        adminOnly = c.adminOnly,
        active = c.active
      })
    end
  end
  table.sort(list, function(a, b)
    if a.category == b.category then
      return a.name < b.name
    end
    return a.category < b.category
  end)
  return list
end

loadControllers()

-- Permissions table
local baseCommands = { "status", "whoami", "message" }
local adminCommands = { "status", "whoami", "message" }

-- UI state
local tabs = { "LOGS", "CTRL", "USERS" }
local currentTab = 1
local selection = 1
local ctrlPage = "root"

local function drawTabs()
  local w, _ = term.getSize()
  term.setCursorPos(1, 1)
  term.clearLine()
  term.setCursorPos(1, 1)
  write("<A> ")
  local line = ""
  for i, t in ipairs(tabs) do
    if i == currentTab then
      line = line .. "[" .. t .. "] "
    else
      line = line .. t .. " "
    end
  end
  write(line)
  write("<D>")
  local hint = "[U] UPDATE  [R] REFRESH"
  term.setCursorPos(w - #hint + 1, 1)
  write(hint)

  term.setCursorPos(1, 2)
  term.clearLine()
  write(string.rep("-", w))
end

local function drawFooter()
  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.clearLine()
  local left = "ICYTEK  ID:" .. os.getComputerID()
  local right = "V" .. VERSION .. "  USER: " .. username
  term.setCursorPos(1, h)
  write(left)
  term.setCursorPos(w - #right + 1, h)
  write(right)
end

local function getMenuItems()
  local tab = tabs[currentTab]
  if tab == "LOGS" then
    local items = {}
    if #logLines == 0 then
      table.insert(items, { label = "No logs yet" })
    else
      local start = math.max(1, #logLines - 6)
      for i = start, #logLines do
        table.insert(items, { label = logLines[i] })
      end
    end
    return items
  elseif tab == "USERS" then
    local items = {
      { label = "Admin: " .. username },
    }
    local names = {}
    for name, _ in pairs(users) do
      table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local last = users[name].lastSeen or "--:--:--"
      table.insert(items, { label = name .. "  (" .. last .. ")" })
    end
    table.insert(items, { label = "Total Users: " .. tostring(#names) })
    return items
  elseif tab == "CTRL" then
    if ctrlPage == "root" then
      local categories = {}
      for _, c in pairs(controllers) do
        categories[c.category or "Unsorted"] = true
      end
      local items = {}
      local list = {}
      for name, _ in pairs(categories) do
        table.insert(list, name)
      end
      table.sort(list)
      for _, name in ipairs(list) do
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
      local adminList = {}
      local normalList = {}
      for _, c in pairs(controllers) do
        if (c.category or "Unsorted") == ctrlPage then
          local entry = {
          label = "[" .. c.name .. "]",
          status = c.active and "ACTIVE" or "INACTIVE",
          action = function()
            c.active = not c.active
            saveControllers()
            rednet.send(c.id, { type = "controller_set", state = c.active })
            logLine("Toggle sent to " .. c.name)
            broadcastControllerUpdate(c)
          end
        }
          if c.adminOnly then
            table.insert(adminList, entry)
          else
            table.insert(normalList, entry)
          end
        end
      end
      if #adminList > 0 then
        table.insert(items, { label = "-- ADMIN CONTROLS --" })
        for _, v in ipairs(adminList) do
          table.insert(items, v)
        end
        table.insert(items, { label = "--------------------" })
      end
      for _, v in ipairs(normalList) do
        table.insert(items, v)
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

local function drawUI()
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

local function handleString(id, msg)
  local key = msg:match("%[(.-)%] handshake")
  if key then
    local stationUser = key:match("^Station:(.+)$")
    if stationUser then
      stationUser = trim(stationUser)
      addUser(stationUser)
      local isAdmin = (stationUser == username)
      local perms = isAdmin and adminCommands or baseCommands
      rednet.send(id, textutils.serialize({
        type = "permissions",
        commands = perms,
        isAdmin = isAdmin
      }))
      logLine("Handshake: " .. stationUser)
    else
      rednet.send(id, textutils.serialize({
        type = "denied",
        reason = "Unauthorized terminal"
      }))
      logLine("Handshake denied")
    end
  end

  local lower = msg:lower()
  if lower:find("status") then
    rednet.send(id, "System online. ICEYTEK Mainframe operational.")
  elseif lower:find("who am i") then
    rednet.send(id, "You are registered as " .. (msg:match("%[(.-)%]") or "UNKNOWN"))
  end
end

local function handleTable(id, msg)
  if msg.type == "version_check" then
    rednet.send(id, { type = "version_info", version = VERSION })
  elseif msg.type == "admin_check" then
    if trim(msg.user or "") == username then
      addUser(username)
      rednet.send(id, { type = "admin_ok", user = username })
    else
      rednet.send(id, { type = "admin_denied" })
    end
  elseif msg.type == "update_request" then
    if not fs.exists("updatedstartup.lua") then
      rednet.send(id, { type = "error", reason = "Missing updatedstartup.lua" })
      logLine("Update request failed (missing updatedstartup.lua)")
      return
    end
    local f = fs.open("updatedstartup.lua", "r")
    local content = f.readAll()
    f.close()
    rednet.send(id, { type = "update_payload", version = VERSION, content = content })
    logLine("Update payload sent to " .. id)
  elseif msg.type == "controller_version_check" then
    rednet.send(id, { type = "controller_version_info", version = CONTROLLER_VERSION })
  elseif msg.type == "controller_update_request" then
    if not fs.exists("controller_updatedstartup.lua") then
      rednet.send(id, { type = "error", reason = "Missing controller_updatedstartup.lua" })
      logLine("Controller update failed (missing controller_updatedstartup.lua)")
      return
    end
    local f = fs.open("controller_updatedstartup.lua", "r")
    local content = f.readAll()
    f.close()
    rednet.send(id, { type = "controller_update_payload", version = CONTROLLER_VERSION, content = content })
    logLine("Controller update payload sent to " .. id)
  elseif msg.type == "controller_register" or msg.type == "controller_status" then
    msg.id = msg.id or id
    upsertController(msg)
    if msg.type == "controller_register" then
      logLine("Controller registered: " .. (msg.name or "?"))
    end
  elseif msg.type == "controller_list" then
    local isAdmin = trim(msg.user or "") == username
    if msg.refresh then
      requestControllerStatus()
      sleep(0.3)
    end
    rednet.send(id, { type = "controller_list", controllers = listControllers(isAdmin) })
  elseif msg.type == "controller_toggle" then
    local target
    for _, c in pairs(controllers) do
      if c.name == msg.name and (c.category or "Unsorted") == msg.category then
        target = c
        break
      end
    end
    if target then
      target.active = not target.active
      saveControllers()
      rednet.send(target.id, { type = "controller_toggle" })
      logLine("Toggle sent: " .. target.name)
      broadcastControllerUpdate(target)
      rednet.send(id, { type = "ok", message = "Command sent" })
    else
      rednet.send(id, { type = "error", reason = "Controller not found" })
    end
  end
end

local function listener()
  while true do
    local id, msg = rednet.receive()
    if type(msg) == "string" then
      handleString(id, msg)
    elseif type(msg) == "table" then
      handleTable(id, msg)
    end
  end
end

local function inputLoop()
  drawUI()
  while true do
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
    elseif key == keys.u then
      VERSION = bumpVersion(VERSION)
      writeVersion(VERSION_FILE, VERSION)
      CONTROLLER_VERSION = bumpVersion(CONTROLLER_VERSION)
      writeVersion(CONTROLLER_VERSION_FILE, CONTROLLER_VERSION)
    elseif key == keys.r then
      requestControllerStatus()
    end

    drawUI()
  end
end

parallel.waitForAny(listener, inputLoop)
