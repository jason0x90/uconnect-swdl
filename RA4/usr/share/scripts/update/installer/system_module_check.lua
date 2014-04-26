-- System module check installer



module("system_module_check",package.seeall)

local onoff         = require "onoff"
local helper        = require "installerhelper"
local lfs           = require "lfs"
local string        = require "string"
local os            = os


local printLog      = helper.printLog

-- error code 
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE 
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL

--------------------------------------------------------------------------------
-- install  
--  
--------------------------------------------------------------------------------
function install(unit,progress, mountpath)
    local env_value = nil
    local translated_env_val = nil
    local percent = 1
    local authenticated = false;
  
    if (unit == nil) then 
        printLog("No Unit specified, system_module_check")
        return false
    end 
    
    progress(unit, percent)
    
    -- First, check the MARKET    
    if (unit.market_env_name == nil) or (unit.market_env_name == "") or
       (unit.variant_market == nil) or (unit.variant_market == "") then 
        return false
    end    

    env_value = os.getenv(unit.market_env_name)       
    if (env_value == nil) or (env_value == "") then
        local err = string.format("system_module_check, Unable to find environment variable %s\n", unit.market_env_name)
        printLog(err)        
        return false, err, STOP_SWDL_CLEAR_UPDATE
    else    
        -- Handle tranlation between VARIANT_MARKET environment variable and two-letter market designation in Product ID
        -- ECE -> EU
        -- ROW -> RW
        -- All others are pass through
        translated_env_value = string.upper(env_value)
        if (translated_env_value == "ECE") then
            translated_env_value = "EU"
        elseif (translated_env_value == "ROW") then
            translated_env_value = "RW"
        end
        local match = string.match(translated_env_value, string.upper(unit.variant_market))
        if (match == nil) or (match == "") then            
            local err_code = string.format(" System market mismatch, stick contains %s but target is %s", unit.variant_market, translated_env_value)
            printLog(err_code)
            return false, err_code, STOP_SWDL_CLEAR_UPDATE
        end
    end
    printLog(string.format(" System Market matches"))


    -- Then, check the PRODUCT
    if (unit.product_env_name == nil) or (unit.product_env_name == "") or
       (unit.variant_product == nil) or (unit.variant_product == "") then 
        return false
    end    

    env_value = os.getenv(unit.product_env_name)       
    if (env_value == nil) or (env_value == "") then
        local err = string.format("system_module_check, Unable to find environment variable %s\n", unit.product_env_name)
        printLog(err)        
        return false, err, STOP_SWDL_CLEAR_UPDATE
    else
       local match = string.match(env_value, string.upper(unit.variant_product))    
        if (match == nil) or (match == "") then            
            local err_code = string.format(" System product mismatch, stick contains %s but target is %s", unit.variant_product, env_value)
            printLog(err_code)
            return false, err_code, STOP_SWDL_CLEAR_UPDATE
        end
    end
    printLog(string.format(" System Product matches"))


    -- Start full-ISO Authentication
    local cmd = ""
    local isoSigFile = "/tmp/isoSigHash"  -- this is the full signed-hash of the full-ISO
    local isoHashFile = "/tmp/isoHash"    -- this is where we'll have openssl put the verified hash
    local calcHashFile = "/tmp/calcHash"  -- this is where we'll store our own generated hash
    local iso_path = string.format("%s/swdl.iso", os.getenv("USB_STICK") or "/fs/usb0")

    -- Step 1: Extract the FULL-ISO signed-hash from the iso (skipping past the digest signature)
    cmd = "inject -e -i "..iso_path.." -f "..isoSigFile.." -o 64 -s 64"
    print(cmd)
    os.execute(cmd)

    -- Step 2: Now extract the original hash from this signature (adapted from loader.lua) 
    --        (using each public key found in the keysdir, until the first success)
    local keysdir = "/etc/keys"
    local key_file = ""
    local flag = 0
    if ((lfs.attributes(keysdir)) == nil) then 
        return false, "Authentication key directory could not be found", STOP_SWDL_CLEAR_UPDATE 
    end
    for file in lfs.dir(keysdir) do
        if (flag == 1) then 
            break
        end    
        if file ~= "." and file ~= ".." then
            local key_file = keysdir..'/'..file          
            local attr = lfs.attributes (key_file)
            assert (type(attr) == "table")
            if attr.mode == "directory" then
                print(" directory "..key_file.." not expected at "..keysdir)
                return false, "Unable to find authentication keys", STOP_SWDL_CLEAR_UPDATE           
            else
                -- authenticate iso
                print("key_file "..key_file)
                cmd = string.format("openssl rsautl -verify -inkey %s -in %s -pubin -out %s >/dev/null 2>/dev/null; echo $?;", 
                                    key_file, isoSigFile, isoHashFile) 
                print(cmd)
                local f = assert (io.popen (cmd, "r"))  
                for line in f:lines() do
                    print(line)
                    if (string.match(line,"^%s*%d") ~= nil) then
                       local result = tonumber(line)
                       if (result == 0) then  -- openssl returns status 0 upon success
                          flag = 1
                          break
                       end
                    end
                end 
                f:close()
            end
        end
    end     
    if (flag ~= 1) then
        return false, "Failed to authenticate ISO signature", STOP_SWDL_CLEAR_UPDATE
    end
    
    -- Step 3: Calculate our own FULL-ISO hash w/hashFile utility (skips first 32 KB; and provides progress output)
    cmd = "hashFile "..unit.iso_full_hash_type.." "..iso_path.." "..calcHashFile.." 32768"
    print(cmd)
    local f, error = io.popen (cmd, "r")
    if (f == nil) or (error ~= nil) then
       print(string.format("ERROR: could not execute cmd:[%s], error:[%s]", cmd, error))
       return false, "ISO Authentication utility could not be run", STOP_SWDL_CLEAR_UPDATE
    end
    for line in f:lines() do
        --print(line)
        if (string.match(line,"^%s*%d") ~= nil) then
            local pcnt = tonumber(line)
            if (pcnt and pcnt ~= 0) then
                percent = pcnt
                progress(unit, percent)
            end
        end
        -- if case of error
        if ( string.match(string.upper(line), "^%s*ERROR" ) ~= nil) then
            printLog(line,"\nISO Authentication error")
            return false, "ISO Authentication error", STOP_SWDL_CLEAR_UPDATE
        end
    end
    f:close()
   
    -- Step 4: Compare the ISO-verified and calculated hashes; if the same, then PASS, otherwise fail
    cmd = "cmp -s "..isoHashFile.." "..calcHashFile.." ; echo $?;"
    print(cmd)
    local f, error = io.popen (cmd, "r")
    if (f == nil) or (error ~= nil) then
        print(string.format("ERROR: could not execute cmd:[%s], error:[%s]", cmd, error))
        return false, "ISO Authentication cmp could not be run", STOP_SWDL_CLEAR_UPDATE
    end
    for line in f:lines() do
        --print(line)
        if (string.match(line,"^%s*%d") ~= nil) then
            local result = tonumber(line)
            if (result ~= 0) then
                return false, "ISO Authentication failed", STOP_SWDL_CLEAR_UPDATE
            end
        end
    end
    f:close()
   
    progress(unit, 100)
    
    return true
end
