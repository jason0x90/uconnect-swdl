require "service"

local retries_iteration, retries_total = ...

gpsSvc="com.harman.service.NDR"
gpsMethod="JSON_GetProperties"
gpsParams={inprop={'SEN_GPSInfo'}}
name = "com.harman.service.EmbeddedPhone"
filename = "/tmp/GPSResetAR5550_count"
logname = "/fs/etfs/usr/var/ecall/GPSReset.log"
retries_iteration = tonumber(retries_iteration)
retries_total = tonumber(retries_total)

function sendReset()
	method = "debugAT"
	params = {atString = "AT!RESET\r"}
	service.invoke(name, method, params, timeout)
end

function getCompletedRetries()
	fd = io.open(filename, "r")
	if (fd == nil) then
		return 0
	end
	local retVal = fd:read("*n")
	fd:close()
	return tonumber(retVal)
end

function writeCompletedRetries(numToWrite)
	fd = io.open(filename, "w+")
	if (fd == nil) then
		os.execute("touch "..filename)
		fd = io.open(filename, "w+")
	end
	fd:write(numToWrite)
	fd:flush()
	fd:close()
end

function logLine(msg)
	print("***"..msg.."***")
	local fd = io.open(logname, "a+")
	if (fd ~= nil) then
		fd:write(os.date()..": "..msg.."\n")
		fd:flush()
	end
	fd:close()
end

function isClockActive()
	local resp = nil
	local e = nil
	first_time = 0
	second_time = 0

    local resp,e = service.invoke(gpsSvc,gpsMethod,gpsParams)
    if resp and resp.outprop and resp.outprop.SEN_GPSInfo then
		local gpsInfo = resp.outprop.SEN_GPSInfo
		first_time = gpsInfo.sec
	end

	os.sleep(5)

	resp,e = service.invoke(gpsSvc, gpsMethod, gpsParams)
	if resp and resp.outprop and resp.outprop.SEN_GPSInfo then
		gpsInfo = resp.outprop.SEN_GPSInfo
		second_time = gpsInfo.sec
	end

	if first_time == second_time then
		return false
	end

	return true
end

function isSWIUSB3Up()
	local f = io.open("/dev/swiusb3","r")
	if nil ~= f then
		io.close(f)
		return true
	end
	return false
end

function isResetSierraInprogressMarkerExist()
	local f = io.open("/tmp/resetSierraInprogress","r")
	if nil ~= f then
		io.close(f)
		return true
	end
	return false
end

retries = getCompletedRetries()
local exitnow = false
exitnow = isResetSierraInprogressMarkerExist()
for i=1,retries_iteration,1 do
	if exitnow == true then
		logLine("Reset Sierra Inprogress marker file exist.exit now")
		break
	end

	if (retries + i <= retries_total) then
		os.execute('slay -f vdev-flexgps')
		logLine("Reset Sierra AR5550 due to GPS issue.  Has reset "..retries+i.." times")
		sendReset()
		writeCompletedRetries(retries+i)
		while false == isSWIUSB3Up() do
			exitnow = isResetSierraInprogressMarkerExist()
			if exitnow == true then
				logLine("Reset Sierra Inprogress already. Exit waiting for swiusb3 now")
				break
			end
			os.sleep(10)
		end
		os.sleep(10)
		if isClockActive()==true or exitnow == true then
			break
		end
		if i < retries_iteration then
			os.execute('slay -f vdev-flexgps')
			os.sleep(180)
		else
			logLine("Have exhausted retries in this iteration. exit")
		end
	else
		logLine("embedded call NOT Active, but Sierra Module reset limit reached.  Do not reset again")
		os.execute("touch /tmp/resetFlexGPSOnly")
		break;
	end
end
