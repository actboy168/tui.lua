-- examples/hello.lua — Stage 1 smoke demo.
-- Run with: luamake lua examples/hello.lua
-- Exit with Ctrl+C, Ctrl+D, q, or Esc.

local tui = require "tui"

local function App()
    local app = tui.useApp()
    tui.useInput(function(input, key)
        if input == "q" or key.name == "escape" then
            app.exit()
        end
    end)
    return tui.Box {
        justifyContent = "center",
        alignItems     = "center",
        tui.Box {
            borderStyle = "round",
            padding     = "0 1",
            tui.Text { "Hello, tui.lua" },
        },
    }
end

tui.render(App)
