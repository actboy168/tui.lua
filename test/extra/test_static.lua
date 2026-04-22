-- test/extra/test_static.lua — unit tests for <Static> component.

local lt     = require "ltest"
local tui    = require "tui"
local Static = require "tui.extra.static".Static
local testing = require "tui.testing"
local vterm  = require "tui.testing.vterm"

local suite = lt.test "static"

function suite:test_static_initial_items_render()
    local items = { "hello", "world" }
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            Static {
                items = items,
                render = function(s) return tui.Text { s } end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    lt.assertEquals(h:row(1):sub(1, 5), "hello")
    lt.assertEquals(h:row(2):sub(1, 5), "world")
    h:unmount()
end

function suite:test_static_appending_items_produces_incremental_diff()
    local items = { "first" }
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            Static {
                items = items,
                render = function(s) return tui.Text { s } end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    -- Drain the initial-frame ANSI so we only measure the incremental diff.
    h:clear_ansi()
    items[#items + 1] = "second"
    h:rerender()
    local ansi = h:ansi()
    lt.assertEquals(#ansi > 0, true, "expected some ANSI for new row")
    lt.assertEquals(#ansi < 300, true, "expected a small diff, got " .. #ansi .. " bytes")
    lt.assertEquals(h:row(2):sub(1, 6), "second", "new row content should appear")
    h:unmount()
end

function suite:test_static_no_change_produces_zero_diff()
    local items = { "a", "b" }
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            Static {
                items = items,
                render = function(s) return tui.Text { s } end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    local vt = h:vterm()
    -- Capture the screen before rerender
    local before = vterm.screen_string(vt)
    h:rerender()
    local after = vterm.screen_string(vt)
    -- Screen content must be identical (no cell changes)
    lt.assertEquals(after, before, "second identical render should not change screen content")
    h:unmount()
end

function suite:test_static_preserves_item_identity_when_cached()
    -- Each render() call increments a counter. After two paints with the same
    -- items array, render() should have been called exactly len(items) times.
    local items = { "x", "y" }
    local render_calls = 0
    local function App()
        return tui.Box {
            width = 20, height = 5,
            flexDirection = "column",
            Static {
                items = items,
                render = function(s)
                    render_calls = render_calls + 1
                    return tui.Text { s }
                end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    h:rerender()
    lt.assertEquals(render_calls, 2, "render() should be memoized per item")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. items array cleared then re-appended: cache must be invalidated for the
--    dropped tail and re-render must run for newly-appended slots.

function suite:test_static_clear_then_reappend()
    local items = { "alpha", "beta", "gamma" }
    local render_calls = 0
    local function App()
        return tui.Box {
            width = 20, height = 10,
            flexDirection = "column",
            Static {
                items = items,
                render = function(s)
                    render_calls = render_calls + 1
                    return tui.Text { s }
                end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 10 })
    lt.assertEquals(render_calls, 3, "initial render once per item")
    -- Clear (in-place) then re-append; each new slot must re-render because
    -- identity check fails (nil cache slot from the earlier shrink).
    for i = #items, 1, -1 do items[i] = nil end
    h:rerender()
    lt.assertEquals(render_calls, 3, "no new render calls after clear")
    items[#items + 1] = "x"
    items[#items + 1] = "y"
    h:rerender()
    lt.assertEquals(render_calls, 5, "two new render calls for re-appended items")
    lt.assertEquals(h:row(1):sub(1, 1), "x")
    lt.assertEquals(h:row(2):sub(1, 1), "y")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 6. A render fn that throws propagates up to an enclosing ErrorBoundary.

function suite:test_static_render_error_caught_by_boundary()
    local items = { "ok", "boom", "unreachable" }
    local function App()
        return tui.ErrorBoundary {
            fallback = tui.Text { "FB" },
            tui.Box {
                width = 8, height = 3,
                flexDirection = "column",
                Static {
                    items = items,
                    render = function(s)
                        if s == "boom" then error("render blew up", 0) end
                        return tui.Text { s }
                    end,
                },
            },
        }
    end
    local h = testing.render(App, { cols = 8, rows = 3 })
    lt.assertEquals(h:row(1):sub(1, 2), "FB")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 7. 1000-item append then unmount: harness :unmount cleans up; no lingering
--    cached instances (indirectly observed via a fresh mount starting clean).

function suite:test_static_large_list_append_then_unmount()
    local items = {}
    local render_calls = 0
    local function App()
        return tui.Box {
            width = 8, height = 1000,
            flexDirection = "column",
            Static {
                items = items,
                render = function(s)
                    render_calls = render_calls + 1
                    return tui.Text { s }
                end,
            },
        }
    end
    for i = 1, 1000 do items[i] = "row" .. i end
    local h = testing.render(App, { cols = 8, rows = 1000 })
    lt.assertEquals(render_calls, 1000, "each of 1000 items rendered once")
    -- Rerender: everything cached, zero additional calls.
    h:rerender()
    lt.assertEquals(render_calls, 1000, "no extra render after rerender")
    h:unmount()
    -- Fresh mount with empty items: new component instance, fresh cache,
    -- render_calls stays at 1000 because the new mount uses a fresh closure
    -- scope is not what we test — we test the harness can mount again
    -- without inheriting any reconciler state from the prior run.
    local items2 = { "after" }
    local calls2 = 0
    local function App2()
        return tui.Box {
            width = 8, height = 2,
            flexDirection = "column",
            Static {
                items = items2,
                render = function(s)
                    calls2 = calls2 + 1
                    return tui.Text { s }
                end,
            },
        }
    end
    local h2 = testing.render(App2, { cols = 8, rows = 2 })
    lt.assertEquals(calls2, 1, "fresh mount starts with empty cache")
    lt.assertEquals(h2:row(1):sub(1, 5), "after")
    h2:unmount()
end

-- ---------------------------------------------------------------------------
-- 8. items table reference stable and slot identity stable — no re-render
--    even if unrelated table fields mutate.

function suite:test_static_items_identity_stable_no_rerender()
    local a, b = { tag = "A" }, { tag = "B" }
    local items = { a, b }
    local render_calls = 0
    local function App()
        return tui.Box {
            width = 8, height = 4,
            flexDirection = "column",
            Static {
                items = items,
                render = function(it)
                    render_calls = render_calls + 1
                    return tui.Text { it.tag }
                end,
            },
        }
    end
    local h = testing.render(App, { cols = 8, rows = 4 })
    lt.assertEquals(render_calls, 2)
    -- Mutate an unrelated field on the cached item objects. Static compares
    -- via rawequal (object identity), so this is a cache hit.
    a.tag = "A2"
    b.tag = "B2"
    h:rerender()
    lt.assertEquals(render_calls, 2,
        "mutating fields on cached item (same identity) should NOT re-render")
    h:unmount()
end
