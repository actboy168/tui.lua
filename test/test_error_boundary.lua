-- test/test_error_boundary.lua — ErrorBoundary isolates render-time errors.
--
-- Semantics under test:
--   * A component fn raising during render propagates upward until the
--     nearest <ErrorBoundary> catches it and renders its `fallback` instead.
--   * No boundary in scope -> error propagates to Harness:_paint (testing
--     harness makes this observable; in tui.render the top-level pcall
--     swaps in a banner tree instead of crashing — not covered here, see
--     roadmap Stage 7 notes).
--   * Boundary does NOT auto-reset across frames. Once a subtree has
--     thrown, the boundary keeps showing fallback on subsequent renders
--     (Ink/React semantics).

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "error_boundary"

-- Small helper: build a component element.
local function comp(fn, props)
    return { kind = "component", fn = fn, props = props or {} }
end

-- ---------------------------------------------------------------------------
-- 1. Boundary catches a child that throws, renders fallback.

function suite:test_error_boundary_catches_child_throw()
    local function Bad() error("bad!", 0) end

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FALLBACK" },
            comp(Bad),
        }
    end

    local h = testing.render(App, { cols = 8, rows = 1 })
    lt.assertEquals(h:frame(), "FALLBACK")
    -- Subsequent rerenders keep showing fallback (boundary stays tripped).
    h:rerender()
    lt.assertEquals(h:frame(), "FALLBACK")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 2. Normal case: no throw -> children render, fallback unused.

function suite:test_error_boundary_no_throw_passthrough()
    local function Good() return tui.Text { "OK" } end

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FB" },
            comp(Good),
        }
    end

    local h = testing.render(App, { cols = 2, rows = 1 })
    lt.assertEquals(h:frame(), "OK")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. Sibling isolation: one boundary catches, others keep working.

function suite:test_error_boundary_isolates_sibling_subtrees()
    local function Bad()  error("boom", 0) end
    local function Good() return tui.Text { "GOOD" } end

    local function App()
        return tui.Box {
            flexDirection = "column",
            tui.ErrorBoundary {
                fallback = tui.Text { "BAD!" },
                comp(Bad),
            },
            tui.ErrorBoundary {
                fallback = tui.Text { "----" },
                comp(Good),
            },
        }
    end

    local h = testing.render(App, { cols = 4, rows = 2 })
    lt.assertEquals(h:row(1), "BAD!")
    lt.assertEquals(h:row(2), "GOOD")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 4. Nested boundaries: the innermost one catches first.

function suite:test_error_boundary_nested_inner_catches_first()
    local function Bad() error("inner", 0) end

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "OUTER" },
            tui.ErrorBoundary {
                fallback = tui.Text { "INNER" },
                comp(Bad),
            },
        }
    end

    local h = testing.render(App, { cols = 5, rows = 1 })
    lt.assertEquals(h:frame(), "INNER")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. Error raised by a component several levels deep still reaches the
--    boundary (error propagates through Box host nodes unchanged).

function suite:test_error_from_deeper_descendant_caught()
    local function Bad() error("deep", 0) end
    local function Middle()
        return tui.Box {
            tui.Box {
                comp(Bad),
            },
        }
    end

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "DEEP-FB" },
            comp(Middle),
        }
    end

    local h = testing.render(App, { cols = 7, rows = 1 })
    lt.assertEquals(h:frame(), "DEEP-FB")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 6. Without any boundary, reconciler errors propagate to the harness. This
--    pins down the framework-level contract: the boundary is *opt-in* for
--    tree recovery; without one, render errors are loud. (tui.render itself
--    has a banner fallback on top of this, verified by example only.)

function suite:test_no_boundary_error_propagates()
    local function Bad() error("unhandled", 0) end
    local function App() return comp(Bad) end

    local ok, err = pcall(function()
        testing.render(App, { cols = 4, rows = 1 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("unhandled", 1, true) ~= nil, true,
        "expected error to mention 'unhandled', got: " .. tostring(err))
end
