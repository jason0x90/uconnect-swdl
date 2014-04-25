
module("dumper", package.seeall)

require "json"

-----------------------------------------------
-- json_encode
--
-- Encode into a JSON string.  This can be 
-- the compact form or a readable form.
--
-- tbl    ....Lua table to encode
-- compact....nil or 0=readable, 1=compact
--
-- Return:   JSON formatted string of tbl
-----------------------------------------------
function json_encode( tbl, compact )

    local str = json.encode( tbl )

    if compact ~= nil and compact == 1 then
        return str
    end

    -- expand for readability
    -----------------------------
    local expStr    = ""
    local idx       = 1
    local indent    = 0
    local indentLen = 3
    local ch        = string.sub(str, idx, 1)
    local inStr     = false

    while idx <= string.len(str) do

        if ch == "\"" then
            if idx-1 > 0 and string.sub(str, idx-1, idx-1) ~= "\\" then
                -- Toggle this
                if inStr == true then
                    --expStr = expStr.."-" -- debug
                    inStr = false
                else
                    --expStr = expStr.."+" -- debug
                    inStr = true
                end
            end
        end

        if ch == ":" and inStr == false then

            expStr = expStr.." : "

        elseif ch == "," and inStr == false then

            expStr = expStr..",\n"..string.rep(" ", indent)

        elseif (ch == "{" or ch == "[") and inStr == false then

            if idx-1 > 0 then

                if string.sub(str, idx-1, idx-1) ~= ":" and 
                       string.sub(str, idx-1, idx-1) ~= "," then
                    expStr = expStr.."\n"..string.rep(" ", indent)
                end
            end

            expStr = expStr..ch.."\n"..string.rep(" ", indent+indentLen)
            indent = indent + indentLen

        elseif (ch == "}" or ch == "]") and inStr == false then

            if (indent - indentLen) >= 0 then
                indent = indent - indentLen
            else
                indent = 0
            end

            if string.sub(str, idx+1, idx+1) == "," then
                idx = idx + 1
                expStr = expStr.."\n"..string.rep(" ", indent)..ch..",\n"
            else
                expStr = expStr.."\n"..string.rep(" ", indent)..ch.."\n"
            end

            expStr = expStr..string.rep(" ", indent)

        else
            expStr = expStr..ch
        end

        idx = idx + 1
        ch  = string.sub(str, idx, idx)
    end

    return expStr
end

-- --------------------------------------
-- dumpTable
--
-- Called to better dump a table which
-- may contain tables, that will also
-- be dumped.
-- 
-- NOTE: This is JSON compatible syntax.
--
-- tbl    ....Lua table to encode
-- compact....nil or 0=readable, 1=compact
-- --------------------------------------
function dumpTable( tbl, compact )
    print( json_encode( tbl, compact ) )
end