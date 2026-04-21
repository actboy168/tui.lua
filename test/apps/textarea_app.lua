-- test/apps/textarea_app.lua — app fixture for Textarea mouse tests.
-- Loaded via testing.load_app("test/apps/textarea_app.lua").
--
-- Provides a Textarea with fixed height=4 inside a fixed-height container
-- so overflow triggers scroll behavior.

local tui = require "tui"

local function App()
    local value, setValue = tui.useState("")
    return tui.Box {
        width = 30,
        height = 4,
        tui.Textarea { value = value, onChange = setValue, height = 4, maxHeight = 4 },
    }
end

tui.render(App)
