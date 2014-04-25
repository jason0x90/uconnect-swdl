local ipc     = require "ipc"
local timer   = require "timer"
local respMsg = {}

-- open the IPC channel to send pet to
local chan2 = assert(ipc.open(2))

if arg[1] and arg[1] == "i" then
   -- send initializing message
   respMsg = { 0x02, 0x01, 0x03, 0x00 }
   chan2:write(respMsg)

   -- send request for hardware type
   respMsg = { 0x11, 0x00 }
   chan2:write(respMsg)
end

-- send the petting signal
respMsg = { 0x02, 0x02, 0x03, 0x03 }

-- Start watchdog timer
function petWatchdog()
   chan2:write(respMsg)
end

-- create and start
local watchdogTimer = timer.new(petWatchdog)
watchdogTimer:start(500,140)

