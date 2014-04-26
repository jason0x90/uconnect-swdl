-- mmc files installer
 
module("mmc",package.seeall) 

local helper    = require "installerhelper" 
local g_path    = nil 
local printLog  = helper.printLog
 
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
local function get_qkcp_status( pathToShmemFile )
    local qkcpStatus = {}
    local cmd
    
    print("read status")
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
        printLog(" Unable to "..operation.." mmc driver successfully")
        printLog(" ret_code "..ret_code)
        return false, "Unable to "..operation.."  mmc driver successfully"
    end     
    return true 
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
    
    -- TODO: Remove this, only for testing 
    -- local src_dir = "/fs/mmc0/gracenote/"  
    -- local dst_dir = "/fs/etfs/pranay/"       
    
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
    
    os.sleep(1)
    
    -- delete the destination directory
    cmd = "rm -rf "..dst_dir
    print(cmd)
    os.execute(cmd)      
    
    os.sleep(1)
    
    cmd = "mkdir "..dst_dir
    print(cmd)
    os.execute(cmd)          
    os.sleep(1)
    
    -- Create the file in shared memory to read qkcp progress
    cmd = "touch /tmp/"..qkcp_progress  
    os.execute(cmd)     

    -- Start qkcp in background
    cmd = "qkcp -h "..qkcp_progress.." "..src_dir.." "..dst_dir.." &"    
    print(cmd)    
    os.execute(cmd)
    
    os.sleep(1)
    
    -- read the progress notification
    while 1 do
    
        qkcpStatus = get_qkcp_status( "/tmp/"..qkcp_progress )

        os.sleep(1)
        
        if qkcpStatus and not qkcpStatus.error then
           print( "" )
           print( string.format( "jobSizeK     = %dK", qkcpStatus["jobSizeK"] )) 
           print( string.format( "jobSizeDoneK = %dK", qkcpStatus["jobSizeDoneK"] )) 
           print( string.format( "jobFiles     = %d", qkcpStatus["jobFiles"] )) 
           print( string.format( "jobFilesDone = %d", qkcpStatus["jobFilesDone"] )) 
           print( string.format( "jobTime      = %d seconds", qkcpStatus["jobTime"] )) 
           print( string.format( "jobTimeLeft  = %d seconds", qkcpStatus["jobTimeLeft"] )) 
           printLog ( string.format( "percent      = %d%%", qkcpStatus["percent"] )) 
           print( string.format( "phase.value  = %d, phase.string  = %s", qkcpStatus["phase"]["value"], qkcpStatus["phase"]["string"] )) 
           printLog( string.format( "status.value = %d, status.string = %s", qkcpStatus["status"]["value"], qkcpStatus["status"]["string"] )) 
        
           if ( string.find(string.upper(qkcpStatus.status.string), "FAILURE" ) ~= nil) then    
               printLog("mmc.lua: qkcp failed")
               error_flag = 1
               -- An error occured.  Since the error occured while reading/writing to the mmc,
               -- any further attempts to do anything such as unmount it may fail by blocking forever.
               -- Therefore, don't call executeMMC(..."stop"), just exit with the error, which will
               -- abort the update
               return false, "mmc.lua: ERROR: qkcp failed "
           end              

           if qkcpStatus["percent"] == prevPercent then
              progressCounter = progressCounter + 1
              if progressCounter > progressTimeout then
                 return false, string.format("mmc.lua: ERROR: no copy progress from %d%% after %d seconds", prevPercent, progressCounter)
              end
           else 
              prevPercent = qkcpStatus["percent"]
              progressCounter = 0
           end
           
           progress(unit, qkcpStatus["percent"]) 

           if qkcpStatus.phase.value == 3 then            
               printLog("qkcp done")
               break
           end        
        else
           printLog("mmc.lua: qkcp status is blank")
           progressCounter = progressCounter + 1
           if progressCounter > progressTimeout then
              return false, string.format("mmc.lua: ERROR - no copy progress from %d%% after %d seconds", prevPercent, progressCounter)
           end
        end
  
    end 
 
    -- call postInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "post")
    if not ok then 
        return false, "post installer failure"
    end      

    -- please see "c:\proj\cf\trunk_a\tcfg\omap\update\KaliSWDL\prebuilt\ISO\usr\nav_temp\readme_TMCLocFilter_NA.zip.txt" for information on this section of code
    if unit.name == "System Data" then 
       cmd="mkdir -p /fs/mmc0/nav/NNG/content/tmc"
       print(cmd)
       os.execute(cmd)

       cmd="cp "..mountpath.."/usr/nav_temp/TMCLocFilter_NA.zip  /fs/mmc0/nav/NNG/content/tmc/"
       print(cmd)
       os.execute(cmd)
    end
    
    -- do the cleanup
    local ok, err = executeMMC(unit, "stop")           
    if not ok then 
        return false, err 
    end         
    
    os.execute("rm /tmp/"..qkcp_progress)    
    
    return true 
  
end
