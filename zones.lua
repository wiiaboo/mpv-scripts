--  zones.lua: mpv - script for handling commands depending on where the mouse pointer is at,
--            mostly for mouse wheel handling, by configuring it via input.conf, e.g.:
--  input.conf:
--
-- # wheel up/down with my mouse
-- MOUSE_BTN3 script_message_to zones commands "default: seek  10" "*-left: add volume  5" "middle-right: add brightness  1"
-- MOUSE_BTN4 script_message_to zones commands "default: seek -10" "*-left: add volume -5" "middle-right: add brightness -1"
local msg = mp.msg
local ZONE_THRESH_PERCENTAGE = 20;
-- sides get 20% each, mid gets 60%, same vertically

-- returns the mouse zone as a string [top/middle/bottom]-[left/middle/right], e.g. "middle-right"
-- TODO: refine: diagonal borders, etc.

function getMouseZone()
    local screenW, screenH = mp.get_osd_resolution()
    local mouseX, mouseY = mp.get_mouse_pos()

    local threshY = screenH * ZONE_THRESH_PERCENTAGE / 100
    local threshX = screenW * ZONE_THRESH_PERCENTAGE / 100

    local yZone = (mouseY < threshY) and "top" or (mouseY < (screenH - threshY)) and "middle" or "bottom"
    local xZone = (mouseX < threshX) and "left" or (mouseX < (screenW - threshX)) and "middle" or "right"

    return yZone, xZone
end

function main (...)
    local arg={...}
    msg.debug('commands: \n\t'..table.concat(arg,'\n\t'))
    local keyY, keyX = getMouseZone()
    msg.debug("mouse at: " .. keyY .. '-' .. keyX)
    local fallback = nil

    for i,v in ipairs(arg) do
        cmdY = v:match("^([%w%*]+)%-?[%w%*]*:")
        cmdX = v:match("^[%w%*]*%-([%w%*]+)%s*:")
        cmd  = v:match("^[%S]-%s*:%s*(.+)")
        -- msg.debug('cmdY: '..tostring(cmdY))
        -- msg.debug('cmdX: '..tostring(cmdX))

        if (cmdY == keyY and cmdX == keyX) then
            msg.debug("cmd: "..cmd)
            mp.command(cmd)
            return
        elseif  (cmdY == "*"  and cmdX == keyX) or
                (cmdY == keyY and cmdX == "*") then
            msg.debug("cmd: "..cmd)
            mp.command(cmd)
            return
        elseif cmdY == "default" then
            fallback = cmd
        end
    end
    if fallback ~= nil then
        msg.debug("default cmd: "..fallback)
        mp.command(fallback)
        return
    else
        msg.debug("no command assigned for "..keyY .. '-' .. keyX)
        return
    end
end
mp.register_script_message("commands", main)
