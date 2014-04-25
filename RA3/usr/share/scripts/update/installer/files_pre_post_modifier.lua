-- mmc files installer
 
module("files_pre_post_modifier",package.seeall) 

local helper = require "installerhelper"
local parse = require "parseConfig"
local printLog   = helper.printLog

---------------------------------------------------------------
-- install function fro pre-post installer, this will not send 
--  progress notification as the installer calling this will 
-- manage it by itself
--------------------------------------------------------------- 
function install(subunit, mountpath) 
    local files_to_modify
    
    -- if no arguments then this means an error
    if (subunit == nil or type(subunit) ~= "table" or (not next(subunit)) ) then 
        printLog( "inavlid table for files_pre_post_modifier installer")
        return false
    end
    
    if (subunit.files_to_modify == nil) then 
        printLog( "no arguments for files_pre_post installer")   
        return false
    end      

    local dst_dir = nil
    if ( subunit.dst_dir ~= nil) then
        dst_dir = subunit.dst_dir
    end

    if (subunit.script ~= nil) then
        printLog( "executing pre/post-install script "..subunit.script)
        cmd = "sh "..mountpath.."/"..subunit.script

        if ( dst_dir ~= nil) then
            cmd = "cd "..dst_dir.."; "..cmd
        end
        os.execute( cmd)
    end

    -- files to modify should be with the actual mountpath
    files_to_modify = mountpath.."/"..subunit.files_to_modify
    
    
    return(parse.parse_and_perform(files_to_modify, dst_dir))
    
end
