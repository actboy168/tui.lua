-- test/unit/test_clipboard.lua — unit tests for clipboard.lua
-- Tests OSC 52 sequence generation and base64 encoding.

local lt        = require "ltest"
local clipboard = require "tui.internal.clipboard"

local suite = lt.test "clipboard"

-- ---------------------------------------------------------------------------
-- Base64 encoder tests
-- ---------------------------------------------------------------------------

function suite:test_base64_empty()
    lt.assertEquals(clipboard._base64_encode(""), "")
end

function suite:test_base64_one_byte()
    -- "M" = 0x4D = 01001101; pads to 3 bytes → 01001101 00000000 00000000
    -- Indices: 010011 010000 000000 000000 → 19 16 0 0 → T Q = =
    lt.assertEquals(clipboard._base64_encode("M"), "TQ==")
end

function suite:test_base64_two_bytes()
    -- "Ma" = 0x4D 0x61
    lt.assertEquals(clipboard._base64_encode("Ma"), "TWE=")
end

function suite:test_base64_three_bytes()
    -- "Man" = 0x4D 0x61 0x6E → TWFu
    lt.assertEquals(clipboard._base64_encode("Man"), "TWFu")
end

function suite:test_base64_hello()
    lt.assertEquals(clipboard._base64_encode("Hello"), "SGVsbG8=")
end

function suite:test_base64_all_ascii()
    -- "Hello, World!" → standard known value
    lt.assertEquals(clipboard._base64_encode("Hello, World!"), "SGVsbG8sIFdvcmxkIQ==")
end

-- ---------------------------------------------------------------------------
-- OSC 52 sequence generation
-- ---------------------------------------------------------------------------

function suite:test_osc52_sequence()
    local captured = {}
    clipboard.set_writer(function(s) captured[#captured+1] = s end)
    local prev_enabled = clipboard._osc52_enabled
    clipboard._osc52_enabled = true

    clipboard.copy("Hi")

    clipboard._osc52_enabled = prev_enabled
    clipboard.set_writer(function(s) io.stdout:write(s) end)

    lt.assertEquals(#captured, 1)
    local seq = captured[1]
    -- Should start with ESC ] 52 ; c ;
    lt.assertNotNil(seq:find("\x1b]52;c;", 1, true), "OSC 52 prefix missing")
    -- Should end with BEL or tmux-style terminator.
    local ends_bel = seq:sub(-1) == "\x07"
    local ends_tmux = seq:sub(-2) == "\x1b\\"
    lt.assertTrue(ends_bel or ends_tmux, "OSC 52 must end with BEL or ST")
    -- Payload should be base64 of "Hi" = "SGk="
    lt.assertNotNil(seq:find("SGk=", 1, true), "base64 payload for 'Hi' missing")
end

function suite:test_osc52_disabled_by_default()
    -- When _osc52_enabled is false, copy() should NOT write an OSC 52 sequence.
    -- (It would fall through to CLI tools instead, which may silently fail in CI.)
    lt.assertFalse(clipboard._osc52_enabled,
        "_osc52_enabled should be false by default")
end

return suite
