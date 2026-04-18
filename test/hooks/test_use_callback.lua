-- test/test_use_callback.lua — useCallback behavior.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_callback"

-- Wrapper identity stays the same when deps are unchanged.
function suite:test_callback_identity_stable_on_unchanged_deps()
    local seen = {}
    local function Comp()
        local cb = tui.useCallback(function() return 1 end, { "x" })
        seen[#seen + 1] = cb
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    b:rerender()
    b:rerender()
    lt.assertEquals(rawequal(seen[1], seen[2]), true)
    lt.assertEquals(rawequal(seen[2], seen[3]), true)
    b:unmount()
end

-- Wrapper identity is ALSO stable across dep change (React semantics).
-- The difference from useMemo: wrapper ref never changes; only the inner
-- fn it delegates to is swapped when deps change.
function suite:test_callback_new_identity_on_dep_change()
    local seen = {}
    local dep = "a"
    local function Comp()
        local cb = tui.useCallback(function() return dep end, { dep })
        seen[#seen + 1] = cb
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    dep = "b"
    b:rerender()
    lt.assertEquals(#seen, 2)
    lt.assertEquals(rawequal(seen[1], seen[2]), true)
    -- wrapper delegates to latest fn body
    lt.assertEquals(seen[1](), "b")
    b:unmount()
end

-- Wrapper sees the latest fn body on each call (no stale closure).
function suite:test_callback_sees_latest_fn_body_via_wrapper()
    local first_cb
    local iter = 1
    local function Comp()
        local cb = tui.useCallback(function() return iter end, { iter })
        if not first_cb then first_cb = cb end
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    lt.assertEquals(first_cb(), 1)
    iter = 2
    b:rerender()
    lt.assertEquals(first_cb(), 2)    -- same wrapper, new body
    iter = 3
    b:rerender()
    lt.assertEquals(first_cb(), 3)
    b:unmount()
end

-- nil deps: wrapper identity still stable, but slot.fn refreshes each render.
function suite:test_callback_nil_deps_wrapper_stable_body_refreshes()
    local seen = {}
    local iter = 1
    local function Comp()
        local cb = tui.useCallback(function() return iter end, nil)
        seen[#seen + 1] = cb
        return tui.Text { "" }
    end
    local b = testing.mount_bare(Comp)
    iter = 2
    b:rerender()
    iter = 3
    b:rerender()
    lt.assertEquals(rawequal(seen[1], seen[2]), true)
    lt.assertEquals(rawequal(seen[2], seen[3]), true)
    lt.assertEquals(seen[1](), 3)
    b:unmount()
end
