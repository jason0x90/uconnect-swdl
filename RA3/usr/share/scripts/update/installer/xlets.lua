-- mmc files installer
 
module("xlets",package.seeall) 

local helper    = require "installerhelper" 
local g_path    = nil 
local printLog  = helper.printLog

local partNumberFile = "/dev/fram/partnumber"

---------------------------------------------------------------
-- convertUInt  
---------------------------------------------------------------
local function convertUInt( str, offset, numbytes )
    assert(string.len(str) >= numbytes )
    local result = 0;
    for i=numbytes + offset,1+offset,-1 do
      result = ( result * 256 ) + string.byte( str, i )
    end
    return result
end

---------------------------------------------------------------
-- get_qkcp_status  
---------------------------------------------------------------
local function get_qkcp_status( pathToShmemFile, display, logit )
    local qkcpStatus = {}
    local cmd

    cmd = "cp "..pathToShmemFile.." /tmp/temp_file"
    os.execute(cmd)
    pathToShmemFile = "/tmp/temp_file" 
    
    local f = io.open(pathToShmemFile, "rb")
    if not f then 
        qkcpStatus["error"] = string.format( "Unable to open file:%s", pathToShmemFile )
        return qkcpStatus
    end
    
    local strStruct = f:read("*all");
    if string.len(strStruct) < 52 then 
        qkcpStatus["error"] = string.format( "Not enough bytes in %s:%d", pathToShmemFile, string.len(strStruct) )
        f:close()
        return qkcpStatus 
    end

    local offset = 0
    qkcpStatus["jobSizeK"]        = convertUInt(strStruct, offset, 8)
    offset = offset + 8
    
    qkcpStatus["jobSizeDoneK"]    = convertUInt(strStruct, offset, 8)
    offset = offset + 8
    
    qkcpStatus["jobFiles"]        = convertUInt(strStruct, offset, 4)
    offset = offset + 4
    
    qkcpStatus["jobFilesDone"]    = convertUInt(strStruct, offset, 4)
    offset = offset + 4
    
    qkcpStatus["jobTime"]         = convertUInt(strStruct, offset, 8)
    offset = offset + 8

    qkcpStatus["jobTimeLeft"]     = convertUInt(strStruct, offset, 8)
    offset = offset + 8

    qkcpStatus["percent"]         = convertUInt(strStruct, offset, 4)
    offset = offset + 4

    qkcpStatus["phase"] = {}
    qkcpStatus["phase"]["value"]  = convertUInt(strStruct, offset, 4)
    offset = offset + 4
    local phase = qkcpStatus["phase"]["value"]
    
    if phase == 1 then 
        qkcpStatus["phase"]["string"] = "get job size"
    elseif phase == 2 then 
        qkcpStatus["phase"]["string"] = "copy data"
    elseif phase == 3 then 
        qkcpStatus["phase"]["string"] = "copy done"
    else                   
        qkcpStatus["phase"]["string"] = "unknown phase" 
    end

    qkcpStatus["status"] = {}
    qkcpStatus["status"]["value"] = convertUInt(strStruct, offset, 4)
    offset = offset + 4
    local status = qkcpStatus["status"]["value"];
    if status == 0 then 
        qkcpStatus["status"]["string"] = "success"
    elseif status == 1 then 
        qkcpStatus["status"]["string"] = "failure (default)"
    elseif status == 2 then 
        qkcpStatus["status"]["string"] = "failure (graceful stop)"
    elseif status == 3 then 
        qkcpStatus["status"]["string"] = "failure (checkpoint corrupt)"
    elseif status == 4 then 
        qkcpStatus["status"]["string"] = "failure (read error)"
    elseif status == 5 then 
        qkcpStatus["status"]["string"] = "failure (write error)"
    elseif status == 6 then 
        qkcpStatus["status"]["string"] = "failure (corrupt file system)"
    elseif status == 7 then 
        qkcpStatus["status"]["string"] = "failure (no space left on device)"
    else
        qkcpStatus["status"]["string"] = "unknown status" 
    end
    
    cmd = "rm "..pathToShmemFile
    os.execute(cmd)    
    
    f:close()

    if display then
        print( string.format( "\njobSizeK     = %dK", qkcpStatus["jobSizeK"] )) 
        print( string.format( "jobSizeDoneK = %dK", qkcpStatus["jobSizeDoneK"] )) 
        print( string.format( "jobFiles     = %d", qkcpStatus["jobFiles"] )) 
        print( string.format( "jobFilesDone = %d", qkcpStatus["jobFilesDone"] )) 
        print( string.format( "jobTime      = %d seconds", qkcpStatus["jobTime"] )) 
        print( string.format( "jobTimeLeft  = %d seconds", qkcpStatus["jobTimeLeft"] )) 
        print( string.format( "phase.value  = %d, phase.string  = %s", qkcpStatus["phase"]["value"], qkcpStatus["phase"]["string"] )) 
    end
      
    if log then
        printLog( string.format( "percent      = %d%%", qkcpStatus["percent"] )) 
        printLog( string.format( "status.value = %d, status.string = %s", qkcpStatus["status"]["value"], qkcpStatus["status"]["string"] )) 
    end
    
    return qkcpStatus    
end

---------------------------------------------------------------
-- executeMMC 
---------------------------------------------------------------
local function executeMMC(unit, operation)
    
    local cmd = g_path.."/"..unit.mmc_start_script.." "..operation
    print(cmd)
    
    printLog(string.format("mmc driver operation %s",operation)) 
    local ret_code = os.execute(cmd)/256
    
    -- Check for the return code     
    if (ret_code ~= 0) then 
        printLog(" Unable to"..operation.." mmc driver successfully")
        printLog(" ret_code "..ret_code)
        return false, "Unable to"..operation.."  mmc driver successfully"
    end     
    return true 
end

---------------------------------------------------------------
-- getPartNumber - returns partnumber or 'PN ERROR'
---------------------------------------------------------------
local function getPartNumber()

   local partnumber = "PN ERROR"
   local device = require "device"
   local fd = device.open(partNumberFile, "r")

   if fd then
      partnumber = fd:read(10)
      fd:close()
      if partnumber and string.find(partnumber,"^%d%d%d%d%d%d%d%d[%l%u][%l%u]") then
         -- chrysler
         partnumber = string.sub(partnumber, 1,8)
      elseif partnumber and string.find(partnumber,"^%d%d%d%d%d%d%d%d%d") then
         -- fiat
         partnumber = string.sub(partnumber, 1,9)
      end
   else
      print("Unable to get part number")
   end

   return partnumber
end

---------------------------------------------------------------
-- getKimSubdir - returns kim package string or 'KIM0'
---------------------------------------------------------------
local function getKimSubdir(pn)
   local rval = "KIM0"

   dofile("../../XLETS/kim_packages/kim_pkg_map.lua")
   
   if kim_pkg_map and kim_pkg_map[pn] then
      rval = kim_pkg_map[pn]
   end

   return rval
end

---------------------------------------------------------------
-- install function
--  Will be called by softwareUpdater
--------------------------------------------------------------- 
function install(unit, progress, mountpath) 
    
    local error_flag = 0 
    local cmd
    local qkcp_progress = "swdl_"..unit.installer.."_progress"  
    local qkcpStatus = {}
    local prevPercent = 0
    local progressCounter = 0
    local progressTimeout = 60  -- num sec of no qkcp "percent" progress before declaring a USB driver failure
    
    g_path = mountpath 	
    local src_dir = mountpath.."/"..unit.src_dir.."/"        
    local dst_dir = unit.dst_dir 
    
    print(" src dir "..src_dir)
    print(" dst_dir "..dst_dir)

    local partnumber = getPartNumber()
    local kimpkgsubdir = getKimSubdir(partnumber)
    printLog("xlets.lua: Installing "..kimpkgsubdir.." for part number "..partnumber)
    
    progress(unit, 0) 
    -- Check if source directory exists
    cmd = "ls -l "..src_dir
    print(cmd)   

    local f = assert (io.popen (cmd, "r")) 
    local lines = f:read("*l") 
    print(lines)
    if (lines == nil) then     
        printLog(string.format("%s source directory does not exists, exiting installer",src_dir))
        progress(unit, 100)
        return true    
    end   
    f:close()
    
    print(" Start devb-mmcsd")
    local ok, err = executeMMC(unit, "start")           
    if not ok then 
        return false, err 
    end     
    print(" Started devb-mmcsd")
        
    -- call preInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "pre")
    if not ok then 
        return false, "pre installer failure"
    end  
    
    -- delete factory installed JAR files in the destination directory(s)
    cmd = "[[ -d /fs/mmc1/kona/preload ]] && for d in `find "..dst_dir.."kona/preload/xlets/ -type d -level 1 -printf \"%f\\n\"`; do echo \"Deleting $d\"; rm -rf "..dst_dir.."xletsdir/xlets/$d; done"
    print(cmd)
    os.execute(cmd)
    progress(unit, 5) 
    printLog("deleted existing factory installed xlets from working directory")

    -- finish removing current factory installed xlets
    cmd = "rm -rf "..dst_dir.."kona/preload/xlets/*"
    print(cmd)
    os.execute(cmd)
    progress(unit, 10) 
    printLog("deleted existing factory installed xlets from preload directory")
    
    -- Copy over the baseline structure
    cmd = "qkcp "..src_dir.."base "..dst_dir    
    print(cmd)    
    os.execute(cmd)
    progress(unit, 20) 
    printLog("restored baseline xlet directory structure")

    -- TODO: Remove this, once qnx fat32 cache coherency is fixed, 
    -- umount and mounting file system is just a workarond that problem
    local ok, err        
    ok, err = executeMMC(unit, "umount")
    if not ok then
        return false, err
    end        
    ok, err = executeMMC(unit, "mount")
    if not ok then 
        return false, err
    end
    
    if kimpkgsubdir then
       
       if kimpkgsubdir ~= "KIM0" then
       
         -- create the file in shared memory to read qkcp progress
         cmd = "rm -f /tmp/"..qkcp_progress..";touch /tmp/"..qkcp_progress  
         print(cmd)
         os.execute(cmd)
      
         -- restore factory preloaded apps from proper KIM package
         cmd = "qkcp -h "..qkcp_progress.." "..src_dir.."kim_packages/"..kimpkgsubdir.." "..dst_dir.."kona/preload/ &"
         print(cmd)
         os.execute(cmd)
      
         -- read the progress notification
         qkcpStatus = get_qkcp_status( "/tmp/"..qkcp_progress )
         while qkcpStatus.phase.value ~= 3 do
    
            qkcpStatus = get_qkcp_status( "/tmp/"..qkcp_progress, 1, 1 )
  
            os.sleep(1)
        
            if ( string.find(string.upper(qkcpStatus.status.string), "FAILURE" ) ~= nil) then    
               printLog("xlets.lua: qkcp failed")
               error_flag = 1
               -- An error occured.  Since the error occured while reading/writing to the mmc,
               -- any further attempts to do anything such as unmount it may fail by blocking forever.
               -- Therefore, don't call executeMMC(..."stop"), just exit with the error, which will
               -- abort the update
               return false, "xlets.lua: ERROR: qkcp to kona/preload failed "
            end              

            if qkcpStatus["percent"] == prevPercent then
               progressCounter = progressCounter + 1
               if progressCounter > progressTimeout then
                  return false, string.format("xlets.lua: ERROR: no qkcp progress from %d%% after %d seconds", prevPercent, progressCounter)
               end
            else 
               prevPercent = qkcpStatus["percent"]
               progressCounter = 0
            end
       
            progress(unit, 20 + qkcpStatus["percent"]/2.5) 
  
         end  --while
         printLog("completed installing new factory preload apps into preload directory")

         -- Create the file in shared memory to read qkcp progress
         cmd = "rm -f /tmp/"..qkcp_progress..";touch /tmp/"..qkcp_progress  
         print(cmd)
         os.execute(cmd)
      
         -- mirror factory preloaded apps to the working directory
         cmd = "qkcp -h "..qkcp_progress.." "..src_dir.."kim_packages/"..kimpkgsubdir.."/xlets "..dst_dir.."xletsdir/xlets &"    
         print(cmd)    
         os.execute(cmd)
      
         -- read the progress notification
         prevPercent = 0
         progressCounter = 0
         qkcpStatus = get_qkcp_status( "/tmp/"..qkcp_progress )
         while qkcpStatus.phase.value ~= 3 do
    
            qkcpStatus = get_qkcp_status( "/tmp/"..qkcp_progress, 1, 1 )
  
            os.sleep(1)
        
            if ( string.find(string.upper(qkcpStatus.status.string), "FAILURE" ) ~= nil) then    
               printLog("xlets.lua: qkcp failed")
               error_flag = 1
               -- An error occured.  Since the error occured while reading/writing to the mmc,
               -- any further attempts to do anything such as unmount it may fail by blocking forever.
               -- Therefore, don't call executeMMC(..."stop"), just exit with the error, which will
               -- abort the update
               return false, "xlets.lua: ERROR: qkcp to xletsdir/xlets failed "
            end              

            if qkcpStatus["percent"] == prevPercent then
               progressCounter = progressCounter + 1
               if progressCounter > progressTimeout then
                  return false, string.format("xlets.lua: ERROR: no qkcp progress from %d%% after %d seconds", prevPercent, progressCounter)
               end
            else 
               prevPercent = qkcpStatus["percent"]
               progressCounter = 0
            end
       
            progress(unit, 60 + qkcpStatus["percent"]/2.5) 
  
         end  --while
         
         os.execute("rm /tmp/"..qkcp_progress)    
         
         printLog("completed installing new factory preload apps into working directory")

      else -- handle no KIM packages for KIM0

         cmd = "rm -rf /fs/mmc1/xletsdir/xlets/*"
         print(cmd)    
         os.execute(cmd)
         progress(unit, 60) 
         printLog("removed working xlets")
         
         cmd = "rm -rf /fs/mmc1/kona/preload"
         print(cmd)    
         os.execute(cmd)
         progress(unit, 100) 
         printLog("removed preload directory")
 
      end
    else
      error_flag = 1 
    end
    
    -- if error the send the error 
    if error_flag == 1 then 
       local ok, err = executeMMC(unit, "stop")           
        if not ok then 
            return false, err 
        end
        return false, qkcpStatus["status"]["string"]
    end
    
    -- call postInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "post")
    if not ok then 
        return false, "post installer failure"
    end      
    
    -- do the cleanup
    local ok, err = executeMMC(unit, "stop")           
    if not ok then 
        return false, err 
    end         
    
    return true 
  
end
