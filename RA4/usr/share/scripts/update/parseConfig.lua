-- script to copy files to a stating area (e.g. for etfs or mmc file systems)
-- this must be run from the client root, e.g.
--    lua tcfg\omap\tools\copyfiles.lua tcfg\omap\images\etfs tcfg\omap\etfs\files.txt -vv
-- -v option to print as we go

-- currently quite slow due to using os.execute("cp"...) for every file

----------------------------------------------------------------------
-- parse arguments


module("parseConfig",package.seeall) 

local helper            = require "installerhelper" 
local printLog          = helper.printLog 

local function default_action( line)
    print( "No action defined - "..line.." cannot be handled")
    return false, nil
end

local g_current_post    = nil
local g_current_action  = default_action

local g_action_state    = {}

local g_first_backup = true

local g_dst_dir = nil

----------------------------------------------------------------------
-- create directories and files
----------------------------------------------------------------------
local function performCreate(line)
    local cmd
    if (string.find(line,"/$") ~= nil) then 
        cmd = "mkdir -p "..line.."  > /dev/null 2>&1 "
    else
        cmd = "touch "..line.."  > /dev/null 2>&1"
    end    
    if os.execute(cmd) then
        printLog(string.format("Creating %s", line))
    else        
        return false, "failed to create files"
    end     
    return true
end

----------------------------------------------------------------------
-- remove directories and files
----------------------------------------------------------------------
local function performRemove(line)
    local cmd    
    cmd = "rm -rf "..line
    os.execute(cmd)
    return true
end


----------------------------------------------------------------------
-- create copies of directories and files
-- 
-- This does not create the destination directory, or check whether
-- it is a directory or file. You must make sure the proper
-- structure exists first. Do a Create if you need to.
--
----------------------------------------------------------------------
local function performCopy(line)    
    local src,dst
    src, dst = line:match("^%s*(.+)%s*,%s*(.+)%s*")
    if ((src == nil) or (dst == nil)) then 
        printLog("badly formatted file for links")
        return false, "badly formatted file"
    end    

    --
    -- Always do a -r, in case it's a directory. This won't hurt individual
    -- files and lets us do things like src == "/blah/blah/*"
    --
    cmd = "cp -r "..src.." "..dst.." >/dev/null 2>&1"

    printLog(string.format("Copying src %s to dst %s",src, dst))

    if not os.execute(cmd) then
        return false, string.format( "Failed to copy file or directory from %s to %s", src, dst)
    end 

    return true
end

----------------------------------------------------------------------
-- create links
----------------------------------------------------------------------
local function performLink(line)    
    local src,dst
    src, dst = line:match("^%s*(.+)%s*,%s*(.+)%s*")
    if ((src == nil) or (dst == nil)) then 
        printLog("badly formatted file for links")
        return false, "badly formatted file"
    end    
     
    printLog(string.format("source = %s destination = %s",src, dst))    
    cmd = "ln -sf "..src.." "..dst     
    if os.execute(cmd) then
        printLog(string.format("Creating link src %s dst %s",src, dst))
    else        
        return false, "failed to create links"
    end 
    return true
end

----------------------------------------------------------------------
-- chmod directories and files
----------------------------------------------------------------------
local function performChmod(line)    
    local perms,dst
    perms, dst = line:match("^%s*(.+)%s*,%s*(.+)%s*")
    if ((perms == nil) or (dst == nil)) then 
        printLog("badly formatted file for chmod")
        return false, "badly formatted file"
    end    
     
    printLog(string.format("perms = %s, destination = %s",perms, dst))    
    cmd = "chmod -R "..perms.." "..dst     
    if os.execute(cmd) then
        printLog(string.format("Chmod'ing to %s on %s",perms, dst))
    else        
        return false, "failed to chmod"
    end 
    return true
end

----------------------------------------------------------------------
-- backup directories and files
----------------------------------------------------------------------
local function performBackup(line)
    
    local cmd = "backup "..line

    if ( g_dst_dir ~= nil) then
       cmd = "cd "..g_dst_dir.."; "..cmd
    end
    
    if ( os.execute( cmd)) then
        print( "Backed up "..line)
    else
        return false, "Failed to backup "..line
    end

    return true
end

----------------------------------------------------------------------
-- restore directories and files
--
----------------------------------------------------------------------
local function performRestore( line)
    local cmd = "restore "..line

    if ( g_dst_dir ~= nil) then
       cmd = "cd "..g_dst_dir.."; "..cmd
    end

    os.execute( cmd)

    return true
end


local actionTable = 
{ 
    ["CREATE"]      = { nil, performCreate, nil },
    ["REMOVE"]      = { nil, performRemove, nil },
    ["COPY"]        = { nil, performCopy, nil },
    ["LINK"]        = { nil, performLink, nil },
    ["CHMOD"]       = { nil, performChmod, nil },
    ["BACKUP"]       = { nil, performBackup, nil },
    ["RESTORE"]       = { nil, performRestore, nil }
}

----------------------------------------------------------------------

-- remove comments and leading and trailing spaces
local function trim(s)
   local i,n = s:find("#")
   if i then s = s:sub(1,i-1) end
   return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end
 
local function performAction(line)
    if (g_current_action == nil) then 
        printLog("badly formatted file, no action specified")
        return false, "badly formatted file, no action specified"
    elseif (actionTable[g_current_action] ~= nil) then
        return(actionTable[g_current_action](line))    
    else
        printLog("action not supported "..g_current_action)
        return false, string.format("action not supported %s",g_current_action)
    end
end

-- process one line from the input file, if new action then 
-- modify current_action
local function doline(line)
    local status = true
    local err = nil
    new_action = line:match("%[(.+)%]")

    if (new_action ~= nil) then
        if ( g_current_post ~= nil) then

           status, err = g_current_post()
           if ( status == false) then
               print( "Could not execute post")
               return status, err
           end

           g_current_post = nil
        end

        g_current_action = default_action
        print( "new action = "..new_action)   

        new_action = string.upper( new_action)

        if ( actionTable[new_action] ~= nil) then
           local action = actionTable[new_action]
           g_current_action = action[2]
           g_current_post = action[3]

           if ( action[1] ~= nil) then
               action[1]()
           end
   else
           print( "Action "..new_action.." is not supported")
           g_current_action =
               function( line)
                   print( "Line "..line.." cannot be handled")
                   return false, nil
               end
        end
   else
        if ( g_current_action ~= nil) then
           status, err = g_current_action( line)
        end
   end
   return status, err
end

----------------------------------------------------------------------
--  parse config file and perfrom actions specified
----------------------------------------------------------------------
function parse_and_perform(config_file, dst_dir)

    g_dst_dir = dst_dir

    if config_file == nil then
        printLog("Invalid arguments for parse_and_perform")
        return false, "Invalid arguments for parse_and_perform"
    end

    local input = io.open(config_file, "r")
    if input == nil then 
        printLog("Unable to open config file")
        return false, "Unable to open config file"
    end    
    
    for line in input:lines() do
        local s = trim(line)
        if s == "EOF" then 
            break 
        end
        if s:len() > 0 then 
            local status,err = doline(s)
            if (status == false) then        
                return false, err
            end            
        end
    end
    
    if ( g_current_post ~= nil) then
       status, err = g_current_post()
       if ( status == false) then
           return false, err
       end
    end
    
    return true
end         







