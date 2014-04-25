require "json"

-----------------------------------------------
-- json_encode
--
-- Encode into a JSON string.  This can be
-- the compact form or a readable form.
--
-- tbl    ....Lua table to encode
-- compact....nil or 0=readable, 1=compact
--
-- Return:   JSON formatted string of tbl
-----------------------------------------------
function json_encode( tbl, compact )

    local str = json.encode( tbl )

    if compact ~= nil and compact == 1 then
        return str
    end

    -- expand for readability
    -----------------------------
    local expStr    = ""
    local idx       = 1
    local indent    = 0
    local indentLen = 3
    local ch        = string.sub(str, idx, 1)
    local inStr     = false

    while idx <= string.len(str) do

        if ch == "\"" then
            if idx-1 > 0 and string.sub(str, idx-1, idx-1) ~= "\\" then
                -- Toggle this
                if inStr == true then
                    --expStr = expStr.."-" -- debug
                    inStr = false
                else
                    --expStr = expStr.."+" -- debug
                    inStr = true
                end
            end
        end

        if ch == ":" and inStr == false then

            expStr = expStr.." : "

        elseif ch == "," and inStr == false then

            expStr = expStr..",\n"..string.rep(" ", indent)

        elseif (ch == "{" or ch == "[") and inStr == false then

            if idx-1 > 0 then

                if string.sub(str, idx-1, idx-1) ~= ":" and
                       string.sub(str, idx-1, idx-1) ~= "," then
                    expStr = expStr.."\n"..string.rep(" ", indent)
                end
            end

            expStr = expStr..ch.."\n"..string.rep(" ", indent+indentLen)
            indent = indent + indentLen

        elseif (ch == "}" or ch == "]") and inStr == false then

            if (indent - indentLen) >= 0 then
                indent = indent - indentLen
            else
                indent = 0
            end

            if string.sub(str, idx+1, idx+1) == "," then
                idx = idx + 1
                expStr = expStr.."\n"..string.rep(" ", indent)..ch..",\n"
            else
                expStr = expStr.."\n"..string.rep(" ", indent)..ch.."\n"
            end

            expStr = expStr..string.rep(" ", indent)

        else
            expStr = expStr..ch
        end

        idx = idx + 1
        ch  = string.sub(str, idx, idx)
    end

    return expStr
end

-- --------------------------------------
-- dumpTable
--
-- Called to better dump a table which
-- may contain tables, that will also
-- be dumped.
--
-- NOTE: This is JSON compatible syntax.
--
-- tbl    ....Lua table to encode
-- compact....nil or 0=readable, 1=compact
-- --------------------------------------
function dumpTable( tbl, compact )
    print( json_encode( tbl, compact ) )
end

-- Required modules
require "lfs"
require "service"
require "timer"
require "mcd"

-- Global Constants
local g_InstallServiceName = "com.harman.service.SoftwareInstaller"
local g_AMSBusName         = "com.aicas.xlet.manager.AMS"
local g_KonaLocation       = "/var/kona/xletslib/Kona.jar"
local g_xletBaseDir        = "/fs/mmc0/xlets"
local g_xletStagingDir     = g_xletBaseDir .. "/temp"
local g_xletUserDir        = g_xletBaseDir .. "/user"
local g_xletFactoryDir     = g_xletBaseDir .. "factory"
local g_xletUpgradeDir     = "usr/share/APPS"
local g_WaitForAMSTime     = 60000 -- 60 seconds

local g_mountpath
local g_usbpath
local g_AMSVersion
local g_KonaVersion

-- Exit Codes
local EXIT_SUCCESS        = 0
local EXIT_INVAL_NUM_ARGS = 1
local EXIT_NO_ISO_PATH    = 2
local EXIT_NO_USB_PATH    = 3
local EXIT_SVC_START_FAIL = 4
local EXIT_NO_AMS_FOUND   = 5
local EXIT_USBREMOVED     = 6



-- Global variables
local g_timerAMSWait
local g_methods = {}
local g_jarsToInstall = {}
local g_currentJarInstall = nil
local g_upgradeState =
{
   state    = "noMedia",
   fromInfo = nil,
   toInfo   = nil
}

----------------------
-- Helper Functions --
----------------------
local function compareVersions( actual, min, max )

   local function splitVersion( version )
      local result
      result = { string.match( version, "^([^.]+)%.([^.]+)%.([^.]+)$" ) }
      if #result == 3 then
         return result
      end

      result = { string.match( version, "^([^.]+)%.([^.]+)$" ) }
      if #result == 2 then
         return result
      end
      
      result = { string.match( version, "^([^.]+)$" ) }
      if #result == 1 then
         return result
      end

      print ( "Can't parse version ", version )
      return {}
   end

   if actual == nil then
      -- No version number specified so can't check
      return true
   end

   local actualSplit = splitVersion( actual )
   local minSplit    = splitVersion( min )
   local maxSplit    = splitVersion( max )

   while true do
      local currNum = table.remove( actualSplit, 1 )
      if currNum == nil then
         break
      end

      local minNum = table.remove( minSplit, 1 ) or "0"
      if currNum < minNum then
         return -1
      end

      local maxNum = table.remove( maxSplit, 1 ) or "65535"
      if currNum > maxNum then
         return 1
      end
   end

   return 0

end


-------------------------------------------------------------------------------
-- Emit Signals
-------------------------------------------------------------------------------

local function createUpdateStatusParams()
   local params = { state=g_upgradeState.state, versionInfo={} }
   if g_upgradeState.state ~= "noMedia" then
      params.versionInfo.newVersion     = g_upgradeState.toInfo["xlet.name"] .. " " .. g_upgradeState.toInfo["xlet.version"]
      if g_upgradeState.fromInfo then
         params.versionInfo.currentVersion = g_upgradeState.fromInfo["xlet.name"] .. " " .. g_upgradeState.fromInfo["xlet.version"]
      end
      params.updateType = "Apps"
      params.activationRequestCode = ""
      --params.upgradeType = "USApp"
   end
   return params
end

local function emit(signal, params)
   print("Emiting Signal = "..signal)
   service.emit(g_updateService, signal, params)
end

local function emitUpdateStatus()
   emit( "updateStatus", createUpdateStatusParams() )
end

function sendError(err)
    local error = "Software Update : "..err 
    print(error)
    emit("updateStatus", { state = "updateDone", errorInfo = { id= "4" , name = error } } )           
end


----------------------------
-- Installation Functions --
----------------------------

local function verifyDirectory( dir )

   local status = lfs.attributes( dir, "mode" )

   if status == nil then
      lfs.mkdir( dir )
      return 1
   elseif status ~= "directory" then
      return nil
   else
      return 1
   end
end
      
local function installApp()
   print ("Installing app " .. g_currentJarInstall )
   
   local appIdDir, jarName = string.match( g_currentJarInstall, "/([^/]+)/([^/]+%.jar)$" )

   if verifyDirectory( g_xletBaseDir ) == nil then 
      -- TODO: Handle error case   
   end
   if verifyDirectory( g_xletStagingDir ) == nil then
      -- TODO: Handle error
   end

   -- Start by copying to temporary staging location
   local appStagingLocation = g_xletStagingDir .. "/" .. jarName
   local cpResult = os.execute( "cp " .. g_currentJarInstall .. " " .. appStagingLocation )
   if cpResult ~= 0 then
      -- Failure copying the app to temporary directory
      os.exit(EXIT_USBREMOVED)
   end

   -- Save the new temporary location
   g_currentJarInstall = appStagingLocation

   -- Get information about this jar file
   g_upgradeState.toInfo = service.invoke(g_AMSBusName, 'getPackageInfo', { uri="file://" .. g_currentJarInstall, auth=false }, 600000 )
   dumpTable( g_upgradeState.toInfo )

   -- Determine if it is already installed
   g_upgradeState.fromInfo=service.invoke( g_AMSBusName, 'getPackageInfo', { appId=g_upgradeState.toInfo["xlet.appId"], auth=false }, 600000 )
   dumpTable( g_upgradeState.fromInfo )

   g_upgradeState.state   = "updateMediaAvailable"
   emitUpdateStatus()
end

local function installNextApp()

   -- App installation already in progress
   if g_currentJarInstall ~= nil then
      return
   end

   -- No app currently reported, pull next if possible
   if #g_jarsToInstall <= 0 then
      -- No more
      g_upgradeState.state   = "noMedia"
      emitUpdateStatus()
      os.exit(EXIT_SUCCESS)
   end

   -- Announce next one to the HMI
   g_currentJarInstall = table.remove( g_jarsToInstall )
   installApp()

end

--
-- Dig through the ISO where the jars live.  Each jar is
-- in an appid-named directory.
--
local function findAvailableApps()
   local xletsRoot = g_mountpath .. "/" ..  g_xletUpgradeDir
   for appIdName in lfs.dir(xletsRoot) do
      local absAppIdName = xletsRoot .. '/' .. appIdName
      if appIdName ~= "." and appIdName ~= ".." and lfs.attributes(absAppIdName, "mode" ) == "directory" then
         for packageItem in lfs.dir( absAppIdName ) do
            local absPackageItem = absAppIdName .. "/" .. packageItem
            if lfs.attributes(absPackageItem, "mode" ) == "file" and string.find( packageItem, "%.jar$" ) then
               table.insert( g_jarsToInstall, absPackageItem )
            end
         end
      end
   end

   -- Get info about AMS
   local AMSInfo = service.invoke(g_AMSBusName, 'getAllProperties', {}, 600000 )
   if AMSInfo and AMSInfo.version then
      g_AMSVersion = AMSInfo.version
   end

   -- Get info about Kona
   local KonaInfo = service.invoke(g_AMSBusName, 'getPackageInfo', { uri="file://" .. g_KonaLocation } )
   if KonaInfo and KonaInfo["kona.version"] then
      g_KonaVersion = KonaInfo["kona.version"]
   end

   installNextApp()
end

------------------------
-- Assorted callbacks --
------------------------
local function onAMSAvailable( newName, oldOwner, newOwner )
   if newOwner then
      g_timerAMSWait:stop()
      findAvailableApps()
   end
end

local function onAMSAppearTimeout()
   print "AMS Never appeared"
   os.exit(EXIT_NO_AMS_FOUND)
end

local function processEject()
   g_upgradeState.state = "noMedia"
   emitUpdateStatus()
   os.exit(EXIT_USBREMOVED)
end

--------------------
-- svcipc methods --
--------------------
function g_methods.getStatus(params, context, resultExpected)
   return createUpdateStatusParams()
end

function g_methods.update(params, context, resultExpected)
   print( "Update requested" )
   local appletName = g_upgradeState.toInfo["xlet.name"] .. " " .. g_upgradeState.toInfo["xlet.version"]

   local errorMsg

   if g_currentJarInstall == nil then
      installNextApp()
      return
   end

   if g_upgradeState.toInfo == nil then
      g_currentJarInstall = nil
      installNextApp()
      return
   end

   -- Check if it compatible with our kona version (skip if we just don't know kona version)
   if g_KonaVersion then
      local compatValue =
         compareVersions( g_KonaVersion, g_upgradeState.toInfo["kona.minimum.version"], g_upgradeState.toInfo["kona.maximum.version"] )

      if compatValue < 0 then
         errorMsg = appletName .. " requires a system software update"
      elseif compatValue > 0 then
         errorMsg = appletName .. " is too old for current system software"
      end
   end

    
   if not errorMsg then
      local resp
      if g_upgradeState.fromInfo == nil then
         -- Need to do an AMS install
         resp = service.invoke(g_AMSBusName, 'install', { uri="file://" .. g_currentJarInstall }, 600000 )
      else
         -- Need to do an AMS upgrade
         resp = service.invoke(g_AMSBusName, 'upgrade', { uri="file://" .. g_currentJarInstall }, 600000 )
      end

      dumpTable(resp)

      -- Decode the AMS response and reply to HMI
      if not resp or not resp.status or resp.status ~= "ok" then
         errorMsg = "Failure installing " .. appletName
      end
   end

   if errorMsg then
      service.returnResult( context, {status="failed"} )
      sendError(errorMsg)
   else
      service.returnResult( context, {status="success"} )
   end
   
   -- Remove the temporary copy
   os.execute( "rm " .. g_currentJarInstall )

   -- Do the next file if there is one
   g_currentJarInstall = nil
   installNextApp()

   return
end

function g_methods.updateDeclined(params, context, resultExpected)
   print ("Update declined")
   g_currentJarInstall = nil
   installNextApp()
end


-----------------------------
------- Main App ------------
-----------------------------

local function init()
   -- Verify that we have the correct two arguments
   if #arg ~= 2 then
      print( "Usage: us-app-install.lua PathToISO PathToUSB\n" );
      os.exit(EXIT_INVAL_NUM_ARGS)
   end
   
   -- Verify that we have received the ISO mount path
   g_mountpath = arg[1]
   if (g_mountpath == nil) or ( lfs.attributes(g_mountpath,"mode") == "dir") then
      print "ISO_PATH missing or not a directory"
      os.exit(EXIT_NO_ISO_PATH)
   end
   
   -- Verify that we have received the USB mount path
   g_usbpath = arg[2]
   if (g_usbpath == nil) or ( lfs.attributes(g_usbpath,"mode") == "dir") then
      print "USB_PATH missing or not a directory"
      -- TODO : Send a HMI signal about error
      os.exit(EXIT_NO_USB_PATH)
   end

   -- Register for removal notifications
   mcd.notify("EJECTED", processEject)
   
   -- Register the softwareInstaller service
   g_updateService = service.register(g_InstallServiceName, g_methods)
   if not g_updateService then
      print ( "Unable to start the update service " .. g_InstallServiceName )
      os.exit(EXIT_SVC_START_FAIL)
   end
   
   -- Figure out if AMS is present, if not, wait
   if service.nameHasOwner(g_AMSBusName) then
      findAvailableApps()
   else
      -- Start a maximum amount of time we will wait for AMS
      g_timerAMSWait = timer.new(onAMSAppearTimeout)
      g_timerAMSWait:start( g_WaitForAMSTime, 1 )
   
      -- Subscribe for owner changes in this case
      service.subscribeOwnerChanged(g_AMSBusName, onAMSAvailable)
   end
end

init()
