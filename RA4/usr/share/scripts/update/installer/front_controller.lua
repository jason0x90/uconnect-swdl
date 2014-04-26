-- front_controller installer

module("front_controller",package.seeall)

local onoff         = require "onoff"
local helper        = require "installerhelper"
local os            = os
local printLog      = helper.printLog

local FRONT_CONTROLLER_CHANNEL = 25

local fcChannel = nil
local finished = false
local updateError = false


--
-- Get a response of a certain type on the FC channel
--
local function getResponse( response, timeout, retry)
	if ( fcChannel == nil) then
		print( "No fcChannel, returning response of 'nil'")
		return nil
	end

	local replyTimeout = timeout or 1000
	local retries = retry or 3
	local gotResponse = false

	local reply = fcChannel:read( replyTimeout)
	if ( reply ~= nil) then

		if ( #reply >= 1) then
		   if ( reply[1] == response) then
			  gotResponse = true
		  end
		end
	end

	while ( not gotResponse) do
		if retries == 0 then
		    print( "Failed to get response, returning nil result")
			return nil
		end

		print( "Failed to get response, waiting again");
		retries = retries - 1

		reply = fcChannel:read( replyTimeout)
	    if ( reply ~= nil) then

		    if ( #reply >= 1) then
			   if ( reply[1] == response) then
				  gotResponse = true
			  end
			end
		end
	end

	return reply
end


--
-- Handle version information
--
local function getVersion( versionType, retries)
	local version = nil
	local retryCount = retries or 3

	if ( fcChannel == nil) then
		print( "fcChannel not set up, returning 'nil' for version")
		return nil
	end

    local reply
	while ( ( reply == nil) and ( retryCount > 0)) do

      if ( versionType == "current") then
	     print( "Requesting current version")
         fcChannel:write( 0x00)
	     reply = getResponse( 0x01, 2000)
      elseif ( versionType == "available") then
	     print( "Requesting available version")
	     fcChannel:write( 0x03)
	     reply = getResponse( 0x03, 2000)
	 end

	 if ( reply == nil) then
		 print( "Failed to get version - trying again")
		 retryCount = retryCount - 1
	 end
   end


   if ( reply ~= nil) then

	   print( "Got version reply")
	   version = {}

      version["high"]  = reply[2]
      version["mid"] = reply[3]
      version["low"] = reply[4]
   end

   return version
end


--
-- Start the update
--
local function startUpdate()
	if ( fcChannel == nil) then
		print( "fcChannel not set up, not starting update")
		return
	end

	fcChannel:write( 0x02)
end


---------------------------------------------------------------
-- install 
--  Function will be called by update
---------------------------------------------------------------
function install(unit, progress, mountpath, current_unit)

    local boloflag    
    local percent = 0
	local state = unit["progressState"]

	local retryNum = tonumber( state)
	if ( retryNum == nil) then
		retryNum = -1
	end

	retryNum = retryNum + 1

	--
	-- Call this once to update the display
	--
	progress( unit, percent)

    fcChannel = assert( ipc.open(FRONT_CONTROLLER_CHANNEL))
	os.execute( "sleep 0.5")
    
	--
	-- Keep this order (available first, then current)
	-- For some reason, the Fiat doesn't work right otherwise
	--

	local availableVersion = getVersion( "available")

	if ( availableVersion == nil) then
	   print( "Could not get available version")
	end

	local currentVersion = getVersion( "current")

	if ( currentVersion == nil) then
	   print( "Could not get current version")
	end

	--
	-- If either version is nil, it means we weren't able to communicate
	-- with the IOC. In that case, reset and try again, keeping our place
	-- in the update
	-- 
	if ( ( retryNum == 0) and
		( ( currentVersion == nil) or ( availableVersion == nil))) then

		--
		-- Print a nice big banner for the console
		--
		print( "*******************************************************************************")
		print( "*******************************************************************************")
		print( "*******************************************************************************")
		print( "***************                                                 ***************")
		print( "***************                                                 ***************")
		print( "***************  FAILED TO GET FRONT CONTROLLER VERSION -       ***************")
		print( "***************         RESETTING TO TRY AGAIN                  ***************")
		print( "***************                                                 ***************")
		print( "***************                                                 ***************")
		print( "*******************************************************************************")
		print( "*******************************************************************************")
		print( "*******************************************************************************")

		return false, "The Head Unit needs to be reset to continue. Please wait...", helper.RETRY_SWDL_UNIT
	end

	--
	-- If versions match, then just move on, but if current is nil, then
	-- update anyway (we already tried a reset, above)
	--
	percent = 0
	progress( unit, percent)

	if ( ( currentVersion == nil) or 
		( not (( currentVersion.high == availableVersion.high) and
		( currentVersion.mid == availableVersion.mid) and
		  ( currentVersion.low == availableVersion.low)))) then

	   --
	   -- Start the update 
	   --
	   startUpdate()
	   os.sleep( 1)

	   local msg

	   while ( not ( finished or updateError)) do
		  msg = getResponse( 0x02, 2000, 3)

		  if ( msg ~= nil) then
   		     print( "Got message: ", msg)

        	 if ( ( msg[2] == 0xff) or ( msg[2] == 100)) then
		        finished = true
	         elseif ( msg[2] >= 0 and msg[2] < 100) then
				 percent = msg[2]
		        progress( unit, percent)
	         else
		        updateError = true
	         end
	      end
	   end
   else 
	   percent = 100
   end

   if ( finished == true) then
	   percent = 100
   end

	progress( unit, percent)
    
    printLog("front controller update done")

	-- should never return here
    return true
end    
        
    
       
    
