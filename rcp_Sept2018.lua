setTickRate(100) --100Hz 
tick = 0

-- What CAN bus ShiftX2 is connected to. 0=CAN1, 1=CAN2
sxCan = 1
-- 0=first ShiftX2 on bus, 1=second ShiftX2 (if ADR1 jumper is cut)
sxId = 0
--Brightness, 0-100. 0=automatic brightness
sxBright = 0
sxBrightScale = 45 --0-255 default is 51

sxCanId = 0xE3600 + (256 * sxId)
println('shiftx2 base id ' ..sxCanId)

--virtual channels 
--addChannel("name",SR,prec,min,max,"unit") 
speeddiff_id = addChannel("Speed_",10,0,0,160,"MPH") 

--global variables 
speed = 0 

local function updateCalcs() 
	local tirediameter = 24.7 

	local rpm = getTimerRpm(0)
	local rpm_diff = getTimerRpm(1) 
	speed = rpm_diff*tirediameter*0.002975 
	setChannel(speeddiff_id, speed) 
end 


local function sendCAN(can, id, data)
	local res = txCAN(can, id, 0, data,100)
	if res == 0 then println('txCAN failed, id:' ..id) end
end

local function sendHaltech_50()
	local rpm = getTimerRpm(0)
	local tps = getAnalog(3)*10 --convert % to 0.10% units
	local op = (getAnalog(2)*6.89476+100)*10 --convert psi to 0.1 kPa units

	--RPM, manifold pressure, TPS, coolant pressure
	sendCAN(0, 864, {spu(rpm), spl(rpm), 0, 0, spu(tps), spl(tps), 0, 0})

	--fuel pressure, oil pressure, accel pedal pos, wastegate pressure
	sendCAN(0, 865, {0, 0, spu(op), spl(op), 0, 0, 0, 0})
end

local function sendHaltech_20()
	local sped = speed*1.609344*10 --convert mph to 0.1km/h units
	
	--wheel speed gen., gear, 
	sendCAN(0, 880, {spu(sped), spl(sped), 0, 0, 0, 0, 0, 0})
end

local function sendHaltech_5()
	local ot = (((getAnalog(1) - 32)*5)/9 + 273.15)*10 --convert F to 0.1Kelvin units
	local wt = (((getAnalog(0) - 32)*5)/9 + 273.15)*10 --convert F to 0.1Kelvin units
	
	--coolant temp, air temp, fuel temp, oil temp
	sendCAN(0, 992, {spu(wt), spl(wt), 0, 0, 0, 0, spu(ot), spl(ot)})
end


function sxOnUpdate()
	sxUpdateLinearGraph(getTimerRpm(0)) --RPM
	sxUpdateAlert(0, getAnalog(0)) --water temp
	sxUpdateAlert(1, getAnalog(2)) --oil pressure
end

function sxOnInit()
  --config shift light
  sxCfgLinearGraph(0,0,0,7000) --left to right graph, linear style, 0 - 7000 RPM range

  sxSetLinearThresh(0,0,5000,0,255,0,0) --green at 5000 RPM
  sxSetLinearThresh(1,0,6000,255,255,0,0) --yellow at 6000 RPM
  sxSetLinearThresh(2,0,6500,255,0,0,0) --red  at 6500 RPM
  sxSetLinearThresh(3,0,6800,255,0,0,10) --red+flash at 6800 RPM
  
  --configure first alert (right LED) as engine temperature (F)
  sxSetAlertThresh(0,0,220,255,255,0,0) --yellow warning at 205F
  sxSetAlertThresh(0,1,225,255,0,0,10) -- red flash at 225F

  --configure second alert (left LED) as oil pressure (PSI)
  sxSetAlertThresh(1,0,0,255,0,0,10) --red flash below 7 psi
  sxSetAlertThresh(1,2,7,0,0,0,0) --above 7, no alert
end

function sxSetLinearThresh(id,s,th,r,g,b,f)
  sxTx(41,{id,s,spl(th),spu(th),r,g,b,f})
end

function sxSetAlertThresh(id,tid,th,r,g,b,f)
  sxTx(21,{id,tid,spl(th),spu(th),r,g,b,f})
end

function setBaseConfig(bright, brightscale)
  sxTx(3,{bright, brightscale})
end

function sxUpdateAlert(id,v)
  if v~=nil then sxTx(22,{id,spl(v),spu(v)}) end
end

function sxCfgLinearGraph(rs,ls,lr,hr) 
  sxTx(40,{rs,ls,spl(lr),spu(lr),spl(hr),spu(hr)})
end

function sxUpdateLinearGraph(v)
  if v ~= nil then sxTx(42,{spl(v),spu(v)}) end
end

function sxInit()
  println('Init ShiftX2')
  setBaseConfig(sxBright,sxBrightScale)
  if sxOnInit~=nil then sxOnInit() end
end

function sxChkCan()
  id,ext,data=rxCAN(sxCan,0)
  if id==sxCanId then sxInit() end
  if id==sxCanId+60 and sxOnBut~=nil then sxOnBut(data[1]) end
end

function sxProcess()
  sxChkCan()
  if sxOnUpdate~=nil then sxOnUpdate() end
end

function sxTx(offset, data)
  txCAN(sxCan, sxCanId + offset, 1, data)
end

function spl(v) return bit.band(v,0xFF) end
function spu(v) return bit.rshift(bit.band(v,0xFF00),8) end


function onTick()

  collectgarbage() 
  
  if tick%2 == 0 then --50Hz
	sendHaltech_50()
  end
  
  if tick%5 == 0 then --20Hz
    updateCalcs()
	sendHaltech_20()
  end
  
  if tick%10 == 0 then --10Hz
    sxProcess()
  end
  
  if tick%20 == 0 then --5Hz
	sendHaltech_5()
  end
  
  tick = tick +1
  if tick > 99 then tick = 0 end
end

sxInit()
