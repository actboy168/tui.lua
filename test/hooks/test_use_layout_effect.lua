-- test/hooks/test_use_layout_effect.lua — useLayoutEffect behavior.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_layout_effect"

-- Runs synchronously during render, before tree is returned.
function suite:test_runs_synchronously_during_render()
    local order = {}
    local function Comp()
        tui.useLayoutEffect(function()
            order[#order + 1] = "layout"
        end, {})
        order[#order + 1] = "render"
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(order[1], "render")
    lt.assertEquals(order[2], "layout")
    b:unmount()
end

-- Runs cleanup before re-running on dep change.
function suite:test_cleanup_before_rerun()
    local order = {}
    local n = 1
    local function setN(v) n = v end
    local function Comp()
        local val = n
        tui.useLayoutEffect(function()
            order[#order + 1] = "run" .. tostring(val)
            return function()
                order[#order + 1] = "cleanup" .. tostring(val)
            end
        end, { val })
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(order[1], "run1")
    setN(2)
    b:rerender()
    lt.assertEquals(order[2], "cleanup1")
    lt.assertEquals(order[3], "run2")
    b:unmount()
    lt.assertEquals(order[4], "cleanup2")
end

-- Mount-once with empty deps.
function suite:test_empty_deps_runs_once()
    local count = 0
    local function Comp()
        tui.useLayoutEffect(function()
            count = count + 1
        end, {})
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(count, 1)
    b:rerender()
    lt.assertEquals(count, 1)
    b:rerender()
    lt.assertEquals(count, 1)
    b:unmount()
end

-- Nil deps runs every render.
function suite:test_nil_deps_runs_every_render()
    local count = 0
    local function Comp()
        tui.useLayoutEffect(function()
            count = count + 1
        end, nil)
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(count, 1)
    b:rerender()
    lt.assertEquals(count, 2)
    b:rerender()
    lt.assertEquals(count, 3)
    b:unmount()
end

-- Cleanup runs on unmount.
function suite:test_cleanup_on_unmount()
    local cleaned = false
    local function Comp()
        tui.useLayoutEffect(function()
            return function()
                cleaned = true
            end
        end, {})
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(cleaned, false)
    b:unmount()
    lt.assertEquals(cleaned, true)
end

-- setState inside useLayoutEffect is visible on next frame, not same render.
function suite:test_setState_visible_next_frame()
    local val = 0
    local function setVal(v) val = v end
    local function Comp()
        tui.useLayoutEffect(function()
            if val == 0 then
                setVal(1)
            end
        end, {})
        return tui.Text { tostring(val) }
    end
    local b = testing.bare(Comp)
    -- Layout effect ran but setState is deferred to next frame.
    lt.assertEquals(val, 1)
    -- The tree from first render still has "0" because setState was after stabilization.
    lt.assertEquals(b:tree().children[1], "0")
    b:unmount()
end

-- useLayoutEffect and useEffect on same component run in correct order.
function suite:test_layout_effect_runs_before_effect()
    local order = {}
    local function Comp()
        tui.useLayoutEffect(function()
            order[#order + 1] = "layout"
        end, {})
        tui.useEffect(function()
            order[#order + 1] = "effect"
        end, {})
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(order[1], "layout")
    lt.assertEquals(order[2], "effect")
    b:unmount()
end
