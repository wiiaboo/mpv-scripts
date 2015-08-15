-- evenbetterchapters.lua
-- Hacked from https://gist.github.com/Hakkin/4f978a5c87c31f7fe3ae and autoload.lua
-- Loads the next or previous playlist entry if there are no more chapters in the seek direction.
-- Loads next file if there is no playlist so there's no need for autoload.lua, but should work as normal with autoload.lua loaded.
-- To bind in input.conf, use: <keybind> script-binding <keybind name>
-- Keybind names: chapter_next, chapter_prev

function Set (t)
    local set = {}
    for _, v in pairs(t) do set[v] = true end
    return set
end

EXTENSIONS = Set {
    'mkv', 'avi', 'mp4', 'ogv', 'webm', 'rmvb', 'flv', 'wmv', 'mpeg', 'mpg', 'm4v', '3gp',
    'mp3', 'wav', 'ogv', 'flac', 'm4a', 'wma',
}

mputils = require 'mp.utils'

function get_extension(path)
    return string.match(path, "%.([^%.]+)$" )
end

table.filter = function(t, iter)
    for i = #t, 1, -1 do
        if not iter(t[i]) then
            table.remove(t, i)
        end
    end
end

function find_and_open_file(direction)
    local path = mp.get_property("path", "")
    local dir, filename = mputils.split_path(path)
    if #dir == 0 then
        return
    end

    local files = mputils.readdir(dir, "files")
    if files == nil then
        return
    end
    table.filter(files, function (v, k)
        local ext = get_extension(v)
        if ext == nil then
            return false
        end
        return EXTENSIONS[string.lower(ext)]
    end)
    table.sort(files, function (a, b)
        return string.lower(a) < string.lower(b)
    end)

    if dir == "." then
        dir = ""
    end

    -- Find the current pl entry (dir+"/"+filename) in the sorted dir list
    local current
    for i = 1, #files do
        if files[i] == filename then
            current = i
            break
        end
    end
    if current == nil then
        return
    end

    local file = files[current + direction]
    if file == nil or file[1] == "." then
        return
    end

    local filepath = dir .. file
    mp.commandv('loadfile', filepath)
end

function chapter_seek(direction)
    local chapters = mp.get_property_number("chapters")
    local chapter  = mp.get_property_number("chapter")
    local isplaylist = mp.get_property_number('playlist-count') > 1
    if chapter == nil then chapter = 0 end
    if chapter+direction < 0 then
        if isplaylist then
            mp.command("playlist_prev")
        else
            find_and_open_file(-1)
        end
    elseif chapter+direction >= chapters then
        if isplaylist then
            mp.command("playlist_next")
        else
            find_and_open_file(1)
        end
    else
        mp.commandv("osd-msg", "add", "chapter", direction)
    end
end

mp.add_key_binding("PGUP", "chapter_next", function() chapter_seek(1) end)
mp.add_key_binding("PGDWN", "chapter_prev", function() chapter_seek(-1) end)