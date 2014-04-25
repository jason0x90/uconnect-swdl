--[[
   Sierra Wireless embedded cell phone installer
--]]

module("sierra_wireless",package.seeall)

local onoff          = require "onoff"
local lfs            = require "lfs"
local helper         = require "installerhelper"
local math           = require "math"

local printLog           = helper.printLog
local BOOT_HOLD_COMMAND  = "AT!BOOTHOLD\r"
local RESET_CHIP         = "AT!RESET\r"
local g_hold_port        = nil
local g_install_port     = nil 
local g_unit             = {}
local g_complete_percent = 0
local installed_version  = {}

-- error code(s) returned by installer
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE 
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL


---------------------------------------------------------------
-- chipReset  
---------------------------------------------------------------
local function chipReset()
   local command = "echo "..RESET_CHIP.." > "..g_hold_port
   os.execute(command) 
   os.sleep(10)
end 


---------------------------------------------------------------
-- getSierraVersions - return a table with the versions
---------------------------------------------------------------
local function getSierraVersions()
   local t = { hw_rev="NULL", appl_rev = "NULL", boot_rev = "NULL" }
   
   -- remove any copies of output file '/tmp/p.txt'
   local cmd="rm -f /tmp/p.txt >/dev/null"
   os.execute(cmd)

   -- execute chat script and send output to '/tmp/p.txt'
   cmd="chat -t6 -r /tmp/p.txt -f "..chat_ver_file.." <> /dev/swiusb4 1>&0"
   print(cmd)
   local r=os.execute(cmd)
   if r==0 then
      local f=io.open("/tmp/p.txt", "r")
      for line in f:lines() do

         local st, en = string.find(line, "HW Version: ")
         if en then
            t.hw_rev = string.sub(line, en+1)
         end

         st, en = string.find(line, "APPL Revision: ")
         if en then
            t.appl_rev = string.sub(line, en+1)
         end

         st, en = string.find(line, "BOOT Revision: ")
         if en then
            t.boot_rev = string.sub(line, en+1)
         end
      end
   else
      printLog("Sierra Wireless: Unable to execute chat script to get versions "..r)
   end
   
   return t
end


---------------------------------------------------------------
-- install 
--  Function will be called by update
---------------------------------------------------------------
function install(unit, progress, mountpath, current_unit)

   local boloflag    
   local percent = 0
   local bolo_file 
   local app_file 
   local ok, err
   local err_code = nil
   local chat_file 

   g_unit = unit
   bolo_file = mountpath.."/"..g_unit.boot_bin
   app_file  = mountpath.."/"..g_unit.app_bin
   chat_file = mountpath.."/"..g_unit.sierra_flow_control_chat
   chat_ver_file = mountpath.."/"..g_unit.sierra_version_chat
   sierra_iso_version_file = mountpath.."/"..g_unit.sierra_new_version_file

   g_hold_port = g_unit.hold_port
   g_install_port = g_unit.install_port

   printLog("Hold port: "..g_hold_port)
   printLog("Install port: "..g_install_port)  

   progress(g_unit, 1)     

   -- call preInstaller, if specified
   ok, err, err_code = helper.callPrePostInstaller(g_unit, mountpath, "pre")
   if not ok then 
      return false, err, err_code
   end  

   -- If the binary files don't exist stop the update
   if ((lfs.attributes( bolo_file, "mode" ) == nil) or ((lfs.attributes( app_file, "mode" ) == nil) )) then 
      printLog("Sierra Wireless: Update binaries missing")
      return false, "Unable to locate binary files"
   else
      printLog("Using Sierra bootloader file: "..bolo_file)
      printLog("Using Sierra application file: "..app_file)
   end

   -- If the chat executable doesn't exist stop the update
   if (lfs.attributes( chat_file, "mode" ) == nil) then
      printLog("Sierra Wireless: No Chat script to run")
      return false, "Unable to locate chat executable"
   else
      printLog("Using chat script: "..chat_file)
   end

   -- check if hold port is there and get "from" versions
   ok = waitforMountPoint(g_hold_port, 60)
   if ok then
      installed_version = getSierraVersions()
      if installed_version and installed_version.hw_rev then printLog("Current hardware rev: \""..installed_version.hw_rev.."\"") else printLog("Not defined") end
      if installed_version and installed_version.appl_rev then printLog("Current APPL rev: \""..installed_version.appl_rev.."\"") else printLog("Not defined") end
      if installed_version and installed_version.boot_rev then printLog("Current BOOT rev: \""..installed_version.boot_rev.."\"") else printLog("Not defined") end
   else
      printLog("Sierra Wireless: Hold port is not available")
      installed_version  = { hw_rev="CURRENT_DEFAULT", appl_rev = "CURRENT_DEFAULT", boot_rev = "CURRENT_DEFAULT" }
   end

   -- get the new versions from the manifest
   printLog("Trying Sierra Wireless firmware version file: "..sierra_iso_version_file)
   if (lfs.attributes( sierra_iso_version_file, "mode" ) == nil) then
      printLog("Sierra Wireless: No firmware version file")
      return false, "No Sierra Wireless firmware version file"      
   end

   h = loadfile(sierra_iso_version_file)
   if h then
      h()
   else
      printLog("Sierra Wireless: unable to load new version file")
      iso_version = { hw_rev="ISO_DEFAULT", appl_rev = "ISO_DEFAULT", boot_rev = "ISO_DEFAULT" }
   end
   if iso_version and iso_version.hw_rev then printLog("New hardware rev: \""..iso_version.hw_rev.."\"") else printLog("Not defined") end
   if iso_version and iso_version.appl_rev then printLog("New APPL rev: \""..iso_version.appl_rev.."\"") else printLog("Not defined") end
   if iso_version and iso_version.boot_rev then printLog("New BOOT rev: \""..iso_version.boot_rev.."\"") else printLog("Not defined") end

   -- if already same version then done
   if installed_version and iso_version and installed_version.boot_rev ==  iso_version.boot_rev then
      printLog("Sierra Wireless: new BOOT firmware same as installed")
      if installed_version.appl_rev ==  iso_version.appl_rev then
         g_complete_percent = 100
         progress(g_unit, g_complete_percent)
         os.sleep(2)
         printLog("Sierra Wireless: new APPL firmware same as installed")
         return true
      else
         printLog("Sierra Wireless: new APPL firmware different than installed")
      end
   else
      printLog("Sierra Wireless: new BOOT firmware different than installed")
   end

   -- try up to 3 times to install the new ecell bootloader binary   
   for try_count = 1,3 do
      ok, err = installCommand(bolo_file, progress)      
      if not ok then 
         printLog("Sierra Wireless: bootloader upload failed on try "..try_count)
         if err then printLog("Sierra Wireless: "..err) end
         if try_count >= 2 then
            return false, "Sierra Wireless: bolo file install failed"
         end
      else
         printLog("Sierra bolo install completed") 
         break
      end
   end
   printLog("Done with Sierra bolo, now perfrom app")
     
   g_complete_percent = 40
   progress(g_unit, g_complete_percent)

   -- try up to 3 times to install the new ecell application binary
   for try_count = 1,3 do
      ok, err = installCommand(app_file, progress)      
      if not ok then 
         printLog("Sierra Wireless: application upload failed on try "..try_count)
         if err then printLog("Sierra "..err) end
         if try_count >= 2 then
            return false, "Sierra Wireless: application file install failed"
         end
      else
         printLog("Sierra application install completed") 
         break
      end
   end

   g_complete_percent = 75
   progress(g_unit, g_complete_percent)

   -- wait for all the ports to appear, we will wait for install port to appear 
   -- which is good enough sign that chip is in reset and now ready to use 
   printLog("Done with Sierra app, now check status")
   ok ,err = waitforMountPoint(g_hold_port, 60)
   if not ok then 
      printLog("Sierra Wireless: after update ports are not coming up")
      return false, "Sierra after-update ports are not coming up. "
   end    

   g_complete_percent = 80    
   progress(g_unit, g_complete_percent)  

   -- run the chat script, to disable flow control  
   local cmd = "chat -vs -t6 -f "..chat_file.." <> "..g_hold_port.." >&0"
   print(cmd)
   local ret_code = os.execute(cmd)/256
   -- Check for the return code
   if (ret_code == nil or ret_code ~= 0) then 
      printLog(string.format("Sierra Wireless: chat script failure %d\n",ret_code))		 
      return false,  "Sierra update chat script failure"
   end    

   -- check if hold port is there and get newly installed versions
   ok = waitforMountPoint(g_hold_port, 60)
   if ok then
      installed_version = getSierraVersions()
      if installed_version and installed_version.appl_rev then printLog("New APPL rev \""..installed_version.appl_rev.."\"") end
      if installed_version and installed_version.boot_rev then printLog("New BOOT rev \""..installed_version.boot_rev.."\"") end

      if not iso_version or installed_version.boot_rev ~= iso_version.boot_rev then
         return false, "Sierra install failed - Installed bootloader version does not match expected"
      end

      if not iso_version or installed_version.appl_rev ~= iso_version.appl_rev then
         return false, "Sierra install failed - Installed application version does not match expected"
      end
   else
      printLog("Sierra Wireless: Hold port is not available for version check after install")
   end

   -- reset the chip
   chipReset()

   g_complete_percent = g_complete_percent + 10    
   progress(g_unit, g_complete_percent)  
   -- wait for all the ports to appear, we will wait for install port to appear 
   ok ,err = waitforMountPoint(g_install_port, 300)
   if not ok then 
      printLog("Sierra Wireless: after update ports are not coming up")
      return false, "Sierra after-reset, after-update ports are not coming up. "
   end          

   -- call postInstaller, if specified
   ok, err, err_code = helper.callPrePostInstaller(g_unit, mountpath, "post")
   if not ok then 
      return false, err, err_code
   end  

   g_complete_percent = 100  
   progress(g_unit, g_complete_percent)      
   printLog("Sierra update done")
   return true
end   


---------------------------------------------------------------
-- waitforMountPoint  
---------------------------------------------------------------
function waitforMountPoint(path, secs)
   local i
   local status = false
    
    -- this is a really long time to wait but its much safe
   for i = 1, secs, 1 do
      if ((lfs.attributes( path, "mode" ) ~= nil)) then 
         status = true
         printLog(" path exists "..i.." "..path)
         printLog("lfs_attr"..(lfs.attributes(path, "mode" )))
         break
      end    
      printLog(" waiting for port= "..path.." count = "..i)
      os.sleep(1)
   end    
   return status
end


---------------------------------------------------------------
-- makebootholdmode  
---------------------------------------------------------------
function makebootholdmode()
   local command = "echo "..BOOT_HOLD_COMMAND.." > "..g_hold_port
   os.execute(command) 
   os.sleep(10)
end


---------------------------------------------------------------
-- installCommand  
---------------------------------------------------------------
function installCommand(file_name, progress)
   local   command 
   local   prev_percent    
   local   ok

   command = "mploader "..g_install_port.." "..file_name.." -q -d "
   print(command)

   -- check for install port indicating module is present
   ok = waitforMountPoint(g_install_port, 300)
   if not ok then
      printLog("Sierra Wireless: Install port is not available before update, something wrong with chip")
      return false, "Sierra device not detected"
   end

   -- check if hold port is there and enter boot & hold mode
   ok = waitforMountPoint(g_hold_port, 60)    
   if ok then     
      makebootholdmode()  	        
   else
      printLog("Sierra Wireless: Hold port is not available, assume chip already in update mode")
   end        

   local pipe = assert(io.popen(command))
   for line in pipe:lines() do
      print(line)
      local unit_percent = 0
      local percent = tonumber(line)
      if percent then
         if percent ~= prev_percent then
            -- the reason for percent to be divided in half is because 
            -- we are doing both the app and bolo updates               
            unit_percent =  math.floor(g_complete_percent + (percent/3))
            progress(g_unit, unit_percent)
            prev_percent = percent
         end           
      end    
      if line:sub(1,5) == "ERROR" then
         pipe:close()
         return false, line              
      end
      if line:sub(1,8) == "FINISHED" then	
         pipe:close()
         return true                     
      end       
   end
   pipe:close()
   return false, "failure in updating Sierra Wireless card"
end
