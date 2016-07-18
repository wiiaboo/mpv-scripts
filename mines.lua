local assdraw = require 'mp.assdraw'

local W = 0
local H = 0
-- 2D array of size W*H that's addressed via gField[x][y]. Each entry is a
-- table, with the following fields:
--      is_mine:        true or false
--      area_mines:     mine count in the 3x3 surrounding area
--      is_covered:     true or false, for visibility
--      flag:           flag put by user, one of FLAG_*
local gField = nil

local FLAG_NONE = ""          -- not flagged
local FLAG_MINE = "⚑" -- "⚐"         -- flagged as containing mine
local FLAG_MAYBE_MINE = "!"   -- flagged as maybe containing mine
local FLAG_MAYBE_SAFE = "?"   -- flagged as maybe empty

local STATUS_PLAYING = "playing"
local STATUS_WON = "won"
local STATUS_LOST = "lost"

local gStatus = nil

local gMines = 0

local gX = 0
local gY = 0

local gNeedRefresh = false
local gHidden = true
local gTransparent = false

local PRESETS = {
    -- taken from kmines
    { name = "easy",    w = 9,  h = 9,  mines = 10 },
    { name = "medium",  w = 16, h = 16, mines = 40 },
    { name = "hard",    w = 30, h = 16, mines = 99 },
}
local gCurrentPreset = 2

function init_field()
    local preset = PRESETS[gCurrentPreset]
    gStatus = STATUS_PLAYING
    gField = {}
    W = preset.w
    H = preset.h
    gMines = math.min(preset.mines, W * H - 1)
    gX = 1
    gY = 1

    for x = 1, W do
        gField[x] = {}
        for y = 1, H do
            gField[x][y] = {
                is_mine = false,
                area_mines = 0,
                is_covered = true,
                flag = FLAG_NONE,
            }
        end
    end

    -- place mines using the dumbfuck algorithm
    local place_mines = gMines
    while place_mines > 0 do
        local x = math.random(1, W)
        local y = math.random(1, H)
        if not gField[x][y].is_mine then
            gField[x][y].is_mine = true
            place_mines = place_mines - 1
        end
    end

    -- pick a random start position (also using dumbfuck algorithm)
    for i = 1, 1000000 do
        local x = math.random(1, W)
        local y = math.random(1, H)
        if not gField[x][y].is_mine then
            gX = x
            gY = y
            break
        end
    end

    -- compute proximities after mines have been placed
    for y = 1, H do
        for x = 1, W do
            local tile = gField[x][y]
            for a_x = -1, 1 do
                for a_y = -1, 1 do
                    local t_x = x + a_x
                    local t_y = y + a_y
                    if t_x >= 1 and t_x <= W and t_y >= 1 and t_y <= H and
                       gField[t_x][t_y].is_mine
                    then
                        tile.area_mines = tile.area_mines + 1
                    end
                end
            end
        end
    end

    uncover()

    check_status()

    gNeedRefresh = true
end

function uncover_at(x, y)
    if x < 1 or x > W or y < 1 or y > H then
        return
    end

    local tile = gField[x][y]

    if not tile.is_covered then
        return
    end

    tile.is_covered = false

    if tile.is_mine then
        return -- lost anyway
    end

    -- uncover mines as far as it goes
    -- apparently, the standard thing to do is recursively uncovering all
    -- tiles which have 0 neightbours - tiles with 1 or more neighbours are
    -- uncovered, but not recursively
    if tile.area_mines == 0 then
        for a_x = -1, 1 do
            for a_y = -1, 1 do
                uncover_at(x + a_x, y + a_y)
            end
        end
    end

    gNeedRefresh = true
end

function check_status()
    if gStatus ~= STATUS_PLAYING then
        return
    end

    local won = true
    local lost = false

    for y = 1, H do
        for x = 1, W do
            local tile = gField[x][y]
            won = won and (tile.is_mine == tile.is_covered)
            lost = lost or (tile.is_mine and not tile.is_covered)
        end
    end

    if lost then
        gStatus = STATUS_LOST
        gNeedRefresh = true
    elseif won then
        gStatus = STATUS_WON
        gNeedRefresh = true
    end
end

function uncover()
    if gStatus ~= STATUS_PLAYING and not gField[gX][gY].is_covered then
        init_field()
        render()
        return
    end
    uncover_at(gX, gY)
    check_status()
    render()
end

function flag()
    local tile = gField[gX][gY]
    local cycle = {FLAG_NONE, FLAG_MINE, FLAG_MAYBE_MINE, FLAG_MAYBE_SAFE}
    for i = 1, #cycle do
        if tile.flag == cycle[i] then
            tile.flag = cycle[(i - 1 + 1) % #cycle + 1]
            break
        end
    end
    if not tile.is_covered then
        tile.flag = FLAG_NONE
    end
    force_render()
end

function move(x, y)
    gX = math.min(math.max(gX + x, 1), W)
    gY = math.min(math.max(gY + y, 1), H)

    force_render()
end

function force_render()
    gNeedRefresh = true
    render()
end

function render()
    if not gNeedRefresh then
        return
    end

    if gHidden then
        mp.set_osd_ass(1280, 720, "")
        return
    end

    local canvas_w = 1280
    local canvas_h = 720
    local dw, dh, da = mp.get_osd_size()
    if dw ~= nil and dw > 0 and dh > 0 then
        canvas_w = dw / dh * canvas_h
    end

    local tile_wh = 32

    local o_x = canvas_w / 2 - tile_wh * W / 2
    local o_y = canvas_h / 2 - tile_wh * (H + 2) / 2 + tile_wh

    local ass = assdraw.ass_new()

    local transp = nil
    if gTransparent then
        transp = "{\\1a&HA0&\\3a&HA0&}"
    end

    -- some shitty background
    ass:new_event()
    ass:append("{\\1c&Ha3a3a3&\\1a&H30&}")
    if transp then
        ass:append(transp)
    end
    ass:pos(o_x - tile_wh, o_y - tile_wh)
    ass:draw_start()
    ass:rect_cw(0, 0, (W + 2) * tile_wh, (H + 2) * tile_wh)
    -- grid
    local function grid_line(x0, y0, x1, y1)
        ass:new_event()
        ass:append("{\\bord0.5}")
        if transp then
            ass:append(transp)
        end
        ass:pos(x0, y0)
        ass:draw_start()
        ass:coord(0, 0)
        ass:line_to(x1 - x0, y1 - y0)
    end
    for x = 0, W do
        local p_x = x * tile_wh + o_x
        grid_line(p_x, o_y, p_x, o_y + tile_wh * H)
    end
    for y = 0, H do
        local p_y = y * tile_wh + o_y
        grid_line(o_x, p_y, o_x + tile_wh * W, p_y)
    end

    local function draw_sym(x, y, sym, c)
        ass:new_event()
        ass:pos(x, y)
        ass:append("{\\an5\\fs25\\bord0\\1c&H" .. c .. "&\\b1}" .. sym)
    end

    for x = 1, W do
        for y = 1, H do
            local tile = gField[x][y]
            local p_x = (x - 1) * tile_wh + tile_wh / 2 + o_x
            local p_y = (y - 1) * tile_wh + tile_wh / 2 + o_y
            local wh = tile_wh - 4
            local sym = nil
            if tile.is_covered then
                ass:new_event()
                if transp then
                    ass:append(transp)
                end
                ass:pos(p_x, p_y)
                ass:draw_start()
                ass:round_rect_cw(-wh / 2, -wh / 2, wh / 2, wh / 2, 5)
                ass:draw_stop()
            elseif tile.is_mine then
                draw_sym(p_x, p_y, "💣", "0000FF")
            elseif tile.area_mines > 0 then
                draw_sym(p_x, p_y, tile.area_mines, "000000")
            end
            if tile.flag ~= FLAG_NONE then
                draw_sym(p_x, p_y, tile.flag, "FF0000")
            end
            if x == gX and y == gY then
                local wh = tile_wh - 12
                ass:new_event()
                ass:append("{\\1a&HFF&}")
                ass:pos(p_x, p_y)
                ass:draw_start()
                ass:rect_cw(-wh / 2, -wh / 2, wh / 2, wh / 2)
                ass:draw_stop()
            end
        end
    end

    local banner = nil
    if gStatus == STATUS_WON then
        banner = "You may have won, but actually you just wasted time."
    elseif gStatus == STATUS_LOST then
        banner = "You lost (and wasted time)."
    end
    if banner then
        ass:new_event()
        ass:pos(o_x + tile_wh * W / 2, o_y - tile_wh - 10)
        ass:append("{\\fs40\\b1\\an2}" .. banner)
    end

    mp.set_osd_ass(canvas_w, canvas_h, ass.text)
end

mp.observe_property("osd-width", "native", force_render)
mp.observe_property("osd-height", "native", force_render)

init_field()
force_render()

function toggle_transp()
    gTransparent = not gTransparent
    force_render()
end

function cycle_preset()
    gCurrentPreset = (gCurrentPreset + 1 - 1) % #PRESETS + 1
    init_field()
    render()
end

function toggle_show()
    if gHidden then
        gHidden = false

        local REP = {repeatable = true}
        mp.add_forced_key_binding("left", "mines-left", function() move(-1, 0) end, REP)
        mp.add_forced_key_binding("right", "mines-right", function() move(1, 0) end, REP)
        mp.add_forced_key_binding("up", "mines-up", function() move(0, -1) end, REP)
        mp.add_forced_key_binding("down", "mines-down", function() move(0, 1) end, REP)
        mp.add_forced_key_binding("space", "mines-uncover", uncover)
        mp.add_forced_key_binding("b", "mines-flag", flag)
        mp.add_forced_key_binding("t", "mines-transp", toggle_transp)
        mp.add_forced_key_binding("w", "mines-preset", cycle_preset)
    else
        gHidden = true

        mp.remove_key_binding("mines-left")
        mp.remove_key_binding("mines-right")
        mp.remove_key_binding("mines-up")
        mp.remove_key_binding("mines-down")
        mp.remove_key_binding("mines-uncover")
        mp.remove_key_binding("mines-flag")
        mp.remove_key_binding("mines-transp")
        mp.remove_key_binding("mines-preset")
    end

    force_render()
end

mp.add_forced_key_binding("ctrl+x", "mines-show", toggle_show)
