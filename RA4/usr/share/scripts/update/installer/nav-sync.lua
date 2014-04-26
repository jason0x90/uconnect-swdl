-- nav-sync files installer

module("nav-sync",package.seeall)

local helper        = require "installerhelper"
local lfs           = require "lfs"
local bit           = require "bit"
local naviSyncTools = require "naviSyncTools"
local dumper        = require "dumper"

local path = nil
local service = require "service"
local navSyncBusName = "com.harman.service.NavigationUpdate"

local printLog   = helper.printLog

local g_VariantPath

local g_product_type = "/etc/product_type"

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
function get_qkcp_status( pathToShmemFile )
    local qkcpStatus = {}

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


    return qkcpStatus

end


function executeMMC(unit, operation)

    local cmd = path.."/"..unit.mmc_start_script.." "..operation
    printLog(cmd)

    local ret_code = os.execute(cmd)/256

    -- Check for the return code
    if (ret_code ~= 0) then
        printLog(" Unable to"..operation.." mmc driver successfully")
        printLog(" ret_code "..ret_code)
        return false, "Unable to"..operation.."  mmc driver successfully"
    end

    return true
end

function parseCopyList( nngCopyList )

   local copyList = {}

   printLog( "Files to Add from SyncTool:")   

   for i,v in ipairs( nngCopyList ) do 
   
      local copyItem = {}

      for type, path in string.gmatch( v, "<([PATHMD5]+)>([^<]+)<[*]>" ) do
         if type == "PATH" then
            if not copyItem.fromPath then
               copyItem.fromPath = path
            elseif not copyItem.toPath then
               copyItem.toPath = path
            else
               print ( "Unknown format: third path variable in a copy line" )
            end
         elseif type == "MD5" then
            if not copyItem.md5 then
               copyItem.md5 = path
            end
         else
            print ( string.format( "Unknown operator: %s" ) )
         end
      end

      if copyItem.fromPath then
         copyItem.fileSize = lfs.attributes( copyItem.fromPath, "size" )
         printLog( string.format( "%10d %s", copyItem.fileSize, copyItem.fromPath ) )
      end
   
      if( copyItem.fromPath and copyItem.toPath and copyItem.fileSize ) then
         copyItem.fromPath = "\"" .. copyItem.fromPath .. "\""
         copyItem.toPath   = "\"" .. copyItem.toPath   .. "\""
         table.insert( copyList, copyItem )
      end
   end

   return copyList

end

---------------------------------------------------------------
-- parseRemoveList
--    Takes a NNG-provided remove list and parses into a more
--    lua-friendly list
---------------------------------------------------------------
function parseRemoveList( nngRemoveList )
   local removeList = {}
   
   printLog( "Files to Remove from SyncTool:")

   for i,v in ipairs( nngRemoveList ) do 
   
      local removeItem = {}
   
      for type, path in string.gmatch( v, "<([PATHMD5]+)>([^<]+)<[*]>" ) do
         if type == "PATH" then
            if not removeItem.path then
               removeItem.path = path
            else
               print ( "Unknown format: extra path variable in a delete line" )
            end
         else
            print ( string.format( "Unknown operator: %s" ) )
         end
      end
   
      printLog( removeItem.path )

      table.insert( removeList, removeItem )
   end

   return removeList

end

---------------------------------------------------------------
-- requestCheckForUpdate
--    Requests list of files to add/remove from NaviSyncTool
---------------------------------------------------------------
function requestCheckForUpdate( usbPath )

   local result = {}

   local resp, err = service.invoke(navSyncBusName, 'UPD_RequestCheckForUpdate', {updatePath=string.format("<PATH>%s<*>", usbPath)}, 600000 )
   print ( err )

   if resp.result then
      print ("resp.result = " .. resp.result )
   else
      printLog( "No result in response.  Treat as failure" )
      return nil, "Failure communicating with nav-sync"
   end
   
   if resp.update then
      print ("resp.update = " .. resp.update )
   end
   
   -- Make sure we got a response back
   if not resp then
      printLog( "Likely there is no dbus service running\n" )   
      return nil, "No response from UPD_RequestCheckForUpdate"
   end

   if resp.result ~= 0 then
      if bit.band( resp.result, 1 ) then
         printLog( "Invalid navigation package" )
         return nil, "Invalid package"
      end
   
      if bit.band( resp.result, 2 ) then
         printLog( "Activation required" )
         return nil, "Activation required"
      end

      if bit.band( resp.result, 4 ) then
         printLog( "Not enough space" )
         return nil, "Not enough space"
      end

      if bit.band( resp.result, 8 ) then
         printLog( "Older package" )
         return nil, "Older package"
      end

      return nil, "Unknown error"
   end

   if resp.update ~= 1 then
      return nil, "Invalid path"
   end

   result.copyList = {}
   if resp and resp.itemsToCopy then
      result.copyList = parseCopyList( resp.itemsToCopy )
   end

   if not result.copyList then
      return nil, "Unable to parse NNG-provided copy list"
   end

   result.removeList = {}
   if resp and resp.itemsToRemove then
      result.removeList  = parseRemoveList( resp.itemsToRemove )
   end

   if not result.removeList then
      return nil, "Unable to parse NNG-provided remove list"
   end

   return result

end

function getMD5ForFile( fileName )
   cmd = "openssl dgst -md5 " .. fileName
   print(cmd)
   
   f = assert (io.popen (cmd, "r"))  
   
   local start, stop, md5
   for line in f:lines() do
      print (line)
      local start, stop, md5 = string.find(line, "^MD5%([^)]+%)= ([0-9a-f]+)$")
      if md5 then
         return md5
      else
         printLog("Failure getting md5 for file " .. fileName )
         return nil, "Failure getting md5 of file " .. fileName
      end
   end

   return md5

end

---------------------------------------------------------------
-- Copy Files function
--    This routine verifies that all files to copy over pass
--    an MD5 check
---------------------------------------------------------------
function md5Check( unit, progress, phase, md5FileList )

   reportProgress( unit, progress, phase, 0 )

   -- figure out how many bytes need to be md5'd
   local totalSizeOfFiles = 0
   for i,v in ipairs( md5FileList ) do
      if v.md5 then
         totalSizeOfFiles = totalSizeOfFiles + v.fileSize
      end
   end

   -- Copy the files over
   local totalBytesMD5d = 0
   for i,v in ipairs( md5FileList ) do

      local fileToCheck = ( phase == "premd5" and v.fromPath or v.toPath )

      if fileToCheck and v.md5 then
         -- verify that the md5 passes for this file
         local md5, errorMsg = getMD5ForFile( fileToCheck )
         if not md5 then
            printLog( errorMsg )
            return false, errorMsg
         end
       
         if string.upper( md5 ) ~= v.md5 then
            printLog( phase .. " File " .. fileToCheck .. " has MD5 " .. md5 .. " but is supposed to have " .. v.md5 )
            return false, "MD5 " .. phase .. " failure"
         end

         totalBytesMD5d = totalBytesMD5d + v.fileSize
         reportProgress( unit, progress, phase, 100 * totalBytesMD5d / totalSizeOfFiles )
         printLog( "MD5 for file " .. fileToCheck .. " passed" )
      end
   end -- for loop

   reportProgress( unit, progress, phase, 100 )

   return true

end

---------------------------------------------------------------
-- Copy Files function
--    This routine takes a list of files to copy and 
--    qkcp's the files
---------------------------------------------------------------
function copyNavFileList( unit, progress, copyFileList )

   local error_flag = 0
   local qkcp_progress = "swdl_"..unit.installer.."_progress"

   reportProgress( unit, progress, "copy", 0 )

   -- Create the file in shared memory to read qkcp progress
    cmd = "touch /tmp/"..qkcp_progress  
    os.execute(cmd)  

   -- figure out how many bytes need to be copied over
   totalSizeOfFiles = 0
   for i,v in ipairs( copyFileList ) do
      totalSizeOfFiles = totalSizeOfFiles + v.fileSize
   end

   -- Copy the files over
   local totalBytesCopied = 0
   for i,v in ipairs( copyFileList ) do
      local toDir = string.sub( v.toPath, 1, string.find(v.toPath, "[^/]+$" ) - 1 ) .. "\""
      
      cmd = "qkcp -h "..qkcp_progress.." " .. v.fromPath .. " " .. toDir .. " &"
      printLog(cmd)
      os.execute(cmd)

      -- read the progress notification
      while 1 do
         qkcpStatus = get_qkcp_status( "/tmp/"..qkcp_progress )
         if (qkcpStatus[ "error" ]) then
              printLog( string.format( "qkcpStatus error = %s", qkcpStatus[ "error" ] ) )

              printLog( "qkcp error - attempting to use CP to copy file" )
              local cmd = "cp -Mqnx -R -f "..v.fromPath.." "..toDir
              print (cmd)
              local f = assert (io.popen (cmd..' 2>&1; echo "-retcode:$?"', 'r'))
              local l = f:read'*a'
              f:close()

              local i1,i2,ret = l:find('%-retcode:(%d+)\n$')

              -- in case of error 
              if ( ret == '1' ) then  
                  printLog(" Error when copying file")
                  error_flag = 1
              end  
              break
         end
         printLog ( string.format( "%s: percent:%d%% phase:%d:%s status:%d:%s",
               v.fromPath,
               qkcpStatus["percent"],
               qkcpStatus["phase"]["value"], qkcpStatus["phase"]["string"],
               qkcpStatus["status"]["value"], qkcpStatus["status"]["string"] ))

         -- Identify failure to copy
         if ( string.find(string.upper(qkcpStatus.status.string), "FAILURE" ) ~= nil) then
            printLog( string.format( "qkcp failed: %s: %d:%s", v.fromPath, qkcpStatus["status"]["value"], qkcpStatus["status"]["string"]  ) )
            error_flag = 1
            break
         end

         printLog(string.format("qkcp: filesize %d",v.fileSize))
         -- Identify file completion and skip to next file
         -- qkcp neverupdates shared memory if filesize is 0 
         -- qkcp completes, but status in shared memory is never updated.  
         -- This is a special case in qkcp - therefore check if filesize is 0 - then exit
         if (qkcpStatus.phase.value == 3 or v.fileSize == 0) then
             if (v.fileSize == 0) then
                 printLog( string.format( "Filesize of %s is 0", v.fromPath ) )
             end 

            printLog(string.format( "qkcp done: %s", v.fromPath ) )
            break
         end

         -- Calculate the mid-file copy progress
         local percentDone = ( ( totalBytesCopied + ( v.fileSize * qkcpStatus["percent"] / 100 ) ) / totalSizeOfFiles ) * 100
         percentDone = math.floor(percentDone)
         reportProgress( unit, progress, "copy", percentDone )

         -- Wait 1 second for qkcp to do some work         
         os.sleep(1)

         
      end

      if error_flag == 1 then
         printLog("Error Detected in qkcp: breaking out of copy loop")
         break
      end

      -- calculate the between file copy progress
      totalBytesCopied = totalBytesCopied + v.fileSize
      reportProgress( unit, progress, "copy", math.floor( totalBytesCopied * 100 / totalSizeOfFiles ) )
      
   end

   os.execute("rm /tmp/"..qkcp_progress)

   return error_flag
   
end

---------------------------------------------------------------
-- Remove Files function
--    Takes a list of files to remove and removes them
---------------------------------------------------------------
function removeNavFileList( unit, progress, removeFileList )

   -- Report the beginning of this phase
   reportProgress( unit, progress, "remove", 0 )
   
   local numDeleted = 0
   for i,v in ipairs( removeFileList ) do
      printLog( "Removing file " .. v.path )
      os.execute("rm " .. v.path)
      numDeleted = numDeleted + 1
      reportProgress( unit, progress, "remove", numDeleted * 100 / #removeFileList )
   end
   reportProgress( unit, progress, "remove", 100 )
end

---------------------------------------------------------------
-- reportProgress
--    Helper function that allows for different phases of the
--    startup/premd5/copy/remove/postmd5/shutdown to take different amounts
--    of time
---------------------------------------------------------------
function reportProgress( unit, progress, phase, percent )

   local scaledPercent = 0
   local Scale = { startup=5, premd5=90, copy=100, remove=5, postmd5=50, shutdown=5 }
   Scale.premd5  = unit.run_pre_md5  and Scale.premd5  or 0
   Scale.postmd5 = unit.run_post_md5 and Scale.postmd5 or 0

   if phase == "startup" then 
      scaledPercent = ( percent * Scale.startup  / 100 )
   elseif phase == "premd5" then 
      scaledPercent = ( percent * Scale.premd5   / 100 ) + Scale.startup
   elseif phase == "copy"  then
      scaledPercent = ( percent * Scale.copy     / 100 ) + Scale.startup + Scale.premd5
   elseif phase == "remove"  then
      scaledPercent = ( percent * Scale.remove   / 100 ) + Scale.startup + Scale.premd5 + Scale.copy
   elseif phase == "postmd5"  then
      scaledPercent = ( percent * Scale.postmd5  / 100 ) + Scale.startup + Scale.premd5 + Scale.copy + Scale.remove
   elseif phase == "shutdown"  then
      scaledPercent = ( percent * Scale.shutdown / 100 ) + Scale.startup + Scale.premd5 + Scale.copy + Scale.remove + Scale.postmd5
   else
      printLog( "Unknown phase " .. phase )    
   end
   
   local totalScalePoints = Scale.startup + Scale.premd5 + Scale.copy + Scale.remove + Scale.postmd5 + Scale.shutdown
   progress( unit, math.floor( 100 * scaledPercent / totalScalePoints ) )

end

NavProductIdFile = "/dev/mmap/productid"
---------------------------------------------------------------
-- getNavProductID - returns the first 16 bytes of the productid
---------------------------------------------------------------
function getNavProductID()
 
   local nav_productid
   local device = require "device"
   local fd = device.open(NavProductIdFile, "r")

   if fd then
      nav_productid = fd:read(16)
      fd:close()
   else
      io.output(stdout):write("Unable to get Nav Product ID\n")
      nav_productid = nil, "ERROR: got "..nav_productid
   end

   return nav_productid
end

local function getVariantDir(dir)
   -- Determine which variant to try
   productType = getNavProductID()
   if not productType then
      return nil, "Unknown variant " .. productType
   end

   local variantPath = dir .. "/nav/" .. string.sub(productType,1,6) .. "/"
   if lfs.attributes(variantPath,"mode") == "directory" then
      return variantPath
   else
      
      return nil, "Path " .. variantPath .. " does not exist"
   end

end

---------------------------------------------------------------
-- install function
--  Will be called by softwareUpdater
---------------------------------------------------------------
function install(unit, progress, mountpath)

   printLog( "Starting nav-sync install" )

   local error_flag = 0
   local cmd

   path = mountpath
   local src_dir = "/fs/usb0"
   local dst_dir = unit.dst_dir

   printLog(" src dir "..src_dir)
   printLog(" dst_dir "..dst_dir)

   printLog( "mkdir " .. dst_dir )    
   lfs.mkdir( dst_dir )

   
   -- Start service monitor
   local rval = os.execute("/usr/bin/service-monitor &")
   if rval ~= 0 then
      printLog("nav-sync.lua:  Unable to start service monitor")
      return false, "nav-sync.lua:  Unable to start service monitor"
   end
   
   -- Start authentication service
   rval = os.execute("authenticationService -k /etc/system/config/authenticationServiceKeyFile.json &")
   if rval ~= 0 then
      printLog("nav-sync.lua:  Unable to start authentication service")
      return false, "nav-sync.lua:  Unable to start authentication service"
   end

   -- Wait for authentication service to appear on DBUS
   rval = os.execute("waitfor /dev/serv-mon/com.harman.service.authenticationService")
   if rval ~= 0 then
      printLog("nav-sync.lua:  Unable to detect authentication service")
      return false, "nav-sync.lua:  Unable to detect authentication service"
   end
   
   reportProgress( unit, progress, "startup", 10 )

   -- Check if source directory exists
   if lfs.attributes( src_dir, "mode" ) ~= "directory" then 
      printLog(string.format("%s source directory does not exists, exiting installer",src_dir))
      return false, "Unable to locate source directory " .. src_dir
   end

   reportProgress( unit, progress, "startup", 20 )
   printLog(" Start devb-mmcsd")
   local ok, err = executeMMC(unit, "start")

   if not ok then
      return false, err
   end
   printLog(" Started devb-mmcsd")

   reportProgress( unit, progress, "startup", 40 )
   printLog(" Start navi-sync")

   local ok, err = naviSyncTools.start( mountpath )

   if not ok then
      return false, err
   end
   printLog(" Started navi-sync")

   -- Wait a few seconds to give sync tool time to initialize
   os.sleep(3)

   g_VariantPath = getVariantDir(src_dir)
   if not g_VariantPath then
      return false, "Unable to determine variant"
   end

   reportProgress( unit, progress, "startup", 60 )
   local updateJob
   updateJob, err = requestCheckForUpdate( g_VariantPath .. "nng" )
   if not updateJob then
      printLog( "Null back from requestCheckForUpdate" )
      return false, err
   end

   -- Startup phase is complete!
   reportProgress( unit, progress, "startup", 100 )

   -- If a pre-test is requested in the manifest, let's do it!
   if unit.run_pre_md5 then
      ok, err = md5Check( unit, progress, "premd5", updateJob.copyList )
      if not ok then
         printLog( "Failed MD5 pre check" )
         return false, err
      end
   end

   -- Copy the files that are supposed to be copied
   printLog( "Adding files according to remove list" )
   error_flag = copyNavFileList( unit, progress, updateJob.copyList )
   
    -- TODO: Remove this, once qnx fat32 cache coherency is fixed, 
    -- umount and mounting file system is just a workarond that problem
    ok, err = executeMMC(unit, "umount")
    if not ok then
      printLog( "Problem unmounting mmc" )
      error_flag = 1
    end        
    ok, err = executeMMC(unit, "mount")
    if not ok then 
      printLog( "Problem mounting mmc" )
      error_flag = 1
    end       
   

   if error_flag == 0 then
      printLog( "Removing files according to remove list" )
      error_flag = removeNavFileList( unit, progress, updateJob.removeList )
   end

   -- If a post-test is requested in the manifest, let's do it!
   if unit.run_post_md5 then
      ok, err = md5Check( unit, progress, "postmd5", updateJob.copyList )
      if not ok then
         printLog( "Failed MD5 post check" )
         return false, err
      end
   end
   
   -- Stop NaviSyncTools
   printLog("Stopping NaviSyncTools")
   ok, err = naviSyncTools.stop()
   if not ok then
      printLog( "Failure stopping naviSyncTools" )
      error_flag = 1
   end

   -- Stop the MMC
   printLog("Stopping MMC")
   ok, err = executeMMC(unit, "stop")
   if not ok then
      printLog( "Failure stopping MMC" )
      error_flag = 1
   end

   -- if error the send the error
   if error_flag == 1 then
      printLog("Error flag is set")
      return false, qkcpStatus["status"]["string"]
   end

   return true

end
