-- examples/minimal.lua — 最简单的 example。
-- Run with: luamake lua examples/minimal.lua
-- Exit with Ctrl+C, Ctrl+D, or 'q'.

local tui = require "tui"

tui.render(
    tui.Text { "Hello, world!" }
)
