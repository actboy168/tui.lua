-- test/test_wcwidth.lua — unit tests for tui_core.wcwidth.

local lt      = require "ltest"
local wc      = require "tui.core".wcwidth

local suite = lt.test "wcwidth"

function suite:test_ascii()
    lt.assertEquals(wc.wcwidth(string.byte("a")), 1)
    lt.assertEquals(wc.wcwidth(string.byte("Z")), 1)
    lt.assertEquals(wc.wcwidth(string.byte("0")), 1)
    lt.assertEquals(wc.wcwidth(string.byte(" ")), 1)
end

function suite:test_control_chars_are_negative()
    lt.assertEquals(wc.wcwidth(0x00), 0)       -- NUL by convention
    lt.assertEquals(wc.wcwidth(0x1B), -1)      -- ESC
    lt.assertEquals(wc.wcwidth(0x7F), -1)      -- DEL
    lt.assertEquals(wc.wcwidth(0x08), -1)      -- BS
end

function suite:test_cjk_wide()
    lt.assertEquals(wc.wcwidth(0x4E2D), 2)     -- 中
    lt.assertEquals(wc.wcwidth(0x65E5), 2)     -- 日
    lt.assertEquals(wc.wcwidth(0xAC00), 2)     -- 가 (Hangul)
    lt.assertEquals(wc.wcwidth(0xFF21), 2)     -- Fullwidth A
end

function suite:test_emoji_presentation()
    lt.assertEquals(wc.wcwidth(0x1F600), 2)    -- 😀
    lt.assertEquals(wc.wcwidth(0x1F4A9), 2)    -- 💩
    lt.assertEquals(wc.wcwidth(0x2615), 2)     -- ☕ (emoji presentation)
end

function suite:test_zero_width()
    lt.assertEquals(wc.wcwidth(0x0301), 0)     -- Combining acute accent
    lt.assertEquals(wc.wcwidth(0x200D), 0)     -- ZWJ
    lt.assertEquals(wc.wcwidth(0x200B), 0)     -- ZWSP
    lt.assertEquals(wc.wcwidth(0xFE0F), 0)     -- Variation Selector-16
end

function suite:test_string_width_ascii()
    lt.assertEquals(wc.string_width(""), 0)
    lt.assertEquals(wc.string_width("hello"), 5)
    lt.assertEquals(wc.string_width("hi world"), 8)
end

function suite:test_string_width_cjk()
    lt.assertEquals(wc.string_width("中"), 2)
    lt.assertEquals(wc.string_width("中文"), 4)
    lt.assertEquals(wc.string_width("中a"), 3)
    lt.assertEquals(wc.string_width("a中b"), 4)
end

function suite:test_string_width_emoji()
    lt.assertEquals(wc.string_width("😀"), 2)
    lt.assertEquals(wc.string_width("a😀b"), 4)
end

function suite:test_string_width_combining()
    -- "e" + combining acute = 1 column (combining mark is zero-width)
    lt.assertEquals(wc.string_width("e\204\129"), 1)
    -- Precomposed 4-byte emoji + VS-16 = still 2 (VS16 is zero-width).
    -- Using 😀 (U+1F600) which IS in our wide table, unlike bare U+2600.
    lt.assertEquals(wc.string_width("\240\159\152\128\239\184\143"), 2)
end

function suite:test_char_width_advances()
    local cw, ni = wc.char_width("中a", 1)
    lt.assertEquals(cw, 2)
    lt.assertEquals(ni, 4)  -- "中" = 3 bytes
    cw, ni = wc.char_width("中a", ni)
    lt.assertEquals(cw, 1)
    lt.assertEquals(ni, 5)
end

function suite:test_char_width_past_end()
    local cw, ni = wc.char_width("ab", 3)
    lt.assertEquals(cw, 0)
    lt.assertEquals(ni, 3)  -- past end returns n+1
end

function suite:test_invalid_utf8_doesnt_crash()
    -- Lone continuation byte → replacement (zero-ish), should not throw.
    local w = wc.string_width("\128")
    lt.assertEquals(type(w), "number")
end
