-- examples/hello.lua — Stage 1 smoke demo.
-- Run with: luamake lua examples/hello.lua
-- Exit with Ctrl+C, Ctrl+D, or 'q'.

local tui = require "tui"

tui.render(
    tui.Box {
        justifyContent = "center",
        alignItems     = "center",
        tui.Box {
            border  = "round",
            padding = "0 1",
            tui.Text { "Hello, tui.lua" },
        },
    }
)
