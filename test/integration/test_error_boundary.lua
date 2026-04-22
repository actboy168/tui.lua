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
local tui_input = require "tui.input"
local tui_input = require "tui.input"
local testing = require "tui.testing"

local suite = lt.test "error_boundary"

-- ---------------------------------------------------------------------------
-- 1. Boundary catches a child that throws, renders fallback.

function suite:test_error_boundary_catches_child_throw()
    local function Bad_fn() error("bad!", 0) end
    local Bad = tui.component(Bad_fn)

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FALLBACK" },
            Bad {},
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
    local function Good_fn() return tui.Text { "OK" } end
    local Good = tui.component(Good_fn)

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FB" },
            Good {},
        }
    end

    local h = testing.render(App, { cols = 2, rows = 1 })
    lt.assertEquals(h:frame(), "OK")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. Sibling isolation: one boundary catches, others keep working.

function suite:test_error_boundary_isolates_sibling_subtrees()
    local function Bad_fn()  error("boom", 0) end
    local function Good_fn() return tui.Text { "GOOD" } end
    local Bad  = tui.component(Bad_fn)
    local Good = tui.component(Good_fn)

    local function App()
        return tui.Box {
            flexDirection = "column",
            tui.ErrorBoundary {
                fallback = tui.Text { "BAD!" },
                Bad {},
            },
            tui.ErrorBoundary {
                fallback = tui.Text { "----" },
                Good {},
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
    local function Bad_fn() error("inner", 0) end
    local Bad = tui.component(Bad_fn)

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "OUTER" },
            tui.ErrorBoundary {
                fallback = tui.Text { "INNER" },
                Bad {},
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
    local function Bad_fn() error("deep", 0) end
    local Bad = tui.component(Bad_fn)
    local function Middle()
        return tui.Box {
            tui.Box {
                Bad {},
            },
        }
    end

    local MiddleComp = tui.component(Middle)

    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "DEEP-FB" },
            MiddleComp {},
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
    local function Bad_fn() error("unhandled", 0) end
    local Bad = tui.component(Bad_fn)
    local function App() return Bad {} end

    local ok, err = pcall(function()
        testing.render(App, { cols = 4, rows = 1 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("unhandled", 1, true) ~= nil, true,
        "expected error to mention 'unhandled', got: " .. tostring(err))
end

-- ---------------------------------------------------------------------------
-- 7. Fatal errors bypass the boundary pcall and propagate.
--
-- Programming bugs (duplicate reconciler key, duplicate focus id, internal
-- asserts) are tagged with the "[tui:fatal] " prefix via reconciler.fatal().
-- An ErrorBoundary MUST rethrow them so they surface as a hard failure
-- rather than masquerading as a routine render error behind fallback.

function suite:test_fatal_error_bypasses_boundary()
    local function Bad_fn() testing.fatal("something broke") end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FB" },
            Bad {},
        }
    end

    local ok, err = pcall(function()
        testing.render(App, { cols = 4, rows = 1 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("[tui:fatal]", 1, true) ~= nil, true,
        "expected fatal prefix to survive, got: " .. tostring(err))
    lt.assertEquals(err:find("something broke", 1, true) ~= nil, true,
        "expected original message to survive, got: " .. tostring(err))
end

function suite:test_reconciler_duplicate_key_is_fatal_past_boundary()
    -- Duplicate key thrown by a child must NOT be swallowed by a wrapping
    -- ErrorBoundary — the key bug would otherwise silently corrupt state.
    local function Noop_fn() return tui.Text { "x" } end
    local Noop = tui.component(Noop_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FB" },
            Noop { key = "dup" },
            Noop { key = "dup" },
        }
    end

    local ok, err = pcall(function()
        testing.render(App, { cols = 4, rows = 1 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("duplicate key", 1, true) ~= nil, true,
        "expected duplicate-key fatal to propagate, got: " .. tostring(err))
end

-- ---------------------------------------------------------------------------
-- 9. Post-commit errors from useEffect body bubble to the nearest boundary.
--
-- Effects run after the tree has been expanded/committed, so the Boundary's
-- render-time pcall cannot catch them. tui._flush_effects routes the error
-- onto the instance's captured nearest_boundary, marks it dirty, and asks
-- the scheduler for a redraw. The harness stabilization loop picks up the
-- dirty flag and repaints — second pass observes caught_error and swaps in
-- the fallback.

function suite:test_useeffect_body_throw_caught_by_boundary()
    local function Bad_fn()
        tui.useEffect(function() error("effect-boom", 0) end, {})
        return tui.Text { "BAD" }
    end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FB!!" },
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    -- Effect error sets boundary.caught_error after the tree is committed;
    -- the next paint observes the tripped boundary and swaps in fallback.
    h:rerender()
    lt.assertEquals(h:frame(), "FB!!")
    h:rerender()
    lt.assertEquals(h:frame(), "FB!!", "boundary stays tripped after effect error")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 10. useEffect cleanup errors on unmount / re-run bubble to boundary too.

function suite:test_useeffect_cleanup_throw_caught_by_boundary()
    local phase = { "first" }
    local function Child_fn()
        tui.useEffect(function()
            return function() error("cleanup-boom", 0) end
        end, { phase[1] })
        return tui.Text { "C" }
    end
    local Child = tui.component(Child_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FB##" },
            Child {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    lt.assertEquals(h:frame(), "C   ", "first mount OK — effect returned cleanup, not yet invoked")
    -- Flip deps so cleanup fires before the new body runs.
    phase[1] = "second"
    h:rerender()
    -- Cleanup error is routed during effect flush after this paint;
    -- the next paint observes the tripped boundary.
    h:rerender()
    lt.assertEquals(h:frame(), "FB##", "cleanup throw caught by boundary on re-run")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 11. Without a boundary in scope, effect errors escape the framework. The
--     harness surfaces this as a regular Lua error out of :rerender().

function suite:test_useeffect_throw_without_boundary_propagates()
    local function Bad_fn()
        tui.useEffect(function() error("loose-effect", 0) end, {})
        return tui.Text { "X" }
    end
    local Bad = tui.component(Bad_fn)
    local function App() return Bad {} end

    local ok, err = pcall(function()
        testing.render(App, { cols = 2, rows = 1 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("loose-effect", 1, true) ~= nil, true,
        "expected unhandled effect error, got: " .. tostring(err))
end

function suite:test_boundary_caught_error_is_sticky()
    local armed = { true }  -- first mount throws; after we disarm, Bad returns clean
    local function Bad_fn()
        tui.useEffect(function()
            if armed[1] then error("first-only", 0) end
        end, {})
        return tui.Text { "OK" }
    end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FBzz" },
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    -- Effect error sets boundary.caught_error after the tree is committed;
    -- the next paint observes the tripped boundary and swaps in fallback.
    h:rerender()
    lt.assertEquals(h:frame(), "FBzz")
    -- Even though subsequent renders wouldn't throw (effect ran once, deps={}),
    -- boundary must stay in its tripped state.
    armed[1] = false
    h:rerender()
    lt.assertEquals(h:frame(), "FBzz", "boundary is sticky even when children could render clean")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 13. useInput handler errors bubble to the nearest ErrorBoundary. The
--     handler runs synchronously inside input.dispatch well after commit,
--     so it relies on the instance's .nearest_boundary field (refreshed
--     every render) rather than any ambient boundary stack.

function suite:test_useinput_handler_throw_caught_by_boundary()
    local function Bad_fn()
        tui.useInput(function() error("key-boom", 0) end)
        return tui.Text { "BAD" }
    end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FBkb" },
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    lt.assertEquals(h:frame(), "BAD ", "no key pressed yet, child still mounted")
    tui_input.type("x")   -- drives input.dispatch → broadcast handler → throws
    h:rerender()
    lt.assertEquals(h:frame(), "FBkb", "boundary catches useInput handler error")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 14. Focused on_input errors (useFocus with on_input) bubble to the
--     nearest boundary on the focused component's instance.

function suite:test_usefocus_on_input_throw_caught_by_boundary()
    local function Bad_fn()
        tui.useFocus {
            autoFocus = true,
            on_input = function() error("focus-boom", 0) end,
        }
        return tui.Text { "BAD" }
    end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FBfb" },
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    lt.assertEquals(h:focus_id() ~= nil, true, "autoFocus took focus")
    tui_input.type("y")   -- dispatch_focused delivers to focused on_input → throws
    h:rerender()
    lt.assertEquals(h:frame(), "FBfb", "boundary catches focused on_input error")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 15. Without a boundary in scope, useInput errors propagate out of the
--     dispatch call — framework callers (main loop / harness) get a hard
--     failure rather than silent swallowing.

function suite:test_useinput_throw_without_boundary_propagates()
    local function Bad_fn()
        tui.useInput(function() error("loose-key", 0) end)
        return tui.Text { "x" }
    end
    local Bad = tui.component(Bad_fn)
    local function App() return Bad {} end

    local h = testing.render(App, { cols = 2, rows = 1 })
    local ok, err = pcall(function() tui_input.type("a"); h:rerender() end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("loose-key", 1, true) ~= nil, true,
        "expected unhandled input error, got: " .. tostring(err))
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 16. fallback as function: receives (err, reset); return value rendered
--     as the fallback tree. The err is exactly what the child threw.

function suite:test_fallback_function_receives_err_and_reset()
    local seen_err, seen_reset_type
    local function Bad_fn() error("bang", 0) end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = function(err, reset)
                seen_err = err
                seen_reset_type = type(reset)
                return tui.Text { "FN!!" }
            end,
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    lt.assertEquals(h:frame(), "FN!!")
    lt.assertEquals(seen_reset_type, "function")
    lt.assertEquals(type(seen_err), "table",
        "fallback should receive error table, got: " .. tostring(seen_err))
    lt.assertNotEquals(seen_err.message:find("bang", 1, true), nil,
        "error message should contain 'bang', got: " .. tostring(seen_err.message))
    lt.assertNotNil(seen_err.trace, "error table should have a trace field")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 17. Calling reset() clears caught_error and lets children re-render
--     cleanly (when they don't throw on the next pass).

function suite:test_reset_clears_caught_error()
    local armed = { true }
    local captured_reset
    local function Bad_fn()
        if armed[1] then error("first", 0) end
        return tui.Text { "OK  " }
    end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = function(_err, reset)
                captured_reset = reset
                return tui.Text { "FB  " }
            end,
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    lt.assertEquals(h:frame(), "FB  ")
    -- Flip so Bad no longer throws, then reset.
    armed[1] = false
    captured_reset()
    h:rerender()
    lt.assertEquals(h:frame(), "OK  ", "children render after reset when they no longer throw")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 18. If reset() is called but children still throw, the boundary traps
--     the new error and shows fallback again (sticky behavior re-arms).

function suite:test_reset_then_rethrow_catches_new_error()
    local which = { "first" }
    local got_errs = {}
    local last_reset
    local function Bad_fn() error(which[1], 0) end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = function(err, reset)
                got_errs[#got_errs + 1] = err
                last_reset = reset
                return tui.Text { "FB" }
            end,
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 2, rows = 1 })
    lt.assertEquals(h:frame(), "FB")
    which[1] = "second"
    last_reset()
    h:rerender()
    lt.assertEquals(h:frame(), "FB", "boundary still fallback after second throw")
    -- Two error values delivered to fallback across the two trips.
    lt.assertEquals(#got_errs >= 2, true, "expected at least 2 fallback invocations, got " .. #got_errs)
    local last = got_errs[#got_errs]
    lt.assertEquals(type(last), "table",
        "most recent err should be a table, got: " .. tostring(last))
    lt.assertNotEquals(last.message:find("second", 1, true), nil,
        "most recent err.message should be 'second', got: " .. tostring(last.message))
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 19. reset closure is reference-stable across frames — critical for using
--     it as a useEffect dep or passing it to memoized children.

function suite:test_reset_is_reference_stable()
    local seen = {}
    local function Bad_fn() error("x", 0) end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = function(_err, reset)
                seen[#seen + 1] = reset
                return tui.Text { "F" }
            end,
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    h:rerender()
    h:rerender()
    lt.assertEquals(#seen >= 3, true, "expected multiple fallback invocations, got " .. #seen)
    lt.assertEquals(seen[1] == seen[2], true, "reset reference must be stable (frame 1 vs 2)")
    lt.assertEquals(seen[2] == seen[3], true, "reset reference must be stable (frame 2 vs 3)")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 20. A throwing fallback function is caught — boundary degrades to empty
--     box rather than crashing the whole render. Fatal prefix still escapes.

function suite:test_fallback_function_that_throws_degrades_to_empty()
    local function Bad_fn() error("child", 0) end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = function() error("fallback-boom", 0) end,
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 4, rows = 1 })
    -- Empty box fills with spaces at this width.
    lt.assertEquals(h:frame(), "    ")
    h:unmount()
end

function suite:test_fallback_function_with_fatal_still_propagates()
    local function Bad_fn() error("normal", 0) end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = function() testing.fatal("fatal-from-fb") end,
            Bad {},
        }
    end

    local ok, err = pcall(function()
        testing.render(App, { cols = 4, rows = 1 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("fatal-from-fb", 1, true) ~= nil, true,
        "fatal from fallback must propagate, got: " .. tostring(err))
end

-- ---------------------------------------------------------------------------
-- 21. useErrorBoundary() inside a descendant reads the nearest boundary
--     state; useful when fallback=element can't carry err itself.

function suite:test_useerrorboundary_sees_caught_error()
    -- Flag-flipping state so the fallback tree can observe a tripped boundary.
    local seen_err_in_fb
    local function FbView_fn()
        local eb = tui.useErrorBoundary()
        seen_err_in_fb = eb.caught_error
        return tui.Text { "fb" }
    end
    local FbView = tui.component(FbView_fn)
    local function Bad_fn() error("observed", 0) end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = FbView {},
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 2, rows = 1 })
    lt.assertEquals(h:frame(), "fb")
    lt.assertEquals(type(seen_err_in_fb), "table",
        "useErrorBoundary should expose caught_error as table, got: " .. tostring(seen_err_in_fb))
    lt.assertNotEquals(seen_err_in_fb.message:find("observed", 1, true), nil,
        "caught_error.message should contain 'observed', got: " .. tostring(seen_err_in_fb.message))
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 22. useErrorBoundary().reset clears the boundary the same way the fallback
--     function's reset does.

function suite:test_useerrorboundary_reset_clears_boundary()
    local armed = { true }
    local captured
    local function FbView_fn()
        local eb = tui.useErrorBoundary()
        captured = eb
        return tui.Text { "fb  " }
    end
    local FbView = tui.component(FbView_fn)
    local function Bad_fn()
        if armed[1] then error("e", 0) end
        return tui.Text { "CLEAN" }
    end
    local Bad = tui.component(Bad_fn)
    local function App()
        return tui.ErrorBoundary {
            fallback = FbView {},
            Bad {},
        }
    end

    local h = testing.render(App, { cols = 5, rows = 1 })
    lt.assertEquals(h:row(1):sub(1, 4), "fb  ")
    lt.assertEquals(captured.caught_error ~= nil, true)
    armed[1] = false
    captured.reset()
    h:rerender()
    lt.assertEquals(h:frame(), "CLEAN")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 23. useErrorBoundary() called with no ancestor boundary returns a no-op
--     reset + nil caught_error (won't crash).

function suite:test_useerrorboundary_without_ancestor_is_noop()
    local seen
    local function View()
        seen = tui.useErrorBoundary()
        return tui.Text { "v" }
    end

    local h = testing.render(View, { cols = 1, rows = 1 })
    lt.assertEquals(seen.caught_error, nil)
    lt.assertEquals(type(seen.reset), "function")
    -- Calling reset is a no-op.
    seen.reset()
    h:unmount()
end
