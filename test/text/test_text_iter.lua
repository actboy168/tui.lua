-- test/test_text_iter.lua — coverage for tui.text.iter (iter_chars closure).

local lt   = require "ltest"
local text = require "tui.text"

local suite = lt.test "text_iter"

function suite:test_ascii_chars()
    local chars = {}
    for ch, w in text.iter("abc") do
        chars[#chars + 1] = { ch, w }
    end
    lt.assertEquals(chars, {
        { "a", 1 },
        { "b", 1 },
        { "c", 1 },
    })
end

function suite:test_cjk_wide_chars()
    local chars = {}
    for ch, w in text.iter("\xe4\xb8\xad") do  -- 中
        chars[#chars + 1] = { ch, w }
    end
    lt.assertEquals(chars, {
        { "\xe4\xb8\xad", 2 },
    })
end

function suite:test_empty_string()
    local found = false
    for _ in text.iter("") do
        found = true
    end
    lt.assertEquals(found, false)
end

function suite:test_combining_mark_attaches_to_base()
    -- e + combining acute (U+0301) should form one grapheme cluster
    local chars = {}
    for ch, w in text.iter("e\xcc\x81") do
        chars[#chars + 1] = { ch, w }
    end
    lt.assertEquals(#chars, 1)
    lt.assertEquals(chars[1][2], 1)  -- width = 1 (base char width)
end

function suite:test_newline_delivered_as_cluster()
    local chars = {}
    for ch, w in text.iter("a\nb") do
        chars[#chars + 1] = { ch, w }
    end
    lt.assertEquals(#chars, 3)
    lt.assertEquals(chars[2][1], "\n")
    lt.assertEquals(chars[2][2], 0)  -- control char width = 0
end

function suite:test_mixed_ascii_and_cjk()
    local chars = {}
    for ch, w in text.iter("a\xe4\xb8\xadb") do  -- a中b
        chars[#chars + 1] = { ch, w }
    end
    lt.assertEquals(#chars, 3)
    lt.assertEquals(chars[1], { "a", 1 })
    lt.assertEquals(chars[2], { "\xe4\xb8\xad", 2 })
    lt.assertEquals(chars[3], { "b", 1 })
end
