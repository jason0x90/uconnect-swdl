--[[
   This will start the software update.
   It will read the manifest from mountpoint and will 
   run each installer
]]

local mcd       = require "mcd"
local onoff     = require "onoff"
local helper    = require "installerhelper" 
local service   = require "service"
local os        = os
local type      = type

-------------------------------------------------------------------------------
-- global variables 
-------------------------------------------------------------------------------

-- service name 
local serviceName           = "com.harman.service.SoftwareUpdate"

local methods               = {} 
local updateStarted         = false
local updateCompleted       = false
local current_unit          = nil
local total_units           = nil
local complete_percentage   = 0 
local mountpath             = nil
local printLog              = helper.printLog
local updateService         = nil
local config                = {}  

-- error code returned by installer
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE 
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL
local RETRY_SWDL_UNIT               = helper.RETRY_SWDL_UNIT

-- MCD rules
config.mcdEjectRule                 = "EJECTED"
config.manifestName                 = "etc/manifest.lua" 

-- error message send on dbus in case when installer returns an error code indicating 
-- recall
local recall_error_msg = "Unable to update this prototype unit. Please return to Harman Automotive"

local eject_usb_msg = "Please remove USB stick to reset."

local g_error_flag = 0

local needsResetMsg = "The Head Unit needs to reset to continue. Please wait..."

-------------------------------------------------------------------------------
-- Emit Signals
-------------------------------------------------------------------------------
local function emit(signal, params)
    if (updateService ~= nil) then 
        service.emit(updateService, signal, params)
    end    
end

-------------------------------------------------------------------------------
-- Used to send the dbus-message indicating an error
-------------------------------------------------------------------------------
local function sendError(unit, error)
    local status = {}
    if (error ~= nil) then      
        printLog(string.format(" ERROR: %s",error))
        status.state = string.format("%s. %s", error, eject_usb_msg)        
    else
        local err_text          
        if (unit ~= nil and unit.name ~= nil) then     
            err_text = string.format(" Failure during %s ", unit.name)
        else
            err_text = string.format(" Failure executing software update")
        end        
        printLog(string.format(" ERROR: %s",err_text))  
        status.state = string.format(" %s %s. %s",err_text, error, eject_usb_msg)
    end    
    
    -- only send the error if there is no error before
    -- else it might display the error and then when usb is ejected it 
    -- will display it again
    if (g_error_flag == 0) then 
        service.emit(updateService, "status", status)    
        g_error_flag = 1
    end    
end

----------------------------------------------------------------------
-- Display progress
----------------------------------------------------------------------
local function progress(unit, percent)  
    local swprogress = {}
    if (percent > 0) then  
        if (percent > 100) then 
            percent = 100
        end      
	elseif ( percent < 0) then
		percent = 0
    end 

        complete_percentage = ((percent) * (1 /total_units))  +  ((current_unit -1 ) * 100 / total_units)

    swprogress.unitName         = unit.name
    swprogress.unitNumber       = current_unit
    swprogress.totalUnitCount   = total_units
    swprogress.totalPercentComplete = complete_percentage
    swprogress.unitPercentComplete = percent
    service.emit(updateService, "progress", swprogress)
end


--------------------------------------------------------------------------------
-- Load the update manifest script and return the manifest (a table).
-- If an error occurs, return nil and an error message.
-- @param mountpath
--------------------------------------------------------------------------------
local function loadManifest(mountpath)
    local manifestpath
    
    if not mountpath then 
        printLog( "Mountpath is not specified" )
        return nil, "mountpath is not specified"
    end
        
    manifestpath = mountpath.."/"..config.manifestName

    -- load the manifest
    print("loading manifest "..manifestpath)
    local chunk, error = loadfile(manifestpath)
    if not chunk then
        printLog("error loading manifest:"..error)
        return nil, error
    end

    -- run the manifest which should return a table
    print("calling manifest")
    local ok, manifest = pcall(chunk)
    if not ok then
        printLog("Error running manifest")
        return nil, "Invalid manifest"
    end
    
    -- make sure manifest type is a table
    if type(manifest) ~= "table" then
        -- error or warning?
        printLog("Invalid manifest type")
        return nil, "Invalid manifest"
    end

    return manifest
end

----------------------------------------------------------------------
-- Install unit, will call install function for the installer
----------------------------------------------------------------------
local function installUnit(unit)
    local avail = nil
    print( string.format("Installing unit %s",unit.installer))
   
   -- check is module is available or not
    avail = helper.checkModuleAvailable(unit)
    if (avail == true) then   
        local installer = require(unit.installer)
        printLog( string.format( "Got the unit installer for %s",unit.name))
        return installer.install(unit, progress, mountpath, current_unit, total_units)
    else
        -- if module not available
        printLog(string.format("Unit %s is not part of this system" ,unit.name))
        return true
    end        
end

----------------------------------------------------------------------
-- Will scan through manifest and execute each installer
----------------------------------------------------------------------
local function installPart(part) 
    local num       = nil      
    local number, state    = onoff.getUpdateInProgress()
    
    print(number, state)
    printLog(string.format("Total units to update: %s",#part))
    total_units =  #part  
 
    if (number == nil) then 
        number = 1 
    end  
    
    num = tonumber(number)  
    if (num == nil) then 
        num = 1 
    end
    
    local function xpCallErrorHandler(o)
       printLog( debug.traceback(o, 2) )
    end

    for i=num, #part do       
        local unit = part[i]
		unit["progressState"] = state
        current_unit = i
        printLog(string.format("Installing unit %d %s ",i, unit.name))      
        -- temporary code only for testing
        --installUnit(unit)
        --completed = true
        --success = true
		--
        
		local completed = false
		local success = false
		local err = nil
		local err_code = nil

		local requiredIocMode = "bolo"
		local boloflag

		if ( unit["iocmode"] ~= nil) then
			requiredIocMode = unit["iocmode"]
		end

	    boloflag, err = onoff.getBootMode()

		if (requiredIocMode ~= "no_check") and ( boloflag ~= requiredIocMode ) then
			--
			-- need to reset into proper mode
			--
			local status = {}
			status.state = needsResetMsg
            service.emit( updateService, "status", status)    

            printLog( string.format( "softwareupdate.lua: requiredIocMode [%s], does not match curr IOC mode [%s], resetting", 
			         requiredIocMode, boloflag));
			onoff.setUpdateInProgress( current_unit)
			onoff.setExpectedIOCBootMode( requiredIocMode)
			onoff.reset( requiredIocMode)
			os.sleep( 20)
			print( "***************ERROR: should not have gotten here during reset *********************")
		else
		   completed, success, err, err_code = xpcall( function() return installUnit(unit) end, xpCallErrorHandler)
	    end

        -- xpcall failure
        if not completed then 
            err = "INSTALL ERROR"
            sendError(unit, err)            
            return false
        end         
        
		--
		-- Need to handle this processing here, before we evaluate the general
		-- success return value. If the retry max-out kicks in, then we want to
		-- proceed with the next update unit as though it had succeeded.
		--
		local new_state = "I"
		if ( not success) and ( err_code == RETRY_SWDL_UNIT) then

			-- If there is no max_retries specification in the unit
			-- then we retry ad infinitum

		   if ( unit["max_retries"] ~= nil) then
		      local new_state_value = tonumber( state)
			  local max_retries = tonumber( unit["max_retries"])
					   
			  if ( max_retries == nil) then
			     max_retries = 0
			  end

			  if ( new_state_value == nil) then
			     new_state_value = -1
			  end

			  new_state_value = new_state_value + 1

			  if ( new_state_value >= max_retries) then
			     --
			     -- We're done retrying, so just mark this as success
			     -- and go on
			     --
				 success = true
			 else
				 new_state = tostring( new_state_value)
			 end
		 end
	 end

        -- if install failed, then check the err_code to decide what to do
        if not success then 
            if err_code then 
                --  err_code received 
                if (err_code == STOP_SWDL_DONT_CLEAR_UPDATE) then 
                    printLog(
                        string.format(" Failure in update unit %s, will stuck in SWDL mode", unit.name))
                    sendError(unit, err)              
                    return false  
                elseif (err_code == STOP_SWDL_CLEAR_UPDATE) then 
                    local msg
                    if err then 
                        msg = err
                    else
                        msg = string.format("%s ", recall_error_msg)
                    end    
                    sendError(unit, msg) 
                    -- clear update flag 
                    onoff.setUpdateMode(false)
                    return false
                -- this means err_code == CONTINUE_SWDL    
                elseif (err_code == CONTINUE_SWDL) then 
                    printLog(string.format(" Error while updating %s, but will continue update", unit.name))   
                    sendError(unit, err) 
				elseif ( err_code == RETRY_SWDL_UNIT) then
					--
					-- The new_state processing for this was handled above
					--
					printLog( string.format( " Error while updating %s, will reset and try again", unit.name))
					sendError( unit, err)

					onoff.setUpdateInProgress( current_unit, new_state)
					onoff.setExpectedIOCBootMode( requiredIocMode)
					onoff.reset( requiredIocMode)
					os.sleep( 20)
					print( "***************ERROR: should not have gotten here during reset *********************")
                else
                    printLog(string.format(" Unexpected err_code returned by installer %s", unit.name))
                    sendError(unit, err)
                    return false
                end                   
            else 
                -- if err_code is nil , then default state is stop update with out clearing update flag
                if (err ~= nil) then 
                    sendError(unit, err) 
                    return false
                else
                    err = string.format(" Update failed %s, will stop SWDL", unit.name)
                    printLog(" Update failed, will stop SWDL")
                    sendError(unit, err)
                    return false
                end    
            end                
        end    
    end        
    return true
end

----------------------------------------------------------------------
-- This function is called with the manifest. 
----------------------------------------------------------------------
local function processManifest(manifest)
    if manifest then
        local part = manifest.parts
    
        if type(part) ~= "table" then
            printLog( "Invalid manifest")
        end  
        updateStarted = true
        
        if installPart(part) then
            printLog("Software Update successfully completed")
            os.execute("sync")
            os.sleep(1)
            onoff.setUpdateMode(false)
            onoff.resetUpdateInProgress()  
            -- set the update done flag, will be used to update software download count
            onoff.setUpdateDone()         
            onoff.reset()
        else
            os.execute("sync")
            printLog("Software Update failed, see 'swdlLog.txt' on the USB stick for more details")
            onoff.resetUpdateInProgress()
            printLog("Eject USB for RESET")
        end
    end
end

----------------------------------------------------------------------
-- Function to load and verfiy manifest. If manifest valid then 
-- start update
----------------------------------------------------------------------
local function beginUpdate(mountpath)   
    printLog("Starting Update")
    -- sleep for 1 second so that flash has enough time to start up and
    -- listen for errors and progress
    os.sleep(1)    
    local manifest, err = loadManifest(mountpath)
    if not manifest then
        sendError(nil, "Unable to load manifest")
        printLog("Unable to load manifest")
        os.exit(3)
    end           
    processManifest(manifest)    
end

----------------------------------------------------------------------
-- Media has been ejected, reset into application
----------------------------------------------------------------------
local function processEject(path)   
    if ( string.find(path, "usb" ) ~= nil) then  
        sendError(nil, "USB ejected, please insert USB back to start the Update")    
        printLog(" USB EJECTED") 
        -- sync the file system before resetting
        os.execute("sync")
        os.sleep(1)       
        onoff.reset()
        os.sleep(1)
        os.exit(2)
    end 
end


 
--------------------------------------------------------------------------------
-- Start the software update dbus service
--------------------------------------------------------------------------------
updateService = assert(service.register(serviceName, methods))

--------------------------------------------------------------------------------
-- DBUS method to stop software download service, currently its not used
--------------------------------------------------------------------------------
function methods.reset(params)
	printLog("DBUS Reset method")
	onoff.setUpdateMode(false)
    onoff.resetUpdateInProgress()	
	onoff.reset() 
end

--------------------------------------------------------------------------------
-- Set notifications for USB eject
--------------------------------------------------------------------------------
mcd.notify(config.mcdEjectRule, processEject)


-- create logfile if this is fresh start, which means 
-- package we are currently executing is nil as default state 
-- in FRAM is 'X' 
local package_number = onoff.getUpdateInProgress()
if ( tonumber( package_number) == nil) then 
   -- if this is the start of update then create the logfile
    helper.createLogFile()
end    

mountpath = arg[1]
print("mountpath  "..mountpath)
print("arg[0] "..arg[0])
print("arg[1] "..arg[1])
if (mountpath == nil) then 
    printLog(" No mountpath specified")
    sendError(nil, "No mountpath specified")
    os.exit(1)
end        

beginUpdate(mountpath)

