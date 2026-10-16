-- Functional tests for the Zank drivers against a mock Control4 DriverWorks API.
-- Run from the repo root after building:  texlua tests/run_tests.lua   (or lua5.1/5.3)

local BUILD = 'tests/build/'
local passed, failed = 0, 0

local function check(name, cond, detail)
  if (cond) then passed = passed + 1
  else failed = failed + 1; print('FAIL: ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')) end
end

-- ---------------------------------------------------------------- mock C4
local function newC4(deviceId, world)
  local C4 = { sent = {}, net = {}, props = {}, vars = {}, events = {}, timers = {}, toDevice = {}, binds = {}, propLists = {} }
  local env
  function C4:GetDeviceID() return deviceId end
  function C4:UpdateProperty(n, v) env.Properties[n] = v; self.props[n] = v end
  function C4:UpdatePropertyList(n, v) self.propLists[n] = v end
  function C4:GetDriverConfigInfo(k) return '20261016' end
  function C4:AddVariable(n, v) self.vars[n] = v end
  function C4:SetVariable(n, v) self.vars[n] = v end
  function C4:FireEvent(e) self.events[#self.events + 1] = e end
  function C4:CreateNetworkConnection(b, ip) self.net[b] = { ip = ip } end
  function C4:NetConnect(b, port, kind) self.net[b] = self.net[b] or {}; self.net[b].port = port; self.net[b].kind = kind or 'TCP' end
  function C4:NetDisconnect() end
  function C4:SendToNetwork(b, port, data) self.sent[#self.sent + 1] = { binding = b, port = port, data = data } end
  function C4:SetTimer(ms, fn, rep)
    local t = { ms = ms, fn = fn, rep = rep, cancelled = false }
    function t:Cancel() self.cancelled = true end
    self.timers[#self.timers + 1] = t
    return t
  end
  function C4:SendToDevice(id, cmd, params) self.toDevice[#self.toDevice + 1] = { id = id, cmd = cmd, params = params }
    if (world and world.devices[id]) then world.devices[id].ExecuteCommand(cmd, params) end
  end
  function C4:GetBoundConsumerDevices(dev, binding) return world.consumers[dev .. ':' .. binding] end
  function C4:GetBoundProviderDevice(dev, binding) return world.providers[dev .. ':' .. binding] or 0 end
  function C4:GetDeviceVariables(dev) return world.devVars[dev] or {} end
  function C4:GetDevicesByC4iName() return { [100] = 'Living Room' } end
  function C4:GetDeviceVariable() return 0 end
  function C4:RegisterVariableListener() end
  function C4:UnregisterVariableListener() end
  function C4:Bind(...) self.binds[#self.binds + 1] = { ... } end
  function C4:GetDeviceDisplayName(dev) return (world.names or {})[dev] end
  return C4, function(e) env = e end
end

local function loadDriver(path, deviceId, props, world)
  local C4, setEnv = newC4(deviceId, world)
  local logs = {}
  local env = setmetatable({ C4 = C4, Properties = props, PersistData = {},
    print = function(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end logs[#logs + 1] = table.concat(t, ' ') end },
    { __index = _G })
  setEnv(env)
  local chunk
  if (setfenv) then chunk = assert(loadfile(path)); setfenv(chunk, env)
  else chunk = assert(loadfile(path, 't', env)) end
  chunk()
  env._logs = logs
  return env, C4
end

local function lastSent(C4) return C4.sent[#C4.sent] end
local function fireTimers(C4, repeatingOnly)
  for _, t in ipairs(C4.timers) do
    if (not t.cancelled and (not repeatingOnly or t.rep)) then t.fn(t) end
  end
end

local function remoteProps(extra)
  local p = {
    ['IP Address'] = '192.168.1.50', ['UDP Port'] = '1028', ['TCP Port'] = '1029',
    ['Key Mode'] = 'Zank Commands', ['Default Transport'] = 'UDP', ['TCP Framing'] = '!len! header',
    ['Command Overrides'] = '', ['Key Repeat Rate (ms)'] = '150', ['Play/Pause Mode'] = 'Toggle',
    ['Stop Button'] = 'Media Stop', ['Volume Handling'] = 'Audio Endpoint', ['On Command'] = 'None',
    ['Off Command'] = 'None', ['Passthrough Mode'] = 'On', ['Auto Fetch App List'] = 'Yes',
    ['Red Button App'] = '', ['Green Button App'] = '', ['Yellow Button App'] = '', ['Blue Button App'] = '',
    ['Log Incoming Data'] = 'No', ['Debug Mode'] = 'Off', ['Info Button Action'] = 'Long press OK',
  }
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end

-- World: remote driver 10, media proxy 11, switcher proxy 12,
--        netflix mini app driver 20 with proxy 21 bound to MiniApp 1 (3101)
local function newWorld()
  return {
    devices = {},
    consumers = {
      ['10:5001'] = { [11] = 'Zank Android Remote' },
      ['10:5002'] = { [12] = 'App Switcher' },
      ['20:5001'] = { [21] = 'Netflix (Zank)' },
      ['21:2000'] = { [12] = 'App Switcher' },
    },
    providers = { ['12:3103'] = 41, ['12:3101'] = 21, ['21:5001'] = 20, ['12:5002'] = 10, ['12:3102'] = 31, ['31:5001'] = 30 },
    names = { [41] = 'YouTube (Android TV)' },
    devVars = {
      [20] = { { name = 'ZANK_PACKAGE', value = 'com.netflix.ninja' }, { name = 'APP_NAME', value = 'Netflix' } },
      -- an "official" universal mini app with only APP_NAME
      [30] = { { name = 'APP_NAME', value = 'Disney+' }, { name = 'UM_ROKU', value = '291097' } },
    },
  }
end

-- ================================================================ remote driver
local world = newWorld()
local R, C4 = loadDriver(BUILD .. 'remote.lua', 10, remoteProps(), world)
world.devices[10] = R
R.OnDriverInit()
R.OnDriverLateInit()

check('UDP connection created', C4.net[6002] and C4.net[6002].ip == '192.168.1.50' and C4.net[6002].port == 1028 and C4.net[6002].kind == 'UDP')
check('TCP connection created', C4.net[6001] and C4.net[6001].port == 1029)
check('no bindings created by the driver', #C4.binds == 0)
check('colour lists populated', C4.propLists['Red Button App'] and C4.propLists['Red Button App']:find('com.netflix.ninja', 1, true))

R.OnConnectionStatusChanged(6002, 1028, 'ONLINE')
check('heartbeat getName on UDP online', lastSent(C4).data == 'getName' and lastSent(C4).binding == 6002)
R.OnConnectionStatusChanged(6001, 1029, 'ONLINE')
check('online variable', C4.vars.ONLINE == '1')
check('online event', C4.events[#C4.events] == 'Device Online')
check('auto app list request over TCP framed', lastSent(C4).binding == 6001 and lastSent(C4).data == '!7!getApps', lastSent(C4).data)

R.ReceivedFromNetwork(6002, 1028, 'Living Room Box')
check('device name from getName reply', C4.props['Device Name'] == 'Living Room Box')

-- navigation
R.ReceivedFromProxy(5001, 'UP', {})
check('UP -> dpadUp over UDP', lastSent(C4).data == 'dpadUp' and lastSent(C4).binding == 6002)
R.ReceivedFromProxy(5001, 'ENTER', {})
check('ENTER -> dpadCenter', lastSent(C4).data == 'dpadCenter')
R.ReceivedFromProxy(5001, 'CANCEL', {})
check('CANCEL -> back', lastSent(C4).data == 'back')
R.ReceivedFromProxy(5001, 'MENU', {})
check('MENU -> home', lastSent(C4).data == 'home')
R.ReceivedFromProxy(5001, 'PAUSE', {})
check('PAUSE -> playPause (toggle)', lastSent(C4).data == 'playPause')
R.ReceivedFromProxy(5001, 'PULSE_CH_UP', {})
check('CH UP -> pageUp', lastSent(C4).data == 'pageUp')
R.ReceivedFromProxy(5001, 'NUMBER_5', {})
check('NUMBER_5 -> keycode 12', lastSent(C4).data == 'keycode 12', lastSent(C4).data)
local before = #C4.sent
R.ReceivedFromProxy(5001, 'PULSE_VOL_UP', {})
check('volume ignored by default', #C4.sent == before)
R.Properties['Volume Handling'] = 'Send to Box'
R.ReceivedFromProxy(5001, 'PULSE_VOL_UP', {})
check('volume sent when enabled', lastSent(C4).data == 'volumeUp')

-- Info button and DVR (sent as PVR) share one configurable action
R.ReceivedFromProxy(5001, 'INFO', {})
check('Info default = long press OK (dpadCenterLong)', lastSent(C4).data == 'dpadCenterLong', lastSent(C4).data)
R.Properties['Info Button Action'] = 'Menu key'
n = #C4.sent
R.ReceivedFromProxy(5001, 'PVR', {})
check('PVR ignored when DVR setting Off', #C4.sent == n)
R.Properties['DVR Button As Info'] = 'On'
R.ReceivedFromProxy(5001, 'PVR', {})
check('PVR does exactly what Info does', lastSent(C4).data == 'keycode 82', lastSent(C4).data)
R.ReceivedFromProxy(5002, 'PVR', {})
check('PVR on Virtual Switcher', lastSent(C4).data == 'keycode 82')
R.ReceivedFromProxy(5001, 'DVR', {})
check('DVR alias also works', lastSent(C4).data == 'keycode 82')
R.Properties['Info Button Action'] = 'Info key'
R.ReceivedFromProxy(5001, 'PVR', {})
check('Info Button Action = Info key', lastSent(C4).data == 'keycode 165')
R.Properties['Info Button Action'] = 'Long press OK'
R.ReceivedFromProxy(5001, 'PVR', {})
check('PVR long press = dpadCenterLong', lastSent(C4).data == 'dpadCenterLong', lastSent(C4).data)
R.Properties['Command Overrides'] = 'LONG_SELECT=tcp:longOk'
R.OnPropertyChanged('Command Overrides')
R.ReceivedFromProxy(5001, 'PVR', {})
check('long press uses LONG_SELECT override', lastSent(C4).data == '!6!longOk', lastSent(C4).data)
R.Properties['Command Overrides'] = ''
R.OnPropertyChanged('Command Overrides')
R.ReceivedFromProxy(5001, 'START_PVR', {})
check('holding PVR does not repeat', R.Timers.Repeat == nil)
R.ReceivedFromProxy(5001, 'STOP_PVR', {})
R.Properties['DVR Button As Info'] = 'Off'
R.Properties['Info Button Action'] = 'Menu key'

-- long press finder walks every candidate on UDP then TCP, BACK in between
R.ExecuteCommand('LUA_ACTION', { ACTION = 'Find Long Press Command' })
local probe = R.Timers.LongPressProbe
local steps = #R.LONG_PRESS_CANDIDATES * 2
local udpSeen, tcpSeen = 0, 0
local base = #C4.timers
for i = 1, steps + 1 do probe.fn(probe) end
for i = base + 1, #C4.timers do C4.timers[i].fn(C4.timers[i]) end
for _, m in ipairs(C4.sent) do
  for _, c in ipairs(R.LONG_PRESS_CANDIDATES) do
    if (m.data == c and m.binding == 6002) then udpSeen = udpSeen + 1 end
    if (m.data == '!' .. #c .. '!' .. c and m.binding == 6001) then tcpSeen = tcpSeen + 1 end
  end
end
check('finder sends every candidate on UDP and TCP', udpSeen >= #R.LONG_PRESS_CANDIDATES and tcpSeen >= #R.LONG_PRESS_CANDIDATES, udpSeen .. '/' .. tcpSeen)
check('finder sends BACK between steps', lastSent(C4).data == 'back')
check('finder stops after last step', R.Timers.LongPressProbe == nil)

-- hold / repeat
R.ReceivedFromProxy(5001, 'START_DOWN', {})
check('START_DOWN sends once', lastSent(C4).data == 'dpadDown')
local n = #C4.sent
R.Timers.Repeat.fn(); R.Timers.Repeat.fn()
check('repeat timer resends', #C4.sent == n + 2 and lastSent(C4).data == 'dpadDown')
local rt = R.Timers.Repeat
R.ReceivedFromProxy(5001, 'STOP_DOWN', {})
check('STOP_DOWN cancels repeat', rt.cancelled and R.Timers.Repeat == nil)

-- overrides + keycode mode
R.Properties['Command Overrides'] = 'UP=tcp:key up; SELECT = ok ; LAUNCH=udp:start {pkg}/{activity}'
R.OnPropertyChanged('Command Overrides')
R.ReceivedFromProxy(5001, 'UP', {})
check('override with tcp: prefix framed', lastSent(C4).binding == 6001 and lastSent(C4).data == '!6!key up', lastSent(C4).data)
R.ReceivedFromProxy(5001, 'SELECT', {})
check('override trims spaces', lastSent(C4).data == 'ok')
R.Properties['Command Overrides'] = ''
R.OnPropertyChanged('Command Overrides')
R.Properties['Key Mode'] = 'Android Keycodes'
R.ReceivedFromProxy(5001, 'LEFT', {})
check('keycode mode LEFT -> keycode 21', lastSent(C4).data == 'keycode 21')
R.Properties['Key Mode'] = 'Zank Commands'

-- newline framing
R.Properties['TCP Framing'] = 'Newline'
R.SendRaw('hello', 'TCP')
check('newline framing', lastSent(C4).data == 'hello\n')
R.Properties['TCP Framing'] = '!len! header'

-- app list parsing: JSON array
local j1 = '[{"name":"Netflix","packageName":"com.netflix.ninja"},{"name":"My App","packageName":"com.example.app"}]'
R.ReceivedFromNetwork(6001, 1029, '!' .. #j1 .. '!' .. j1)
check('JSON app list stored', #R.PersistData.apps == 2, #R.PersistData.apps)
-- split across packets
local msg = '{"apps":[{"label":"Kodi","package":"org.xbmc.kodi"},{"label":"Plex","package":"com.plexapp.android"},{"label":"Other","package":"com.other.app"}]}'
local frame = '!' .. #msg .. '!' .. msg
R.ReceivedFromNetwork(6001, 1029, frame:sub(1, 20))
R.ReceivedFromNetwork(6001, 1029, frame:sub(21))
check('framed JSON across packets', #R.PersistData.apps == 3, #R.PersistData.apps)
check('Installed Apps property', C4.props['Installed Apps'] == '3 found')
-- line based
R.HandleMessage('Kodi|org.xbmc.kodi\ncom.foo.bar|Foo Bar\nPlain|com.plain.app')
check('line app list', #R.PersistData.apps == 3 and R.PackageFromLabel('Foo Bar') == 'com.foo.bar')
-- chatter must not wipe list
R.HandleMessage('ok')
check('chatter ignored', #R.PersistData.apps == 3)

local list = R.GetCommandParamList('Launch App', 'App')
local found = false
for _, v in ipairs(list) do if (v == 'Netflix (com.netflix.ninja)') then found = true end end
check('dynamic Launch App list includes presets', found)

-- programming commands
R.ExecuteCommand('Launch App', { App = 'Kodi (org.xbmc.kodi)' })
check('Launch App command', lastSent(C4).data == 'openApp org.xbmc.kodi', lastSent(C4).data)
check('CURRENT_APP variable', C4.vars.CURRENT_APP == 'Kodi')
check('App Launched event', C4.events[#C4.events] == 'App Launched')
n = #C4.sent
R.ExecuteCommand('Launch App', { App = 'Kodi (org.xbmc.kodi)' })
check('duplicate launch debounced', #C4.sent == n)
R.State.lastLaunch.time = 0
R.ExecuteCommand('Launch Package', { Package = 'not a package' })
check('invalid package rejected', #C4.sent == n)
R.ExecuteCommand('Send Text', { Text = 'star wars' })
check('Send Text', lastSent(C4).data == 'setFinalText star wars')
R.ExecuteCommand('Send Key', { Key = 'home' })
check('Send Key', lastSent(C4).data == 'home')
R.ExecuteCommand('Send Raw Command', { Command = 'getApps', Transport = 'TCP' })
check('Send Raw TCP', lastSent(C4).data == '!7!getApps')
R.ExecuteCommand('LUA_ACTION', { ACTION = 'Print Command Map' })
check('Print Command Map logs', #R._logs > 10)

-- colour buttons
R.Properties['Red Button App'] = 'Plex (com.plexapp.android)'
R.ReceivedFromProxy(5001, 'PROGRAM_A', {})
check('red button launches Plex', lastSent(C4).data == 'openApp com.plexapp.android')
R.Properties['Blue Button App'] = '(Default key)'
R.ReceivedFromProxy(5001, 'PROGRAM_D', {})
check('blue default key', lastSent(C4).data == 'keycode 186')

-- mini app via SET_INPUT (official UMA flow)
R.State.lastLaunch.time = 0
R.ReceivedFromProxy(5002, 'SET_INPUT', { INPUT = '3101', OUTPUT = '2110' })
check('SET_INPUT MiniApp 1 launches Netflix', lastSent(C4).data == 'openApp com.netflix.ninja', lastSent(C4).data)
n = #C4.sent
R.ExecuteCommand('ZANK_LAUNCH', { PACKAGE = 'com.netflix.ninja', NAME = 'Netflix' })
check('mini app ON right after SET_INPUT is de-duplicated', #C4.sent == n)
R.ReceivedFromProxy(5002, 'SET_INPUT', { INPUT = '3102' })
check('UMA with APP_NAME only resolves via presets', lastSent(C4).data == 'openApp com.disney.disneyplus', lastSent(C4).data)
R.State.lastLaunch.time = 0
R.ReceivedFromProxy(5002, 'SET_INPUT', { INPUT = '3103' })
check('third-party mini app resolved by Composer name', lastSent(C4).data == 'openApp com.google.android.youtube.tv', lastSent(C4).data)
n = #C4.sent
R.ReceivedFromProxy(5002, 'SET_INPUT', { INPUT = '3000' })
check('non mini app input launches nothing', #C4.sent == n)
R.State.lastLaunch.time = 0
R.ReceivedFromProxy(5002, 'SET_INPUT', { INPUT = '3102' })
R.ReceivedFromProxy(5002, 'SET_INPUT', { INPUT = '3110' })
check('unbound input is safe', lastSent(C4).data == 'openApp com.disney.disneyplus')
R.ReceivedFromProxy(5002, 'PASSTHROUGH', { PASSTHROUGH_COMMAND = 'RIGHT' })
check('switcher PASSTHROUGH -> dpadRight', lastSent(C4).data == 'dpadRight')
R.ReceivedFromProxy(5002, 'UP', {})
check('Virtual Switcher as Watch source: UP -> dpadUp', lastSent(C4).data == 'dpadUp')
R.ReceivedFromProxy(5002, 'START_DOWN', {})
check('Virtual Switcher hold repeats', R.Timers.Repeat ~= nil)
R.ReceivedFromProxy(5002, 'STOP_DOWN', {})
check('Virtual Switcher release stops', R.Timers.Repeat == nil)
n = #C4.sent
R.ReceivedFromProxy(5002, 'GET_STATE', {})
check('Virtual Switcher ignores GET_*', #C4.sent == n)

-- offline handling
R.OnConnectionStatusChanged(6001, 1029, 'OFFLINE')
R.OnConnectionStatusChanged(6002, 1028, 'OFFLINE')
R.State.lastSeen = 0
R.UpdateOnline()
check('offline variable', C4.vars.ONLINE == '0')
n = #C4.sent
R.ReceivedFromProxy(5001, 'UP', {})
check('no send while offline', #C4.sent == n)

-- missing IP
local R2, C42 = loadDriver(BUILD .. 'remote.lua', 40, remoteProps({ ['IP Address'] = '' }), newWorld())
R2.OnDriverInit(); R2.OnDriverLateInit()
check('no IP -> status prompt', (C42.props['Connection Status'] or ''):find('IP Address') ~= nil)

-- JSON decoder edge cases
check('json unicode', R.JSON.decode('["caf\\u00e9"]')[1] == 'caf\195\169')
check('json garbage -> nil', R.JSON.decode('{bad') == nil)

-- ================================================================ mini app driver
local world2 = newWorld()
local Rp, C4p = loadDriver(BUILD .. 'remote.lua', 10, remoteProps(), world2)
world2.devices[10] = Rp
Rp.OnDriverInit(); Rp.OnDriverLateInit()
Rp.OnConnectionStatusChanged(6002, 1028, 'ONLINE')

local M, C4m = loadDriver(BUILD .. 'miniapp_netflix.lua', 20, {
  ['App Name'] = 'Netflix', ['Package'] = 'com.netflix.ninja', ['Activity'] = '',
  ['Zank Remote Device'] = '', ['Debug Mode'] = 'Off' }, world2)
M.OnDriverInit(); M.OnDriverLateInit()
check('mini app publishes ZANK_PACKAGE', C4m.vars.ZANK_PACKAGE == 'com.netflix.ninja')
check('mini app finds parent', (C4m.props.Status or ''):find('remote device 10') ~= nil, C4m.props.Status)
M.ReceivedFromProxy(5001, 'ON', {})
check('mini app ON -> parent launch', lastSent(C4p).data == 'openApp com.netflix.ninja')
M.ReceivedFromProxy(5001, 'UP', {})
check('mini app passthrough UP', lastSent(C4p).data == 'dpadUp')
local cnt = #C4p.sent
M.ReceivedFromProxy(5001, 'GET_STATE', {})
check('mini app ignores GET_*', #C4p.sent == cnt)

local Mc, C4c = loadDriver(BUILD .. 'miniapp_netflix.lua', 50, {
  ['App Name'] = '', ['Package'] = '', ['Activity'] = '', ['Zank Remote Device'] = '', ['Debug Mode'] = 'Off' }, newWorld())
Mc.PRESET = { name = '', package = '', activity = '' }
Mc.OnDriverInit(); Mc.Publish()
check('custom mini app without package warns', (C4c.props.Status or ''):find('package') ~= nil, C4c.props.Status)

-- ================================================================ passthrough when the AV binding
-- cannot be walked downstream (what Composer showed): the remote announces itself instead
do
  local w = newWorld()
  w.consumers['21:2000'] = nil
  local Rr, C4r = loadDriver(BUILD .. 'remote.lua', 10, remoteProps(), w)
  w.devices[10] = Rr
  Rr.OnDriverInit(); Rr.OnDriverLateInit()
  Rr.OnConnectionStatusChanged(6002, 1028, 'ONLINE')
  local Mm, C4mm = loadDriver(BUILD .. 'miniapp_netflix.lua', 20, {
    ['App Name'] = 'Netflix', ['Package'] = 'com.netflix.ninja', ['Activity'] = '',
    ['Zank Remote Device'] = '', ['Debug Mode'] = 'Off' }, w)
  w.devices[20] = Mm
  Mm.OnDriverInit(); Mm.OnDriverLateInit()
  local before = #C4r.sent
  Mm.ReceivedFromProxy(5001, 'UP', {})
  check('reproduced: no parent before announce', #C4r.sent == before)
  check('mini app reports missing parent', (C4mm.props.Status or ''):find('Bind') ~= nil, C4mm.props.Status)
  check('announce reaches all 3 bound mini apps', Rr.AnnounceToMiniApps() == 3)
  check('mini app learned parent', Mm.PersistData.parentId == 10)
  Mm.ReceivedFromProxy(5001, 'UP', {})
  check('passthrough UP after announce', lastSent(C4r).data == 'dpadUp')
  Mm.ReceivedFromProxy(5001, 'START_LEFT', {})
  check('passthrough hold starts repeat', lastSent(C4r).data == 'dpadLeft' and Rr.Timers.Repeat ~= nil)
  Mm.ReceivedFromProxy(5001, 'STOP_LEFT', {})
  check('passthrough release stops repeat', Rr.Timers.Repeat == nil)
  Mm.ReceivedFromProxy(5001, 'CANCEL', {})
  check('passthrough CANCEL -> back', lastSent(C4r).data == 'back')
  -- SET_INPUT also announces (selection works even before the periodic announce)
  local w3 = newWorld(); w3.consumers['21:2000'] = nil
  local R3 = loadDriver(BUILD .. 'remote.lua', 10, remoteProps(), w3); w3.devices[10] = R3
  local M3 = loadDriver(BUILD .. 'miniapp_netflix.lua', 20, { ['App Name'] = 'Netflix', ['Package'] = 'com.netflix.ninja', ['Zank Remote Device'] = '' }, w3)
  w3.devices[20] = M3
  R3.OnDriverInit(); R3.OnDriverLateInit(); M3.OnDriverInit()
  R3.ReceivedFromProxy(5002, 'SET_INPUT', { INPUT = '3101' })
  check('SET_INPUT teaches mini app its parent', M3.PersistData.parentId == 10)
end

print(string.format('\n%d passed, %d failed', passed, failed))
if (failed > 0) then os.exit(1) end
