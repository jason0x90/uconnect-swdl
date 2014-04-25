
require "lfs"

module("naviSyncTools", package.seeall)

io.output(stdout):write("naviSyncTools.lua: START\n")

local gSyncToolPath      = "usr/bin/nav/NNG_SyncTool"
local gSyncToolFName     = "Synctool"
local gSyncToolCtrlPath  = "usr/bin/nav/update"
local gSyncToolCtrlFName = "NavUpdateController"

function stop()
   os.execute( "slay -f " .. gSyncToolFName .. " " .. gSyncToolCtrlFName )
   return true
end

function start( isoRoot )
   local resp

   local gSyncTool     = isoRoot .. "/" .. gSyncToolPath ..     "/" .. gSyncToolFName
   local gSyncToolCtrl = isoRoot .. "/" .. gSyncToolCtrlPath .. "/" .. gSyncToolCtrlFName

   -- Make sure the tools exist
   if lfs.attributes( gSyncTool, "mode" ) ~= "file" or
      lfs.attributes( gSyncToolCtrl, "mode" ) ~= "file" then
      return nil, "one ore more sync tools missing"
   end

   -- Stop the tools if they are running
   stop()

   -- Start SyncTool
   local currDir = os.currentdir()
   os.chdir(isoRoot .. "/" .. gSyncToolPath)
   local syncToolCmd = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:" .. isoRoot .. "/usr/bin/nav/update " .. "./" .. gSyncToolFName .. " &"
   io.output(stdout):write("naviSyncTools.lua: "..syncToolCmd.."\n")
   os.execute( syncToolCmd )

   -- Sleep for a bit.  Seems to be necessary for proper communication
   os.sleep(3)

   -- Start SyncToolController
   os.chdir( isoRoot .. "/" .. gSyncToolCtrlPath )
   cmd = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:. ./" .. gSyncToolCtrlFName .. " &"
   io.output(stdout):write("naviSyncTools.lua: "..cmd.."\n")
   os.execute( cmd )
   
   -- Wait for update service to start
   resp = os.execute( "waitfor /dev/serv-mon/com.harman.service.NavigationUpdate 60" )
   if resp ~= 0 then
      os.chdir(currDir)
      stopSyncTools()
      return nil, "NavUpdateController did not appear"
   end

   os.chdir(currDir)

   io.output(stdout):write("naviSyncTools.lua: END\n")

   return true   
end
