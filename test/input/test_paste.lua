-- test/input/test_paste.lua — tests for bracketed paste accumulation in
-- tui.input and the subscribe_paste API.

local lt        = require "ltest"
local input_mod = require "tui.internal.input"
local input_helpers = require "tui.testing.input"

local suite = lt.test "input_paste"

-- Helper: reset state before each test.
local function reset()
    input_mod._reset()
end

-- Full bracketed paste in one dispatch call (the common case).
function suite:test_single_chunk_paste()
    reset()
    local received = {}
    input_mod.subscribe_paste(function(text) received[#received + 1] = text end)

    input_mod.dispatch(input_helpers.raw("\x1b[200~hello world\x1b[201~"))

    lt.assertEquals(#received, 1)
    lt.assertEquals(received[1], "hello world")
end

-- Bracketed paste split across two dispatch calls (rare but valid).
function suite:test_multi_chunk_paste()
    reset()
    local received = {}
    input_mod.subscribe_paste(function(text) received[#received + 1] = text end)

    input_mod.dispatch(input_helpers.raw("\x1b[200~foo"))
    lt.assertEquals(#received, 0, "paste_end not yet seen")

    input_mod.dispatch(input_helpers.raw("bar\x1b[201~"))
    lt.assertEquals(#received, 1)
    lt.assertEquals(received[1], "foobar")
end

-- During pasting, regular key events must NOT be dispatched to subscribe().
function suite:test_pasting_suppresses_key_events()
    reset()
    local keys_seen = {}
    local paste_seen = {}
    input_mod.subscribe(function(_, key)
        keys_seen[#keys_seen + 1] = key.name
    end)
    input_mod.subscribe_paste(function(text)
        paste_seen[#paste_seen + 1] = text
    end)

    input_mod.dispatch(input_helpers.raw("\x1b[200~abc\x1b[201~"))

    -- Only a single paste event, no individual char events.
    lt.assertEquals(#paste_seen, 1)
    for _, k in ipairs(keys_seen) do
        lt.assertNotEquals(k, "char",
            "char event leaked during bracketed paste")
    end
end

-- subscribe_paste returns a cleanup function; after calling it the handler
-- must no longer receive events.
function suite:test_unsubscribe()
    reset()
    local count = 0
    local unsub = input_mod.subscribe_paste(function() count = count + 1 end)
    input_mod.dispatch(input_helpers.raw("\x1b[200~x\x1b[201~"))
    lt.assertEquals(count, 1)

    unsub()
    input_mod.dispatch(input_helpers.raw("\x1b[200~y\x1b[201~"))
    lt.assertEquals(count, 1, "handler called after unsubscribe")
end

-- _reset() clears in-progress paste state so a subsequent normal dispatch
-- doesn't accidentally carry over leftover _paste_buf.
function suite:test_reset_clears_paste_state()
    reset()
    local received = {}
    input_mod.subscribe_paste(function(text) received[#received + 1] = text end)

    -- Start a paste but don't finish it.
    input_mod.dispatch(input_helpers.raw("\x1b[200~partial"))
    lt.assertEquals(#received, 0)

    -- Reset mid-paste, then dispatch a complete new paste.
    input_mod._reset()
    input_mod.subscribe_paste(function(text) received[#received + 1] = text end)
    input_mod.dispatch(input_helpers.raw("\x1b[200~fresh\x1b[201~"))

    lt.assertEquals(#received, 1)
    lt.assertEquals(received[1], "fresh")
end

-- Multi-line paste (newlines inside the paste text).
function suite:test_multiline_paste()
    reset()
    local received = {}
    input_mod.subscribe_paste(function(text) received[#received + 1] = text end)

    input_mod.dispatch(input_helpers.raw("\x1b[200~line1\nline2\x1b[201~"))

    lt.assertEquals(#received, 1)
    lt.assertEquals(received[1], "line1\nline2")
end

function suite:test_multichunk_paste_via_helper_normalized_bytes()
    reset()
    local received = {}
    input_mod.subscribe_paste(function(text) received[#received + 1] = text end)

    input_mod.dispatch(input_helpers.posix("\x1b[200~mid"))
    input_mod.dispatch(input_helpers.posix("dle\x1b[201~"))

    lt.assertEquals(#received, 1)
    lt.assertEquals(received[1], "middle")
end
