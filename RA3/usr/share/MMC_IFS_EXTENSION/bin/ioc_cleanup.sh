#!/usr/bin/lua

----------------------------------------------------------------------------------------
-- Make the V850 reset it's EEPROM
-- Note that the code to reset is 0xf4 and the response is 0xf4
-- Note that 0x14 will be output by the V850 during EEPROM reset and should be ignored
----------------------------------------------------------------------------------------

require "ipc"

local hex_f4 = 244 -- $F4
local hex_14 = 20  -- $14
local max_reads = 10 -- maximum number of read attempts

local function main()

	local done = false
	local msg,err

	local ch7,err = ipc.open(7, "rw")
	if (err ~= nil) then
		print("ioc_cleanup: error - unable to open IPC channel 7 ("..err..")")
		os.exit(-1)
	end

	print("ioc_cleanup: V850 EEPROM reset started")
	msg,err = ch7:write(string.char(hex_f4))
	if(err ~= nil) then
		print("ioc_cleanup: error - write ("..err..")")
		os.exit(-1)
	end

	local tries = 0
	repeat
		msg,err = ch7:read(500)
		if(err ~= nil) then
			print("ioc_cleanup: error - read ("..err..")")
			os.exit(-1)
		end

		if(msg[1] == hex_f4) then
			done = true
		elseif(msg[1] == hex_14) then
			-- ignore this
		else
			print("ioc_cleanup: error - improper responses while trying V850 EEPROM reset")
			os.exit(-1)
		end

		tries = tries + 1
		if(tries >= max_reads) then
			print("ioc_cleanup:  error - maximum number of read attempts ("..tries..")")
			os.exit(-1)
   	end

	until done

	print("ioc_cleanup: V850 EEPROM reset complete")
	os.exit()

end

main()
