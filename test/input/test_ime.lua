-- test/input/test_ime.lua — unit & integration tests for IME support.
local lt       = require "ltest"
local tui      = require "tui"
local testing  = require "tui.testing"
local info     = require "tui.terminal_info"
local ime_mod  = require "tui.ime"

local test_ime = lt.test "ime"

-- ---------------------------------------------------------------------------
-- 1. terminal_info: terminal type detection

function test_ime:test_detect_returns_string()
    local t = info.detect()
    lt.assertEquals(type(t), "string")
    -- Must be one of the known identifiers.
    local valid = {
        iterm2 = true, kitty = true, apple_terminal = true,
        alacritty = true, wezterm = true, unknown = true,
    }
    lt.assertEquals(valid[t] ~= nil, true)
end

function test_ime:test_capabilities_returns_table()
    local caps = info.capabilities()
    lt.assertEquals(type(caps), "table")
    lt.assertEquals(type(caps.ime_osc1337), "boolean")
    lt.assertEquals(type(caps.ime_kitty_proto), "boolean")
    lt.assertEquals(type(caps.ime_csi_cup), "boolean")
end

function test_ime:test_csi_cup_always_true()
    -- Every terminal supports the CSI CUP fallback.
    local caps = info.capabilities()
    lt.assertEquals(caps.ime_csi_cup, true)
end

function test_ime:test_terminal_type_cached()
    local a = info.terminal_type()
    local b = info.terminal_type()
    lt.assertEquals(a, b)
end

function test_ime:test_reset_clears_cache()
    info.terminal_type()
    info._reset()
    -- After reset, next call re-detects (still returns a valid string).
    local t = info.terminal_type()
    lt.assertEquals(type(t), "string")
end

-- ---------------------------------------------------------------------------
-- 2. ime module: sequence generation

function test_ime:test_csi_cup_sequence_format()
    local seq = ime_mod._csi_cup_sequence(5, 3)
    -- Should contain DECSC + CUP(3,5) + DECRC
    lt.assertEquals(seq:find("\0277", 1, true) ~= nil, true)     -- DECSC
    lt.assertEquals(seq:find("\0278", 1, true) ~= nil, true)     -- DECRC
    lt.assertEquals(seq:find("\027%[3;5H") ~= nil, true) -- CUP row=3 col=5
end

function test_ime:test_iterm2_sequence_contains_osc1337()
    local seq = ime_mod._iterm2_sequence(10, 2)
    lt.assertEquals(seq:find("1337;SetMark", 1, true) ~= nil, true)
    lt.assertEquals(seq:find("\0277", 1, true) ~= nil, true)       -- DECSC
    lt.assertEquals(seq:find("\0278", 1, true) ~= nil, true)       -- DECRC
end

function test_ime:test_kitty_sequence_is_cup_fallback()
    -- kitty sequence is the same as CSI CUP (no OSC 1337).
    local kitty_seq = ime_mod._kitty_sequence(7, 4)
    local cup_seq   = ime_mod._csi_cup_sequence(7, 4)
    lt.assertEquals(kitty_seq, cup_seq)
end

-- ---------------------------------------------------------------------------
-- 3. ime.set_pos: dispatches through fake terminal

function test_ime:test_set_pos_writes_to_terminal()
    local h = testing.render(function()
        return tui.Text { "hello" }
    end)
    -- Clear any prior ansi buffer content.
    h:clear_ansi()

    ime_mod.set_pos(h._terminal, 5, 3)
    local ansi = h:ansi()
    -- Something should have been written (DECSC + CUP + DECRC at minimum).
    lt.assertEquals(#ansi > 0, true)
    h:unmount()
end

function test_ime:test_set_pos_nil_coords_noop()
    local h = testing.render(function()
        return tui.Text { "hello" }
    end)
    h:clear_ansi()
    ime_mod.set_pos(h._terminal, nil, nil)
    lt.assertEquals(h:ansi(), "")
    ime_mod.set_pos(h._terminal, 5, nil)
    lt.assertEquals(h:ansi(), "")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 4. IME position tracked in harness

function test_ime:test_ime_pos_after_paint()
    local value, setValue = "", nil
    local function App()
        local v, setV = tui.useState("")
        value, setValue = v, setV
        return tui.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- After initial render with focused TextInput, IME pos should be set.
    local col, row = h:ime_pos()
    lt.assertEquals(col ~= nil, true)
    lt.assertEquals(row ~= nil, true)
    lt.assertEquals(col, 1)  -- caret at col 1 (1-based, first char)
    lt.assertEquals(row, 1)  -- first row

    h:unmount()
end

function test_ime:test_ime_pos_updates_after_typing()
    local setValue = nil
    local function App()
        local v, setV = tui.useState("")
        setValue = setV
        return tui.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    h:type("abc")
    local col, row = h:ime_pos()
    lt.assertEquals(col ~= nil, true)
    -- After typing "abc", caret is after "c" at column 4 (1-based).
    lt.assertEquals(col, 4)
    lt.assertEquals(row, 1)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. Composing text: composing → confirm

function test_ime:test_composing_then_confirm()
    local lastValue = ""
    local function App()
        local v, setV = tui.useState("")
        lastValue = v
        return tui.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- Simulate IME composing: user types pinyin "ni".
    h:type_composing("ni")
    -- Composing text is shown but not committed.
    lt.assertEquals(lastValue, "")

    -- Simulate IME confirmation: user selects "你".
    h:type_composing_confirm("你")
    -- The confirmed text is now in the value.
    lt.assertEquals(lastValue, "你")

    h:unmount()
end

function test_ime:test_composing_cancel_by_escape()
    local lastValue = ""
    local function App()
        local v, setV = tui.useState("")
        lastValue = v
        return tui.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- Start composing.
    h:type_composing("hao")
    lt.assertEquals(lastValue, "")

    -- Cancel with Escape.
    h:press("escape")
    lt.assertEquals(lastValue, "")

    h:unmount()
end

function test_ime:test_composing_shown_at_caret()
    local function App()
        local v, setV = tui.useState("ab")
        return tui.TextInput { value = v, onChange = setV, width = 20 }
    end
    local h = testing.render(App)

    -- Move caret to position 1 (between 'a' and 'b').
    h:press("left")

    -- Start composing — the composing text appears between 'a' and 'b'.
    h:type_composing("x")
    -- Value should still be "ab" (composing text not committed).
    -- The visual display includes composing text but value is unchanged.
    local col, row = h:ime_pos()
    lt.assertEquals(col ~= nil, true)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 6. Focus linkage: composing cleared on blur

function test_ime:test_composing_cleared_on_focus_loss()
    local lastValue = ""
    local function App()
        local v1, setV1 = tui.useState("")
        local v2, setV2 = tui.useState("")
        lastValue = v1
        return tui.Box {
            flexDirection = "column",
            tui.TextInput { value = v1, onChange = setV1, width = 20, focusId = "first" },
            tui.TextInput { value = v2, onChange = setV2, width = 20, focusId = "second" },
        }
    end
    local h = testing.render(App)

    -- Start composing in the first TextInput.
    h:type_composing("test")

    -- Tab to the next TextInput — focus moves away.
    h:press("tab")

    -- The first TextInput's value should remain empty (composing was cancelled).
    lt.assertEquals(lastValue, "")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 7. IME position cleared when no cursor

function test_ime:test_no_ime_pos_without_focused_input()
    local function App()
        return tui.Text { "no input here" }
    end
    local h = testing.render(App)

    -- No focused TextInput → no IME position.
    local col, row = h:ime_pos()
    lt.assertEquals(col, nil)

    h:unmount()
end
