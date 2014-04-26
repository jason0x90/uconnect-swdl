-- mmc files installer
 
module("cleanup",package.seeall) 

local helper = require "installerhelper"
local loadfile = loadfile
local printLog   = helper.printLog

---------------------------------------------------------------
-- install function
--  Will be called by softwareUpdater
--------------------------------------------------------------- 
function install(unit, progress, mountpath) 
    local ok , err
    local etfs_file = mountpath.."/"..unit.files_to_remove    
    local files_to_remove
 
    local chunk, error = loadfile(etfs_file)
    if not chunk then
        printLog("error loading etfs_file:", error)
        return false, error
    end 
    
    ok, files_to_remove = pcall(chunk)
    if not ok then
        printLog("error opening files_to_remove:", files_to_remove)
        return false, files_to_remove
    end
    
    if (type(files_to_remove) ~= "table") then 
        printLog("Files to remove manifest not found")
        return false, "files to remove manifest not found"
    end

    ok, err = helper.executeETFS(mountpath, unit, "start")
    if not ok then 
        printLog(err)
        return false, err
    end      
    
    progress(unit, 1)
    for index,file_name in ipairs(files_to_remove) do        
        printLog(string.format("Removing %s", file_name))
        local cmd = "rm -rf "..file_name.." > /dev/null 2>&1 "    
        os.execute(cmd)
        local percentage = (index) * 100 / #files_to_remove   
        progress(unit, percentage)
    end
    
    ok, err = helper.executeETFS(mountpath, unit, "stop")
    if not ok then 
        printLog(err)
        return false, err
    end   
    
    progress(unit, 100)
    return true 
    
end
