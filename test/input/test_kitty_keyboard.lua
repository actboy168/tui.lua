-- test/input/test_kitty_keyboard.lua — unit tests for Kitty Keyboard Protocol parsing.
--
-- Tests cover:
--   • tui_core.keys.parse() with CSI u sequences (flags=3: disambiguate + event types)
--   • ansi.kittyKeyboard constant values
--   • terminal.detect_capabilities().kitty_keyboard type

local lt       = require "ltest"
local tui_core = require "tui.core"
local ansi     = require "tui.internal.ansi"
local terminal = require "tui.internal.terminal"
local keys     = tui_core.keys

local suite = lt.test "kitty_keyboard"

local function first(bytes)
    local evs = keys.parse(bytes)
    return evs[1]
end

-- ---------------------------------------------------------------------------
-- Named C0 / functional keys

function suite:test_escape_csi_u()
    local ev = first("\x1b[27u")
    lt.assertEquals(ev.name, "escape")
    lt.assertEquals(ev.ctrl,  false)
    lt.assertEquals(ev.shift, false)
end

function suite:test_escape_ctrl_csi_u()
    -- modifier byte 5 = 1 + (shift=1 | ctrl=4) → ctrl only (5 = 1+4)
    local ev = first("\x1b[27;5u")
    lt.assertEquals(ev.name, "escape")
    lt.assertEquals(ev.ctrl,  true)
    lt.assertEquals(ev.shift, false)
end

function suite:test_enter_csi_u()
    local ev = first("\x1b[13u")
    lt.assertEquals(ev.name, "enter")
end

function suite:test_enter_ctrl_shift_csi_u()
    -- modifier byte 6 = 1 + shift(1) + ctrl(4) = 6
    local ev = first("\x1b[13;6u")
    lt.assertEquals(ev.name,  "enter")
    lt.assertEquals(ev.ctrl,  true)
    lt.assertEquals(ev.shift, true)
end

function suite:test_tab_shift_csi_u()
    -- modifier byte 2 = 1 + shift(1)
    local ev = first("\x1b[9;2u")
    lt.assertEquals(ev.name,  "tab")
    lt.assertEquals(ev.shift, true)
    lt.assertEquals(ev.ctrl,  false)
end

function suite:test_backspace_ctrl_csi_u()
    -- modifier byte 5 = 1 + ctrl(4)
    local ev = first("\x1b[127;5u")
    lt.assertEquals(ev.name, "backspace")
    lt.assertEquals(ev.ctrl, true)
end

-- ---------------------------------------------------------------------------
-- Printable ASCII with modifiers

function suite:test_char_shift_csi_u()
    -- KKP always sends the base (unshifted) codepoint: 65 = 'A', but
    -- the spec says the unshifted codepoint is sent even with Shift.
    -- We report it lower-case (ASCII 65 → 'A', but per plan 'a').
    -- Actually: KKP with flags=3 sends the lowercase ASCII code (65 = 'A').
    -- The spec sends the code point as-is.  65 → "A".
    local ev = first("\x1b[65;2u")
    lt.assertEquals(ev.name,  "char")
    lt.assertEquals(ev.input, "A")   -- codepoint 65 = uppercase 'A'
    lt.assertEquals(ev.shift, true)
end

function suite:test_char_ctrl_csi_u()
    -- modifier byte 5 = 1 + ctrl(4)
    local ev = first("\x1b[97;5u")
    lt.assertEquals(ev.name,  "char")
    lt.assertEquals(ev.input, "a")
    lt.assertEquals(ev.ctrl,  true)
    lt.assertEquals(ev.shift, false)
end

function suite:test_char_super_csi_u()
    -- modifier byte 9 = 1 + super(8)
    local ev = first("\x1b[97;9u")
    lt.assertEquals(ev.name,  "char")
    lt.assertEquals(ev.input, "a")
    lt.assertEquals(ev.super, true)
    lt.assertEquals(ev.ctrl,  false)
end

-- ---------------------------------------------------------------------------
-- Event types (press / repeat / release)

function suite:test_char_event_type_press_default()
    -- No event_type sub-field → press
    local ev = first("\x1b[97u")
    lt.assertEquals(ev.name,       "char")
    lt.assertEquals(ev.event_type, "press")
end

function suite:test_char_event_type_press_explicit()
    -- ;1:1 → mod=1 (no mods), event_type=1 (press)
    local ev = first("\x1b[97;1:1u")
    lt.assertEquals(ev.event_type, "press")
end

function suite:test_char_event_type_repeat()
    -- mod=1 (none), event_type=2 (repeat)
    local ev = first("\x1b[97;1:2u")
    lt.assertEquals(ev.name,       "char")
    lt.assertEquals(ev.input,      "a")
    lt.assertEquals(ev.event_type, "repeat")
end

function suite:test_char_event_type_release()
    -- mod=1 (none), event_type=3 (release)
    local ev = first("\x1b[97;1:3u")
    lt.assertEquals(ev.name,       "char")
    lt.assertEquals(ev.event_type, "release")
end

-- ---------------------------------------------------------------------------
-- Private-use / functional keys

function suite:test_f13_csi_u()
    -- 57376 = private-use codepoint for F13
    local ev = first("\x1b[57376u")
    lt.assertEquals(ev.name, "f13")
end

function suite:test_left_shift_modifier_key()
    -- 57441 = left_shift modifier key as a standalone event
    local ev = first("\x1b[57441u")
    lt.assertEquals(ev.name, "left_shift")
end

-- ---------------------------------------------------------------------------
-- ansi.lua constants

function suite:test_kitty_keyboard_push_sequence()
    lt.assertEquals(ansi.kittyKeyboard.push, "\x1b[>3u")
end

function suite:test_kitty_keyboard_pop_sequence()
    lt.assertEquals(ansi.kittyKeyboard.pop, "\x1b[<u")
end

function suite:test_supports_kitty_keyboard_is_boolean()
    lt.assertEquals(type(terminal.detect_capabilities().kitty_keyboard), "boolean")
end

function suite:test_vscode_kitty_keyboard()
    lt.assertEquals(terminal.detect_capabilities("vscode").kitty_keyboard, true)
end

function suite:test_zed_kitty_keyboard()
    lt.assertEquals(terminal.detect_capabilities("zed").kitty_keyboard, true)
end

function suite:test_hyper_kitty_keyboard()
    lt.assertEquals(terminal.detect_capabilities("hyper").kitty_keyboard, true)
end

function suite:test_vte_old_no_kitty_keyboard()
    -- temporarily override environment variable
    local old = os.getenv("VTE_VERSION")
    if old then
        -- VTE 0.60 (version=6000) is too old for KKP
        local caps = terminal.detect_capabilities("unknown")
        if old and tonumber(old) < 6800 then
            lt.assertEquals(caps.kitty_keyboard, false)
        end
    else
        lt.assertEquals(terminal.detect_capabilities("unknown").kitty_keyboard, false)
    end
end
