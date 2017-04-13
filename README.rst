Introduction
------------

These are Lua scripts for use with mpv. See here how to use them:

https://mpv.io/manual/master/#lua-scripting

auto-profiles.lua
-----------------

Automatically apply profiles based on predicates written as Lua expressions. See
file header for details.

fix-sub-timing.lua
------------------

Compute the correct speed/delay of subtitles by manually synching two points in
time. Useful for subtitles that were e.g. timed against a PAL version of the
video, or otherwise fucked up cases.

mines.lua
---------

Minesweeper clone. For when you watch something too boring.

Bring up with ctrl+x, then move with the cursor keys, and use space to
uncover tiles, or b to flag them.

Once you've won or lost, press space on an uncovered tile to restart.

t toggles transparent mode, if what you're watching is boring but not that boring.

w starts a new game and cycles through presets.

Bugs:

- weird scaling issues
- uses undocumented/private API and might thus break any time
