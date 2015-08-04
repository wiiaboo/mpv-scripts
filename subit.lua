-- input.conf: d script-binding subit/subit
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'

o = {
    path = "subliminal",
    languages = "en,pt"
}
options.read_options(o)

function main()
    mp.osd_message("looking for subs...")
    t = {}
    t.args = {o.path, "download", "-f"}
    for i in string.gmatch(o.languages, "%a+") do
        table.insert(t.args, "-l")
        table.insert(t.args, i)
    end
    table.insert(t.args, mp.get_property("path"))
    res = utils.subprocess(t)

    if res.status ~= 0 then
        mp.osd_message("no subtitles found")
        msg.debug("no subtitles found")
    else
        mp.commandv("rescan_external_files", "reselect")
        if not has_sub() then
            msg.debug("subtitles found but not downloaded")
        else
            msg.debug("subtitles found")
            mp.osd_message("subtitles found!")
        end
    end
end

function has_sub()
    local r = mp.get_property("sid")
    return r and r ~= "no" and r ~= ""
end

mp.add_key_binding("d", mp.get_script_name(), main)