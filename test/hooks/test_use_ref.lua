-- test/test_use_ref.lua — useRef behavior.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_ref"

-- Initial value is stored in .current on mount.
function suite:test_ref_initial_value_on_mount()
    local ref_seen
    local function Comp()
        local r = tui.useRef(42)
        ref_seen = r
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(type(ref_seen), "table")
    lt.assertEquals(ref_seen.current, 42)
    b:unmount()
end

-- Table identity is stable across rerenders.
function suite:test_ref_identity_stable_across_renders()
    local seen = {}
    local function Comp()
        local r = tui.useRef("anything")
        seen[#seen + 1] = r
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    b:rerender()
    b:rerender()
    lt.assertEquals(rawequal(seen[1], seen[2]), true)
    lt.assertEquals(rawequal(seen[2], seen[3]), true)
    b:unmount()
end

-- Mutating .current does NOT cause a rerender.
function suite:test_ref_mutation_does_not_trigger_rerender()
    local captured_ref
    local function Comp()
        local r = tui.useRef(0)
        captured_ref = r
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    b:expect_renders(1)
    captured_ref.current = 999
    -- No rerender should be forced; calling rerender() explicitly still
    -- preserves the mutated value (not reinitialized to 0).
    b:rerender()
    b:expect_renders(2)
    lt.assertEquals(captured_ref.current, 999)
    b:unmount()
end

-- The initial argument passed on rerender is ignored (eager-init only).
function suite:test_ref_current_persists_across_rerenders()
    local seed = "first"
    local captured
    local function Comp()
        local r = tui.useRef(seed)
        captured = r
        return tui.Text { "" }
    end
    local b = testing.bare(Comp)
    lt.assertEquals(captured.current, "first")
    captured.current = "mutated"
    seed = "second"
    b:rerender()
    lt.assertEquals(captured.current, "mutated")
    b:unmount()
end
