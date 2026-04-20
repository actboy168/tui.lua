local lt = require "ltest"
local input_helpers = require "tui.testing.input"
local input = require "tui.internal.input"
local focus = require "tui.internal.focus"

local suite = lt.test "terminal_normalize"

local function ev(vk, ch, extra)
    local t = {
        vk = vk,
        char = ch,
    }
    if extra then
        for k, v in pairs(extra) do
            t[k] = v
        end
    end
    return t
end

function suite:setup()
    input._reset()
    focus._reset()
end

function suite:teardown()
    input._reset()
    focus._reset()
end

function suite:test_raw_passthrough()
    lt.assertEquals(input_helpers.raw("a\27[A"), "a\27[A")
end

function suite:test_posix_passthrough()
    lt.assertEquals(input_helpers.posix("hello\r"), "hello\r")
end

function suite:test_windows_ime_confirm_space_is_swallowed()
    local out = input_helpers.windows {
        ev(0xE5, ""),   -- VK_PROCESSKEY
        ev(0, "中"),
        ev(0, "午"),
        ev(0x20, " "),  -- VK_SPACE confirmation echo
    }
    lt.assertEquals(out, "中午")
end

function suite:test_windows_plain_space_is_preserved()
    local out = input_helpers.windows {
        ev(0x20, " "),
    }
    lt.assertEquals(out, " ")
end

function suite:test_windows_ctrl_enter_normalizes_to_csi_u()
    local evs = input_helpers.parse {
        platform = "windows",
        events = {
            ev(0, "\r", { ctrl = true }),
        },
    }
    lt.assertEquals(#evs, 1)
    lt.assertEquals(evs[1].name, "enter")
    lt.assertEquals(evs[1].ctrl, true)
end

function suite:test_windows_shift_enter_normalizes_to_csi_u()
    local evs = input_helpers.parse {
        platform = "windows",
        events = {
            ev(0, "\r", { shift = true }),
        },
    }
    lt.assertEquals(#evs, 1)
    lt.assertEquals(evs[1].name, "enter")
    lt.assertEquals(evs[1].shift, true)
end

function suite:test_windows_arrow_keys_normalize_to_csi()
    local evs = input_helpers.parse {
        platform = "windows",
        events = {
            ev(0x26, ""),
            ev(0x27, ""),
            ev(0x24, ""),
            ev(0x23, ""),
        },
    }
    lt.assertEquals(#evs, 4)
    lt.assertEquals(evs[1].name, "up")
    lt.assertEquals(evs[2].name, "right")
    lt.assertEquals(evs[3].name, "home")
    lt.assertEquals(evs[4].name, "end")
end

function suite:test_windows_confirm_space_then_real_space_kept()
    local out = input_helpers.windows {
        ev(0xE5, ""),
        ev(0, "中"),
        ev(0x20, " "),
        ev(0x20, " "),
    }
    lt.assertEquals(out, "中 ")
end

function suite:test_windows_ascii_after_processkey_clears_pending_swallow()
    local out = input_helpers.windows {
        ev(0xE5, ""),
        ev(0, "a"),
        ev(0x20, " "),
    }
    lt.assertEquals(out, "a ")
end

function suite:test_windows_fixture_can_drive_input_dispatch()
    local got = {}
    input.subscribe(function(str, key)
        got[#got + 1] = { str = str, name = key.name }
    end)
    input.dispatch(input_helpers.windows {
        ev(0, "你"),
        ev(0, "好"),
    })
    lt.assertEquals(#got, 2)
    lt.assertEquals(got[1].str, "你")
    lt.assertEquals(got[2].str, "好")
end
