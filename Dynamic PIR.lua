--[[
Dynamic triggered light level
-----------------------------

Resident, zero delay, name: 'Dynamic PIR'

Set a light level when triggered by a PIR to differing set points throughout a day.

At sunrise the target level is set to high, then lowered at a specified evening time, the lowered
again at a subsequent time or when a late night scene is set. When the optional 'scene' is set then
the target level will be immediately set to super-low. The late night scene is triggered elsewhere
(a key?).

If the group is manually set to off (or by a scene), then control of the group by this script will
suspend for a given 'egress' to allow for area egress with the PIR disabled. Useful for turning off
the hall or toilet light when leaving and not having the PIR trigger again.

If the group is manually set to a level other than the script target (like with a switch timer) then
this script will not turn it off after the timer runtime. To re-enable the timer function the group
must be switched to off.

A PIR to turn on the group should be configured to pulse a lighting group (the 'trigger' group) for 
approx one second, and also have a lighting group (the 'enable' group) for that PIR defined.

Set keywords for the trigger group, which will be read by this script.
  DPIR
  grp= Group to control (mandatory)
  en= Enable group (mandatory)
  run= Runtime
  lv= Dynamic levels - 3x separated by slash = daytime/low/super-low (super-low optional)
  hr= Hour transitions - 2x sep by / = hour-for-low/hour-for-super-low (super-low optional)
  ramp= Ramp rate - 2x sep by / = ramp-on/ramp-off
  dd= Seconds to allow for egress (disable duration)
  scene= Name of a late night scene (when set make immediate switch to super-low dynamic level)

Defaults are noted below in variables.

Keyword examples, applied to each PIR trigger group:

DPIR, grp=Hall Mid Pendants, en=Hall PIR_1 Enable, run=90, lv=127/89/31, hr=22/0, ramp=4/12, dd=15, scene=Late night, 
DPIR, grp=Hutch Bathroom, en=Hutch Bathroom PIR Enable, run=300, lv=179/127, hr=22, ramp=0/12, dd=5, 
DPIR, grp=Outside Carport, en=Outside Carport Enable, run=120, lv=205/153, hr=22, ramp=4/8, dd=15, 
DPIR, grp=Kitchen Pantry LV, en=Kitchen Pantry PIR Enable, run=60, lv=240/180/80, hr=22/0, ramp=0/20, dd=0, 

Changes to keywords are not detected (to improve performance), and require a resident script re-start.
--]]

local logging = false

-- Runtime global variable checking. Globals must be explicitly declared, which will catch variable name typos
local declaredNames = {['vprint'] = true, ['vprinthex'] = true, ['maxgroup'] = true, }
local function declare(name, initval) rawset(_G, name, initval) declaredNames[name] = true end
local exclude = {['ngx'] = true, }
setmetatable(_G, {
  __newindex = function (t, n, v) if not declaredNames[n] then log('Warning: Write to undeclared global variable "'..n..'"') end rawset(t, n, v) end,
  __index = function (_, n) if not exclude[n] and not declaredNames[n] then log('Warning: Read undeclared global variable "'..n..'"') end return nil end,
})

local defaultRun = '120'; local defaultLv = '210/127/127'; local defaultHr = '22/0'; local defaultRamp = '4/8'; local defaultDd = '15'; local defaultScene = '' -- Defaults for trigger groups
local busTimeout = 1
local received = nil
local pirs = {}
local targets = {}

--[[
C-Bus callback
--]]

local function eventCallback(event)
  local level = tonumber(string.sub(event.datahex,1,2),16)
  if pirs[event.dst] then if level > 0 then received = event.dst return end end
  if targets[event.dst] then
    local ramp = tonumber(string.sub(event.datahex,7,8),16)
    if event.sender == 'cl' then -- Script initiated a ramp
      if ramp > 0  then -- Ramp begin
        targets[event.dst].targetLevel = tonumber(string.sub(event.datahex,3,4),16)
        targets[event.dst].ramping = true
        return
      end
      targets[event.dst].level = level
    else
      targets[event.dst].level = level
      if level == targets[event.dst].targetLevel then targets[event.dst].ramping = false targets[event.dst].targetLevel = -1 end -- Ramp end
    end
  end
end

local localbus = require('localbus').new(busTimeout) -- Set up the localbus
localbus:sethandler('groupwrite', eventCallback)

--[[
Utility functions
--]]

require('uci')
local sunrise, sunset
local function calculateSunriseSunset() sunrise, sunset = rscalc(tonumber(uci.get('genohm-scada.core.latitude')), tonumber(uci.get('genohm-scada.core.longitude'))) end

local function isEmpty(s) return s == nil or s == '' end

local timer = {}
local function timerStart(alias) timer[alias] = { timerStarted = os.time(), timerDuration = pirs[alias].runtime } end
local function timerStop(alias) timer[alias] = { timerStarted = 0, timerDuration = 0 } end
local function timerExpired(alias) return (timer[alias].timerStarted == 0) or (os.time() - timer[alias].timerStarted >= timer[alias].timerDuration) end

local function simulateTrigger(pir) PulseCBusLevel(pir.net, pir.app, pir.dTrigger, 255, 0, 1, 0) end -- Simulate a PIR trigger

--[[
Initialisation
--]]

local grps = GetCBusByKW('DPIR', 'or')
local found = {}
local n = 0
local k, v

for k, v in pairs(grps) do
  local error = false
  local run = defaultRun; local lv = defaultLv; local hr = defaultHr; local ramp = defaultRamp; local dd = defaultDd; local scene = defaultScene -- Reset to defaults
  local net = v['address'][1]; local app = v['address'][2]; local group = v['address'][3]
  local alias = net..'/'..app..'/'..group
  local target, en
  pirs[alias] = {}

  for _, t in ipairs(v['keywords']) do
    local tp = string.split(t, '=')
    tp[1] = trim(tp[1])
    if tp[2] then
      tp[2] = trim(tp[2])
      if tp[1] == 'grp' then target = tp[2]
      elseif tp[1] == 'en' then en = tp[2]
      elseif tp[1] == 'run' then run = tp[2]
      elseif tp[1] == 'lv' then lv = tp[2]
      elseif tp[1] == 'hr' then hr = tp[2]
      elseif tp[1] == 'ramp' then ramp = tp[2]
      elseif tp[1] == 'dd' then dd = tp[2]
      elseif tp[1] == 'scene' then scene = tp[2]
      end
    end
  end
  pirs[alias] = {
    net = net,
    app = app,
    dGroup = GetCBusGroupAddress(net, app, target),
    dTrigger = group,
    dTriggerEn = GetCBusGroupAddress(net, app, en),
    dTriggerAlias = net..'/'..app..'/'..GetCBusGroupAddress(net, app, en),
    runtime = tonumber(run),
    egress = tonumber(dd),
    scene = scene
  }
  local parts
  parts = string.split(lv, '/')
  if #parts == 3 then
    pirs[alias].levelHigh = tonumber(parts[1])
    pirs[alias].levelLow = tonumber(parts[2])
    pirs[alias].levelSuperLow = tonumber(parts[3])
  elseif #parts == 2 then
    pirs[alias].levelHigh = tonumber(parts[1])
    pirs[alias].levelLow = tonumber(parts[2])
    pirs[alias].levelSuperLow = pirs[alias].levelLow
  else
    log('ERROR: Need two or optionally three parts for "lv" keyword of '..alias..' (high/low/optional super-low)')
    error = true
  end
  parts = string.split(hr, '/')
  if #parts == 2 then
    pirs[alias].hourLow = tonumber(parts[1])
    pirs[alias].hourSuperLow = tonumber(parts[2])
  elseif #parts == 1 then
    pirs[alias].hourLow = tonumber(parts[1])
    pirs[alias].hourSuperLow = 0
  else
    log('ERROR: Need at least one part for "hr" keyword of '..alias..' (hour-low/optional hour-super-low)')
    error = true
  end
  parts = string.split(ramp, '/')
  if #parts == 2 then
    pirs[alias].rampOn = tonumber(parts[1])
    pirs[alias].rampOff = tonumber(parts[2])
  else
    log('ERROR: Need two parts for "ramp" keyword of '..alias..' (ramp on/ramp off)')
    error = true
  end
  if error then pirs[alias] = nil end
end

calculateSunriseSunset()

local now = os.date('*t')
local nowMinute = now.hour * 60 + now.min
local lastMinute = -1

for k, pir in pairs(pirs) do
  timerStop(k)

  pir.target = pir.net..'/'..pir.app..'/'..pir.dGroup
  targets[pir.target] = {
    targetLevel = -1,
    level = grp.getvalue(pir.target),
    ramping = false
  }
  SetCBusState(pir.net, pir.app, pir['dTriggerEn'], true)
  pir.dynamicSet = pir.levelHigh

  if pir.hourLow * 60 > sunrise then -- i.e. Low is before midnight
    pir.dynamicSet = pir.levelSuperLow
    if nowMinute >= sunrise then pir.dynamicSet = pir.levelHigh end
    if now.hour >= pir.hourLow then pir.dynamicSet = pir.levelLow end
    if pir.hourSuperLow > pir.hourLow and now.hour >= pir.hourSuperLow then pir.dynamicSet = pir.levelSuperLow end -- For super-low before midnight too
  else -- Low is after midnight
    pir.dynamicSet = pir.levelHigh
    if nowMinute < sunrise then
      if nowMinute >= pir.hourLow * 60 then pir.dynamicSet = pir.levelLow end
      if nowMinute >= pir.hourSuperLow * 60 then pir.dynamicSet = pir.levelSuperLow end -- Super-low must be after low
    end
  end
  pir.oldDynamicSet = pir.dynamicSet

  if logging then log(
    'Initialised DPIR target '..pir.target..
    ', dynamic level ' .. pir.dynamicSet..
    ', level='..pir.levelHigh..'/'..pir.levelLow..'/'..pir.levelSuperLow..
    ', hour='..pir.hourLow..'/'..pir.hourSuperLow..
    ', ramp='..pir.rampOn..'/'..pir.rampOff..
    ', run='..pir.runtime..
    ', egress='..pir.egress
  ) end
  if GetCBusLevel(pir.net, pir.app, pir.dGroup) == pir.dynamicSet then -- If the group is currently at the dynamic level then start the timer
    if logging then log(pir.target..' at desired level, so starting timer') end
    timerStart(k)
  end
  pir.lateNightSet = false
  pir.suspended = nil
  pir.oldGroupLevel = grp.getvalue(pir.target)
end

log('DPIR initialised')


--[[
PIR trigger processing
--]]

local function processTrigger(alias)
  local pir = pirs[alias]
  local target = pir.target
  if not pir.suspended then
    if timer[alias].timerStarted > 0 then
      if logging then log(target..' triggered, reset timer') end
      timerStart(alias) -- Reset the timer if already running
    else
      local groupLevel = targets[target].level
      if groupLevel == 0 or groupLevel == pir.dynamicSet or pir.rampingOff then -- Turn on the group and start the timer
        if logging then log(target..' triggered, turning on') end
        SetCBusLevel(pir.net, pir.app, pir.dGroup, pir.dynamicSet, pir.rampOn)
        groupLevel = pir.dynamicSet
        timerStart(alias)
        if pir.rampingOff then
          pir.rampingOff = false
          if logging then log(pir.target..' ramping off cleared') end
        end
      else
        if logging then log(target..' was not turned on, dynamicSet='..pir.dynamicSet..', rampingOff='..tostring(pir.rampingOff)) end
      end
      pir.groupLevel = groupLevel
    end
  else
    if logging then log(target..' suspended, doing nothing') end
  end
end
    
    
--[[
Main loop
--]]

local setDR = false
local setSR = false

while true do
  localbus:step()

  local groupLevel

  now = os.date('*t')

  for alias, pir in pairs(pirs) do
    local level = targets[pir.target].level

    if pir.rampingOff and level == 0 then
      pir.rampingOff = false
      if logging then log(pir.target..' ramping off cleared') end
    end
    if not targets[pir.target].ramping then groupLevel = level else groupLevel = pir.oldGroupLevel end
  
    if not pir.suspended then -- Suspension occurs to allow egress
      if (groupLevel ~= pir.oldGroupLevel) then
        -- if logging then log('Group change, old='..pir.oldGroupLevel..', new='..groupLevel) end
        pir.oldGroupLevel = groupLevel

        -- CHECK FOR GROUP TURNED OFF
        if timer[alias].timerStarted > 0 and groupLevel == 0 then
          if logging then log(pir.target..' has been turned off') end
          if grp.getvalue(pir.dTriggerAlias) > 0 then
            PulseCBusLevel(pir.net, pir.app, pir.dTriggerEn, 0, 0, pir.egress, 255)
            if logging then log(pir.target..' stopping timer and delaying '..pir.egress..' seconds') end
            timerStop(alias)
            received = nil -- Clear any pending triggers
            pir.suspended = os.time() -- Suspend trigger detection until the end of the disable duration, as no point running
          end
        end

        -- DESIRED STATE SENSE
        if level == pir.dynamicSet then
          if logging then log(pir.target..' is at desired level of '..pir.dynamicSet) end
          if timer[alias].timerStarted == 0 then
            if logging then log(pir.target..' turned on at target level, so simulating PIR trigger') end
            simulateTrigger(pir)
          end
        end
      end

      -- CHECK FOR TIMER EXPIRY
      if timer[alias].timerStarted > 0 then
        if timerExpired(alias) then
          if logging then log(pir.target..' timer expired') end
          if groupLevel == pir.dynamicSet then
            if logging then log(pir.target..' ramping off') end
            SetCBusLevel(pir.net, pir.app, pir.dGroup, 0, pir.rampOff)
            pir.rampingOff = true
          else
            if groupLevel == pir.oldDynamicSet then
              if logging then log(pir.target..' at prior expected level ('..groupLevel..', so setting to target level and simulating a trigger') end
              SetCBusLevel(pir.net, pir.app, pir.dGroup, pir.dynamicSet, pir.rampOn)
              simulateTrigger(pir)
            else
              if logging then log(pir.target..' at unexpected level ('..groupLevel..', expected '..pir.dynamicSet..'), doing nothing (re-switching off if already off)') end
              if not groupLevel then grp.setlevel(pir.target) end
            end
          end
          timerStop(alias)
        end
      end

    else
      -- PIR IS SUSPENDED...
      if os.time() - pir.suspended >= pir.egress then
        pir.suspended = nil
        if logging then log(pir.target..' resumed') end
      else
        if level == pir.dynamicSet then -- manually switched on again, so re-trigger
          pir.suspended = nil
          if logging then log(pir.target..' turned on again before egress duration, so re-triggering PIR') end
          simulateTrigger(pir)
        end
      end
    end -- if not suspended

    -- CHECK FOR LATE NIGHT SCENE SET
    if not isEmpty(pir['scene']) then
      local sceneSet = SceneIsSet(pir['scene'])
      if not pir.lateNightSet and sceneSet then
        pir.lateNightSet = true
        pir.dynamicSet = pir.levelSuperLow
        if logging then log(pir.target..' adjusted for late night mode at level '..pir.dynamicSet) end
        if groupLevel > 0 and timer[alias].timerStarted > 0 then -- Group is on, so adjust it
          simulateTrigger(pir)
          pir.rampingOff = true
        end
      else
        if pir.lateNightSet and (not sceneSet) then
          pir.lateNightSet = false
          if logging then log(pir.target..' late night mode off') end
          if pir.hourLow * 60 > sunrise then -- i.e. Low is before midnight
            if now.hour < pir.hourLow then pir.dynamicSet = pir.levelHigh else pir.dynamicSet = pir.levelLow end
            if pir.hourSuperLow > pir.hourLow and now.hour >= pir.hourSuperLow then pir.dynamicSet = pir.levelSuperLow end
          else
            pir.dynamicSet = pir.levelHigh
            nowMinute = now.hour * 60 + now.min
            if nowMinute < sunrise then
              if nowMinute >= pir.hourLow * 60 then pir.dynamicSet = pir.levelLow end
              if nowMinute >= pir.hourSuperLow * 60 then pir.dynamicSet = pir.levelSuperLow end
            end
          end
          if logging then log(pir.target..' adjusted dynamic level to '..pir.dynamicSet) end
        end
      end
    end
  end -- for alias in

  -- PROCESS ANY RECEIVED MESSAGE
  -- Done after checks above, mostly to cater for group manually turned off
  if received ~= nil then processTrigger(received) received = nil end

  -- ADJUST TARGET GROUP DYNAMIC LIGHT LEVEL
  local function setDynamicGroupLevel(pir, level)
    local oldLevel = pir.dynamicSet
    pir.dynamicSet = level
    if pir.dynamicSet ~= oldLevel then if logging then log('Adjusted DPIR target '..pir.target..' dynamic level ' .. pir.dynamicSet) end end
    pir.oldDynamicSet = oldLevel
    if targets[pir.target].level > 0 then -- Lights are on, so set the new level and start the timer
      SetCBusLevel(pir.net, pir.app, pir.dGroup, pir.dynamicSet, pir.rampOn)
      simulateTrigger(pir)
    end
  end
  if now.min ~= lastMinute and not setDR then -- check for change every minute
    lastMinute = now.min
    nowMinute = now.hour * 60 + now.min
    if nowMinute == sunrise then -- Reset to high at sunrise
      setDR = true
      for alias, pir in pairs(pirs) do setDynamicGroupLevel(pir, pir.levelHigh) end
    end
    if now.min == 0 then -- check transition to low/super low
      setDR = true
      for alias, pir in pairs(pirs) do
        if now.hour == pir.hourLow then if pir.dynamicSet ~= pir.levelSuperLow then setDynamicGroupLevel(pir, pir.levelLow) end end -- Set to low if the right hour, unless already at super-low because of scene trigger
        if now.hour == pir.hourSuperLow then setDynamicGroupLevel(pir, pir.levelSuperLow) end -- Set to super-low if the right hour
      end
    end
  end
  if setDR and now.min == 1 then setDR = false end -- Reset the time-based 'set' flag

  -- CALCULATE SUNRISE/SUNSET ONCE PER DAY
  if now.hour == 1 and now.min == 0 and not setSR then calculateSunriseSunset() setSR = true if logging then log('Sunrise set to: '..sunrise..', and sunset: '..sunset) end end
  if setSR and now.min == 1 then setSR = false end -- Reset the time-based 'set' flag
end