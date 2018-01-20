--[[
Original from:
    https://github.com/lvml/mpv-plugin-excerpt/blob/master/excerpt.lua
This script allows to create excerpts of a video that is played,
press "i" to mark the begin of the range to excerpt,
press "o" to mark the end   of the range to excerpt,
press "x" to actually start the creation of the excerpt,
which will be done using mpv itself
--]]


utils = require 'mp.utils'
options = require 'mp.options'
msg = require 'mp.msg'

local excerpt = {
    mpv_path = "mpv",
    mpv_searched = false,
    clipboard_searched = false,
    _begin = 0.0,
    _end = 0.0,
    announce_args = {},
}

-- set options by using --script-opts=excerpt-option=value
-- or creating lua-settings/excerpt.conf inside mpv config dir
-- by default, basedir is pwd if empty.
local o = {
    basedir = "",
    basename = "",
    char_size = 4,  -- number of random characters
    container = "webm",
    -- profile in encoding-profiles.conf to use,
    -- by default uses "enc-to-<container>"
    profile = "",
    baseurl = "",  -- with trailing slash, ex: "http://0x0.st/"
    milliseconds = false,
    announce = false,
    -- filename, time-pos, base_url, screenshot filename
    announce_format = "/me - %s - %s - %s%s",
}
options.read_options(o)


local function makeHtmlSafeRandomString(l, seed)
    l = math.max(1, l)
    math.randomseed(seed)
    local safechars = "0123456789"
    safechars = safechars .. "abcdefghijklmnopqrstuvwxyz"
    safechars = safechars .. "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    safechars = safechars .. "-_.~"
    local s = {}
    for i = 1, l do
        r = math.random(#safechars)
        s[i] = string.sub(safechars, r, r)
    end
    return table.concat(s)
end

local function secondsToTime(s, ms)
    local ms = (ms ~= nil and ms) or false
    local h = math.floor(s/(60*60))
    local m = math.floor(s/60%60)
    local s = (ms == true and s%60 or math.floor(s%60))
    local format = "%02d:%02d:" .. (ms == true and "%06.3f" or "%02d")
    return string.format(format, h, m, s)
end

function set_clipboard(text)
    local res = utils.subprocess({ args = {
        'powershell', '-NoProfile', '-Command', string.format([[& {
            Trap {
                Write-Error -ErrorRecord $_
                Exit 1
            }
            Add-Type -AssemblyName PresentationCore
            [System.Windows.Clipboard]::SetText('%s')
        }]], text)
    } })
end

local function announce_to_clipboard(timestamps, filename)
    msg.info(timestamps..'\n'..filename)
    if not (o.announce or timestamps or filename) then
        return
    end
    local announce = ""
    if not (o.announce_format == "") then
        local srcfname = mp.get_property_osd('filename')
        local srcpath = mp.get_property_osd('path')
        if (srcpath:find("://") ~= nil) then
            srcfname = srcpath
        end
        announce = string.format(o.announce_format, srcfname,
                                 timestamps, o.baseurl, filename)
    elseif not (o.baseurl == "") then
        announce = string.format(o.baseurl .. filename)
    end
    if not (announce == "") then
        msg.info('Pasting: '..announce)
        set_clipboard(announce)
    end
end

local function excerpt_rangemessage()
    local duration = excerpt._end - excerpt._begin
    local message = string.format("begin=%s end=%s duration=% 6.1fs",
                                  excerpt._begin, excerpt._end, duration)
    return message
end

local function excerpt_rangeinfo()
    local message = excerpt_rangemessage()
    msg.info(message)
    mp.osd_message(message, 5)
end

local function get_fname(seed, format, default_name)
    local cwd, _ = utils.split_path(mp.get_property("path", '.'))
    local home = nil
    if os.getenv('HOMEDRIVE') then
        home = string.format('%s%s', os.getenv('HOMEDRIVE'), os.getenv('HOMEPATH'))
    elseif os.getenv('HOME') then
        home = os.getenv('HOME')
    else
        home = '~'
    end
    msg.debug('home: '..home)
    if (cwd:find("://") ~= nil) then
        cwd = home
    end
    local path = ""
    local screenshot_dir = mp.get_property('screenshot-directory', '')
    if not (o.basedir == "") then
        path = o.basedir
    elseif not (screenshot_dir == "") then
        path = screenshot_dir
    else
        path = cwd
    end
    path = path:gsub('^(~)', home)
    msg.debug('cwd: '..cwd..' path: '..path..' screenshot-directory: '..screenshot_dir)

    local basename = (o.basename == "" and default_name or o.basename)
    local direntries = utils.readdir(path, "files")
    local ftable = {}
    for i = 1, #direntries do
        ftable[direntries[i]] = 1
    end
    local fname = ""
    for i=0, 999 do
        local f = ""
        if (o.basename == "random") then
            f = string.format('%s.%s', makeHtmlSafeRandomString(o.char_size, seed+i), format)
        else
            f = string.format('%s_%03d.%s', basename, i, format)
        end
        if ftable[f] == nil then
            msg.debug('fname: '..f)
            return f, path, cwd
        end
    end
    return nil
end

local function excerpt_mark_handle(_type)
    local pt = mp.get_property_native("playback-time")
    if (_type == "_begin") then
        excerpt._begin = pt
        excerpt._end = (excerpt._begin > excerpt._end) and pt or excerpt._end
    elseif (_type == "_end") then
        excerpt._end = pt
        excerpt._begin = (excerpt._end < excerpt._begin) and pt or excerpt._begin
    end
    excerpt_rangeinfo()
end

local function excerpt_write_handler()
    local abloop_a = mp.get_property_native("ab-loop-a")
    local abloop_b = mp.get_property_native("ab-loop-b")

    if (not abloop_a == "not") and (not abloop_b == "not") then
        excerpt._begin = abloop_a
        excerpt._end = abloop_b
    end

    if excerpt._begin == excerpt._end then
        message = "excerpt_write: not writing because begin == end == " .. excerpt._begin
        mp.osd_message(message, 3)
        return
    end
    
    local fname, path, cwd = get_fname(excerpt._begin + excerpt._end,
                                       o.container, "excerpt")

    local srcname = mp.get_property_native("path")
    
    local endfname = utils.join_path(path, fname)

    local message = string.format("%s\n%s '%s'\n%s '%s'",
        excerpt_rangemessage(),
        "writing excerpt of source file", srcname,
        "to destination file", endfname)
    msg.info(message)
    mp.osd_message(message, 10)

    local profile = ""
    if o.profile == "" then
        profile = "enc-to-"..o.container
    else
        profile = o.profile
    end

    local tmpname = utils.join_path(cwd, fname)
    t = {}
    t.args = {excerpt.mpv_path, srcname, '--quiet'}
    table.insert(t.args, '--start=+' .. excerpt._begin)
    table.insert(t.args, '--end=+' .. excerpt._end)
    table.insert(t.args, '--profile=' .. profile)
    table.insert(t.args, '--o=' .. tmpname)
    if not (mp.get_property('edition') == nil) then
        table.insert(t.args, '--edition=' .. mp.get_property('edition'))
    end
    props = {'vid', 'aid', 'sid', 'mute', 'sub-visibility',
             'sub-ass-override', 'audio-delay', 'sub-delay'}
    for _, i in pairs(props) do
        table.insert(t.args, '--'..i..'='..mp.get_property(i))
    end

    msg.debug("Running: " .. table.concat(t.args,' '))
    local res = utils.subprocess(t)

    if (res.status < 0) then
        msg.warn("encode failed")
        mp.osd_message("encode failed")
        return
    else
        msg.debug("encode complete")
        mp.osd_message("encode complete")
        msg.debug('moving: '..tmpname..' to '..endfname)
        os.rename(tmpname, endfname)
        local timestamps = string.format("%s-%s",
                secondsToTime(excerpt._begin, o.milliseconds),
                secondsToTime(excerpt._end, o.milliseconds))
        announce_to_clipboard(timestamps, fname)
    end
end


mp.add_key_binding("I", "excerpt_mark_begin",
    function () excerpt_mark_handle("_begin") end)
mp.add_key_binding("O", "excerpt_mark_end",
    function () excerpt_mark_handle("_end") end)
mp.add_key_binding("x", "excerpt_write", excerpt_write_handler)

mp.add_key_binding("u", "screenshot_write", function ()
    local pos = mp.get_property_native('playback-time')
    local fname, path = get_fname(pos, mp.get_property('screenshot-format'),
                                     "shot")
    if not (fname == nil) then
        mp.commandv("screenshot-to-file", utils.join_path(path, fname))
        announce_to_clipboard(secondsToTime(pos, o.milliseconds), fname)
    end
end)

mp.register_event("file-loaded", function ()
    local duration = mp.get_property_native("duration")
    if not (duration == nil) then
        excerpt._end = duration
    end
    if not (excerpt.mpv_searched) then
        local exesuff = (package.config:sub(1,1) == '\\') and '.exe' or ''
        local mpv_mcd = mp.find_config_file(excerpt.mpv_path..exesuff)
        if not (mpv_mcd == nil) then
            excerpt.mpv_path = mpv_mcd
        end
        excerpt.mpv_searched = true
    end
end)
