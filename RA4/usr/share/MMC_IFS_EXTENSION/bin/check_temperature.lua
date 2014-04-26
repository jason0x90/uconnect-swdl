#!/usr/bin/lua

require "service"

resp,err = service.invoke("com.harman.service.OmapTempService", "getOmapTemperature", {} )

if (err == nil) and (resp.omapTemp ~= nil) then
	-- print("Temperature is ", resp.omapTemp)
	
	if(resp.omapTemp > -20) then
		os.exit(0) -- temperature is acceptable
	else
		os.exit(-1) -- temperature is NOT acceptable
	end
end
