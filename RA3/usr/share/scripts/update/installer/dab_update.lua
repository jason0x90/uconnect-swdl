-- DAB Update installer

module("dab_update",package.seeall)

local helper        = require "installerhelper"
local lfs           = require "lfs"
local os            = os
local printLog      = helper.printLog

-- error code returned by installer
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE 
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL

---------------------------------------------------------------
-- executeDevIPC 
-- Function to start dev-ipc
---------------------------------------------------------------
local function executeDevIPC(unit, operation)
    local cmd = g_path.."/"..unit.dev_ipc_script.." trace "..operation
    print(cmd)
    
    printLog(string.format("dev-ipc operation %s", operation))
    local ret_code = os.execute(cmd)/256
    
    -- Check for the return code     
    if (ret_code ~= 0) then 
        printLog(" Unable to"..operation.." dev-ipc successfully")
        return false, "Unable to"..operation.." dev-ipc successfully"
    end 
    
    return true 
end

---------------------------------------------------------------
-- executedevcSer8250
-- Function to start decv_ser8250
---------------------------------------------------------------
local function executedevcSer8250(operation, port)
    local devc_ser8250_dab_script = g_path.."/"..g_unit.devc_ser8250_script
    local cmd

    if port then
      cmd = devc_ser8250_dab_script.." "..operation.." "..port
    else
      cmd = devc_ser8250_dab_script.." "..operation
    end
    print(cmd)

    printLog(string.format("devc-ser8250 operation %s", operation))
    local ret_code = os.execute(cmd)/256
    print("return code = "..ret_code)

    -- Check for the return code
    if (ret_code ~= 0) then
        printLog(" Unable to"..operation.." devc-ser8250 successfully")
        return false, "Unable to"..operation.." devc-ser8250 successfully"
    end

    return true
end

local function getFirmwareName(mountpath, unit)
    local src_dir = mountpath.."/"..unit.dir_root
    local filename = nil

    -- we want to look for the binary file
    local cmd  = "ls -1 "..src_dir.."/*.bin" 
    local f = assert (io.popen (cmd, "r"))    
    for line in f:lines() do
        if (string.match(line, "M25P80.bin") ~= nil) then            
            printLog("DAB firmware file name = "..line)
            filename = line
            break
        end      
    end       
    f:close()
    
    return filename
end

--[[
    There are two DAB chips to flash. The dabupdate utility needs to be run twice. 
    Each time the utility is run, it prints 100% twice for the write and verify.
    In total for the firmware upate, we need to process 4 prints of "100% complete".
    Hence the percentageDivisor is 4.
--]]
local function flashDABfirmware(cmd, progress, unit, totalpercent, percentageDivisor)
    local util_percent = 0
    local interimPerentage = nil
    local line, byte

    print(cmd)
    local f = assert (io.popen (cmd, "r"))
    
    --print("********* Entered flashDABfirmware")
   
    while true do
        --print("********* flashDABfirmware -- Entered while loop")
        byte = f:read(1)
        --print("********* flashDABfirmware -- read from file")
        if (byte =='\r') or (byte == '\n') then
            -- Got a complete line. Process it for percentage, Done and Error strings
            if line ~= nil then
                -- Print and Process the line -- Start
                print(line)
                -- Process percentage
                interimPerentage = tonumber(string.match(line, "^%s*(%d+)%%"))
                if (interimPerentage ~= nil) then
                    if (interimPerentage % percentageDivisor) == 0 then
                        interimPerentage = (interimPerentage/percentageDivisor)
                        progress( unit, (totalpercent + util_percent + interimPerentage) )
                        print("Actual Percentage="..(totalpercent + util_percent + interimPerentage).."%")
                        if line == "100% complete" then
                            util_percent = util_percent + interimPerentage
                        end
                    end
                end 

                -- Process Done
                if ( string.match(string.upper(line), "^%s*DONE" ) ~= nil) then
                    break
                end

                -- if case of error
                if ( string.match(string.upper(line), "^%s*ERROR" ) ~= nil) then
                    printLog("error"..line)
                    util_percent = 0
                    break
                end
                -- Print and Process the line -- End
                line = nil
            end
        elseif (byte == 0) then
            -- No characters read or End of file. Ideally we should never be in this 
            -- condition as long as the utility prints "DONE" or "ERROR"
            --print("********* flashDABfirmware -- No characters read")
            printLog("No characters read")
            os.sleep(1)
        elseif (byte == nil) then
            -- End of file. Ideally we should never be in this condition as long 
            -- as the utility prints "DONE" or "ERROR"
            --print("********* flashDABfirmware -- End of file error")
            printLog("End of file error")
            util_percent = 0
            break
        else
            -- Keep capturing the characters until we find a new line or carriage return characters
            --print("********* flashDABfirmware -- received byte="..byte)
            if line then
                line = line..byte
            else
                line = byte
            end
        end
    end -- End of While of loop

    f:close()
    
    if util_percent < 50 then
        util_percent = nil
    end
    
    return util_percent
end

---------------------------------------------------------------
-- install
--  Function will be called by update
---------------------------------------------------------------
function install(unit, progress, mountpath, current_unit)

    local percent = 0
    local current_hw_type = nil
    local cmd
    local util_percent
    local ok, err
	local percentDivisor = 4
	local fullDab = true

	-- default is full dab (2 receivers)
	if ( unit.vp ~= nil and unit.vp == "vp2") then
		percentDivisor = 2
		fullDab = false
	end

    -- set the g_path to mountpath
    g_path = mountpath
    g_unit = unit

    percent = 0
    progress(unit, percent)
    
    local firmwareFullPath = getFirmwareName(mountpath, unit)
    if (firmwareFullPath == nil) then
        printLog(" Unable to find update file for DAB Update")
        return false, " Unable to find update file for DAB Update"
    end

    print("Firmware = "..firmwareFullPath)

    -- Start programming the 1st Chip
    -- start devc-ser8250 driver
    ok,err = executedevcSer8250("start", 4)
    if not ok then
        executedevcSer8250("stop", 4)
        return false, err, CONTINUE_SWDL
    end

    percent = 1
    progress(unit, percent)    
    
    cmd = "dabupdate -n "..firmwareFullPath.." -d /dev/ser4 -R /dev/gpio/XM_DAB1Reset -f4 -e0 -p1 -t1 -vvvv"
    util_percent = flashDABfirmware(cmd, progress, unit, percent, percentDivisor)
    print("flashDABfirmware returned ", util_percent)
    if util_percent == nil then
        executedevcSer8250("stop", 4)
        return false, line, CONTINUE_SWDL
    end

    executedevcSer8250("stop", 4)
    
	if ( fullDab ) then
       percent = 50
       progress(unit, percent)
       
       -- Start programming the 2nd Chip
       -- start devc-ser8250 driver
       ok,err = executedevcSer8250("start", 5)
       if not ok then
           executedevcSer8250("stop", 5)
           return false, err, CONTINUE_SWDL
       end
   
       cmd = "dabupdate -n "..firmwareFullPath.." -d /dev/ser5 -R /dev/gpio/HD_DAB2Reset -f4 -e0 -p1 -t1 -vvvv"
       util_percent = flashDABfirmware(cmd, progress, unit, percent, percentDivisor)
       print("flashDABfirmware returned ", util_percent)
       if util_percent == nil then
           executedevcSer8250("stop", 5)
           return false, line, CONTINUE_SWDL
       end
       executedevcSer8250("stop", 5)
   end

    percent = 100
    progress(unit, percent)    

    printLog("dab update done")

    return true
end



