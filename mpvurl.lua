mp.add_hook("on_load", 9, function ()
    local url = mp.get_property("stream-open-filename")

    if (url:find("mpv://") == 1) then
        url = url:sub(7)
        mp.set_property("stream-open-filename", url)
    end
end)