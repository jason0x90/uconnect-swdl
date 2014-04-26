require "service"

local retries_total = ...

epsSvc="com.harman.service.EmbeddedPhone"
epsMethod="getProperties"
epsParams={props={'embeddedPhoneStatus'}}

name_1 = "com.harman.service.EmbeddedPhone"
name_2 = "com.harman.service.ecallService"
filename = "/tmp/GPSResetAR5550_count"
logname = "/fs/etfs/usr/var/ecall/GPSReset.log"
retries_total = tonumber(retries_total)

function sendHardGPSReset()
	method = "hardResetGPS"
	params = {}
	service.invoke(name_2, method, params, timeout)
end

function sendSoftGPSReset()
	method = "debugAT"
	params = {atString = "AT!RESET\r"}
	service.invoke(name_1, method, params, timeout)
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
	print("** restartGPS:"..msg.." **")
	local fd = io.open(logname, "a+")
	if (fd ~= nil) then
		fd:write(os.date('!%c')..": "..msg.."\n")
		fd:flush()
	end
	fd:close()
end

retries = getCompletedRetries()
if (retries < retries_total) then
   local resp,e = service.invoke(epsSvc,epsMethod,epsParams)
   if (resp.embeddedPhoneStatus.status == true) then
      logLine("Sending Soft Reset to Sierra AR5550 Module.")
      sendSoftGPSReset()
   else
      logLine("Sending Hard Reset to Sierra AR5550 Module.")
      sendHardGPSReset()
   end
   retries=retries+1
   writeCompletedRetries(retries)
   logLine("Reset Sierra AR5550 due to GPS issue.  Has reset "..retries.." times")
else
   logLine("embedded call NOT Active, but Sierra Module reset limit reached.  Do not reset again")
end
