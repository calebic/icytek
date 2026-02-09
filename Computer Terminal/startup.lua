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
local tabs = { "MAIN", "CTRL", "DATA", "MUSIC" }
local currentTab = 1
local selection = 1
local ctrlPage = "root"
local controllerCache = {}
local drawTabs
local drawFooter
local width, height = term.getSize()

-- MUSIC: embedded player state
local music = {
  enabled = true,
  api_base_url = "https://ipod-2to6magyna-uc.a.run.app/",
  version = "2.1",
  tab = 1,
  waiting_for_input = false,
  last_search = nil,
  last_search_url = nil,
  search_results = nil,
  search_error = false,
  in_search_result = false,
  clicked_result = nil,
  playing = false,
  queue = {},
  now_playing = nil,
  looping = 0,
  volume = 1.5,
  playing_id = nil,
  last_download_url = nil,
  playing_status = 0,
  is_loading = false,
  is_error = false,
  player_handle = nil,
  start = nil,
  size = nil,
  decoder = require "cc.audio.dfpwm".make_decoder(),
  needs_next_chunk = 0,
  buffer = nil,
  speakers = { peripheral.find("speaker") },
  inputCursor = 0,
  inputText = "",
}

if #music.speakers == 0 then
  music.enabled = false
end

local function musicQueueRedraw()
  os.queueEvent("music_redraw")
end

local function musicDrawHeader()
  term.setCursorPos(1, 3)
  term.clearLine()
  printCentered("MUSIC")
end

local function musicDrawNowPlaying()
  local statusY = height - 2
  local subY = height - 3
  local controlsY = height - 4
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.lightGrey)
  term.setCursorPos(1, subY)
  term.clearLine()
  term.setCursorPos(1, statusY)
  term.clearLine()

  if music.now_playing ~= nil then
    term.setTextColor(colours.lime)
    term.setCursorPos(2, statusY)
    term.write(music.now_playing.name)
    term.setTextColor(colours.lightGrey)
    term.setCursorPos(2, subY)
    term.write(music.now_playing.artist)
  else
    term.setTextColor(colours.lightGrey)
    term.setCursorPos(2, statusY)
    term.write("NO MEDIA LOADED")
  end

  if music.is_loading == true then
    term.setTextColor(colours.lightGrey)
    term.setBackgroundColor(colours.black)
    term.setCursorPos(2, subY)
    term.write("Loading...")
  elseif music.is_error == true then
    term.setTextColor(colours.red)
    term.setBackgroundColor(colours.black)
    term.setCursorPos(2, subY)
    term.write("Network error")
  end

  -- Controls + volume row (anchored above status)
  term.setTextColor(colours.lime)
  term.setBackgroundColor(colours.black)
  term.setCursorPos(2, controlsY)
  if music.playing then
    term.setBackgroundColor(colours.lime)
    term.setTextColor(colours.black)
    term.write(" Stop ")
  else
    if music.now_playing ~= nil or #music.queue > 0 then
      term.setTextColor(colours.lime)
      term.setBackgroundColor(colours.black)
    else
      term.setTextColor(colours.lightGrey)
      term.setBackgroundColor(colours.black)
    end
    term.write(" Play ")
  end

  term.setTextColor(colours.lime)
  term.setBackgroundColor(colours.black)
  term.setCursorPos(2 + 7, controlsY)
  term.write(" Skip ")

  if music.looping ~= 0 then
    term.setTextColor(colours.black)
    term.setBackgroundColor(colours.lime)
  else
    term.setTextColor(colours.lime)
    term.setBackgroundColor(colours.black)
  end
  term.setCursorPos(2 + 7 + 7, controlsY)
  term.write(" Loop ")

  local sliderStart = 2 + 7 + 7 + 7
  local maxSlider = math.max(8, math.min(18, width - sliderStart - 6))
  local sliderEnd = sliderStart + maxSlider - 1
  music.sliderStart = sliderStart
  music.sliderEnd = sliderEnd

  if sliderEnd < width - 2 then
    paintutils.drawFilledBox(sliderStart, controlsY, sliderEnd, controlsY, colours.lightGrey)
    local filled = math.floor(maxSlider * (music.volume / 3) + 0.5)
    if filled > 0 then
      paintutils.drawFilledBox(sliderStart, controlsY, sliderStart + filled - 1, controlsY, colours.lime)
    end
    local pct = math.floor(100 * (music.volume / 3) + 0.5) .. "%"
    local pctX = math.min(width - #pct + 1, sliderEnd + 2)
    term.setCursorPos(pctX, controlsY)
    term.setBackgroundColor(colours.black)
    term.setTextColor(colours.lime)
    term.write(pct)
  end
end

local function musicDrawSearch()
  local searchW = math.min(24, math.max(12, width - 4))
  local searchX = 2
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.lime)
  term.setCursorPos(searchX - 2, 4)
  term.write(">")
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.lime)
  term.setCursorPos(searchX, 4)
  if music.waiting_for_input then
    term.write(music.inputText)
    term.setCursorPos(searchX + music.inputCursor, 4)
    term.setCursorBlink(true)
  else
    term.setCursorBlink(false)
    if music.last_search and music.last_search ~= "" then
      term.write(music.last_search)
    elseif music.blinkOn then
      term.write("_")
    end
  end

  local listStart = 7
  for y = listStart, height - 6 do
    term.setCursorPos(1, y)
    term.setBackgroundColor(colours.black)
    term.clearLine()
  end

  if music.search_results ~= nil then
    for i = 1, #music.search_results do
      term.setTextColor(colours.lime)
      term.setCursorPos(2, listStart + (i - 1) * 2)
      term.write(music.search_results[i].name)
      term.setTextColor(colours.lightGrey)
      term.setCursorPos(2, listStart + 1 + (i - 1) * 2)
      term.write(music.search_results[i].artist)
    end
  elseif #music.queue > 0 then
    for i = 1, #music.queue do
      term.setTextColor(colours.lime)
      term.setCursorPos(2, listStart + (i - 1) * 2)
      term.write(music.queue[i].name)
      term.setTextColor(colours.lightGrey)
      term.setCursorPos(2, listStart + 1 + (i - 1) * 2)
      term.write(music.queue[i].artist)
    end
  else
    term.setCursorPos(2, listStart)
    term.setBackgroundColor(colours.black)
    if music.search_error == true then
      term.setTextColor(colours.red)
      term.write("Network error")
    elseif music.last_search_url ~= nil then
      term.setTextColor(colours.lightGrey)
      term.write("Searching...")
    end
  end

  if music.in_search_result == true then
    term.setBackgroundColor(colours.black)
    for y = listStart, height - 6 do
      term.setCursorPos(1, y)
      term.clearLine()
    end
    term.setCursorPos(2, listStart)
    term.setTextColor(colours.lime)
    term.write(music.search_results[music.clicked_result].name)
    term.setCursorPos(2, listStart + 1)
    term.setTextColor(colours.lightGrey)
    term.write(music.search_results[music.clicked_result].artist)

    term.setBackgroundColor(colours.black)
    term.setTextColor(colours.lime)

    term.setCursorPos(2, listStart + 3)
    term.clearLine()
    term.write("Play now")

    term.setCursorPos(2, listStart + 5)
    term.clearLine()
    term.write("Play next")

    term.setCursorPos(2, listStart + 7)
    term.clearLine()
    term.write("Add to queue")

    term.setCursorPos(2, listStart + 9)
    term.clearLine()
    term.write("Cancel")
  end
end

local function musicRedraw()
  if currentTab ~= 4 then
    return
  end
  width, height = term.getSize()
  term.setCursorBlink(false)
  term.setBackgroundColor(colours.black)
  term.clear()
  drawTabs()
  musicDrawHeader()
  musicDrawNowPlaying()
  musicDrawSearch()
  drawFooter()
end

local function musicHandleClick(button, x, y)
  if button ~= 1 then return end
  if music.in_search_result == false then
    local searchW = math.min(24, math.max(12, width - 4))
    local searchX = 2
    if y == 4 and x >= searchX and x <= searchX + searchW - 1 then
      music.waiting_for_input = true
      music.inputText = ""
      music.inputCursor = 0
      musicRedraw()
      return
    end

    if music.search_results then
      for i = 1, #music.search_results do
        local listStart = 7
        if y == listStart + (i - 1) * 2 or y == listStart + 1 + (i - 1) * 2 then
          term.setBackgroundColor(colors.white)
          term.setTextColor(colors.black)
          term.setCursorPos(2, listStart + (i - 1) * 2)
          term.clearLine()
          term.write(music.search_results[i].name)
          term.setTextColor(colors.gray)
          term.setCursorPos(2, listStart + 1 + (i - 1) * 2)
          term.clearLine()
          term.write(music.search_results[i].artist)
          sleep(0.2)
          music.in_search_result = true
          music.clicked_result = i
          musicRedraw()
        end
      end
    end
  elseif music.in_search_result == true then
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)

    local listStart = 7
    if y == listStart + 3 then
      term.setCursorPos(2, listStart + 3)
      term.clearLine()
      term.write("Play now")
      sleep(0.2)
      local selected = music.search_results and music.search_results[music.clicked_result]
      music.in_search_result = false
      music.last_search = nil
      music.last_search_url = nil
      music.search_results = nil
      music.search_error = false
      music.waiting_for_input = false
      music.inputText = ""
      music.inputCursor = 0
      for _, speaker in ipairs(music.speakers) do
        speaker.stop()
        os.queueEvent("playback_stopped")
      end
      music.playing = true
      music.is_error = false
      music.playing_id = nil
      if selected and selected.type == "playlist" then
        music.now_playing = selected.playlist_items[1]
        music.queue = {}
        if #selected.playlist_items > 1 then
          for i = 2, #selected.playlist_items do
            table.insert(music.queue, selected.playlist_items[i])
          end
        end
      else
        music.now_playing = selected
      end
      os.queueEvent("audio_update")
    end

    if y == listStart + 5 then
      term.setCursorPos(2, listStart + 5)
      term.clearLine()
      term.write("Play next")
      sleep(0.2)
      music.in_search_result = false
      if music.search_results[music.clicked_result].type == "playlist" then
        for i = #music.search_results[music.clicked_result].playlist_items, 1, -1 do
          table.insert(music.queue, 1, music.search_results[music.clicked_result].playlist_items[i])
        end
      else
        table.insert(music.queue, 1, music.search_results[music.clicked_result])
      end
      os.queueEvent("audio_update")
    end

    if y == listStart + 7 then
      term.setCursorPos(2, listStart + 7)
      term.clearLine()
      term.write("Add to queue")
      sleep(0.2)
      music.in_search_result = false
      if music.search_results[music.clicked_result].type == "playlist" then
        for i = 1, #music.search_results[music.clicked_result].playlist_items do
          table.insert(music.queue, music.search_results[music.clicked_result].playlist_items[i])
        end
      else
        table.insert(music.queue, music.search_results[music.clicked_result])
      end
      os.queueEvent("audio_update")
    end

    if y == listStart + 9 then
      term.setCursorPos(2, listStart + 9)
      term.clearLine()
      term.write("Cancel")
      sleep(0.2)
      music.in_search_result = false
    end

    musicRedraw()
  elseif music.in_search_result == false then
    local controlsY = height - 4
    if y == controlsY then
      if x >= 2 and x < 2 + 6 then
        if music.playing or music.now_playing ~= nil or #music.queue > 0 then
          term.setBackgroundColor(colors.white)
          term.setTextColor(colors.black)
          term.setCursorPos(2, 9)
          if music.playing then
            term.write(" Stop ")
          else
            term.write(" Play ")
          end
          sleep(0.2)
        end
        if music.playing then
          music.playing = false
          for _, speaker in ipairs(music.speakers) do
            speaker.stop()
            os.queueEvent("playback_stopped")
          end
          music.playing_id = nil
          music.is_loading = false
          music.is_error = false
          os.queueEvent("audio_update")
        elseif music.now_playing ~= nil then
          music.playing_id = nil
          music.playing = true
          music.is_error = false
          os.queueEvent("audio_update")
        elseif #music.queue > 0 then
          music.now_playing = music.queue[1]
          table.remove(music.queue, 1)
          music.playing_id = nil
          music.playing = true
          music.is_error = false
          os.queueEvent("audio_update")
        end
      end

      if x >= 2 + 7 and x < 2 + 7 + 6 then
        if music.now_playing ~= nil or #music.queue > 0 then
          term.setBackgroundColor(colors.white)
          term.setTextColor(colors.black)
          term.setCursorPos(2 + 7, 9)
          term.write(" Skip ")
          sleep(0.2)

          music.is_error = false
          if music.playing then
            for _, speaker in ipairs(music.speakers) do
              speaker.stop()
              os.queueEvent("playback_stopped")
            end
          end
          if #music.queue > 0 then
            if music.looping == 1 then
              table.insert(music.queue, music.now_playing)
            end
            music.now_playing = music.queue[1]
            table.remove(music.queue, 1)
            music.playing_id = nil
          else
            music.now_playing = nil
            music.playing = false
            music.is_loading = false
            music.is_error = false
            music.playing_id = nil
          end
          os.queueEvent("audio_update")
        end
      end

      if x >= 2 + 7 + 7 and x < 2 + 7 + 7 + 6 then
        if music.looping == 0 then
          music.looping = 1
        elseif music.looping == 1 then
          music.looping = 2
        else
          music.looping = 0
        end
      end
    end

    if y == controlsY and music.sliderStart and music.sliderEnd then
      if x >= music.sliderStart and x <= music.sliderEnd then
        local span = math.max(1, music.sliderEnd - music.sliderStart + 1)
        music.volume = (x - music.sliderStart) / span * 3
      end
    end

    musicRedraw()
  end
end

local function musicHandleDrag(button, x, y)
  if button ~= 1 then return end
  if music.in_search_result == false then
    local controlsY = height - 4
    if y == controlsY and music.sliderStart and music.sliderEnd then
      if x >= music.sliderStart and x <= music.sliderEnd then
        local span = math.max(1, music.sliderEnd - music.sliderStart + 1)
        music.volume = (x - music.sliderStart) / span * 3
      end
      musicRedraw()
    end
  end
end

local function musicHandleSearchKey(key)
  if not music.waiting_for_input then return false end
  if key == keys.enter or key == keys.numPadEnter then
    local input = music.inputText
    if string.len(input) > 0 then
      music.last_search = input
      music.last_search_url = music.api_base_url .. "?v=" .. music.version .. "&search=" .. textutils.urlEncode(input)
      http.request(music.last_search_url)
      music.search_results = nil
      music.search_error = false
    else
      music.last_search = nil
      music.last_search_url = nil
      music.search_results = nil
      music.search_error = false
    end
    music.waiting_for_input = false
    term.setCursorBlink(false)
    musicRedraw()
    return true
  elseif key == keys.backspace then
    if music.inputCursor > 0 then
      local left = music.inputText:sub(1, music.inputCursor - 1)
      local right = music.inputText:sub(music.inputCursor + 1)
      music.inputText = left .. right
      music.inputCursor = music.inputCursor - 1
      musicRedraw()
    end
    return true
  elseif key == keys.left then
    if music.inputCursor > 0 then
      music.inputCursor = music.inputCursor - 1
      musicRedraw()
    end
    return true
  elseif key == keys.right then
    if music.inputCursor < #music.inputText then
      music.inputCursor = music.inputCursor + 1
      musicRedraw()
    end
    return true
  end
  return false
end

local function musicHandleChar(ch)
  if not music.waiting_for_input then return false end
  local left = music.inputText:sub(1, music.inputCursor)
  local right = music.inputText:sub(music.inputCursor + 1)
  music.inputText = left .. ch .. right
  music.inputCursor = music.inputCursor + 1
  musicRedraw()
  return true
end

local function musicAudioLoop()
  while true do
    if not music.enabled then
      os.pullEvent("audio_update")
    end
    if music.playing and music.now_playing then
      local thisnowplayingid = music.now_playing.id
      if music.playing_id ~= thisnowplayingid then
        music.playing_id = thisnowplayingid
        music.last_download_url = music.api_base_url .. "?v=" .. music.version .. "&id=" .. textutils.urlEncode(music.playing_id)
        music.playing_status = 0
        music.needs_next_chunk = 1

        http.request({ url = music.last_download_url, binary = true })
        music.is_loading = true

        musicQueueRedraw()
        os.queueEvent("audio_update")
      elseif music.playing_status == 1 and music.needs_next_chunk == 1 then
        while true do
          local chunk = music.player_handle.read(music.size)
          if not chunk then
            if music.looping == 2 or (music.looping == 1 and #music.queue == 0) then
              music.playing_id = nil
            elseif music.looping == 1 and #music.queue > 0 then
              table.insert(music.queue, music.now_playing)
              music.now_playing = music.queue[1]
              table.remove(music.queue, 1)
              music.playing_id = nil
            else
              if #music.queue > 0 then
                music.now_playing = music.queue[1]
                table.remove(music.queue, 1)
                music.playing_id = nil
              else
                music.now_playing = nil
                music.playing = false
                music.playing_id = nil
                music.is_loading = false
                music.is_error = false
              end
            end

            musicQueueRedraw()
            music.player_handle.close()
            music.needs_next_chunk = 0
            break
          else
            if music.start then
              chunk, music.start = music.start .. chunk, nil
              music.size = music.size + 4
            end

            music.buffer = music.decoder(chunk)
            local fn = {}
            for i, speaker in ipairs(music.speakers) do
              fn[i] = function()
                local name = peripheral.getName(speaker)
                if #music.speakers > 1 then
                  if speaker.playAudio(music.buffer, music.volume) then
                    parallel.waitForAny(
                      function()
                        repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
                      end,
                      function()
                        os.pullEvent("playback_stopped")
                        return
                      end
                    )
                    if not music.playing or music.playing_id ~= thisnowplayingid then
                      return
                    end
                  end
                else
                  while not speaker.playAudio(music.buffer, music.volume) do
                    parallel.waitForAny(
                      function()
                        repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
                      end,
                      function()
                        os.pullEvent("playback_stopped")
                        return
                      end
                    )
                    if not music.playing or music.playing_id ~= thisnowplayingid then
                      return
                    end
                  end
                end
                if not music.playing or music.playing_id ~= thisnowplayingid then
                  return
                end
              end
            end

            local ok = pcall(parallel.waitForAll, table.unpack(fn))
            if not ok then
              music.needs_next_chunk = 2
              music.is_error = true
              break
            end

            if not music.playing or music.playing_id ~= thisnowplayingid then
              break
            end
          end
        end
        os.queueEvent("audio_update")
      end
    end

    os.pullEvent("audio_update")
  end
end

local function musicHttpLoop()
  while true do
    parallel.waitForAny(
      function()
        local _, url, handle = os.pullEvent("http_success")

        if url == music.last_search_url then
          local results = textutils.unserialiseJSON(handle.readAll())
          if type(results) == "table" then
            local filtered = {}
            for i = 1, #results do
              local name = (results[i].name or ""):lower()
              local artist = (results[i].artist or ""):lower()
              if not (name:find("patreon", 1, true) or artist:find("patreon", 1, true)
                  or name:find("support", 1, true) or artist:find("support", 1, true)) then
                table.insert(filtered, results[i])
              end
            end
            results = filtered
          end
          music.search_results = results
          musicQueueRedraw()
        end
        if url == music.last_download_url then
          music.is_loading = false
          music.player_handle = handle
          music.start = handle.read(4)
          music.size = 16 * 1024 - 4
          music.playing_status = 1
          musicQueueRedraw()
          os.queueEvent("audio_update")
        end
      end,
      function()
        local _, url = os.pullEvent("http_failure")

        if url == music.last_search_url then
          music.search_error = true
          musicQueueRedraw()
        end
        if url == music.last_download_url then
          music.is_loading = false
          music.is_error = true
          music.playing = false
          music.playing_id = nil
          musicQueueRedraw()
          os.queueEvent("audio_update")
        end
      end
    )
  end
end

drawTabs = function()
  local w, _ = term.getSize()
  term.setBackgroundColor(colours.black)
  term.setTextColor(colours.lime)
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
  term.setTextColor(colours.lime)
  write(string.rep("-", w))
end

drawFooter = function()
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
  elseif tab == "MUSIC" then
    if not music.enabled then
      return { { label = "No speaker detected" } }
    end
    return { { label = "Music player ready" } }
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

local function updateControllerCache(c)
  if not c or not c.id then return end
  if c.adminOnly and not isAdmin then
    for i = #controllerCache, 1, -1 do
      if controllerCache[i].id == c.id then
        table.remove(controllerCache, i)
      end
    end
    return
  end
  for i = 1, #controllerCache do
    if controllerCache[i].id == c.id then
      controllerCache[i] = c
      return
    end
  end
  table.insert(controllerCache, c)
end

local function listener()
  while true do
    local _, msg = rednet.receive()
    if type(msg) == "table" and msg.type == "controller_status_update" then
      updateControllerCache(msg)
      drawUI()
    end
  end
end

local function inputLoop()
  refreshControllers()
  local musicBlinkTimer = nil
  while true do
    local event, p1, p2, p3 = os.pullEvent()
    if currentTab == 4 and music.enabled then
      if not musicBlinkTimer then
        musicBlinkTimer = os.startTimer(0.5)
      end
      if event == "key" then
        local key = p1
        if musicHandleSearchKey(key) then
          -- handled
        elseif not music.waiting_for_input then
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
          end
        end
      elseif event == "char" then
        musicHandleChar(p1)
      elseif event == "mouse_click" then
        musicHandleClick(p1, p2, p3)
      elseif event == "mouse_drag" then
        musicHandleDrag(p1, p2, p3)
      elseif event == "timer" and p1 == musicBlinkTimer then
        music.blinkOn = not music.blinkOn
        musicBlinkTimer = os.startTimer(0.5)
      elseif event == "music_redraw" then
        musicRedraw()
      end
      if currentTab == 4 then
        musicRedraw()
      else
        drawUI()
      end
      goto continue
    end

    if musicBlinkTimer then
      musicBlinkTimer = nil
      music.blinkOn = false
    end

    if event == "key" then
      local key = p1
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
    drawUI()
    ::continue::
  end
end

drawUI()
parallel.waitForAny(listener, inputLoop, musicAudioLoop, musicHttpLoop)
