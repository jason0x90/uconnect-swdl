-- XM Update installer


module("xm_update",package.seeall)

local onoff         = require "onoff"
local helper        = require "installerhelper"
local lfs           = require "lfs"
local os            = os
local printLog      = helper.printLog


local g_path = nil
local g_unit = nil
local g_hw_module = nil
local g_sw_version = nil
local g_file_name = nil


local DAB_ON         = onoff.DAB_ON
local DAB_OFF        = onoff.DAB_OFF

-- error code returned by installer
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL

local X65_HW_TYPE                = "01-01-00"
local X65H_HW_TYPE               = "01-01-01"
local X65H2_HW_TYPE              = "01-01-02"


-- Module name, this is what we expect in manifest and the folder file
local X65_MODULE                = "x65"
local X65H_MODULE               = "x65H"
local X65H2_MODULE              = "x65H2"

local g_temp_dir                = "/tmp/" -- xm binary is put in /tmp directory , only reason is SMS is not good when reading it from mounted iso

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
local function executedevcSer8250(operation)
    local cmd = g_path.."/"..g_unit.devc_ser8250_script.." "..operation
    print(cmd)

    printLog(string.format("devc-ser8250 operation %s", operation))
    local ret_code = os.execute(cmd)/256

    -- Check for the return code
    if (ret_code ~= 0) then
        printLog(" Unable to"..operation.." devc-ser8250 successfully")
        return false, "Unable to"..operation.." devc-ser8250 successfully"
    end

    return true
end

----------------------------------------------------------------------
-- checkUpdateRequired ( check the filename on stick withe the current
-- version
----------------------------------------------------------------------
local function checkUpdateRequired()

    local version_on_stick
    local new1, new2, new3
    local current1, current2, current3
    local src_dir = g_path.."/"..g_unit.dir_root.."/"..g_hw_module

    -- we want to look for the binary file by the name of module
    local cmd  = "ls -1 "..src_dir.."/*.bin"
    local f = assert (io.popen (cmd, "r"))
    for line in f:lines() do
        local version  = string.match(line,".-v(%d+%.%d+%.%d+).bin")
        if (version ~= nil) then
            printLog(" version on stick "..version)
            version_on_stick = version
            g_file_name = line
            printLog("filename "..g_file_name)
            -- copy the file into g_temp_dir
            local copy_cmd  = "cp "..g_file_name.." "..g_temp_dir
            print(copy_cmd)
            os.execute(copy_cmd)
            break
        end
    end
    f:close()

    -- check if valid version
    if (version_on_stick == nil) then
        printLog(" Unable to find update file for XM Update")
        return false, " Unable to find update file for XM Update"
    end

    -- get the number form version
    print(version_on_stick)
    new1, new2, new3 =  string.match(version_on_stick,".-(%d+)%.(%d+)%.(%d+)")
    if ((new1 == nil) or (new2 == nil) or (new3 == nil) ) then
        printLog(" Invalid format on stick for XM Binaries")
        return false, "Invalid format on stick for XM Binaries"
    end
    new1 = tonumber(new1)
    new2 = tonumber(new2)
    new3 = tonumber(new3)

    -- get the current version ( format is like 7-8-1)

    current1, current2, current3 =  string.match(g_sw_version,".-(%x+)%-(%x+)%-(%x+)")
    print(current1,current2,current3)

    if ((current1 == nil) or (current2 == nil) or (current3 == nil)) then
        printLog(" Invalid format on target for XM Binaries")
        return false, "Invalid format on target for XM Binaries"
    end

    current1 = tonumber("0x"..current1)
    current2 = tonumber("0x"..current2)
    current3 = tonumber("0x"..current3)

    if ( (new1 > current1) or
         (new1 == current1 and new2 > current2) or
         (new1 == current1 and new2 == current2 and new3 > current3) ) then
        printLog(" Got new update on stick for XM")
        return true
    end
    printLog(" No update required for XM")
    return false
end


---------------------------------------------------------------
-- shutDown
--  Function will be during shutdown
---------------------------------------------------------------
local function shutDown()
    executedevcSer8250("stop")
    os.sleep(1)
    onoff.setDAB(DAB_OFF)
    os.sleep(1)
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

    -- set the g_path to mountpath
    g_path = mountpath
    g_unit = unit

    print("Start dev-ipc ")

    percent = 0
    progress(unit, percent)
    local ok, err = executeDevIPC(unit, "start")
    if not ok then
        return false, err, CONTINUE_SWDL
    end
    percent = 1
    progress(unit, percent)

    -- call preInstaller, if specified, to check if we have right IOC bootloader
    local ok, err, err_code= helper.callPrePostInstaller(unit, mountpath, "pre")
    if not ok then
       return false, err, err_code
    end
    print("dev-ipc started")

    percent = 2
    progress(unit, percent)
   -- This is just to be extra careful , XM Module has timing requirements
   -- for this
    os.sleep(1)
    onoff.setDAB(DAB_ON)
    os.sleep(1)

    -- start devc-ser8250 driver
    ok ,err = executedevcSer8250("start")
    if not ok then
        shutDown()
        return false, err, CONTINUE_SWDL
    end

    percent = 3
    progress(unit, percent)
    -- find the hardware type and software version
     cmd = "xmUpdater -i"
     local f = assert (io.popen (cmd, "r"))
     for line in f:lines() do
        print(line)
        -- sw version is in hex format
        if (string.find(line,"Current SW Ver") ~= nil) then
            g_sw_version = line:match(".-(x%x+%-%x+%-%x+)")
        end

        if (string.find(line,"Current Type") ~= nil) then
            current_hw_type = line:match(".-(%d+%-%d+%-%d+)")
        end

        if ( string.match(string.upper(line), "^%s*ERROR" ) ~= nil) then
            printLog("error"..line)
            shutDown()
            return false, line, CONTINUE_SWDL
        end
    end
    f:close()

    percent = 4
    progress(unit, percent)

    if (g_sw_version == nil or current_hw_type == nil) then
        printLog(" Unable to find current software or hardware version from XM Module")
        shutDown()
        return false, "Unable to find current software hardware version from XM Module", CONTINUE_SWDL
    end

    print(" Software version "..g_sw_version)
    print(" current_hw_type  "..current_hw_type)

    if (current_hw_type == X65_HW_TYPE) then
        g_hw_module = X65_MODULE
    elseif (current_hw_type == X65H_HW_TYPE) then
        g_hw_module = X65H_MODULE
    elseif (current_hw_type == X65H2_HW_TYPE) then
        g_hw_module = X65H2_MODULE
    else
        printLog(" Invalid hardware version for XM "..current_hw_type)
        shutDown()
        return false, "Invalid hardware version for XM", CONTINUE_SWDL
    end
    print(" g_hw_module  "..g_hw_module)

    -- check the version we have on stick
    local ok ,err = checkUpdateRequired()
    if not ok then
        printLog(" XM No update required")
        shutDown()
        return true
    end

    percent = 5
    progress(unit, percent)
	local bin_name =nil
	for token in string.gmatch(g_file_name, "[^/]+") do
		bin_name = token
	end
	print (bin_name)
    cmd = "xmUpdater -f "..g_temp_dir..bin_name
    print(cmd)
    local f = assert (io.popen (cmd, "r"))
    for line in f:lines() do
        print(line)
        if (string.match(line,"^%s*%d") ~= nil) then
            util_percent = tonumber(line)
            print(util_percent)
            if (util_percent > percent) then
                progress(unit, util_percent)
            end
        end

        if ( string.match(string.upper(line), "^%s*DONE" ) ~= nil) then
            break
        end

        -- if case of error
        if ( string.match(string.upper(line), "^%s*ERROR" ) ~= nil) then
            printLog("error"..line)
	        shutDown()
            return false, line, CONTINUE_SWDL
        end
    end
    f:close()

    if (util_percent < 100) then
        shutDown()
        return false, "Unable to finish XM update"
    end

    -- call preInstaller, if specified
    ok, err, err_code= helper.callPrePostInstaller(unit, mountpath, "post")
    if not ok then
       shutDown()
       return false, err, err_code
    end

    shutDown()
    printLog("xm update done")
    return true
end

