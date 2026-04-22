local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "testing_modules"

local function mouse_sig(ev)
    return table.concat({
        ev.name,
        ev.type or "",
        tostring(ev.button),
        tostring(ev.x),
        tostring(ev.y),
        tostring(ev.scroll),
        tostring(ev.shift),
        tostring(ev.meta),
        tostring(ev.ctrl),
    }, "|")
end

function suite:test_input_resolve_key_dispatches_same_semantics_as_press()
    local events = {}
    local function App()
        tui.useInput(function(_, key)
            events[#events + 1] = key
        end)
        return tui.Text { "" }
    end

    local b = testing.mount_bare(App)
    b:dispatch(testing.input.resolve_key("shift+up"))
    b:press("shift+up")

    lt.assertEquals(#events, 2)
    lt.assertEquals(events[1].name, "up")
    lt.assertEquals(events[1].shift, true)
    lt.assertEquals(events[2].name, "up")
    lt.assertEquals(events[2].shift, true)
    b:unmount()
end

function suite:test_input_resolve_key_keeps_printable_chars_on_type_path()
    lt.assertNil(testing.input.resolve_key("a"))
    lt.assertNil(testing.input.resolve_key("中"))
end

function suite:test_input_paste_helper_matches_harness_paste()
    local pasted = {}
    local function App()
        tui.usePaste(function(text)
            pasted[#pasted + 1] = text
        end)
        return tui.Text { "" }
    end

    local h = testing.render(App, { cols = 10, rows = 1 })
    h:dispatch(testing.input.paste("alpha"))
    h:paste("beta")

    h:rerender()

    lt.assertEquals(#pasted, 2)
    lt.assertEquals(pasted[1], "alpha")
    lt.assertEquals(pasted[2], "beta")
    h:unmount()
end

function suite:test_mouse_harness_encoder_matches_sgr_spec()
    local via_harness = testing.mouse.harness("down", 1, 5, 3, {
        shift = true,
        ctrl = true,
    })
    local via_spec = testing.mouse.sgr {
        type = "down",
        button = 1,
        x = 5,
        y = 3,
        shift = true,
        ctrl = true,
    }

    lt.assertEquals(via_harness, via_spec)
end

function suite:test_harness_mouse_matches_helper_dispatch()
    local events = {}
    local function App()
        tui.useMouse(function(ev)
            events[#events + 1] = ev
        end)
        return tui.Text { "" }
    end

    local h = testing.render(App, { cols = 10, rows = 1 })
    h:mouse("scroll_down", nil, 4, 2, { meta = true })
    h:dispatch(testing.mouse.harness("scroll_down", nil, 4, 2, { meta = true }))

    lt.assertEquals(#events, 2)
    lt.assertEquals(mouse_sig(events[1]), mouse_sig(events[2]))
    h:unmount()
end

function suite:test_mouse_helper_parse_matches_harness_semantics()
    local ev = testing.mouse.parse_sgr {
        type = "move",
        button = 2,
        x = 7,
        y = 9,
        ctrl = true,
    }[1]

    lt.assertEquals(ev.name, "mouse")
    lt.assertEquals(ev.type, "move")
    lt.assertEquals(ev.button, 2)
    lt.assertEquals(ev.x, 7)
    lt.assertEquals(ev.y, 9)
    lt.assertEquals(ev.ctrl, true)
end

return suite
