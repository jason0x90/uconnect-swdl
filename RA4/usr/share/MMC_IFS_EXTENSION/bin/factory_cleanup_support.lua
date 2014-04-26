#!/usr/bin/lua

local ipc = require "ipc"

-- --------------------------------------
-- trim
--
-- Return: Trimmed string
-- --------------------------------------
local function trim(s, c)
    if s == nil then
        return nil
    end
 
    if c == nil then
        c = "%s"
    end
    return s:gsub(string.format("^%s+", c), ""):gsub(string.format("%s+$",c), "")
end
 

-- --------------------------------------
-- split
--
-- Called to split a string based on some
-- regular expression string
--
-- Return: Array of values split accordingly
-- --------------------------------------
local function split(keyStr, delimiter)
    local result = { }
    local from  = 1
    local delim_from, delim_to = string.find( keyStr, delimiter, from  )
    while delim_from do
        table.insert( result, string.sub( keyStr, from , delim_from-1 ) )
        from  = delim_to + 1
        delim_from, delim_to = string.find( keyStr, delimiter, from  )
    end
    table.insert( result, string.sub( keyStr, from  ) )
    return result
end
 

-- --------------------------------------
-- get_pid
--
-- Called to get the PID for a running
-- task.  Can also be used to determine
-- if a PID is already running.
--
-- execStr...string to grep for in pidin
-- pidCheck..if nil, checks "pidin a"
--           otherwise only pid values
--           are checked
--
-- Return: pid (numeric), 0 on failure
-- --------------------------------------
local function get_pid( execStr, pidCheck )
    local pid = 0
    local f = io.popen(string.format("/bin/pidin %s | grep -v grep | grep \"%s\"",
                                     pidCheck==nil and "a" or "-F \"%a\"", tostring(execStr)))
    local query = f:read("*a") -- read output of command
    f:close()
 
    if query == nil or query == "" then
        return 0
    end
 
    query = trim(query)
    local cols = split(query," +")
 
    if cols ~= nil and cols[1] ~= nil then
        pid = cols[1]
    end
 
    return tonumber(pid)
end
 

-----------------------------------------------
-- slay_pid
--
-- Slay the parent process and all child processes
-- with the same parent.
--
-- pidToSlay....PID to slay
-- sigType  ....signal to send, if nil = SIGKILL
-----------------------------------------------
local function slay_pid( pidToSlay, sigType )

    local pidStr    = tostring(pidToSlay)
    local line      = ""
    local procTbl   = {}
    local cols      = {}
    local fp        = io.popen(string.format('/bin/pidin -f ae | grep -v grep | grep \"%s\"',
                               tostring(pidStr)))


    -- Build the table, so we can kill the main process first

    for line in fp:lines() do
        line = trim(line)
        cols = split(line," +")
        table.insert(procTbl, cols)
    end

    fp:close()

    -- Kill the main process first
    for i,v in ipairs(procTbl) do
        if v[1] == pidStr then
            os.execute( string.format("slay -Q -s %s %s",
                                      sigType or "SIGKILL",
                                      pidStr) )
        end
    end

    -- Kill any spawned processes next
    for i,v in ipairs(procTbl) do
        if v[2] == pidStr and v[1] then
            os.execute( string.format("slay -Q -s %s %s",
                                      sigType or "SIGKILL",
                                      v[1]) )
        end
    end
end


local function slayProcess( pidName, sigType )
   
    local maxRetry  = 20        -- count for waiting before giving up
    local sleepFor  = 0.1       -- 100 ms
    local pid       = get_pid( pidName )    

    if pid ~= nil and pid ~= 0 then 
        slay_pid( pid, sigType )        
        pid = get_pid( pid, 1 )
        while ((pid ~= 0) and (maxRetry > 0)) do
            os.sleep( sleepFor )
            pid = get_pid( pid, 1 )
            maxRetry = maxRetry - 1
        end
    end
    if pid ~= 0 then 
    	print("slayed failed  ", pidName)
    else
      print("slayed successfully  ", pidName)
    end  	
end

print("Replying to MFG over CAN that cleanup is ALMOST done (15 more seconds til you can pull power, 26 til auto reset)")
local x={}
x[1]=0x31
x[2]=0x01
x[3]=0xf0
x[4]=0x0c
x[5]=0x01
x[6]=0x00
p = assert(ipc.open(7))
p:write(x)

print("Clearing IOC EEPROM and all DTCs...")
os.execute("ioc_cleanup.sh")

slayProcess("dev-mmap", "SIGTERM")
slayProcess("dev-memory", "SIGTERM")
os.execute("dev-memory -r /dev/memory -d fram-i2c.so i2c_port=2, i2c_address=0x50 -v 1")
os.execute("dev-mmap -c /etc/system/config/fram.conf -r /dev/fram/ -d /dev/memory -v 1")
os.execute("waitfor /dev/mmap")

-- save FRAM info so first startup will be OK and clear FRAM (no second reset required)
-- fram_cleanup.sh skips ipl, productid, and partnumber, etc...
print("Clearing FRAM...")
os.execute("fram_cleanup.sh")

-- clear out all ETFS  (repaired by 'initialize_hu.lua')
print("Clearing ETFS...")
slayProcess("fs-etfs-omap3530_micron","SIGTERM")
os.execute("fs-etfs-omap3530_micron -c 1024 -D cfg -m/fs/etfs -f /etc/system/config/nand_partition.txt -e")
os.execute("waitfor /fs/etfs")

-- perform factory initialization on MMC0 and ETFS
print("Restoring default ETFS...")
os.execute("initialize_hu.lua")

-- This will force the cached data to be saved to dev-memory
slayProcess("dev-mmap", "SIGTERM")
slayProcess("dev-memory", "SIGTERM")

-- unmount file system partitions to flush caches
print("Unmounting file systems")
os.execute("umount -f /fs/etfs")
os.execute("umount -f /dev/mmc0t178")
os.execute("umount -f /dev/mmc0t177")
 
print("Safe to pull power")
 
-- reset if requested
if arg[1] ~= nil then
   local c={}
   print("Resetting unit as requested")
   c[1]=0x11
   p = assert(ipc.open(4))
   p:write(c)
end
