-- etfs files installer
 
module("etfs",package.seeall) 

local helper            = require "installerhelper" 
local printLog          = helper.printLog
local g_qkcp_error_code = nil

---------------------------------------------------------------
-- convertUInt  
---------------------------------------------------------------
local function convertUInt( str, offset, numbytes )
    assert(string.len(str) >= numbytes )
    local result = 0
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
-- qkcp_etfs
-- Function to start qkcp and get qkcp progress
--------------------------------------------------------------- 
local function qkcp_etfs(unit, progress, mountpath, start_operation)
    local error_flag    = 0 
    local cmd
    local qkcp_progress = "swdl_etfs_progress"       	
    local src_dir       = mountpath.."/"..unit.data.."/"        
    local dst_dir       = "/fs/etfs/"  
    local ok 
    local err 
    local qkcpStatus    = {}
    local preInstaller  = nil
    local postInstaller = nil
    local prevPercent = 0
    local progressCounter = 0
    local progressTimeout = 60  -- num sec of no qkcp "percent" progress before declaring a USB driver failure
 
     
    ok, err = helper.executeETFS(mountpath, unit, start_operation)
    if not ok then 
        printLog(err)
        return false, err
    end  
    
    -- call preInstaller
    ok, err = helper.callPrePostInstaller(unit, mountpath, "pre")
    if not ok then 
        return false, "post installer failure"
    end 
   
    -- Create the file in shared memory to read qkcp progress
    cmd = "touch /tmp/"..qkcp_progress  
    os.execute(cmd)     

    -- Start qkcp in background
    cmd = "qkcp -h "..qkcp_progress.." "..src_dir.." "..dst_dir.." &"    
    os.execute(cmd)     
    
    -- read the progress notification
    while 1 do    
        qkcpStatus = get_qkcp_status( "/tmp/"..qkcp_progress )        
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

        -- sleep for 1 second so that we are not sending the progress notification 
        -- for very small progress
        os.sleep(1)   
        
        if ( string.find(string.upper(qkcpStatus.status.string), "FAILURE" ) ~= nil) then    
            printLog("etfs.lua: qkcp failed")
            g_qkcp_error_code = qkcpStatus.status.value
            -- An error occured.  Since the error occured while reading/writing to the mmc,
            -- any further attempts to do anything such as unmount it may fail by blocking forever.
            -- Therefore, don't call executeETFS(..."stop"), just exit with the error, which will
            -- abort the update
            return false, "etfs.lua: ERROR: qkcp failed "
        end              

        if qkcpStatus["percent"] == prevPercent then
           progressCounter = progressCounter + 1
           if progressCounter > progressTimeout then
              return false, string.format("etfs.lua: ERROR: no qkcp progress from %d%% after %d seconds", prevPercent, progressCounter)
           end
        else 
           prevPercent = qkcpStatus["percent"]
           progressCounter = 0
        end
        
        if qkcpStatus.phase.value == 3 then            
            printLog("qkcp done")
            break
        end
        
        progress(unit, qkcpStatus["percent"])   
    end
    
    cmd = "rm /tmp/"..qkcp_progress
    os.execute(cmd) 
    
    -- call postInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "post")
    if not ok then 
        return false, "post installer failure"
    end     
    
    ok, err =  helper.executeETFS(mountpath, unit, "stop")
    if not ok then 
        printLog(err)
        return false, err
    end      
    
    return true  
 end

---------------------------------------------------------------
-- install function
-- Will be called by softwareUpdater
--------------------------------------------------------------- 
function install(unit, progress, mountpath) 
    local ok ,err
    
    ok, err = qkcp_etfs(unit, progress, mountpath, "start")
    if ok then 
        return true   
    else 
        -- check if qkcp error is device full error, then reformat ETFS and try again
        if (g_qkcp_error_code and g_qkcp_error_code == 7) then 
            g_qkcp_error_code = nil
            printLog(" ETFS installer error, reformatting and trying again")
            ok, err = qkcp_etfs(unit, progress, mountpath, "format")   
            if ok then 
                return true
            end     
        end
    end
        
    return false, err   
end
