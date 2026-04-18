-- test/test_use_memo.lua — useMemo behavior.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_memo"

-- First render invokes fn() once and returns its result.
function suite:test_memo_computes_on_mount()
    local calls = 0
    local captured
    local function Comp()
        local v = tui.useMemo(function() calls = calls + 1; return 42 end, {})
        captured = v
        return tui.Text { tostring(v) }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(calls, 1)
    lt.assertEquals(captured, 42)
    b:unmount()
end

-- When deps are unchanged (shallow-equal), fn is NOT re-invoked.
function suite:test_memo_cached_on_unchanged_deps()
    local calls = 0
    local function Comp()
        tui.useMemo(function() calls = calls + 1; return {} end, { 1, "a" })
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(calls, 1)
    b:rerender()
    b:rerender()
    lt.assertEquals(calls, 1)
    b:unmount()
end

-- When any dep changes, fn is re-invoked.
function suite:test_memo_recomputes_on_dep_change()
    local calls = 0
    local dep_a = 1
    local function Comp()
        tui.useMemo(function() calls = calls + 1; return dep_a end, { dep_a })
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(calls, 1)
    b:rerender()
    lt.assertEquals(calls, 1)
    dep_a = 2
    b:rerender()
    lt.assertEquals(calls, 2)
    b:rerender()
    lt.assertEquals(calls, 2)
    b:unmount()
end

-- Returned table identity is preserved across renders while cached.
function suite:test_memo_returns_identity_stable_table()
    local seen = {}
    local function Comp()
        local t = tui.useMemo(function() return { a = 1 } end, {})
        seen[#seen + 1] = t
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    b:rerender()
    b:rerender()
    lt.assertEquals(#seen, 3)
    lt.assertEquals(rawequal(seen[1], seen[2]), true)
    lt.assertEquals(rawequal(seen[2], seen[3]), true)
    b:unmount()
end

-- nil deps means recompute every render.
function suite:test_memo_nil_deps_recomputes_every_render()
    local calls = 0
    local function Comp()
        tui.useMemo(function() calls = calls + 1; return 1 end, nil)
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(calls, 1)
    b:rerender()
    b:rerender()
    lt.assertEquals(calls, 3)
    b:unmount()
end
