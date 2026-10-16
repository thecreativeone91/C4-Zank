--[[
  Zank Mini App - open source Control4 mini app driver for the Zank Android Remote.

  Bind this driver's "Mini App Out" connection to an "Android App n" input
  on the Zank Android Remote's Virtual Switcher.  When the mini app is chosen
  in Navigator, the remote driver reads ZANK_PACKAGE from this driver and launches
  it on the Android box.  Remote commands are passed through to the box.

  License: MIT
]]

PROXY = 5001
MINIAPP_OUT = 2000
PARENT_SWITCHER_PROXY = 5002

PRESET = PRESET or { name = '', package = '', activity = '' }
--@@PRESET@@

Timers = Timers or {}

function dbg(...)
  if (Properties and Properties['Debug Mode'] == 'On') then
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print('[Zank MiniApp] ' .. table.concat(parts, ' '))
  end
end

function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

function looksLikePackage(s)
  s = trim(s)
  return s ~= '' and not s:find('%s') and s:find('^[%a_][%w_]*%.[%w_%.]+$') ~= nil
end

function AppName()
  local n = trim(Properties['App Name'])
  if (n == '') then n = PRESET.name end
  if (n == '') then n = 'Custom App' end
  return n
end

function AppPackage()
  local p = trim(Properties['Package Override'] or '')
  if (p == '') then p = trim(Properties['Package'] or '') end
  if (p == '') then p = PRESET.package end
  return p
end

function AppActivity()
  local a = trim(Properties['Activity'] or '')
  if (a == '') then a = PRESET.activity or '' end
  return a
end

function Publish()
  local pkg = AppPackage()
  C4:SetVariable('ZANK_PACKAGE', pkg)
  C4:SetVariable('ZANK_ACTIVITY', AppActivity())
  C4:SetVariable('APP_NAME', AppName())
  C4:SetVariable('APP_ID', pkg)
  local parent = FindParent()
  local status
  if (not looksLikePackage(pkg)) then
    status = 'Set the Android package name'
  elseif (parent) then
    status = 'Ready: ' .. AppName() .. ' -> ' .. pkg .. ' (remote device ' .. parent .. ')'
  else
    status = 'Bind this mini app to an Android App input on the Zank Virtual Switcher'
  end
  C4:UpdateProperty('Status', status)
end

-- Walk the bindings back to the Zank Android Remote protocol driver:
-- this driver -> my proxy -> (app output) -> Virtual Switcher proxy -> remote driver
PersistData = PersistData or {}

-- Parent lookup order:
--   1. the remote that announced itself with ZANK_SET_PARENT (normal case)
--   2. walking the AV binding downstream (works on some OS versions only)
function FindParent()
  if (tonumber(PersistData.parentId or '')) then return tonumber(PersistData.parentId) end
  local myProxy = next(C4:GetBoundConsumerDevices(C4:GetDeviceID(), PROXY) or {})
  if (not myProxy) then return nil end
  local switcher = next(C4:GetBoundConsumerDevices(myProxy, MINIAPP_OUT) or {})
  if (not switcher) then return nil end
  local parent = C4:GetBoundProviderDevice(switcher, PARENT_SWITCHER_PROXY)
  if (parent and parent ~= 0) then return parent end
  return nil
end

function SendToParent(cmd, params)
  local parent = FindParent()
  if (not parent) then
    print('[Zank MiniApp] ' .. AppName() .. ': no Zank Android Remote known yet, dropping ' .. tostring(cmd) ..
      '. Bind this mini app to a Virtual Switcher Android App input, or run "Print Mini App Bindings" on the remote.')
    return false
  end
  dbg('->', parent, cmd, params and params.COMMAND or '')
  C4:SendToDevice(parent, cmd, params or {})
  return true
end

function Launch()
  local pkg = AppPackage()
  if (not looksLikePackage(pkg)) then
    print('[Zank MiniApp] ' .. AppName() .. ': no valid Android package set')
    return
  end
  SendToParent('ZANK_LAUNCH', { PACKAGE = pkg, ACTIVITY = AppActivity(), NAME = AppName() })
end

IGNORED = { OFF = true, CONNECT = true, DISCONNECT = true }

function ReceivedFromProxy(idBinding, strCommand, tParams)
  if (strCommand == nil) then return end
  dbg('Proxy', idBinding, strCommand)
  if (idBinding ~= PROXY) then return end
  if (strCommand == 'ON') then
    -- The remote driver also launches on SET_INPUT; it de-duplicates the two.
    Launch()
  elseif (strCommand:find('^GET_') or IGNORED[strCommand]) then
    return
  else
    SendToParent('ZANK_PASSTHROUGH', { COMMAND = strCommand })
  end
end

function ExecuteCommand(strCommand, tParams)
  tParams = tParams or {}
  if (strCommand == 'ZANK_SET_PARENT') then
    local id = tonumber(tParams.PARENT_ID or '')
    if (id and id ~= tonumber(PersistData.parentId or '')) then
      PersistData.parentId = id
      dbg('Parent set to', id, 'input', tParams.INPUT)
      Publish()
    end
    return
  end
  if (strCommand == 'LUA_ACTION') then
    if (tParams.ACTION == 'Launch Now') then Launch()
    elseif (tParams.ACTION == 'Check Binding') then Publish() end
  elseif (strCommand == 'Launch') then
    Launch()
  end
end

function OnPropertyChanged(strProperty)
  Publish()
end

function OnBindingChanged(idBinding, strClass, bIsBound)
  Publish()
end

function OnDriverInit()
  C4:AddVariable('ZANK_PACKAGE', '', 'STRING')
  C4:AddVariable('ZANK_ACTIVITY', '', 'STRING')
  C4:AddVariable('APP_NAME', '', 'STRING')
  C4:AddVariable('APP_ID', '', 'STRING')
end

function OnDriverLateInit()
  C4:UpdateProperty('Driver Version', C4:GetDriverConfigInfo('version'))
  if (trim(Properties['App Name'] or '') == '' and PRESET.name ~= '') then
    C4:UpdateProperty('App Name', PRESET.name)
  end
  Publish()
  -- bindings may settle after init on a controller reboot
  Timers.Late = C4:SetTimer(10000, function() Publish() end)
end
