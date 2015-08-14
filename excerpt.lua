-- Original from: https://github.com/lvml/mpv-plugin-excerpt/blob/master/excerpt.lua
-- This script allows to create excerpts of a video that is played,
-- press "i" to mark the begin of the range to excerpt,
-- press "o" to mark the end   of the range to excerpt,
-- press "I" to continue playback at the "begin" location,
-- press "O" to jump to the "end" location and pause there,
-- press "x" to actually start the creation of the excerpt,
--  which will be done by starting an external executable
--  named "excerpt_copy" with the parameters $1 = begin,
--  $2 = duration, $3 = source file name
-- (see bottom of this file for all key bindings)

-- initialization:

utils = require 'mp.utils'
options = require 'mp.options'
msg = require 'mp.msg'

excerpt_begin = 0.0
excerpt_end   = mp.get_property_native("duration")
if excerpt_end == nil then
 excerpt_end = 0.0
end

-- set options by using --script-opts=excerpt-option=value
-- or creating lua-settings/excerpt.conf inside mpv config dir
-- by default, basedir is pwd if empty.
local o = {
    basedir = "",
    basename = "excerpt",
    container = "webm",
    profile = ""
}
options.read_options(o)


mp.set_property("hr-seek-framedrop","no")
-- mp.set_property("options/keep-open","always")

-- alas, the following setting seems to not take effect - needs
-- to be specified on the command line of mpv, instead:
-- mp.set_property("options/lua-opts","osc-layout=bottombar,osc-hidetimeout=-1")


function excerpt_on_eof()
    -- pause upon reaching the end of the file
    mp.msg.log("info", "playback reached end of file")
    -- mp.set_property("pause","yes")
    -- mp.commandv("seek", 100, "absolute-percent", "exact")
end
mp.register_event("eof-reached", excerpt_on_eof)

-- range marking

function excerpt_rangemessage() 
    local duration = excerpt_end - excerpt_begin
    local message = ""
    message = message .. "begin=" .. string.format("%4.3f", excerpt_begin) .. "s "
    message = message .. "end=" .. string.format("%4.3f", excerpt_end) .. "s "
    message = message .. "duration=" .. string.format("% 4.3f", duration) .. "s "
    return message
end

function excerpt_rangeinfo() 
    local message = excerpt_rangemessage()
    mp.msg.log("info", message)
    mp.osd_message(message, 5)
end

function excerpt_mark_begin_handler() 
    pt = mp.get_property_native("playback-time")
    
    -- at some later time, setting a/b markers might be used to visualize begin/end
    -- mp.set_property("ab-loop-a", pt)
    -- mp.set_property("loop", 999)
 
    excerpt_begin = pt
    if excerpt_begin > excerpt_end then
        excerpt_end = excerpt_begin
    end
 
    excerpt_rangeinfo()
end

function excerpt_mark_end_handler() 
    pt = mp.get_property_native("playback-time")

    -- at some later time, setting a/b markers might be used to visualize begin/end
    -- mp.set_property("ab-loop-b", pt)
    -- mp.set_property("loop", 999)
  
    excerpt_end = pt
    if excerpt_end < excerpt_begin then
        excerpt_begin = excerpt_end
    end

    excerpt_rangeinfo()
end

-- writing

function excerpt_write_handler() 
    if excerpt_begin == excerpt_end then
        message = "excerpt_write: not writing because begin == end == " .. excerpt_begin
        mp.osd_message(message, 3)
        return
    end
    
    -- determine file name
    local cwd = ""
    if o.basedir == "" then
        cwd = utils.getcwd()
    else
        cwd = o.basedir
    end
    -- mp.msg.debug(cwd)
    local direntries = utils.readdir(cwd)
    local ftable = {}
    for i = 1, #direntries do
        -- mp.msg.log("info", "direntries[" .. i .. "] = " .. direntries[i])
        ftable[direntries[i]] = 1
    end 
    
    local fname = ""
    for i=0,999 do
        local f = string.format(o.basename.."_%03d."..o.container, i)
    
        -- mp.msg.log("info", "ftable[" .. f .. "] = " .. direntries[f])
    
        if ftable[f] == nil then
            fname = utils.join_path(cwd, f)
            break
        end
    end
    if fname == "" then
        message = "not writing because all filenames already in use" 
        mp.osd_message(message, 10)
        return
    end
    
    local srcname = mp.get_property_native("path")
    
    local message = excerpt_rangemessage()
    message = message .. "writing excerpt of source file '" .. srcname .. "'\n"
    message = message .. "to destination file '" .. fname .. "'" 
    msg.log("info", message)
    mp.osd_message(message, 10)

    local profile = ""
    if o.profile == "" then
        profile = "enc-to-"..o.container
    else
        profile = o.profile
    end

    t = {}
    t.args = {'mpv', srcname, '--term-status-msg='}
    table.insert(t.args, '--start=+' .. excerpt_begin)
    table.insert(t.args, '--end=+' .. excerpt_end)
    table.insert(t.args, '--profile=' .. profile)
    table.insert(t.args, '--o=' .. fname)
    if (mp.get_property('edition') ~= nil) then
        table.insert(t.args, '--edition=' .. mp.get_property('edition'))
    end
    table.insert(t.args, '--vid=' .. mp.get_property('vid'))
    table.insert(t.args, '--aid=' .. mp.get_property('aid'))
    table.insert(t.args, '--sid=' .. mp.get_property('sid'))
    table.insert(t.args, '--mute=' .. mp.get_property('mute'))
    table.insert(t.args, '--sub-visibility=' .. mp.get_property('sub-visibility'))
    table.insert(t.args, '--ass-style-override=' .. mp.get_property('ass-style-override'))
    table.insert(t.args, '--profile=subs')
    msg.debug("Running: " .. table.concat(t.args,' '))
    local res = utils.subprocess(t)
    if (res.status < 0) then
        msg.warn("encode failed")
        mp.osd_message("encode failed")
        return
    else
        msg.debug("encode complete")
        mp.osd_message("encode complete")
    end
end

-- assume some plausible frame time until property "fps" is set.
frame_time = 24.0 / 1001.0

function excerpt_fps_changed(name)
    ft = mp.get_property_native("fps")
    if ft ~= nil and ft > 0.0 then
        frame_time = 1.0 / ft
        -- mp.msg.log("info", "fps property changed to " .. ft .. " frame_time=" .. frame_time .. "s")
    end
end
mp.observe_property("fps", native, excerpt_fps_changed)

-- seeking

seek_account = 0.0
seek_keyframe = true

function excerpt_seek()
        
    local abs_sa = math.abs(seek_account)
    if abs_sa < (frame_time / 2.0) then
        seek_account = 0.0
        -- no seek required     
        return
    end
    
    -- mp.msg.log("info", "seek_account = " .. seek_account)
    
    if (abs_sa >= 10.0) then
        -- for seeks above 10 seconds, always use coarse keyframe seek
        seek_account = 0.0
        mp.commandv("seek", seek_account, "relative", "keyframes")
        return
    end

    if ((abs_sa > 0.5) or seek_keyframe) then
        -- for small seeks, use exact seek (unless instructed otherwise by user)
        local s = seek_account
        seek_account = 0.0
        
        local mode = "exact"
        if seek_keyframe then
            mode = "keyframes"
        end
        
        mp.commandv("seek", s, "relative", mode)
        return
    end
    
    -- for tiny seeks, use frame steps
    local s = frame_time
    if (seek_account < 0.0) then
        s = -s
        mp.commandv("frame_back_step")
    else
        mp.commandv("frame_step")
    end
    seek_account = seek_account - s;
end

-- we have excerpt_seek called both periodically and 
-- upon the display of yet another frame - this allows
-- to make "framewise" stepping with autorepeating keys to 
-- work as smooth as possible
excerpt_seek_timer = mp.add_periodic_timer(0.1, excerpt_seek)
mp.register_event("tick", excerpt_seek)
-- (I have experimented with stopping the timer when possible,
--  but this didn't work out for strange reasons, got error
--  messages from the event loop.)


function check_key_release(kevent)
    -- mp.msg.log("info", tostring(kevent))
    -- for k,v in pairs(kevent) do
    --  mp.msg.log("info", "kevent[" .. k .. "] = " .. tostring(v))
    -- end
    
    if kevent["event"] == "up" then
        -- mp.msg.log("info", "key up detected")
        
        -- key was released, so we should immediately stop to do any seeking
        seek_account = 0.0
        
        -- and do a "zero-seek" to reset mpv's internal frame step counter:
        mp.commandv("seek", 0.0, "relative", "exact")
        mp.set_property("pause","yes")
        return true
    end
    return false
end
    
function excerpt_frame_forward(kevent)
    if check_key_release(kevent) then
        return
    end
    
    seek_keyframe = false
    seek_account = seek_account + frame_time    
end

function excerpt_frame_back(kevent)
    if check_key_release(kevent) then
        return
    end
    
    seek_keyframe = false
    seek_account = seek_account - frame_time
end

function excerpt_keyframe_forward(kevent)
    if check_key_release(kevent) then
        return
    end
    
    seek_keyframe = true
    seek_account = seek_account + 0.1
end

function excerpt_keyframe_back(kevent)
    if check_key_release(kevent) then
        return
    end
    
    seek_keyframe = true
    seek_account = seek_account - 0.1
end

function excerpt_seek_begin_handler() 
    mp.commandv("seek", excerpt_begin, "absolute", "exact")
end

function excerpt_seek_end_handler() 
    mp.commandv("seek", excerpt_end, "absolute", "exact")
end

-- zooming and panning

excerpt_zoom = 0.0
excerpt_zoom_increment_factor = math.pow(2, 0.25)

excerpt_pan_x = 0.0
excerpt_pan_y = 0.0

function excerpt_set_pan()
    local max_pan = 0.5 - (1.0 / ((excerpt_zoom+1.0)*2.0))
    
    if (excerpt_pan_x < -max_pan) then
        excerpt_pan_x = -max_pan
    end

    if (excerpt_pan_x > max_pan) then
        excerpt_pan_x = max_pan
    end
    
    if (excerpt_pan_y < -max_pan) then
        excerpt_pan_y = -max_pan
    end
    
    if (excerpt_pan_y > max_pan) then
        excerpt_pan_y = max_pan
    end
    
    mp.set_property("video-pan-x", excerpt_pan_x)    
    mp.set_property("video-pan-y", excerpt_pan_y)    
end

function excerpt_pan_right()
    excerpt_pan_x = excerpt_pan_x - (1.0 / (16*(excerpt_zoom+1.0)))
    excerpt_set_pan()
end

function excerpt_pan_left()
    excerpt_pan_x = excerpt_pan_x + (1.0 / (16*(excerpt_zoom+1.0)))
    excerpt_set_pan()
end

function excerpt_pan_down()
    excerpt_pan_y = excerpt_pan_y - (1.0 / (16*(excerpt_zoom+1.0)))
    excerpt_set_pan()
end

function excerpt_pan_up()
    excerpt_pan_y = excerpt_pan_y + (1.0 / (16*(excerpt_zoom+1.0)))
    excerpt_set_pan()
end

function excerpt_zoominfo() 
    local message = "Zoom factor = " .. string.format("%4.2f", 1.0+excerpt_zoom)
    mp.osd_message(message, 3)
end

function excerpt_zoom_in() 
    excerpt_zoom = ((1.0 + excerpt_zoom) * excerpt_zoom_increment_factor) - 1.0
    if (excerpt_zoom > 15.0) then
        excerpt_zoom = 15.0
    end

    local i = math.floor(excerpt_zoom+0.5)
    
    if (i >= 1 and math.abs(excerpt_zoom - i) < 0.01) then
        -- snap to integer zoom factors when less than 1% away from them
        excerpt_zoom = i
    end
    
    excerpt_set_pan()
    mp.set_property("video-zoom", excerpt_zoom)
    
    excerpt_zoominfo()
end

function excerpt_zoom_out() 
    excerpt_zoom = ((1.0 + excerpt_zoom) / excerpt_zoom_increment_factor) - 1.0
    if (excerpt_zoom < 0.0) then
        excerpt_zoom = 0.0
    end
    
    local i = math.floor(excerpt_zoom+0.5)
    
    if (i >= 1 and math.abs(excerpt_zoom - i) < 0.01) then
        -- snap to integer zoom factors when less than 1% away from them
        excerpt_zoom = i
    end
    
    excerpt_set_pan()
    mp.set_property("video-zoom", excerpt_zoom)

    excerpt_zoominfo()
end


-- things to do whenever a new file was loaded:

function excerpt_on_loaded_late()
    -- for unknown reasons, mpv would start later than at the very
    -- first frame with some files - see https://github.com/mpv-player/mpv/issues/1341
    mp.commandv("seek", -1.0, "relative", "exact")
end

function excerpt_on_loaded()
    -- pause play right after loading a file
    -- mp.commandv("frame_step")
    -- mp.add_timeout(0.1, excerpt_on_loaded_late)
    
    excerpt_zoom = 0.0
    mp.set_property("video-zoom", excerpt_zoom) 

    excerpt_pan_x = 0.0
    excerpt_pan_y = 0.0
    excerpt_set_pan()
end

function excerpt_on_loaded_too_early_workaround()
    -- this function is used as an intermediate to 
    -- do delay actual execution of stuff that seems
    -- to not always work correctly when done immediately
    -- after loading
    -- mp.set_property("pause","yes")
    mp.add_timeout(0.1, excerpt_on_loaded)
end

function excerpt_on_loaded_original()
    -- without workaround:
    mp.set_property("pause","yes")
    excerpt_zoom = 0.0
    mp.set_property("video-zoom", excerpt_zoom) 

    excerpt_pan_x = 0.0
    excerpt_pan_y = 0.0
    excerpt_set_pan()
end
mp.register_event("file-loaded", excerpt_on_loaded_too_early_workaround)
-- mp.register_event("file-loaded", excerpt_on_loaded_original)

--

function excerpt_test(kevent)
    mp.msg.log("info", tostring(kevent))
    for k,v in pairs(kevent) do
        mp.msg.log("info", "kevent[" .. k .. "] = " .. tostring(v))
    end

    mp.commandv("seek", 0.0, "absolute", "exact")

end

--

mp.add_key_binding("I", "excerpt_mark_begin", excerpt_mark_begin_handler)
-- mp.add_key_binding("shift+i", "excerpt_seek_begin", excerpt_seek_begin_handler)
mp.add_key_binding("O", "excerpt_mark_end", excerpt_mark_end_handler)
-- mp.add_key_binding("shift+o", "excerpt_seek_end", excerpt_seek_end_handler)
mp.add_key_binding("x", "excerpt_write", excerpt_write_handler)

mp.add_key_binding("alt+right", "excerpt_keyframe_forward", excerpt_keyframe_forward, { repeatable = true; complex = true })
mp.add_key_binding("alt+left", "excerpt_keyframe_back", excerpt_keyframe_back, { repeatable = true; complex = true })
-- mp.add_key_binding(".", "excerpt_frame_forward", excerpt_frame_forward, { repeatable = true; complex = true })
-- mp.add_key_binding(",", "excerpt_frame_back", excerpt_frame_back, { repeatable = true; complex = true })

-- mp.add_key_binding("e", "excerpt_zoom_in", excerpt_zoom_in, { repeatable = true; complex = false })
-- mp.add_key_binding("w", "excerpt_zoom_out", excerpt_zoom_out, { repeatable = true; complex = false })

-- mp.add_key_binding("ctrl+right", "excerpt_pan_right", excerpt_pan_right, { repeatable = true; complex = false })
-- mp.add_key_binding("ctrl+left", "excerpt_pan_leftt", excerpt_pan_left, { repeatable = true; complex = false })
-- mp.add_key_binding("ctrl+up", "excerpt_pan_up", excerpt_pan_up, { repeatable = true; complex = false })
-- mp.add_key_binding("ctrl+down", "excerpt_pan_down", excerpt_pan_down, { repeatable = true; complex = false })

-- mp.add_key_binding("shift+mouse_btn3", "excerpt_test", excerpt_test, { repeatable = false; complex = true })
-- mp.add_key_binding("shift+mouse_btn4", "excerpt_test", excerpt_test, { repeatable = false; complex = true })
-- mp.add_key_binding("y", "excerpt_test", excerpt_test, { repeatable = false; complex = true })

-- excerpt_rangeinfo()

