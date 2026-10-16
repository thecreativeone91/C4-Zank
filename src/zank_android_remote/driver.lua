--[[
  Zank Android Remote - open source Control4 driver
  Controls Android / AOSP TV boxes through the Zank Remote app running on the box.

  Transport (confirmed from Zank's open source desktop server):
    UDP 1028  plaintext commands, e.g. "getName", "click", "setText <t>", "volumeUp"
    TCP 1029  "!<len>!<payload>" framed messages
  Everything else (D-pad, home, back, app launch, app list) is a configurable
  template.  Use tools/zank_capture.py to learn the exact strings your Zank
  version uses and paste the result into the "Command Overrides" property.

  License: MIT
]]

DRIVER_NAME      = 'Zank Android Remote'

PROXY_MEDIA      = 5001   -- media_player proxy
PROXY_SWITCH     = 5002   -- avswitch proxy for Universal Mini Apps
NET_TCP          = 6001
NET_UDP          = 6002
MINIAPP_START    = 3101
MINIAPP_END      = 3125

-- Variable names a mini app driver may publish with the Android package to launch.
-- Our own mini apps publish ZANK_PACKAGE; the rest cover other UMA-style drivers.
MINIAPP_PACKAGE_VARS = { 'ZANK_PACKAGE', 'UM_ZANK', 'UM_ANDROID', 'UM_ANDROIDTV', 'UM_GOOGLETV', 'UM_SHIELD', 'UM_FIRETV', 'PACKAGE' }

--@@PRESETS@@
APP_PRESETS = APP_PRESETS or {}

------------------------------------------------------------------------------
-- Command catalogue
------------------------------------------------------------------------------

-- Logical keys -> Android KeyEvent codes (stable, from the Android SDK).
KEYCODES = {
  UP = 19, DOWN = 20, LEFT = 21, RIGHT = 22, SELECT = 23,
  BACK = 4, HOME = 3, MENU = 82, RECENTS = 187, SEARCH = 84, INFO = 165,
  SETTINGS = 176, GUIDE = 172,
  PLAY_PAUSE = 85, PLAY = 126, PAUSE = 127, STOP = 86,
  NEXT = 87, PREVIOUS = 88, REWIND = 89, FAST_FORWARD = 90,
  PAGE_UP = 92, PAGE_DOWN = 93, CHANNEL_UP = 166, CHANNEL_DOWN = 167,
  VOLUME_UP = 24, VOLUME_DOWN = 25, MUTE = 164,
  POWER = 26, SLEEP = 223, WAKEUP = 224,
  RED = 183, GREEN = 184, YELLOW = 185, BLUE = 186,
  DIGIT_0 = 7, DIGIT_1 = 8, DIGIT_2 = 9, DIGIT_3 = 10, DIGIT_4 = 11,
  DIGIT_5 = 12, DIGIT_6 = 13, DIGIT_7 = 14, DIGIT_8 = 15, DIGIT_9 = 16,
}

-- Long press of OK (info / context menus in Plex and most Android TV apps).
-- Zank uses "dpadCenterLong" (confirmed on a real box; "keycode --longpress 23"
-- is ignored).  If a different Zank version changes it, the "Find Long Press
-- Command" action steps through these and LONG_SELECT=<string> overrides it.
LONG_PRESS_CANDIDATES = {
  'dpadCenterLong', 'longClick', 'longPress', 'longpress', 'longDpadCenter',
  'longCenter', 'centerLong', 'longOk', 'okLong', 'longPressCenter',
  'longClickCenter', 'holdCenter', 'keycodeLong 23', 'longKeycode 23',
  'keycode 23 long', 'keycode 23 true', 'longpress 23', 'longPress 23',
}

-- What the Info button (and DVR, when enabled) sends, per "Info Button Action".
INFO_ACTIONS = { ['Long press OK'] = 'LONG_SELECT', ['Menu key'] = 'MENU', ['Info key'] = 'INFO' }
DEFAULT_INFO_ACTION = 'Long press OK'

-- Default Zank command strings.  [C] = confirmed from Zank source, others are
-- best guesses: verify with tools/zank_capture.py and override as needed.
-- Prefix "tcp:" to send a command over the TCP channel instead of UDP.
DEFAULT_COMMANDS = {
  PAGE_UP      = 'pageUp',          -- [C]
  PAGE_DOWN    = 'pageDown',        -- [C]
  VOLUME_UP    = 'volumeUp',        -- [C]
  VOLUME_DOWN  = 'volumeDown',      -- [C]
  MUTE         = 'volumeMute',      -- [C]
  CLICK        = 'click',           -- [C] mouse click at pointer
  TEXT         = 'setFinalText {text}', -- [C]
  PING         = 'getName',         -- [C] box replies with its name

  UP           = 'dpadUp',
  DOWN         = 'dpadDown',
  LEFT         = 'dpadLeft',
  RIGHT        = 'dpadRight',
  SELECT       = 'dpadCenter',
  LONG_SELECT  = 'dpadCenterLong',  -- [C] long press OK, confirmed on a real box
  BACK         = 'back',
  HOME         = 'home',
  RECENTS      = 'recent',
  PLAY_PAUSE   = 'playPause',
  NEXT         = 'next',
  PREVIOUS     = 'previous',
  REWIND       = 'rewind',
  FAST_FORWARD = 'fastForward',
  STOP         = 'stop',

  KEYCODE      = 'keycode {code}',  -- generic key event template
  LAUNCH       = 'openApp {pkg}',
  APP_LIST     = 'tcp:getApps',
  OPEN_URL     = 'openUrl {url}',
}

KEY_LIST = {
  'UP', 'DOWN', 'LEFT', 'RIGHT', 'SELECT', 'LONG_SELECT', 'BACK', 'HOME', 'MENU', 'RECENTS',
  'SEARCH', 'INFO', 'SETTINGS', 'GUIDE', 'PLAY_PAUSE', 'PLAY', 'PAUSE', 'STOP',
  'NEXT', 'PREVIOUS', 'REWIND', 'FAST_FORWARD', 'PAGE_UP', 'PAGE_DOWN',
  'CHANNEL_UP', 'CHANNEL_DOWN', 'VOLUME_UP', 'VOLUME_DOWN', 'MUTE', 'POWER',
  'SLEEP', 'WAKEUP', 'RED', 'GREEN', 'YELLOW', 'BLUE', 'CLICK',
  'DIGIT_0', 'DIGIT_1', 'DIGIT_2', 'DIGIT_3', 'DIGIT_4',
  'DIGIT_5', 'DIGIT_6', 'DIGIT_7', 'DIGIT_8', 'DIGIT_9',
}

-- media_player proxy commands -> logical keys
PROXY_KEYMAP = {
  UP = 'UP', DOWN = 'DOWN', LEFT = 'LEFT', RIGHT = 'RIGHT',
  ENTER = 'SELECT', SELECT = 'SELECT', OK = 'SELECT',
  CANCEL = 'BACK', BACK = 'BACK', EXIT = 'BACK',
  MENU = 'HOME', GUIDE = 'HOME', HOME = 'HOME',
  RECALL = 'RECENTS', PREV = 'RECENTS',
  SKIP_FWD = 'NEXT', SKIP_REV = 'PREVIOUS',
  SCAN_FWD = 'FAST_FORWARD', SCAN_REV = 'REWIND',
  PAGE_UP = 'PAGE_UP', PAGE_DOWN = 'PAGE_DOWN',
  PULSE_CH_UP = 'PAGE_UP', PULSE_CH_DOWN = 'PAGE_DOWN',
  CH_UP = 'PAGE_UP', CH_DOWN = 'PAGE_DOWN',
  SEARCH = 'SEARCH',
}
VOLUME_KEYMAP = {
  VOLUME_UP = 'VOLUME_UP', PULSE_VOL_UP = 'VOLUME_UP', VOL_UP = 'VOLUME_UP',
  VOLUME_DOWN = 'VOLUME_DOWN', PULSE_VOL_DOWN = 'VOLUME_DOWN', VOL_DOWN = 'VOLUME_DOWN',
  MUTE_TOGGLE = 'MUTE', MUTE_ON = 'MUTE', MUTE_OFF = 'MUTE',
}
COLOUR_BUTTONS = { PROGRAM_A = 'Red', PROGRAM_B = 'Green', PROGRAM_C = 'Yellow', PROGRAM_D = 'Blue' }

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------
PersistData = PersistData or {}
State = State or {
  tcpOnline = false, udpReady = false, lastSeen = 0, online = false,
  tcpBuffer = '', overrides = {}, repeatTimer = nil, repeatCount = 0,
  lastLaunch = { pkg = nil, time = 0 }, roomSources = {}, rooms = {},
}
Timers = Timers or {}

------------------------------------------------------------------------------
-- Utilities
------------------------------------------------------------------------------
function dbg(...)
  if (Properties and Properties['Debug Mode'] == 'On') then
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print('[Zank] ' .. table.concat(parts, ' '))
  end
end

function log(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  print('[Zank] ' .. table.concat(parts, ' '))
end

function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

function now() return os.time() end

function propNumber(name, default)
  local v = tonumber(Properties and Properties[name])
  if (v == nil) then return default end
  return v
end

function setProp(name, value)
  if (Properties and Properties[name] ~= value) then
    C4:UpdateProperty(name, tostring(value))
  end
end

function cancelTimer(name)
  if (Timers[name]) then
    pcall(function() Timers[name]:Cancel() end)
    Timers[name] = nil
  end
end

function looksLikePackage(s)
  s = trim(s)
  return s ~= '' and not s:find('%s') and s:find('^[%a_][%w_]*%.[%w_%.]+$') ~= nil
end

------------------------------------------------------------------------------
-- Minimal JSON decoder (Lua 5.1, no dependencies) - used for app lists
------------------------------------------------------------------------------
JSON = {}
do
  local function skip(s, i)
    local _, e = s:find('^[ \n\r\t]*', i)
    return e + 1
  end
  local decodeValue
  local escapes = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
  local function decodeString(s, i)
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if (c == '') then error('unterminated string') end
      if (c == '"') then return table.concat(out), j + 1 end
      if (c == '\\') then
        local n = s:sub(j + 1, j + 1)
        if (n == 'u') then
          local code = tonumber(s:sub(j + 2, j + 5), 16) or 63
          if (code < 128) then out[#out + 1] = string.char(code)
          elseif (code < 2048) then
            out[#out + 1] = string.char(192 + math.floor(code / 64), 128 + code % 64)
          else
            out[#out + 1] = string.char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64)
          end
          j = j + 6
        else
          out[#out + 1] = escapes[n] or n
          j = j + 2
        end
      else
        out[#out + 1] = c
        j = j + 1
      end
    end
  end
  decodeValue = function(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if (c == '{') then
      local obj = {}
      i = skip(s, i + 1)
      if (s:sub(i, i) == '}') then return obj, i + 1 end
      while true do
        local k
        k, i = decodeString(s, skip(s, i))
        i = skip(s, i)
        if (s:sub(i, i) ~= ':') then error('expected : at ' .. i) end
        obj[k], i = decodeValue(s, i + 1)
        i = skip(s, i)
        local d = s:sub(i, i)
        if (d == '}') then return obj, i + 1 end
        if (d ~= ',') then error('expected , or } at ' .. i) end
        i = i + 1
      end
    elseif (c == '[') then
      local arr = {}
      i = skip(s, i + 1)
      if (s:sub(i, i) == ']') then return arr, i + 1 end
      while true do
        arr[#arr + 1], i = decodeValue(s, i)
        i = skip(s, i)
        local d = s:sub(i, i)
        if (d == ']') then return arr, i + 1 end
        if (d ~= ',') then error('expected , or ] at ' .. i) end
        i = i + 1
      end
    elseif (c == '"') then
      return decodeString(s, i)
    elseif (s:sub(i, i + 3) == 'true') then return true, i + 4
    elseif (s:sub(i, i + 4) == 'false') then return false, i + 5
    elseif (s:sub(i, i + 3) == 'null') then return nil, i + 4
    else
      local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
      if (not num or num == '') then error('unexpected character at ' .. i) end
      return tonumber(num), i + #num
    end
  end
  function JSON.decode(s)
    local ok, v = pcall(function() return (decodeValue(s, 1)) end)
    if (ok) then return v end
    return nil
  end
end

------------------------------------------------------------------------------
-- Command map
------------------------------------------------------------------------------

-- "Command Overrides" property format:  KEY=value; KEY=value
-- Values may use {code} {pkg} {activity} {text} {url}.  Prefix tcp: / udp:.
function ParseOverrides()
  State.overrides = {}
  local raw = (Properties and Properties['Command Overrides']) or ''
  for pair in raw:gmatch('[^;]+') do
    local k, v = pair:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if (k and v and v ~= '') then
      State.overrides[k:upper()] = v
    end
  end
end

function GetTemplate(key)
  if (State.overrides[key]) then return State.overrides[key], 'override' end
  local mode = Properties['Key Mode'] or 'Zank Commands'
  local isKey = KEYCODES[key] ~= nil
  if (mode == 'Android Keycodes' and isKey) then
    return (State.overrides.KEYCODE or DEFAULT_COMMANDS.KEYCODE), 'keycode'
  end
  if (DEFAULT_COMMANDS[key]) then return DEFAULT_COMMANDS[key], 'default' end
  if (isKey) then return (State.overrides.KEYCODE or DEFAULT_COMMANDS.KEYCODE), 'keycode' end
  return nil
end

function Render(template, vars)
  vars = vars or {}
  return (template:gsub('{(%w+)}', function(name)
    local v = vars[name]
    if (v == nil) then return '' end
    return tostring(v)
  end))
end

function BuildCommand(key, vars)
  local template, source = GetTemplate(key)
  if (not template) then return nil end
  vars = vars or {}
  if (vars.code == nil and KEYCODES[key]) then vars.code = KEYCODES[key] end
  local transport = Properties['Default Transport'] or 'UDP'
  local lower = template:lower()
  if (lower:sub(1, 4) == 'tcp:') then transport = 'TCP'; template = template:sub(5)
  elseif (lower:sub(1, 4) == 'udp:') then transport = 'UDP'; template = template:sub(5) end
  local payload = trim(Render(template, vars))
  -- tidy "openApp pkg/" when no activity was supplied
  payload = payload:gsub('/%s*$', '')
  return payload, transport, source
end

------------------------------------------------------------------------------
-- Network
------------------------------------------------------------------------------
function Connect()
  local ip = trim(Properties['IP Address'])
  Disconnect()
  if (ip == '') then
    setProp('Connection Status', 'Set the IP Address of the Android box')
    return
  end
  State.ip = ip
  setProp('Connection Status', 'Connecting to ' .. ip)
  C4:CreateNetworkConnection(NET_UDP, ip)
  C4:NetConnect(NET_UDP, propNumber('UDP Port', 1028), 'UDP')
  C4:CreateNetworkConnection(NET_TCP, ip)
  C4:NetConnect(NET_TCP, propNumber('TCP Port', 1029))

  cancelTimer('Heartbeat')
  Timers.Heartbeat = C4:SetTimer(30 * 1000, function() Heartbeat() end, true)
end

function Disconnect()
  cancelTimer('Heartbeat')
  cancelTimer('Reconnect')
  if (State.ip) then
    pcall(C4.NetDisconnect, C4, NET_TCP, propNumber('TCP Port', 1029))
    pcall(C4.NetDisconnect, C4, NET_UDP, propNumber('UDP Port', 1028), 'UDP')
  end
  State.tcpOnline, State.udpReady, State.tcpBuffer = false, false, ''
  UpdateOnline()
end

function Heartbeat()
  if (State.udpReady) then
    local payload = BuildCommand('PING')
    if (payload) then C4:SendToNetwork(NET_UDP, propNumber('UDP Port', 1028), payload) end
  end
  if (not State.tcpOnline and State.ip) then
    C4:NetConnect(NET_TCP, propNumber('TCP Port', 1029))
  end
  UpdateOnline()
end

function UpdateOnline()
  local online = State.tcpOnline or (now() - (State.lastSeen or 0) < 95)
  if (online ~= State.online) then
    State.online = online
    C4:SetVariable('ONLINE', online and '1' or '0')
    C4:FireEvent(online and 'Device Online' or 'Device Offline')
  end
  if (online) then
    setProp('Connection Status', 'Online' .. (State.tcpOnline and ' (TCP)' or ' (UDP)'))
  elseif (State.ip) then
    setProp('Connection Status', 'Offline - is Zank Remote running on ' .. State.ip .. '?')
  end
end

function OnConnectionStatusChanged(idBinding, nPort, strStatus)
  dbg('Connection', idBinding, nPort, strStatus)
  if (idBinding == NET_TCP) then
    State.tcpOnline = (strStatus == 'ONLINE')
    if (State.tcpOnline) then
      State.lastSeen = now()
      State.tcpBuffer = ''
      if ((PersistData.apps == nil or #PersistData.apps == 0) and Properties['Auto Fetch App List'] == 'Yes') then
        RequestAppList()
      end
    else
      cancelTimer('Reconnect')
      Timers.Reconnect = C4:SetTimer(15 * 1000, function()
        Timers.Reconnect = nil
        if (State.ip and not State.tcpOnline) then C4:NetConnect(NET_TCP, propNumber('TCP Port', 1029)) end
      end)
    end
  elseif (idBinding == NET_UDP) then
    State.udpReady = (strStatus == 'ONLINE')
    if (State.udpReady) then Heartbeat() end
  end
  UpdateOnline()
end

function ReceivedFromNetwork(idBinding, nPort, strData)
  dbg('<<', idBinding, nPort, strData)
  if (Properties['Log Incoming Data'] == 'Yes') then log('<< [' .. tostring(nPort) .. '] ' .. tostring(strData)) end
  State.lastSeen = now()
  if (idBinding == NET_UDP) then
    local name = trim(strData)
    if (name ~= '' and #name < 80 and not name:find('[{%[]')) then
      setProp('Device Name', name)
    else
      HandleMessage(strData)
    end
  elseif (idBinding == NET_TCP) then
    State.tcpBuffer = (State.tcpBuffer or '') .. strData
    ProcessTcpBuffer()
  end
  UpdateOnline()
end

function ProcessTcpBuffer()
  local framing = Properties['TCP Framing'] or '!len! header'
  local buf = State.tcpBuffer
  if (framing == '!len! header') then
    while true do
      local hdr, len = buf:match('^(!(%d+)!)')
      if (not hdr) then
        -- not framed: fall back to raw handling so nothing gets lost
        if (#buf > 0 and buf:sub(1, 1) ~= '!') then HandleMessage(buf); buf = '' end
        break
      end
      len = tonumber(len)
      if (#buf < #hdr + len) then break end
      HandleMessage(buf:sub(#hdr + 1, #hdr + len))
      buf = buf:sub(#hdr + len + 1)
    end
  elseif (framing == 'Newline') then
    while true do
      local line, rest = buf:match('^(.-)\r?\n(.*)$')
      if (not line) then break end
      if (line ~= '') then HandleMessage(line) end
      buf = rest
    end
  else
    HandleMessage(buf)
    buf = ''
  end
  -- guard against runaway buffers
  if (#buf > 512 * 1024) then buf = '' end
  State.tcpBuffer = buf
end

function SendRaw(payload, transport)
  if (payload == nil or payload == '') then return false end
  transport = (transport or 'UDP'):upper()
  if (transport == 'TCP') then
    if (not State.tcpOnline) then
      dbg('TCP not connected; dropping', payload)
      return false
    end
    local framing = Properties['TCP Framing'] or '!len! header'
    local data = payload
    if (framing == '!len! header') then data = '!' .. tostring(#payload) .. '!' .. payload
    elseif (framing == 'Newline') then data = payload .. '\n' end
    dbg('>> TCP', data)
    C4:SendToNetwork(NET_TCP, propNumber('TCP Port', 1029), data)
  else
    if (not State.udpReady) then
      dbg('UDP not ready; dropping', payload)
      return false
    end
    dbg('>> UDP', payload)
    C4:SendToNetwork(NET_UDP, propNumber('UDP Port', 1028), payload)
  end
  return true
end

function SendKey(key, vars)
  if (key == 'INFO_ACTION') then
    key = INFO_ACTIONS[Properties['Info Button Action'] or DEFAULT_INFO_ACTION] or 'MENU'
    if (key == 'LONG_SELECT' and not GetTemplate('LONG_SELECT')) then
      log('No LONG_SELECT command available; sending Menu instead. Run "Find Long Press Command".')
      key = 'MENU'
    end
  end
  local payload, transport = BuildCommand(key, vars)
  if (not payload) then
    dbg('No command mapped for', key)
    return false
  end
  return SendRaw(payload, transport)
end

------------------------------------------------------------------------------
-- Incoming data / app list
------------------------------------------------------------------------------
function HandleMessage(msg)
  if (msg == nil or msg == '') then return end
  local apps = ParseAppList(msg)
  if (apps and #apps > 0) then
    StoreApps(apps)
  end
end

function ParseAppList(msg)
  local apps = {}
  local data = JSON.decode(msg)
  local function add(name, pkg)
    if (pkg and looksLikePackage(pkg)) then
      apps[#apps + 1] = { name = trim(name ~= nil and name ~= '' and name or pkg), package = trim(pkg) }
    end
  end
  local function fromObject(o)
    if (type(o) ~= 'table') then return end
    local pkg = o.packageName or o.package or o.pkg or o.appPackage or o.id
    local name = o.name or o.label or o.appName or o.title
    add(name, pkg)
  end
  if (type(data) == 'table') then
    local list = data.apps or data.applications or data.data or data
    if (#list > 0) then
      for _, item in ipairs(list) do
        if (type(item) == 'string') then add(nil, item) else fromObject(item) end
      end
    else
      for k, v in pairs(list) do
        if (type(v) == 'string' and looksLikePackage(k)) then add(v, k)
        elseif (type(v) == 'string' and looksLikePackage(v)) then add(k, v) end
      end
    end
  else
    -- line based: "Label|package", "package|Label", "package"
    for line in msg:gmatch('[^\r\n]+') do
      local a, b = line:match('^%s*(.-)%s*[|\t,;]%s*(.-)%s*$')
      if (a and looksLikePackage(b)) then add(a, b)
      elseif (a and looksLikePackage(a)) then add(b, a)
      elseif (looksLikePackage(line)) then add(nil, line) end
    end
  end
  if (#apps < 2 and type(data) ~= 'table') then return nil end -- avoid false positives from chatter
  return apps
end

function StoreApps(apps)
  local seen, clean = {}, {}
  for _, a in ipairs(apps) do
    if (not seen[a.package]) then
      seen[a.package] = true
      a.name = a.name:gsub('[,]', ' ')
      clean[#clean + 1] = a
    end
  end
  table.sort(clean, function(x, y) return x.name:lower() < y.name:lower() end)
  PersistData.apps = clean
  setProp('Installed Apps', tostring(#clean) .. ' found')
  log('App list updated: ' .. #clean .. ' apps')
  RefreshAppLists()
end

function RequestAppList()
  local payload, transport = BuildCommand('APP_LIST')
  if (payload) then SendRaw(payload, transport) end
end

-- All launchable apps: installed list + presets (presets fill gaps before a list is fetched)
function AllApps()
  local list, seen = {}, {}
  for _, a in ipairs(PersistData.apps or {}) do
    if (not seen[a.package]) then seen[a.package] = true; list[#list + 1] = a end
  end
  for _, a in ipairs(APP_PRESETS) do
    if (not seen[a.package]) then seen[a.package] = true; list[#list + 1] = { name = a.name, package = a.package } end
  end
  table.sort(list, function(x, y) return x.name:lower() < y.name:lower() end)
  return list
end

function AppLabel(a) return a.name .. ' (' .. a.package .. ')' end

function PackageFromLabel(label)
  label = trim(label)
  local pkg = label:match('%(([^%(%)]+)%)%s*$')
  if (pkg and looksLikePackage(pkg)) then return pkg end
  if (looksLikePackage(label)) then return label end
  local lower = label:lower()
  for _, a in ipairs(AllApps()) do
    if (a.name:lower() == lower) then return a.package end
  end
  return nil
end

function AppNameForPackage(pkg)
  for _, a in ipairs(AllApps()) do
    if (a.package == pkg) then return a.name end
  end
  return pkg
end

function RefreshAppLists()
  local items = { '(Default key)' }
  for _, a in ipairs(AllApps()) do items[#items + 1] = AppLabel(a) end
  local csv = table.concat(items, ',')
  for _, colour in ipairs({ 'Red', 'Green', 'Yellow', 'Blue' }) do
    pcall(C4.UpdatePropertyList, C4, colour .. ' Button App', csv)
  end
end

------------------------------------------------------------------------------
-- App launching
------------------------------------------------------------------------------
function LaunchApp(pkg, activity, name)
  pkg = trim(pkg)
  if (not looksLikePackage(pkg)) then
    log('LaunchApp: invalid package "' .. pkg .. '"')
    return false
  end
  local t = now()
  if (State.lastLaunch.pkg == pkg and t - State.lastLaunch.time < 3) then
    dbg('Launch debounced', pkg)
    return true
  end
  State.lastLaunch = { pkg = pkg, time = t }
  name = name or AppNameForPackage(pkg)
  local ok = SendKey('LAUNCH', { pkg = pkg, activity = activity or '' })
  log('Launch ' .. name .. ' (' .. pkg .. ')' .. (ok and '' or ' - not sent, device offline'))
  C4:SetVariable('CURRENT_APP', name)
  C4:SetVariable('CURRENT_APP_PACKAGE', pkg)
  setProp('Last Launched App', AppLabel({ name = name, package = pkg }))
  C4:FireEvent('App Launched')
  return ok
end

function ColourButton(colour)
  local label = Properties[colour .. ' Button App'] or ''
  local pkg = PackageFromLabel(label)
  if (pkg) then LaunchApp(pkg) else SendKey(colour:upper()) end
end

------------------------------------------------------------------------------
-- Key handling (with press-and-hold repeat)
------------------------------------------------------------------------------
function StopRepeat()
  cancelTimer('Repeat')
  State.repeatCount = 0
end

function StartRepeat(key)
  StopRepeat()
  local rate = propNumber('Key Repeat Rate (ms)', 150)
  if (rate < 50) then rate = 50 end
  Timers.Repeat = C4:SetTimer(rate, function()
    State.repeatCount = State.repeatCount + 1
    if (State.repeatCount > 150) then StopRepeat(); return end -- safety: never repeat forever
    SendKey(key)
  end, true)
end

function ResolveProxyKey(cmd)
  if (cmd == 'INFO') then return 'INFO_ACTION' end
  if (cmd == 'PVR' or cmd == 'DVR') then
    -- optional: the DVR button (sent as PVR) does exactly what Info does
    if (Properties['DVR Button As Info'] == 'On') then return 'INFO_ACTION' end
    return nil
  end
  if (PROXY_KEYMAP[cmd]) then return PROXY_KEYMAP[cmd] end
  if (cmd == 'PLAY' or cmd == 'PAUSE' or cmd == 'PLAYPAUSE' or cmd == 'PLAY_PAUSE') then
    if (Properties['Play/Pause Mode'] == 'Discrete') then
      return (cmd == 'PAUSE') and 'PAUSE' or ((cmd == 'PLAY') and 'PLAY' or 'PLAY_PAUSE')
    end
    return 'PLAY_PAUSE'
  end
  if (cmd == 'STOP') then
    return (Properties['Stop Button'] == 'Back') and 'BACK' or 'STOP'
  end
  local digit = cmd:match('^NUMBER_(%d)$') or cmd:match('^DIGIT_(%d)$') or cmd:match('^NUM_(%d)$')
  if (digit) then return 'DIGIT_' .. digit end
  if (VOLUME_KEYMAP[cmd]) then
    if (Properties['Volume Handling'] == 'Send to Box') then return VOLUME_KEYMAP[cmd] end
    return nil
  end
  return nil
end

function HandleMediaCommand(cmd, params)
  cmd = tostring(cmd or ''):upper()
  params = params or {}

  if (cmd == 'ON') then
    local b = Properties['On Command'] or 'None'
    if (b == 'Wake') then SendKey('WAKEUP') elseif (b == 'Home') then SendKey('HOME') end
    return
  elseif (cmd == 'OFF') then
    local b = Properties['Off Command'] or 'None'
    if (b == 'Sleep') then SendKey('SLEEP') elseif (b == 'Home') then SendKey('HOME') end
    return
  end

  if (COLOUR_BUTTONS[cmd]) then return ColourButton(COLOUR_BUTTONS[cmd]) end

  local hold = cmd:match('^START_(.+)$')
  local release = cmd:match('^STOP_(.+)$') or cmd:match('^END_(.+)$')
  if (hold) then
    local key = ResolveProxyKey(hold)
    if (key) then
      SendKey(key)
      -- never auto-repeat a long press / info: one press, one action
      if (key ~= 'INFO_ACTION') then StartRepeat(key) end
    end
    return
  elseif (release) then
    StopRepeat()
    return
  end

  local key = ResolveProxyKey(cmd)
  if (key) then
    SendKey(key)
  else
    dbg('Unhandled proxy command', cmd)
  end
end

------------------------------------------------------------------------------
-- Mini app support (RF_ANDROID_APP inputs on the Virtual Switcher)
------------------------------------------------------------------------------
function GetDeviceVar(deviceId, name)
  local vars = C4:GetDeviceVariables(deviceId) or {}
  for _, v in pairs(vars) do
    if (v.name == name) then return v.value end
  end
  return nil
end

function ResolveMiniAppPackage(appDeviceId, appProxyId)
  for _, varName in ipairs(MINIAPP_PACKAGE_VARS) do
    local v = GetDeviceVar(appDeviceId, varName)
    if (v and looksLikePackage(v)) then
      return v, GetDeviceVar(appDeviceId, 'ZANK_ACTIVITY'), GetDeviceVar(appDeviceId, 'APP_NAME')
    end
  end
  local appName = GetDeviceVar(appDeviceId, 'APP_NAME')
  local appId = GetDeviceVar(appDeviceId, 'APP_ID')
  if (appId and looksLikePackage(appId)) then return appId, nil, appName end
  if (appName) then
    local pkg = PackageFromLabel(appName)
    if (pkg) then return pkg, nil, appName end
  end
  -- Last resort (e.g. third-party mini apps): match the device's Composer name,
  -- "YouTube (Android TV)" -> "YouTube", against installed apps and presets.
  for _, id in ipairs({ appDeviceId, appProxyId }) do
    local ok, display = pcall(C4.GetDeviceDisplayName, C4, id)
    if (ok and display and display ~= '') then
      local base = trim(display:gsub('%s*%b()%s*$', ''))
      local pkg = PackageFromLabel(base)
      if (pkg) then return pkg, nil, base end
      appName = appName or base
    end
  end
  return nil, nil, appName
end

-- Tell every mini app bound to the Virtual Switcher which device to send its
-- passthrough commands to.  Lookups from the switcher's inputs (consumer side)
-- are reliable; a mini app looking downstream along its AV binding is not.
function AnnounceToMiniApps()
  local switcherProxyId = next(C4:GetBoundConsumerDevices(C4:GetDeviceID(), PROXY_SWITCH) or {})
  if (not switcherProxyId) then return 0 end
  local count = 0
  for input = MINIAPP_START, MINIAPP_END do
    local appProxyId = C4:GetBoundProviderDevice(switcherProxyId, input)
    if (appProxyId and appProxyId ~= 0) then
      local appDeviceId = C4:GetBoundProviderDevice(appProxyId, 5001)
      if (not appDeviceId or appDeviceId == 0) then appDeviceId = appProxyId end
      C4:SendToDevice(appDeviceId, 'ZANK_SET_PARENT', { PARENT_ID = tostring(C4:GetDeviceID()), INPUT = tostring(input) })
      count = count + 1
    end
  end
  dbg('Announced to ' .. count .. ' mini app(s)')
  return count
end

function HandleMiniAppInput(input)
  local switcherProxyId = next(C4:GetBoundConsumerDevices(C4:GetDeviceID(), PROXY_SWITCH) or {})
  if (not switcherProxyId) then log('Mini app: Virtual Switcher proxy not found'); return end
  local appProxyId = C4:GetBoundProviderDevice(switcherProxyId, input)
  if (not appProxyId or appProxyId == 0) then log('Mini app: nothing bound to input ' .. input); return end
  local appDeviceId = C4:GetBoundProviderDevice(appProxyId, 5001)
  if (not appDeviceId or appDeviceId == 0) then appDeviceId = appProxyId end
  local pkg, activity, name = ResolveMiniAppPackage(appDeviceId, appProxyId)
  if (not pkg) then
    log('Mini app on input ' .. input .. ' (' .. tostring(name) .. ') has no Android package - set it on the mini app driver')
    return
  end
  LaunchApp(pkg, activity, name)
  C4:SendToDevice(appDeviceId, 'ZANK_SET_PARENT', { PARENT_ID = tostring(C4:GetDeviceID()), INPUT = tostring(input) })

  if ((Properties['Passthrough Mode'] or 'On') ~= 'On') then
    -- reselect the Virtual Switcher, which is the box's Watch source
    local mediaProxyId = next(C4:GetBoundConsumerDevices(C4:GetDeviceID(), PROXY_SWITCH) or {})
    C4:SetTimer(500, function()
      for roomId, deviceId in pairs(State.roomSources) do
        if (deviceId == appProxyId and mediaProxyId) then
          C4:SendToDevice(roomId, 'SELECT_VIDEO_DEVICE', { deviceid = mediaProxyId })
        end
      end
    end)
  end
end

function RegisterRooms()
  State.rooms = C4:GetDevicesByC4iName('roomdevice.c4i') or {}
  State.roomSources = {}
  for roomId, _ in pairs(State.rooms) do
    State.roomSources[roomId] = tonumber(C4:GetDeviceVariable(roomId, 1000)) or 0
    pcall(C4.UnregisterVariableListener, C4, roomId, 1000)
    C4:RegisterVariableListener(roomId, 1000)
  end
end

function OnWatchedVariableChanged(idDevice, idVariable, strValue)
  if (State.rooms and State.rooms[idDevice] and tonumber(idVariable) == 1000) then
    State.roomSources[tonumber(idDevice)] = tonumber(strValue) or 0
  end
end

------------------------------------------------------------------------------
-- Director entry points
------------------------------------------------------------------------------
function ReceivedFromProxy(idBinding, strCommand, tParams)
  if (idBinding == nil or strCommand == nil) then return end
  tParams = tParams or {}
  dbg('Proxy', idBinding, strCommand)

  -- Universal Mini App passthrough (must be checked first)
  if (idBinding == PROXY_SWITCH and strCommand == 'PASSTHROUGH') then
    idBinding = PROXY_MEDIA
    strCommand = tParams.PASSTHROUGH_COMMAND or ''
  end

  if (idBinding == PROXY_SWITCH) then
    if (strCommand == 'SET_INPUT') then
      local input = tonumber(tParams.INPUT)
      if (input and input >= MINIAPP_START and input <= MINIAPP_END) then
        HandleMiniAppInput(input)
      end
      return
    end
    -- The Virtual Switcher is the Watch source for the box itself, so its
    -- remote commands drive the box like the media player's would.
    if (not strCommand:find('^GET_') and strCommand ~= 'CONNECT' and strCommand ~= 'DISCONNECT') then
      HandleMediaCommand(strCommand, tParams)
    end
    return
  end

  if (idBinding == PROXY_MEDIA) then
    HandleMediaCommand(strCommand, tParams)
  end
end

function ExecuteCommand(strCommand, tParams)
  tParams = tParams or {}
  if (strCommand == 'LUA_ACTION') then
    return DoAction(tParams.ACTION)
  end

  -- Inter-driver messages from Zank mini app drivers
  if (strCommand == 'ZANK_LAUNCH') then
    return LaunchApp(tParams.PACKAGE, tParams.ACTIVITY, tParams.NAME)
  elseif (strCommand == 'ZANK_PASSTHROUGH') then
    return HandleMediaCommand(tParams.COMMAND, tParams)
  end

  -- Programming commands
  if (strCommand == 'Launch App') then
    local pkg = PackageFromLabel(tParams['App'] or '')
    if (pkg) then LaunchApp(pkg) else log('Launch App: unknown app ' .. tostring(tParams['App'])) end
  elseif (strCommand == 'Launch Package') then
    LaunchApp(tParams['Package'], tParams['Activity'])
  elseif (strCommand == 'Send Key') then
    SendKey(tostring(tParams['Key'] or ''):upper())
  elseif (strCommand == 'Send Text') then
    SendKey('TEXT', { text = tParams['Text'] or '' })
  elseif (strCommand == 'Open Deep Link') then
    SendKey('OPEN_URL', { url = tParams['URL'] or '' })
  elseif (strCommand == 'Send Raw Command') then
    SendRaw(tParams['Command'], tParams['Transport'])
  elseif (strCommand == 'Refresh App List') then
    RequestAppList()
  else
    dbg('Unknown command', strCommand)
  end
end

function GetCommandParamList(commandName, paramName)
  if (commandName == 'Launch App' and paramName == 'App') then
    local items = {}
    for _, a in ipairs(AllApps()) do items[#items + 1] = AppLabel(a) end
    return items
  end
  return {}
end

function DoAction(action)
  if (action == 'Reconnect') then
    Connect()
  elseif (action == 'Request App List') then
    RequestAppList()
  elseif (action == 'Print Apps') then
    local apps = AllApps()
    log('---- Apps (' .. #(PersistData.apps or {}) .. ' installed, presets included) ----')
    for _, a in ipairs(apps) do log(AppLabel(a)) end
  elseif (action == 'Print Command Map') then
    log('---- Command map (Key Mode: ' .. tostring(Properties['Key Mode']) .. ') ----')
    local keys = {}
    for _, k in ipairs(KEY_LIST) do keys[#keys + 1] = k end
    for _, k in ipairs({ 'TEXT', 'LAUNCH', 'APP_LIST', 'OPEN_URL', 'PING' }) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do
      local payload, transport, source = BuildCommand(k, { pkg = '<pkg>', text = '<text>', url = '<url>' })
      log(string.format('%-13s %-4s %-9s %s', k, tostring(transport), tostring(source), tostring(payload)))
    end
  elseif (action == 'Test D-Pad') then
    local seq = { 'UP', 'DOWN', 'LEFT', 'RIGHT', 'BACK' }
    for i, k in ipairs(seq) do
      C4:SetTimer(i * 1200, function() log('Test: ' .. k); SendKey(k) end)
    end
  elseif (action == 'Find Long Press Command') then
    FindLongPress()
  elseif (action == 'Clear App List') then
    PersistData.apps = {}
    setProp('Installed Apps', '0 found')
    RefreshAppLists()
  elseif (action == 'Print Mini App Bindings') then
    log('Announced to ' .. AnnounceToMiniApps() .. ' mini app(s)')
    local switcherProxyId = next(C4:GetBoundConsumerDevices(C4:GetDeviceID(), PROXY_SWITCH) or {})
    for input = MINIAPP_START, MINIAPP_END do
      local appProxyId = switcherProxyId and C4:GetBoundProviderDevice(switcherProxyId, input)
      if (appProxyId and appProxyId ~= 0) then
        local appDeviceId = C4:GetBoundProviderDevice(appProxyId, 5001)
        if (not appDeviceId or appDeviceId == 0) then appDeviceId = appProxyId end
        local pkg, _, name = ResolveMiniAppPackage(appDeviceId, appProxyId)
        log('Android App ' .. (input - MINIAPP_START + 1) .. ': ' .. tostring(name) .. ' -> ' .. tostring(pkg))
      end
    end
  end
end

-- Try each long-press candidate on UDP then TCP, 4 s apart, with BACK in
-- between to close anything that opened.  Put the box on the home screen with
-- an app tile focused, watch for its context menu, and note the step number.
function FindLongPress()
  cancelTimer('LongPressProbe')
  local steps = {}
  for _, c in ipairs(LONG_PRESS_CANDIDATES) do steps[#steps + 1] = { c, 'UDP' } end
  for _, c in ipairs(LONG_PRESS_CANDIDATES) do steps[#steps + 1] = { c, 'TCP' } end
  log('---- Find Long Press Command: ' .. #steps .. ' steps, 4 s apart ----')
  log('Home screen, app tile focused. Watch for a menu to open and note the step number.')
  local i = 0
  Timers.LongPressProbe = C4:SetTimer(4000, function()
    i = i + 1
    if (i > #steps) then
      cancelTimer('LongPressProbe')
      log('---- Done. If step N opened a menu, set Command Overrides: LONG_SELECT=<that string> (prefix tcp: for TCP steps) ----')
      return
    end
    local cand, transport = steps[i][1], steps[i][2]
    log(string.format('Step %d/%d  %s  %s', i, #steps, transport, cand))
    SendRaw(cand, transport)
    C4:SetTimer(2500, function() SendKey('BACK') end)
  end, true)
end

function OnPropertyChanged(strProperty)
  local value = Properties[strProperty]
  if (strProperty == 'IP Address' or strProperty == 'UDP Port' or strProperty == 'TCP Port') then
    Connect()
  elseif (strProperty == 'Command Overrides') then
    ParseOverrides()
  elseif (strProperty == 'Passthrough Mode') then
    RegisterRooms()
  end
end

function OnDriverInit()
  C4:AddVariable('ONLINE', '0', 'BOOL')
  C4:AddVariable('CURRENT_APP', '', 'STRING')
  C4:AddVariable('CURRENT_APP_PACKAGE', '', 'STRING')
end

function OnDriverLateInit()
  C4:UpdateProperty('Driver Version', C4:GetDriverConfigInfo('version'))
  PersistData.apps = PersistData.apps or {}
  setProp('Installed Apps', tostring(#PersistData.apps) .. ' found')
  ParseOverrides()
  RefreshAppLists()
  RegisterRooms()
  Connect()
  -- mini apps may load after us on a controller reboot: announce now, shortly after, and periodically
  Timers.AnnounceSoon = C4:SetTimer(15 * 1000, function() AnnounceToMiniApps() end)
  Timers.Announce = C4:SetTimer(5 * 60 * 1000, function() AnnounceToMiniApps() end, true)
end

function OnBindingChanged(idBinding, strClass, bIsBound)
  C4:SetTimer(2000, function() AnnounceToMiniApps() end)
end

function OnSystemEvent(event)
  local name = tostring(event):match('.-name="(.-)"')
  if (name == 'OnPIP') then RegisterRooms() end
end

function OnDriverDestroyed()
  StopRepeat()
  Disconnect()
end
