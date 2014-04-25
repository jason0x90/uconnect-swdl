
-- Exit Codes possible for this script
local EXIT_OK              = 0 -- Proper exit
local EXIT_INVAL_NUM_ARGS  = 1 -- Invalid number of arguments
local EXIT_NO_ISO_PATH     = 2 -- ISO_PATH missing or incorrect
local EXIT_NO_USB_PATH     = 3 -- USB_PATH missing or incorrect
local EXIT_SYNCTOOL        = 4 -- SyncTool or controller not running
local EXIT_SVC_START_FAIL  = 5 -- Unable to start the SoftwareInstaller Service
local EXIT_VARIANT         = 6 -- Unable to determine variant or path missing on stick
local EXIT_ACT_RESP_TIME   = 7 -- Timeout waiting for activation response from controller
local EXIT_USB_REMOVED     = 8 -- The USB stick was removed prior to completion
local EXIT_INVALID_OPTION  = 9 -- Not sure yet

-- Required modules
local service       = require "service"
local mcd           = require "mcd"
local lfs           = require "lfs"
local timer         = require "timer"
local bit           = require "bit"
local onoff         = require "onoff"
local naviSyncTools = require "naviSyncTools"
local dumper        = require "dumper"

-- Global script variables
local g_mcdConfig = { mcdEjectRule="EJECTED", manifestName="etc/manifest.lua"}
local g_methods = {}
local g_VariantPath
local g_updateService
local g_activationState =
{
   state         = "noMedia",
   targetDBVer   = "",
   stickDBVer    = "",
   skuEISs       = {}
}

-- Constants
local g_product_type = "/etc/product_type"
local platformBusName = "com.harman.service.platform"
local navBusName     = "com.harman.service.Navigation"
local navSyncBusName = "com.harman.service.NavigationUpdate"
local serviceName    = "com.harman.service.SoftwareInstaller"

local function exitAndReportStatus( status )
   naviSyncTools.stop()
   io.output(stdout):write("nav-activation.lua: Exit status is "..status.."\n")
   os.exit(status)
end

-------------------------------------------------------------------------------
-- Emit Signals
-------------------------------------------------------------------------------

local function emit(signal, params)
   io.output(stdout):write("nav-activation.lua: Emitting Signal = "..signal.."\n")
   service.emit(g_updateService, signal, params)
end

---------------------------------------------------------------------
--  Send the error message to HMI
---------------------------------------------------------------------

function sendError(id, err)
    local error = "nav-activation.lua: "..err.."\n"
    io.output(stderr):write(error)
    emit("updateStatus", { state = "updateDone", errorInfo = { id=id , name = error } } )
end

local function findActivationNeeded()
   for i, skuEIS in ipairs( g_activationState.skuEISs ) do
      if skuEIS.RCD then
         return skuEIS.DESC, skuEIS.RCD
      end
   end
   return
end

local function createUpdateStatusParams()

   if not g_activationState.stickDBVer then
      g_activationState.stickDBVer = "Unknown"
   end

   local params = {state       = g_activationState.state,
                   versionInfo = {newVersion = g_activationState.stickDBVer, currentVersion = g_activationState.targetDBVer},
                   updateType  = "navDB" }
   local desc, requestCode = findActivationNeeded()
   if desc and requestCode then
      params.activationRequestCode = requestCode
      params.versionInfo.newVersion = "\"" .. desc .. "\""
   end
   
   dumper.dumpTable(params)

   return params
end

local function emitUpdateStatus()
   emit( "updateStatus", createUpdateStatusParams() )
end

--------------------------------------------------------------------------------
--
-- SoftwareInstaller methods
--
--------------------------------------------------------------------------------
function g_methods.getStatus(params, context, resultExpected)
   return createUpdateStatusParams()
end

function g_methods.update(params, context, resultExpected)

   -- Find out if any skus still need to be activated
   for i, skuEIS in ipairs( g_activationState.skuEISs ) do
      if skuEIS.RCD then
         return {error="SKU \"" .. skuEIS.DESC .. "\" still needs activation" }
      end
   end
      
   -- Return an empty object if requested
   if resultExpected then
      service.returnResult( context, {} )
   end

   io.output(stdout):write("nav-activation.lua: All packages activated, resetting for nav-db update\n")
   onoff.setUpdateMode(true)
   os.sleep(1)
   onoff.reset()

   -- exit with no failure
   exitAndResportStatus(EXIT_OK)

   return

end

function g_methods.updateDeclined(params, context, resultExpected)
   io.output(stdout):write("nav-activation.lua: updateDeclined method called\n")

   -- Return an empty object if requested
   if resultExpected then
      service.returnResult( context, {} )
   end

   -- Exit with no failure
   exitAndReportStatus(EXIT_OK)

   return
end

function g_methods.setActivationCode( params, context, resultExpected )

   -- Validate the parameters
   if not params then
      service.returnError(context, {error="Missing \"params\""})
      return
   end

   if not params.requestCode then
      service.returnError(context, {error="Missing requestCode parameter"})
      return
   end

   if type(params.requestCode) ~= "string" then
      service.returnError(context, {error="requestCode parameter is not type string"})
      return
   end

   if not params.activationCode then
      service.returnError(context, {error="Missing activationCode parameter"})
      return
   end

   if type(params.activationCode) ~= "string" then
      service.returnError(context, {error="activationCode parameter is not type string"})
      return
   end

   -- Find the SKU with the request code provided
   local pos
   for i, skuEIS in ipairs( g_activationState.skuEISs ) do
      if skuEIS.RCD then -- TODO and skuEIS.RCD == params.requestCode then
         pos = i
         break
      end
   end

   dumper.dumpTable(g_activationState.skuEISs)

   local pos = 1
   -- Make the request to activate this SKU with any valid request code
   local skuEISMod = g_activationState.skuEISs[pos].raw .. "<RCD>" .. params.requestCode .. "<*>" .. "<ACD>" .. params.activationCode .. "<*>"

   -- Check if mmc0 is writable so that the ACTIVATION_CODES file can be written
   local mmc0ChangeResult = service.invoke(platformBusName, "change_mmc0_mode", {} )
   if not mmc0ChangeResult or not mmc0ChangeResult.mmc0 then
      service.returnError( context, {error="System does not understand how to modify storage permission"})
      return
   elseif mmc0ChangeResult.mmc0 == "r" then
      -- Make mmc0 writable so that the ACTIVATION_CODES file can be written
      mmc0ChangeResult = service.invoke(platformBusName, "change_mmc0_mode", { mode = "w"})
      if not mmc0ChangeResult or not mmc0ChangeResult.mmc0 or not mmc0ChangeResult.mmc0 == "w" then
         service.returnError( context, {error="Unable to store activation code to internal storage"} )
         return
      end
   else
      service.returnError( context, {error="System does not understand how to modify storage permission"})
      return
   end

   -- Make the request to activate this SKU with this request code
   local skuEISMod = g_activationState.skuEISs[pos].raw .. "<ACD>" .. params.activationCode .. "<*>"
   local resp = service.invoke(navSyncBusName, 'UPD_RequestSetActivationCode', {skuEIS=skuEISMod}, 600000 )
   dumper.dumpTable( resp )

   if not resp or not resp.validState then
      service.returnError( context, {error="Error communicating with SyncTool"} )
      return
   end

   -- make sure we restore the storage back to being read-only before we do anytyhing else.
   os.execute("sync")
   if mmc0RestoreRead then
      -- if it doesn't work, then there's not much else we can do
      mmc0ChangeResult = service.invoke(platformBusName, "change_mmc0_mode", { mode = "r"})
   end
   
   -- Parse the results of the request.  If successful, remove the request code
   if resp.validState == 1 then
      g_activationState.skuEISs[pos].RCD = nil
      service.returnResult( context, {activationStatus=true} )
   else
      service.returnResult( context, {activationStatus=false} )
   end

end

----------------------------------------------------------------------
-- processEject
--    Media has been ejected, bail out
----------------------------------------------------------------------
function processEject(path)
    if ( string.find(path, "usb" ) ~= nil) then
        io.output(stdout):write("nav-activation.lua: USB EJECTED\n")
        
        g_activationState.state = "noMedia"
        emitUpdateStatus()
        
        exitAndReportStatus(EXIT_USB_REMOVED)
    end
end

function requestActivationCheck( variantPath )
   local resp = service.invoke(navSyncBusName, 'UPD_RequestActivationCheck', {updatePath=string.format("<PATH>%s<*>", variantPath)})

   -- Make sure we got a response back
   if not resp then
      io.output(stdout):write( "nav-activation.lua: Likely there is no dbus service running\n" )
      return nil
   end

   return true
end


function parseSkuEIS( nngSkuEIS )
   if type(nngSkuEIS) ~= "table" then
      io.output(stdout):write( "nav-activation.lua: Table expected but received " .. type(nngSkuEIS).."\n" )
      return {}
   end

   local result = {}

   for i, sku in ipairs(nngSkuEIS) do

      local parsedSku = { raw=sku }

      for field, fieldValue in string.gmatch( sku, "<([^>]+)>([^<]+)<%*>" ) do
         parsedSku[field] = fieldValue
      end
      table.insert( result, parsedSku )
   end

   return result

end


NavProductIdFile = "/dev/mmap/productid"
---------------------------------------------------------------
-- getNavProductID - returns the first 16 bytes of the productid
---------------------------------------------------------------
function getNavProductID()
 
   local nav_productid
   local device = require "device"
   local fd = device.open(NavProductIdFile, "r")

   if fd then
      nav_productid = fd:read(16)
      fd:close()
   else
      io.output(stdout):write("nav-activation.lua: Unable to get Nav Product ID\n")
      nav_productid = nil, "ERROR: got "..nav_productid
   end

   return nav_productid
end

local function getVariantDir()

   -- Determine which variant to try
   productType = getNavProductID()
   if not productType then
      return nil, "Unknown variant " .. productType
   end

   local variantPath = usbpath .. "/nav/" .. string.sub(productType,1,6) .. "/nng"
   if lfs.attributes(variantPath,"mode") == "directory" then
      return variantPath
   else
      return nil, "Path " .. variantPath .. " does not exist"
   end
end

local function getStickDBVersion( path )

   local NavDBVer = nil

   if not path or type(path) ~= "string" then
      return NavDBVer
   end
   
   local pathToFile = path .. "/content/dbver.pinfo"
   
   if lfs.attributes(pathToFile, "mode" ) ~= "file" then
      print ( "Unable to find file " .. pathToFile )
      return NavDBVer
   end

   local f = io.open( pathToFile, "r" )
   if not f then
      return NavDBVer
   end
    
   local line = f:read("*l")
   f:close()
   
   if line then
      NavDBVer = string.match( line, "^[^;]+;([^;]+);" )
   end
   
   if NavDBVer then
      io.output(stdout):write( "nav-activation.lua: Database version on stick is " .. NavDBVer.."\n" )
   end
   
   return NavDBVer

end

local function getTargetDBVersion()
   -- Default currently installed version to nil
   local NavDBVer = nil

   -- Request: string "JSON_GetProperties" string "{"inprop":["ETC_SoftwareVersion","ETC_DatabaseVersion"]}"
   local resp = service.invoke(navBusName, 'JSON_GetProperties', {inprop={"ETC_DatabaseVersion"}}, 5000 )
   
   -- Response: string "{"outprop":{"ETC_DatabaseVersion":"TEBR6FEUL;NQFEU2010Q4;20110321","ETC_SoftwareVersion":"9.4.3.193007"}}"
   if resp and resp.outprop and resp.outprop.ETC_DatabaseVersion then
      local field = string.match( resp.outprop.ETC_DatabaseVersion, "^[^;]+;([^;]+);" )
      if field then
         NavDBVer = field
         io.output(stdout):write( "nav-activation.lua: Database version on target is " .. NavDBVer.."\n" )
      end
   end

   return NavDBVer
end


function onActivationCheck( sigName, params )
   io.output(stdout):write( "nav-activation.lua: Received: " .. sigName.."\n" )
   dumper.dumpTable( params )
   
   local pathToUpgrade
   if params and params.updatePath then
      pathToUpgrade = string.match( params.updatePath, "^<PATH>([^<]+)<%*>" )
   end

   if params.update and params.update == 1 and params.result then

      -- DBaker Test code begin
      if false then
      local dummyData = {}
      table.insert( dummyData, "<PATH>/mnt/usb0/nav<*><SKU>9932<*><PNAM>NQ FEU 2010.Q2<*><TYID>15<*><PTYP>Navteq FEU<*><TLIM>0<*><DESC>Navteq Full Europe Content 2010.Q2<*><RCD>D1F3-24H5-2P6V-TM93<*>" )
      table.insert( dummyData, "<PATH>/mnt/usb0/nav<*><SKU>9342<*><PNAM>NQ FEU 2010.Q3<*><TYID>15<*><PTYP>Navteq FEU<*><TLIM>0<*><DESC>Navteq Full Europe Content 2010.Q3<*><RCD>2QZL-MW84-BL0C-NN33<*>" )
      g_activationState.skuEISs = parseSkuEIS(dummyData)
      end
      -- DBaker Test code end
      
      g_activationState.state       = "updateMediaAvailable"
      g_activationState.targetDBVer = getTargetDBVersion()
      g_activationState.stickDBVer  = getStickDBVersion(pathToUpgrade)

      -- If activation is required, parse it      
      if bit.band( params.result, 0x02 ) then
         io.output(stdout):write( "nav-activation.lua: Activation is required, parsing skuEIS\n" )
         g_activationState.skuEISs = parseSkuEIS( params.skuEIS )
      end
      
      emitUpdateStatus()
      return
      
   elseif not params.result then
      sendError( 1, "Internal error in upgrade" )
   elseif bit.band( params.result, 0x01 ) then
      sendError(1, "Nav update not valid for this device")
   elseif bit.band( params.result, 0x04 ) then
      sendError(4, "Insufficient space for update" )
   elseif bit.band( params.result, 0x08 ) then
      sendError(8, "Downgrades not allowed")
   else

   end
end

function onActivationTimeout()
   print "Time for activation result expired"
   exitAndReportStatus(EXIT_ACT_RESP_TIME)
end

-- ===================================================================== (MAIN)

-- Verify that we have the correct two arguments
if #arg ~= 2 then
   io.output(stdout):write( "Usage: nav-activation.lua PathToISO PathToUSB\n" );
   exitAndReportStatus(EXIT_INVAL_NUM_ARGS)
end

-- Verify that we have received the ISO mount path
mountpath = arg[1]
if (mountpath == nil) or ( lfs.attributes(mountpath,"mode") ~= "directory") then
   print "ISO_PATH missing or not a directory"
   -- TODO : Send a HMI signal about error
   exitAndReportStatus(EXIT_NO_ISO_PATH)
end

-- Verify that we have received the USB mount path
usbpath = arg[2]
if (usbpath == nil) or ( lfs.attributes(usbpath,"mode") ~= "directory") then
   print "USB_PATH missing or not a directory"
   -- TODO : Send a HMI signal about error
   exitAndReportStatus(EXIT_NO_USB_PATH)
end

-- Start up the SyncTool and SyncToolController
naviSyncTools.start(mountpath)

-- Verify that the navSyncController is running
if not service.nameHasOwner(navSyncBusName) then
   print "Unable to find nav sync service\n"
   exitAndReportStatus(EXIT_SYNCTOOL)
end

-- Register the softwareInstaller service
g_updateService = service.register(serviceName, g_methods)
if not g_updateService then
   print ( "Unable to start the update service " .. serviceName )
   exitAndReportStatus(EXIT_SVC_START_FAIL)
end

-- Determine the variant path
local errorMsg
g_VariantPath, errorMsg = getVariantDir( usbpath )
if not g_VariantPath then
   io.output(stderr):write( "nav-activation.lua: "..errorMsg.."\n" )
   exitAndReportStatus(EXIT_VARIANT)
end

io.output(stdout):write("nav-activation.lua: Using "..g_VariantPath.." for nav update\n")

-- Set the notification of a pulled stick
mcd.notify(g_mcdConfig.mcdEjectRule, processEject)

-- Listen for asynchronous response to activation check
service.subscribe( navSyncBusName, "UPD_InformActivationCheck", onActivationCheck )

-- Delay required because controller appears before it is ready
-- TODO: Remove once Jason has updated to only show up when actually ready
os.sleep(3)

-- Setup a timer that will bound the length of time this can take
--    since we are running lua with a -s and would never terminate otherwise
local activationTimer = timer.new(onActivationTimeout)
--activationTimer:start(30 * 60 * 1000, 1)     -- fire once in 30 minutes

-- Request the activation status
local result = requestActivationCheck( g_VariantPath )
if not result then
   exitAndReportStatus(EXIT_SYNCTOOL)
end

-- Now just hang out until either the timeout time expires or the activation
--     check comes back.

io.output(stdout):write("nav-activation.lua: Waiting for activation check or a timeout\n")
