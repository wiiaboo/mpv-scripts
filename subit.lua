-- input.conf: d    script-binding subit
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'

o = {
    path = "subliminal",
    languages = "en,pt"
}
options.read_options(o)

function parse_subliminal(txt)
    txt = txt:gsub("[\r\n]", '')
    txt = txt:gsub("(Collecting videos)", '')
    txt = txt:gsub("(Downloading subtitles)", '')
    txt = txt:gsub("(1 video collected / 0 video ignored / 0 error)", '')
    if txt:match("0 video collected / 1 video ignored / 0 error") then
        mp.osd_message("Subtitles already in path")
        mp.commandv("rescan_external_files", "keep-selection")
        return
    end
    local subs_found = txt:match("Downloaded (%d+) subtitles?")
    if subs_found ~= nil then
        subs_found = tonumber(subs_found)
    end
    return subs_found
end

function main()
    mp.osd_message("looking for subs...", 100000)
    local t = {}
    t.args = {o.path, "download"}
    for i in string.gmatch(o.languages, "%a+") do
        table.insert(t.args, "-l")
        table.insert(t.args, i)
    end
    local dir, file = string.match(mp.get_property("path"), "(.-)([^\\/]-[^%.]+)$")
    if dir ~= nil then
        table.insert(t.args, "-d")
        table.insert(t.args, dir)
    end
    table.insert(t.args, file)
    msg.verbose("Running: " .. table.concat(t.args,' '))
    local res = utils.subprocess(t)
    local es, txt = res.status, res.stdout

    if (es < 0) or (txt == nil) or (txt == "") then
        if not res.killed_by_us then
            msg.warn("subliminal failed")
        end
        return
    end

    subs_found = parse_subliminal(txt)

    if subs_found == 0 or subs_found == nil then
        mp.osd_message("No subtitles found")
        msg.warn("No subtitles found")
    else
        mp.osd_message(string.format("Found %d subtitle%s", subs_found, (subs_found == 1) and '' or 's'))
        mp.commandv("rescan_external_files", "reselect")
    end
end

mp.add_key_binding("d", mp.get_script_name(), main)