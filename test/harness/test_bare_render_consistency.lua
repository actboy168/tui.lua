-- test/test_bare_render_consistency.lua — verify same App behaves consistently
-- in both Bare and Harness (render) mode. Both modes share the same reconciler,
-- hooks, scheduler, input, and focus modules; the differences are layout/render
-- and auto-rerender. This file tests that hook semantics are identical.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"
local hooks   = require "tui.hooks"
local element = require "tui.element"

local suite = lt.test "bare_render_consistency"

-- Helper: extract Text content from a tree as a flat string.
local function tree_text(tree)
    return table.concat(testing.text_content(tree), "")
end

-- ---------------------------------------------------------------------------
-- useState

function suite:test_useState_setter_updates_tree()
    local refs = {}
    local App = function()
        local val, setVal = hooks.useState(0)
        refs.setVal = setVal
        return element.Text { tostring(val) }
    end

    -- Bare
    local b = testing.mount_bare(App)
    lt.assertEquals(tree_text(b:tree()), "0")
    refs.setVal(42)
    b:rerender()
    lt.assertEquals(tree_text(b:tree()), "42")
    b:unmount()

    -- Harness
    refs = {}
    local h = testing.render(App)
    lt.assertEquals(tree_text(h:tree()), "0")
    refs.setVal(42)
    h:_paint()
    lt.assertEquals(tree_text(h:tree()), "42")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- useEffect

function suite:test_useEffect_fires_on_mount()
    local count_bare = 0
    local count_harness = 0

    local App1 = function()
        hooks.useEffect(function() count_bare = count_bare + 1 end, {})
        return element.Text { "x" }
    end
    local b = testing.mount_bare(App1)
    lt.assertEquals(count_bare, 1)
    b:unmount()

    local App2 = function()
        hooks.useEffect(function() count_harness = count_harness + 1 end, {})
        return element.Text { "x" }
    end
    local h = testing.render(App2)
    lt.assertEquals(count_harness, 1)
    h:unmount()
end

function suite:test_useEffect_cleanup_on_unmount()
    local bare_cleaned = false
    local harness_cleaned = false

    local App1 = function()
        hooks.useEffect(function()
            return function() bare_cleaned = true end
        end, {})
        return element.Text { "x" }
    end
    local b = testing.mount_bare(App1)
    lt.assertEquals(bare_cleaned, false)
    b:unmount()
    lt.assertEquals(bare_cleaned, true)

    local App2 = function()
        hooks.useEffect(function()
            return function() harness_cleaned = true end
        end, {})
        return element.Text { "x" }
    end
    local h = testing.render(App2)
    lt.assertEquals(harness_cleaned, false)
    h:unmount()
    lt.assertEquals(harness_cleaned, true)
end

-- ---------------------------------------------------------------------------
-- useReducer

function suite:test_useReducer_dispatch_updates_tree()
    local refs = {}
    local reducer = function(state, action)
        if action == "inc" then return state + 1 end
        return state
    end

    local App = function()
        local count, dispatch = hooks.useReducer(reducer, 0)
        refs.dispatch = dispatch
        return element.Text { tostring(count) }
    end

    -- Bare
    local b = testing.mount_bare(App)
    lt.assertEquals(tree_text(b:tree()), "0")
    refs.dispatch("inc")
    b:rerender()
    lt.assertEquals(tree_text(b:tree()), "1")
    b:unmount()

    -- Harness
    refs = {}
    local h = testing.render(App)
    lt.assertEquals(tree_text(h:tree()), "0")
    refs.dispatch("inc")
    h:_paint()
    lt.assertEquals(tree_text(h:tree()), "1")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- useRef

function suite:test_useRef_persists_across_renders()
    local refs = {}
    local App = function()
        local ref = hooks.useRef(0)
        refs.ref = ref
        ref.current = ref.current + 1
        return element.Text { tostring(ref.current) }
    end

    -- Bare
    local b = testing.mount_bare(App)
    lt.assertEquals(refs.ref.current, 1)
    b:rerender()
    lt.assertEquals(refs.ref.current, 2, "bare: ref should persist")
    b:unmount()

    -- Harness
    refs = {}
    local h = testing.render(App)
    lt.assertEquals(refs.ref.current, 1)
    h:_paint()
    lt.assertEquals(refs.ref.current, 2, "harness: ref should persist")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- useMemo

function suite:test_useMemo_caches_until_deps_change()
    local refs = {}
    local compute_counts = { bare = 0, harness = 0 }

    local function make_app(key)
        return function()
            local d, setD = hooks.useState(1)
            refs[key] = refs[key] or {}
            refs[key].setD = setD
            local val = hooks.useMemo(function()
                compute_counts[key] = compute_counts[key] + 1
                return d * 10
            end, { d })
            return element.Text { tostring(val) }
        end
    end

    -- Bare
    local b = testing.mount_bare(make_app("bare"))
    lt.assertEquals(compute_counts.bare, 1)
    refs.bare.setD(1)  -- same dep
    b:rerender()
    lt.assertEquals(compute_counts.bare, 1, "bare: memo should not recompute with same deps")
    refs.bare.setD(2)
    b:rerender()
    lt.assertEquals(compute_counts.bare, 2, "bare: memo should recompute with new deps")
    b:unmount()

    -- Harness
    refs = {}
    local h = testing.render(make_app("harness"))
    lt.assertEquals(compute_counts.harness, 1)
    refs.harness.setD(1)
    h:_paint()
    lt.assertEquals(compute_counts.harness, 1, "harness: memo should not recompute with same deps")
    refs.harness.setD(2)
    h:_paint()
    lt.assertEquals(compute_counts.harness, 2, "harness: memo should recompute with new deps")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- useContext

function suite:test_useContext_same_value_in_both_modes()
    local ctx = hooks.createContext("default")

    local Inner = function()
        local val = hooks.useContext(ctx)
        return element.Text { val }
    end

    local App = function()
        return ctx.Provider { value = "hello", element.Box { Inner } }
    end

    -- Bare
    local b = testing.mount_bare(App)
    lt.assertEquals(tree_text(b:tree()), "hello")
    b:unmount()

    -- Harness
    local h = testing.render(App)
    lt.assertEquals(tree_text(h:tree()), "hello")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Input dispatch (use raw dispatch to avoid focus interception)

function suite:test_dispatch_same_bytes()
    local bare_keys = {}
    local harness_keys = {}

    local function make_app(keys_table)
        return function()
            hooks.useInput(function(_, key)
                if key then keys_table[#keys_table + 1] = key.name end
            end)
            return element.Text { "x" }
        end
    end

    -- Use raw dispatch with up arrow (not intercepted by focus)
    local b = testing.mount_bare(make_app(bare_keys))
    b:dispatch("\x1b[A")  -- CSI A = up arrow
    lt.assertEquals(#bare_keys, 1, "bare: should receive 1 key")
    lt.assertEquals(bare_keys[1], "up")
    b:unmount()

    local h = testing.render(make_app(harness_keys))
    h:dispatch("\x1b[A")
    lt.assertEquals(#harness_keys, 1, "harness: should receive 1 key")
    lt.assertEquals(harness_keys[1], "up")
    h:unmount()
end

function suite:test_type_same_chars()
    local bare_chars = {}
    local harness_chars = {}

    local function make_app(chars_table)
        return function()
            hooks.useInput(function(_, key)
                if key and key.input then
                    chars_table[#chars_table + 1] = key.input
                end
            end)
            return element.Text { "x" }
        end
    end

    local b = testing.mount_bare(make_app(bare_chars))
    b:type("hi")
    lt.assertEquals(bare_chars, { "h", "i" }, "bare: type should deliver chars")
    b:unmount()

    local h = testing.render(make_app(harness_chars))
    h:type("hi")
    lt.assertEquals(harness_chars, { "h", "i" }, "harness: type should deliver chars")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Focus

function suite:test_focus_next_advances_same()
    -- Components need unique keys when siblings
    local A = function()
        hooks.useFocus()
        return element.Text { "A" }
    end
    local B = function()
        hooks.useFocus()
        return element.Text { "B" }
    end
    local CompA = tui.component(A)
    local CompB = tui.component(B)
    local App = function()
        return element.Box {
            CompA { key = "a" },
            CompB { key = "b" },
        }
    end

    local b = testing.mount_bare(App)
    local h = testing.render(App)

    lt.assertEquals(b:focus_id(), h:focus_id(), "initial focus should match")

    b:focus_next()
    h:focus_next()
    lt.assertEquals(b:focus_id(), h:focus_id(), "focus after next should match")

    b:focus_prev()
    h:focus_prev()
    lt.assertEquals(b:focus_id(), h:focus_id(), "focus after prev should match")

    b:unmount()
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Timer (advance)

function suite:test_advance_updates_clock_same()
    local App = function()
        return element.Text { "x" }
    end

    local b = testing.mount_bare(App)
    local h = testing.render(App)

    b:advance(100)
    h:advance(100)
    lt.assertEquals(b._fake_now, h._fake_now)

    b:advance(50)
    h:advance(50)
    lt.assertEquals(b._fake_now, h._fake_now)
    b:unmount()
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Tree structure

function suite:test_same_tree_kind_and_text()
    local App = function()
        return element.Box {
            element.Text { "hello" },
            element.Text { "world" },
        }
    end

    local b = testing.mount_bare(App)
    local h = testing.render(App)

    local bt = b:tree()
    local ht = h:tree()

    lt.assertEquals(bt.kind, ht.kind)
    lt.assertEquals(#bt.children, #ht.children)
    lt.assertEquals(bt.children[1].kind, ht.children[1].kind)
    lt.assertEquals(bt.children[1].text, ht.children[1].text)
    lt.assertEquals(bt.children[2].text, ht.children[2].text)
    b:unmount()
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Unmount cleanup

function suite:test_unmount_runs_effect_cleanups()
    local bare_cleanups = 0
    local harness_cleanups = 0

    local App1 = function()
        hooks.useEffect(function()
            return function() bare_cleanups = bare_cleanups + 1 end
        end, {})
        return element.Text { "x" }
    end
    local b = testing.mount_bare(App1)
    b:unmount()

    local App2 = function()
        hooks.useEffect(function()
            return function() harness_cleanups = harness_cleanups + 1 end
        end, {})
        return element.Text { "x" }
    end
    local h = testing.render(App2)
    h:unmount()

    lt.assertEquals(bare_cleanups, harness_cleanups,
        "both modes should run the same number of effect cleanups")
end
