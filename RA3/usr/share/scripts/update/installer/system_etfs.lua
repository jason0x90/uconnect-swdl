-- system_etfs files installer
 
module("system_etfs",package.seeall) 

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
local function qkcp_etfs(unit, progress, mountpath, startOperation)
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
 
    if ( startOperation ~= nil) then
        ok, err =  helper.executeETFS(mountpath, unit, startOperation)
        if not ok then 
            printLog(err)
            return false, err
        end
    end      

    -- Create the file in shared memory to read qkcp progress
    cmd = "touch /tmp/"..qkcp_progress  
    os.execute(cmd)     

    --
    -- override dest dir, if indicated in the unit
    --
    if ( unit.dst_dir ~= nil) then
        dst_dir = unit.dst_dir
    end

    printLog( string.format( "Getting ready to install "..src_dir.." from "..dst_dir))

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
        
        -- if failure then set the error code
        if (string.find(qkcpStatus.status.string,"failure") ~= nil) then 
            printLog("qkcp failed")            
            g_qkcp_error_code = qkcpStatus.status.value
            break
        end          

        if qkcpStatus.phase.value == 3 then            
            printLog("qkcp done")
            break
        end
        
        progress(unit, qkcpStatus["percent"])   
    end
    
    cmd = "rm /tmp/"..qkcp_progress
    os.execute(cmd) 
    
    -- if error then , stop etfs driver and send the error code
    if g_qkcp_error_code then 
        ok, err =  helper.executeETFS(mountpath, unit, "stop")
        if not ok then 
            printLog(err)
            return false, err
        end 
        return false, qkcpStatus["status"]["string"]
    end
    
    
    -- call postInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "post")
    if not ok then 
        return false, "post installer failure"
    end     
    
    if ( startOperation) then
        ok, err =  helper.executeETFS(mountpath, unit, "stop")
        if not ok then 
            printLog(err)
            return false, err
        end
    end      
    
    return true  
end





---------------------------------------------------------------
-- get_etfs_status  
---------------------------------------------------------------
local function get_etfs_status( pathToShmemFile )
    local etfsStatus = {}
    local cmd
    
    print("read status")
    cmd = "cp "..pathToShmemFile.." /tmp/temp_file"
    os.execute(cmd)
    pathToShmemFile = "/tmp/temp_file" 
    
    local f = io.open(pathToShmemFile, "rb")
    if not f then 
        etfsStatus["error"] = string.format( "Unable to open file:%s", pathToShmemFile )
        return etfsStatus
    end
    
    local strStruct = f:read("*all");
    if string.len(strStruct) < 16 then 
        etfsStatus["error"] = string.format( "Not enough bytes in %s:%d", pathToShmemFile, string.len(strStruct) )
        f:close()
        return etfsStatus 
    end

    local offset = 0
    etfsStatus["total"]        = convertUInt(strStruct, offset, 8)

    offset = offset + 8
    etfsStatus["current"]    = convertUInt(strStruct, offset, 8)

	if ( etfsStatus["total"] == 0) then
		etfsStatus["total"] = 100
		etfsStatus["current"] = 0
	end

    if ( etfsStatus["current"] > etfsStatus["total"]) then
        etfsStatus["error"] = string.format( "An error occurred transferring the secondary system image")
    end
    
    
    cmd = "rm "..pathToShmemFile
    os.execute(cmd)    
    
    f:close()
    return etfsStatus    
end




---------------------------------------------------------------
-- etfsctl_etfs
-- Function to etfsctl the etfs
--------------------------------------------------------------- 
local function etfsctl_etfs(unit, progress, mountpath, startOperation)
    local error_flag    = 0 
    local cmd
    local etfs_progress = "swdl_etfs_progress"
    local etfs_file       = mountpath.."/"..unit.data
    local dst_dir       = "/fs/etfs/"  
    local ok  = true
    local err  = nil
    local preInstaller  = nil
    local postInstaller = nil
 
    if ( startOperation ~= nil) then
        ok, err =  helper.executeETFS(mountpath, unit, startOperation)
        if not ok then 
            printLog(err)
            return false, err
        end
    end      

    progress( unit, 3)
    cmd = "touch /tmp/"..etfs_progress  
    os.execute(cmd)     
    
    --
    -- override dest dir, if indicated in the unit
    --
    if ( unit.dst_dir ~= nil) then
        dst_dir = unit.dst_dir
    end

    printLog( string.format( "Getting ready to install "..etfs_file.." to "..dst_dir))

    -- Run etfsctl...
    cmd = "etfsctl -h /"..etfs_progress.." -d /dev/etfs2 -S -e -w "..etfs_file.." -c &"
    os.execute(cmd)

    os.sleep( 2)

    -- read the progress notification
    while 1 do    
        etfsStatus = get_etfs_status( "/tmp/"..etfs_progress )        

        if etfsStatus["error"] ~= nil then
            printLog("Error fetching status")
            ok = false
            err = "Could not get etfs status"
            break
        end
        
        print( "" )
        print( string.format( "jobSize     = %d clusters", etfsStatus["total"] )) 
        print( string.format( "jobSizeDone = %d clusters", etfsStatus["current"] )) 

	    local percent = 3 + math.floor( ( 97 * etfsStatus["current"] )/ etfsStatus["total"])

		if ( percent > 100) then
			percent = 100
		end

        printLog ( string.format( "percent     = %d%%", percent )) 

        progress(unit, percent)

        -- sleep for 1 second so that we are not sending the progress notification 
        -- for very small progress
        os.sleep(1)   
        
        -- if failure then set the error code
        if ( etfsStatus["current"] > etfsStatus["total"]) then
            printLog("etfsctl failed")            
            ok = false
            err = "ETFS failed to transfer"
            break
        end          

        if ( ( etfsStatus["current"] == etfsStatus["total"] )
           and (etfsStatus["total"] > 0)) then
            printLog("etfsctl done")
            break
        end
    end
    
    cmd = "rm /tmp/"..etfs_progress
    os.execute(cmd) 
    
    progress( unit, 100)

    if ok then
        -- call postInstaller, if specified
        ok, err = helper.callPrePostInstaller(unit, mountpath, "post")
        if not ok then 
            return false, "post installer failure"
        end     
    
        if ( startOperation) then
            ok, err =  helper.executeETFS(mountpath, unit, "stop")
        end      
    end

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
    local do_erase

    --
    -- default to true for erase, if not
    -- given in the unit definition in the manifest
    --
    if ( unit.erase ~= nil) then
        do_erase = unit.erase
    else
        do_erase = true
    end
    
    progress( unit, 0)

    ok, err = helper.executeETFS(mountpath, unit, "start")
    if ok then 
        -- call preInstaller - we don't care about the result
        helper.callPrePostInstaller(unit, mountpath, "pre")
    else
        --
        -- if we failed to even mount the etfs, then go ahead
        -- and erase
        --
        do_erase = true
    end      

    progress( unit, 1)
    helper.executeETFS(mountpath, unit, "stop")
    progress( unit, 2)
   
    if ( do_erase) then
        ok, err = etfsctl_etfs(unit, progress, mountpath, "erase")
    else
        ok, err = etfsctl_etfs(unit, progress, mountpath, "start")
    end
    if ok then 
        return true
    end
        
    return false, err   
end
