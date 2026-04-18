-- test/test_grapheme.lua — unit tests for tui_core.wcwidth.grapheme_next.
--
-- Stage 12: verifies the UAX#29 subset (GB6/7/8 Hangul jamo, GB9/9a extend,
-- GB11 approximated ZWJ, GB12/13 regional indicator pairs, VS16 promotion).

local lt = require "ltest"
local wc = require "tui_core".wcwidth

local suite = lt.test "grapheme"

-- Collect all clusters in `s` into a list of { str, width, clen } triples.
local function split(s)
    local out = {}
    local n, i = #s, 1
    while i <= n do
        local ch, cw, ni = wc.grapheme_next(s, i)
        if ch == "" then break end
        out[#out + 1] = { str = ch, width = cw, clen = #ch }
        i = ni
    end
    return out
end

function suite:test_ascii()
    local c = split("hello")
    lt.assertEquals(#c, 5)
    lt.assertEquals(c[1].str, "h")
    lt.assertEquals(c[1].width, 1)
    lt.assertEquals(c[1].clen, 1)
    lt.assertEquals(c[5].str, "o")
end

function suite:test_combining_mark_fuses()
    -- "e" + COMBINING ACUTE (U+0301, 2 bytes UTF-8) = 1 cluster
    local c = split("e\204\129")
    lt.assertEquals(#c, 1)
    lt.assertEquals(c[1].width, 1)
    lt.assertEquals(c[1].clen, 3)
    lt.assertEquals(c[1].str, "e\204\129")
end

function suite:test_combining_between_bases()
    -- "a" "b+acute" "c" -> 3 clusters
    local c = split("ab\204\129c")
    lt.assertEquals(#c, 3)
    lt.assertEquals(c[1].str, "a")
    lt.assertEquals(c[2].str, "b\204\129")
    lt.assertEquals(c[2].width, 1)
    lt.assertEquals(c[3].str, "c")
end

function suite:test_zwj_family()
    -- 👨(4B) ZWJ(3B) 👩(4B) ZWJ(3B) 👧(4B) = 18 bytes, 1 cluster
    local s = "\240\159\145\168\226\128\141\240\159\145\169\226\128\141\240\159\145\167"
    local c = split(s)
    lt.assertEquals(#c, 1)
    lt.assertEquals(c[1].clen, 18)
    lt.assertEquals(c[1].width, 2)   -- base 👨 is width 2
end

function suite:test_vs16_promotes_width()
    -- ❤ (U+2764, 3 bytes, wcwidth=1) + VS16 (U+FE0F, 3 bytes, zero-width)
    -- → 1 cluster, width 2 (emoji presentation).
    local s = "\226\157\164\239\184\143"
    local c = split(s)
    lt.assertEquals(#c, 1)
    lt.assertEquals(c[1].clen, 6)
    lt.assertEquals(c[1].width, 2)
end

function suite:test_vs15_keeps_base_width()
    -- ❤ + VS15 (U+FE0E) → cluster width 1 (text presentation).
    local s = "\226\157\164\239\184\142"
    local c = split(s)
    lt.assertEquals(#c, 1)
    lt.assertEquals(c[1].clen, 6)
    lt.assertEquals(c[1].width, 1)
end

function suite:test_regional_indicator_pair()
    -- 🇯🇵 = U+1F1EF U+1F1F5, each is 4B → 1 cluster, width 2
    local s = "\240\159\135\175\240\159\135\181"
    local c = split(s)
    lt.assertEquals(#c, 1)
    lt.assertEquals(c[1].clen, 8)
    lt.assertEquals(c[1].width, 2)
end

function suite:test_two_flags_pair_off()
    -- 🇯🇵🇺🇸 = JP + US, 16 bytes → 2 clusters each width 2
    local s = "\240\159\135\175\240\159\135\181"
         .. "\240\159\135\186\240\159\135\184"
    local c = split(s)
    lt.assertEquals(#c, 2)
    lt.assertEquals(c[1].width, 2); lt.assertEquals(c[1].clen, 8)
    lt.assertEquals(c[2].width, 2); lt.assertEquals(c[2].clen, 8)
end

function suite:test_odd_regional_indicator_splits()
    -- JP + lone RI → 2 clusters: JP(w=2, 8B) + stray U(w=1, 4B)
    local s = "\240\159\135\175\240\159\135\181\240\159\135\186"
    local c = split(s)
    lt.assertEquals(#c, 2)
    lt.assertEquals(c[1].width, 2); lt.assertEquals(c[1].clen, 8)
    lt.assertEquals(c[2].width, 1); lt.assertEquals(c[2].clen, 4)
end

function suite:test_hangul_jamo_fuses()
    -- ㅎ (U+1112, 3B) + ㅏ (U+1161, 3B) + ㄴ (U+11AB, 3B) = 한 (LVT) → 1 cluster, w=2
    local s = "\225\132\146\225\133\161\225\134\171"
    local c = split(s)
    lt.assertEquals(#c, 1)
    lt.assertEquals(c[1].clen, 9)
    lt.assertEquals(c[1].width, 2)
end

function suite:test_hangul_precomposed()
    -- 한 = U+D55C (3B, already LVT precomposed) → 1 cluster w=2
    local s = "\237\149\156"
    local c = split(s)
    lt.assertEquals(#c, 1)
    lt.assertEquals(c[1].clen, 3)
    lt.assertEquals(c[1].width, 2)
end

function suite:test_eos_returns_empty()
    local ch, cw, ni = wc.grapheme_next("abc", 4)
    lt.assertEquals(ch, "")
    lt.assertEquals(cw, 0)
    lt.assertEquals(ni, 4)
end

function suite:test_string_width_uses_grapheme()
    -- ❤VS16 x = 2 + 1 = 3 (not 2 if VS16 were ignored)
    lt.assertEquals(wc.string_width("\226\157\164\239\184\143x"), 3)
    -- "e"+acute + "b" = 1 + 1 = 2
    lt.assertEquals(wc.string_width("e\204\129b"), 2)
end
