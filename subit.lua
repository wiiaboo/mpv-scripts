-- input.conf: d    script-binding subit

--[[
Requirements:
- Python 2/3, installed or embedded
- subliminal (python script)
- if Windows, python's Script in PATH or change 'path'
  to absolute path of subliminal.exe

Non-local files are ignored because mpv's --sub-path doesn't work
for those.
]]


local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'

o = {
    key = "d",
    path = "subliminal",    -- absolute path to subliminal if not on PATH
    languages = "en,pt-PT", -- list of IETF languages to search
    forceutf8 = true,       -- Force subtitles to be saved as utf-8
    forcedownload = false,  -- Force download of all languages requested

    -- Some providers need credentials to be used.
    -- This isn't necessary unless you want these providers.
    -- split user/password with any of ": |,"
    -- user/pass can't contain these
    addic7ed = "",
    legendastv = "",
    opensubtitles = "",
}
options.read_options(o)

function parse_subliminal(txt)
    txt = txt:gsub("[\r\n]", '')
    txt = txt:gsub("(Collecting videos)", '')
    txt = txt:gsub("(Downloading subtitles)", '')
    txt = txt:gsub("(1 video collected / 0 video ignored / 0 error)", '')
    if txt:match("0 video collected / 1 video ignored / 0 error") then
        mp.osd_message("Subtitles already in path/video")
        mp.commandv("rescan_external_files", "keep-selection")
        return
    end

    local subs_found = txt:match("Downloaded (%d+) subtitles?")

    if subs_found == 0 or subs_found == nil then
        mp.osd_message("No subtitles found")
        msg.warn("No subtitles found")
    else
        mp.osd_message(string.format("Found %d subtitle%s",
            subs_found, (subs_found == 1) and '' or 's'))
        mp.commandv("rescan_external_files", "reselect")
    end
end

function main()
    local path = mp.get_property("path")

    mp.osd_message("looking for subs...", 100000)
    local t = {}
    t.args = {o.path}

    for _, i in ipairs({"addic7ed", "legendastv",
        "opensubtitles", "subscenter"}) do
        if o[i] and o[i] ~= "" then
            local user, pass =
                string.match(o[i], "([^ :,|]+)[:,| ]([^ :,|]+)")
            if user ~= nil and pass ~= nil then
                table.insert(t.args, "--"..i)
                table.insert(t.args, user)
                table.insert(t.args, pass)
            end
        end
    end

    table.insert(t.args, "download")
    for i in string.gmatch(o.languages, "[%a-_]+") do
        table.insert(t.args, "-l")
        table.insert(t.args, i)
    end

    local dir, file = utils.split_path(path)
    if dir ~= nil then
        table.insert(t.args, "-d")
        if not (dir:find("ytdl:") == 1 or dir:find("http") == 1) then
            table.insert(t.args, dir)
        else
            table.insert(t.args, mp.find_config_file("sub"))
        end
    end

    if o.forceutf8 then
        -- force utf-8 encoding on the output subtitles
        table.insert(t.args, "-e")
        table.insert(t.args, "utf-8")
    end

    if o.forcedownload then
        -- (if false, won't download English subs if subtitles
        --  are already embedded in the container or present in the dir)
        table.insert(t.args, "-f")
    end

    table.insert(t.args, path)
    msg.debug(string.format("Running: \"%s\"", table.concat(t.args,'" "')))
    local res = utils.subprocess(t)
    local es, txt = res.status, res.stdout

    if (es < 0) or (txt == nil) or (txt == "") then
        if not res.killed_by_us then
            mp.osd_message("subliminal failed")
            msg.warn("subliminal failed")
        end
        return
    end
    msg.debug(txt)

    parse_subliminal(txt)
end

mp.add_key_binding(o.key, "subit", main)