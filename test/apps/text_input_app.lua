-- test/apps/text_input_app.lua — app fixture for TextInput mouse tests.
-- Loaded via testing.load_app("test/apps/text_input_app.lua").
--
-- Provides two TextInput fields:
--   1. "first"  — autoFocus, placeholder "first"
--   2. "second" — no autoFocus, placeholder "second"

local tui = require "tui"

local function App()
    local v1, setV1 = tui.useState("")
    local v2, setV2 = tui.useState("")
    return tui.Box {
        flexDirection = "column", gap = 1,
        tui.TextInput { value = v1, onChange = setV1, placeholder = "first", autoFocus = true },
        tui.TextInput { value = v2, onChange = setV2, placeholder = "second", autoFocus = false },
    }
end

tui.render(App)
