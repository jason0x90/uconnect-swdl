---------------------------------------------------------------------------
-- CAN application message manager service for
-- Connected Vehicle Platform (CVP) Test
---------------------------------------------------------------------------

require "service"

busname = "com.harman.service.CANAppMsgMngr"

function invoke(method, params, timeout)
   local invokeResult, error = service.invoke(busname, method, params, timeout)
   if invokeResult == nil then
		--get error
		print("empty result. err msg: ", error)
   else
		print("Invoke result ----", busname, method)
		pr(invokeResult)
   end
   return invokeResult

end

function pr(t)
   if type(t) == 'table' then
      for k,v in pairs(t) do
         print('',k,v)
         if type(v) == 'table' then
            for k,v in pairs(v) do
               print('','',k,v)
            end
         end
      end
   else
      print(t)
   end
end

function printSignal(signal, params)
   print("signal", signal)
   for k,v in pairs(params) do print(k,v) end
end

function subscribe(signal, handler)
   return assert(service.subscribe(busname, signal, handler or printSignal))
end

-------------

function lockdoor(parm)
	if parm == "true" then
		return invoke("doorLock")
	else
		return invoke("doorUnlock")
	end
end


function getVehicleVIN()
	return invoke("getVIN")
end

function setAlarmStatus(stateRq)
    print("Requested alarm state: ", stateRq)
	local result = invoke("setAlarm", {state=stateRq})
end
-- Valid State Requests are:
-- "alarmOff", "alarmOnLightsOnly", "alarmOnLightsAndHorn"


function getprop(name)
   local result = invoke("getProperties",{props={name}})
   return result[name]
end


function getProps(properties)
   props = {}
   if type(properties) == 'table' then
		for k,v in pairs(properties) do
			props[k] = v
		end
   else
		props = properties
   end

   return invoke("getProperties", {props = props})
end

function getAllProps()
   return invoke("getAllProperties")
end


function onSignal(signal, data)
   print("receive signal -- ", signal)
   pr(data)
end

-------------
-- props

subscribe("doorStatus", onSignal)
print("Subscribe to doorStatus")

subscribe("telematicCall", onSignal)
print("Subscribe to telematicCall")

subscribe("alarmStatus", onSignal)
print("Subscribe to alarmStatus")






