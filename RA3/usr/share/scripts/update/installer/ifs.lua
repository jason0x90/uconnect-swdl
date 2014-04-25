-- ifs installer



module("ifs",package.seeall)


local string    = require "string"
local table     = require "table"
local math      = require "math"
local helper    = require "installerhelper"
local io        = io

local printLog                  = helper.printLog

local g_complete_percentage     = 0
local g_current_unit            = 0
local g_ipl_partition           = {}
local g_ifs_partition           = {}
local g_path                    = nil
 
---------------------------------------------------------------
-- callUpdate 
-- Function for calling update_nand_teb and send the progress 
-- notification  
---------------------------------------------------------------
local function callUpdate(unit, progress, partition, ipl)
    local cmd 
    local config_file   = g_path.."/"..unit.config_file
    local total_units   = #g_ipl_partition + #g_ifs_partition
    local percent
  
    print("callupdate")
    g_current_unit = g_current_unit + 1    
    
    -- construct the update_nand_teb command for IPL or IFS      
    if ipl == 1 then     
        local ipl_path = g_path.."/"..unit.ipl_data         
        cmd = "update_nand -i -f "..ipl_path.." -p"..partition.." -c "..config_file.." -q"
    else
        local ifs_path = g_path.."/"..unit.ifs_data 
        cmd = "update_nand -f "..ifs_path.." -p"..partition.." -c "..config_file.." -q"  
    end     
    print(cmd)     
    
    local f = assert (io.popen (cmd, "r"))  
    for line in f:lines() do
        if (string.match(line,"^%s*%d") ~= nil) then 
            percent = tonumber(line)            
            if (percent and percent ~= 0) then 
                g_complete_percentage = math.floor(((percent) * (1 /total_units)  +  ((g_current_unit -1 ) * 100 / total_units)))
                progress(unit, g_complete_percentage) 
            end   
        end             
        -- if case of error 
        if ( string.match(string.upper(line), "^%s*ERROR" ) ~= nil) then  
            if ipl == 1 then 	    
                printLog(" Error when updating IPL"..partition );
            else 
                printLog(" Error when updating IFS"..partition );
            end		
            printLog(line)	  
            return false
        end  
    end       
    f:close()   
    
    return true           
end        

---------------------------------------------------------------
-- adjustImageState 
-- Utility to set the fram bits
---------------------------------------------------------------      
local function adjustImageState(ipl, partition, state)
    local cmd = "adjustImageState"
    
    print("adjustImageState")

    if (ipl == 1) then     
        cmd = cmd.." -v 7 -i 0 -s "..state.." -n "..partition
    else
        cmd = cmd.." -v 7 -i 1 -s "..state.." -n "..partition  
    end
    print(cmd)
    local f = assert (io.popen (cmd, "r"))  
    
    for line in f:lines() do 
        print(line)  
        if ( string.find(line, "^ERROR" ) ~= nil) then    
            printLog("adjustImageState"..line)        
            return false
        end  
    end          
    f:close()
    
    return true
end         


---------------------------------------------------------------
-- install 
-- Function will be called by Updater 
--------------------------------------------------------------- 
function install(unit, progress, mountpath)    
  
    local etfs_start_script
    local max_partition
    local max_table
    local ok, err 
    local temp
    local status
   
    -- set the global path as mountpath
    g_path = mountpath
    print(mountpath)      
    
    -- start the etfs driver
    ok, err = helper.executeETFS(mountpath, unit, "start")
    if not ok then 
        printLog( "Coult not mount ETFS, trying to reformat it")
        ok, err = helper.executeETFS( mountpath, unit, "erase")
        
        if not ok then
        printLog(err)
        return false, err
    end      
    end      


    -- call preInstaller
    ok, err = helper.callPrePostInstaller(unit, mountpath, "pre")
    if not ok then 
        return false, "post installer failure"
    end  
   
    -- parse the config file, to build ipl and ifs partition 
    -- table, table will contain slot numbers for 
    -- ifs and ipl
    local config_file_path = mountpath.."/"..unit.config_file;   
    print("config_file"..config_file_path)
    
    local f = io.open ( config_file_path, "r")    
    if not f then 
        return false, "Unable to open config file"
    end	    
    for line in f:lines() do        
        temp = string.match(string.upper(line), "^%s*IPL(%d)")         
        if temp ~= nil then    
            table.insert(g_ipl_partition, temp)         
        end    
        temp = string.match(string.upper(line), "^%s*IFS(%d)") 
        if temp ~= nil then
            table.insert(g_ifs_partition, temp)    
        end  
    end 
    f:close()	   
 
    -- find which table is bigger 
    max_partition = math.max(#g_ipl_partition , #g_ifs_partition)
    print("max_partition "..max_partition)   
    if (max_partition == #g_ipl_partition) then 
        max_table = g_ipl_partition
    else
        max_table = g_ifs_partition    
    end
    
    -- loop through the bigger table, this 
    -- will make sure that if we have different numbers of 
    -- IPL and IFS, still we flash everything
    -- We will flash IFS first and then IPL both one at a time 
    -- this will ensure that even in  a power failure we will 
    -- have atleast a combination of IFS/IPL which will boot 
    for i,j in ipairs(max_table) do         
    
        print( " i "..i)                
        -- Only update if IFS partition exist
        if (i <= #g_ifs_partition) then
            printLog(string.format("Updating ifs partition %d",g_ifs_partition[i]))
            -- Check if IFS file exists, because it is possible that 
            -- usb is unplugged and the file is no more there
            -- In that case, we don't want to mark all IFS and IPL 
            -- invalid and make system unbootable
            local f = io.open (g_path.."/"..unit.ifs_data, "r")
            if not f then 
                printLog(" ERROR: Unable to open IFS data files")
                return false, " Unable to open IFS data files"
            end  
            f:close()                        
            -- update IFS
            status, err = callUpdate(unit, progress, g_ifs_partition[i], 0)
            if not status then 
                -- mark IFS invalid                
                adjustImageState(0, g_ifs_partition[i], 1)
                printLog(" Error encountered while updating IFS "..g_ifs_partition[i].." Continue with remaining update" )        
            else
                printLog("update ifs done "..i)
                -- mark IFS valid
                status = adjustImageState(0,g_ifs_partition[i], 0)                
                if not status then 
                    printLog("WARNING: Error encountered while updating state flag for IFS "..g_ifs_partition[i].." Continue with remaining update" )        
                    --[[
			  	    -- Until all the VP2 radios have been fixed with the dev-memory reload,
				    -- keep going even if we can't update the IFS status
                    ok, err = helper.executeETFS(mountpath, unit, "stop")
                    if not ok then 
                        printLog(err)
                        return false, err
                    end 
                    return status, "Unable to mark IFS flag in fram"                
				    --]]
                end          
            end               
        end
        
         -- Only update if IPL partition exist        
        if ( i <= #g_ipl_partition) then
            printLog(string.format("Updating IPL partition %d",g_ipl_partition[i]))
            -- Check if IPL file exists, becasue it is possible that it
            -- usb is unplugged and the file is no more there
            -- In that case, we don't want to mark all IFS and IPL 
            -- invalid and make system unbootable
            local f = io.open (g_path.."/"..unit.ipl_data, "r")
            if not f then 
                printLog(" ERROR: Unable to open IPL data files")
                return false, " Unable to open IPL data files"
            end  
            f:close()
            
            status, err = callUpdate(unit, progress, g_ipl_partition[i], 1) 
            if not status then 
                -- mark ipl invalid
                adjustImageState(1, g_ipl_partition[i], 1)
                printLog(" Error encountered while updating IPL "..g_ipl_partition[i].." Continue with remaining update")  
            else
                printLog("update ipl done "..i)
                status = adjustImageState(1, g_ipl_partition[i], 0)
                print(status)            
                if not status then 
                    printLog("WARNING: Error encountered while updating state flag for IPL "..g_ipl_partition[i].." Continue with remaining update" )        
                    --[[
			  	    -- Until all the VP2 radios have been fixed with the dev-memory reload,
				    -- keep going even if we can't update the IFS status
                    ok, err = helper.executeETFS(mountpath, unit, "stop")
                    if not ok then 
                        printLog(err)
                        return false, err
                    end
                    return status, "Unable to mark IPL flag in fram"                
				    --]]
                end
            end 
        end                                 
    
    end                 
     
    -- call postInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "post")
    if not ok then 
        return false, "post installer failure"
    end  
    
    
    ok, err = helper.executeETFS(mountpath, unit, "stop")
    if not ok then 
        printLog(err)
        return false, err
    end
    
    return true
end

