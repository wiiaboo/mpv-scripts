--  zones.lua: mpv script for handling commands depending on where the mouse pointer is at,
--             mostly for mouse wheel handling, by configuring it via input.conf, e.g.:
--
--  Ported from avih's ( https://github.com/avih ) zones.js
--
--  Vertical positions can be top, middle, bottom or "*" to represent the whole column.
--  Horizontal positions can be left, middle, bottom or "*" to represent the whole row.
--  "default" will be the fallback command to be used if no command is assigned to that area.
--
--  # input.conf example of use:
--  #    wheel up/down with mouse
-- MOUSE_BTN3 script_message_to zones commands "middle-right: add brightness  1" "*-left: add volume  5" "default: seek  10"
-- MOUSE_BTN4 script_message_to zones commands "middle-right: add brightness -1" "*-left: add volume -5" "default: seek -10"
--
--  #    Provide some free-text info which the script can display on hover[*]:
-- Z          script_message_to zones info "middle-right: wheel up/down to change brightness" "*-left: wheel up/down to change volume" "default: wheel to seek"
-- # [*] unfortunately, this info cannot be retrieved dynamically without a command to send it to the script
-- #    We can use zones to turn the hover-info on, though!
-- # e.g. right-click is pause, but let's use top-left to toggle hover-info:
-- MOUSE_BTN2 script_message_to zones commands "default: cycle pause" "top-left: keypress Z"

local ZONE_THRESH_PERCENTAGE = 20;
-- -- sides get 20% each, mid gets 60%, same vertically
local VERT = {'top', 'middle', 'bottom'}
local HORZ = {'left', 'middle', 'right'}

local msg = mp.msg

function getMouseZone()
    -- returns the mouse zone as two strings [top/middle/bottom], [left/middle/right], e.g. "middle", "right"

    local screenW, screenH = mp.get_osd_resolution()
    local mouseX, mouseY   = mp.get_mouse_pos()

    local threshY = screenH * ZONE_THRESH_PERCENTAGE / 100
    local threshX = screenW * ZONE_THRESH_PERCENTAGE / 100

    local yZone = (mouseY < threshY) and VERT[1] or (mouseY < (screenH - threshY)) and VERT[2] or VERT[3]
    local xZone = (mouseX < threshX) and HORZ[1] or (mouseX < (screenW - threshX)) and HORZ[2] or HORZ[3]

    return yZone, xZone
end

function string:split(sep)
    local sep, key, cmd = sep or ":", nil, nil
    local sep = self:find(sep)
    if sep ~= nil then
        key = self:sub(0,sep-1):gsub("^%s*(.-)%s*$","%1")
        cmd = self:sub(sep+1,-1):gsub("^%s*(.-)%s*$","%1")
    else
        key = self
        cmd = nil
    end
    return key, cmd
end

function getZonesData(list)
    local data = {}
    for _, v in ipairs(list) do
        local sep = v:find(":")
        if sep < 1 or sep == nil then
            msg.warn("Invalid zone description: " .. v)
            msg.warn("Expected: {default|{top|middle|bottom|*}-{left|middle|right|*}}: <command>")
            msg.warn("E.g. \"default: seek 10\" or \"middle-right: add volume 5\"")
        else
            local pos, cmd = v:split()
            posY, posX = pos:split('-')
            if posX == "*" and (posY ~= "*" or posY ~= "") then
                for _, x in pairs(HORZ) do
                    if data[posY..'-'..x] == nil then
                        data[posY..'-'..x] = cmd
                    end
                end
            elseif posY == "*" and (posX ~= "*" or posX ~= "") then
                for _, y in pairs(VERT) do
                    if data[y..'-'..posX] == nil then
                        data[y..'-'..posX] = cmd
                    end
                end
            elseif posY == "default" or (posY == "*" and posX == "*") then
                data["default"] = cmd
            else
                data[pos] = cmd
            end
        end
    end
    return data
end

mp.register_script_message("commands", function (...)
    local arg={...}
    msg.debug('commands: \n\t'..table.concat(arg,'\n\t'))

    local keyY, keyX = getMouseZone()
    msg.debug(string.format("mouse at: %s-%s", keyY, keyX))

    local cmd = nil
    local commands = getZonesData(arg)
    local precise = commands[keyY..'-'..keyX]
    local default = commands['default']
    cmd = ( precise ~= nil ) and precise or default

    if cmd ~= nil then
        msg.verbose("running cmd: "..cmd)
        mp.command(cmd)
    else
        msg.debug("no command assigned for "..keyY .. '-' .. keyX)
    end
end)

local timeoutId, lastZone = nil, nil
mp.register_script_message("info", function (...)
    local arg={...}
    local info = {}
    local disp = ''
    if timeoutId == nil then
        timeoutId = mp.add_periodic_timer(0.1, function()
            local keyY, keyX = getMouseZone()
            local zone = keyY..'-'..keyX
            disp = info[zone] or info['default'] or ''
            if zone ~= lastZone then
                mp.osd_message(disp, 3)
            end
            lastZone = zone
        end)
    else
        timeoutId:kill()
        timeoutId = nil
    end
    info = getZonesData(arg)
    local status = (timeoutId ~= nil) and "on" or "off"
    mp.osd_message("zones info: "..status)
end)