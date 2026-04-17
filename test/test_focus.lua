-- test/test_focus.lua — unit tests for the focus chain and useFocus /
-- useFocusManager hooks.
--
-- Every test drives the tree through tui.testing; we assert against
-- h:focus_id() (which reads tui.focus.get_focused_id) and, where relevant,
-- against the rendered text to verify isFocused reflects back into state.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "focus"

-- ---------------------------------------------------------------------------
-- 1. Single useFocus with autoFocus default takes focus on first frame.
--
-- The hook uses `useEffect({}, [])` to subscribe, and subscription triggers
-- set_focused → setState(true). The harness stabilization loop rolls the
-- extra render into the first paint so isFocused=true is visible up front.

function suite:test_single_autofocus_by_default()
    local function App()
        local f = tui.useFocus { id = "only" }
        return tui.Text { f.isFocused and "Y" or "N" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(h:focus_id(), "only")
    lt.assertEquals(h:frame(), "Y")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 2. Two entries + Tab / Shift-Tab cycle.
--
-- Entry ordering == subscription order == reconciler DFS preorder == Tab
-- order. First entry auto-focuses (single entry rule at the time of its
-- mount); after the second subscribes, focus stays on the first.

function suite:test_tab_and_shift_tab_cycle()
    local function A() local f = tui.useFocus { id = "a" }; return tui.Text { f.isFocused and "A*" or "A " } end
    local B_impl = function()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local function App()
        return tui.Box {
            flexDirection = "column",
            { kind = "component", fn = A,      props = {} },
            { kind = "component", fn = B_impl, props = {} },
        }
    end

    local h = testing.render(App, { cols = 2, rows = 2 })
    lt.assertEquals(h:focus_id(), "a")

    h:press("tab")
    lt.assertEquals(h:focus_id(), "b")
    h:press("tab")     -- wrap back to "a"
    lt.assertEquals(h:focus_id(), "a")
    h:press("shift+tab")
    lt.assertEquals(h:focus_id(), "b")   -- prev from a wraps to last
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. useFocusManager().focus(id) can jump arbitrarily.

function suite:test_focus_manager_jump()
    local jump_to
    local function Child(props)
        tui.useFocus { id = props.id }
        return tui.Text { props.id }
    end
    local function App()
        local fm = tui.useFocusManager()
        jump_to = fm.focus
        return tui.Box {
            flexDirection = "column",
            { kind = "component", fn = Child, props = { id = "x" } },
            { kind = "component", fn = Child, props = { id = "y" } },
            { kind = "component", fn = Child, props = { id = "z" } },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 3 })
    lt.assertEquals(h:focus_id(), "x")
    jump_to("z")
    h:rerender()
    lt.assertEquals(h:focus_id(), "z")
    jump_to("y")
    h:rerender()
    lt.assertEquals(h:focus_id(), "y")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 4. disableFocus() makes Tab fall back to broadcast.
--
-- We register a plain useInput to capture Tab, which only happens when the
-- focus system is disabled (otherwise Tab is swallowed upstream).

function suite:test_disable_focus_falls_back_to_broadcast()
    local seen_tab = false
    local disable_it
    local function App()
        local fm = tui.useFocusManager()
        disable_it = fm.disableFocus
        tui.useFocus { id = "only" }
        tui.useInput(function(_, key)
            if key.name == "tab" then seen_tab = true end
        end)
        return tui.Text { "x" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(h:focus_id(), "only")

    h:press("tab")
    lt.assertEquals(seen_tab, false, "tab should be swallowed while focus is enabled")

    disable_it()
    h:press("tab")
    lt.assertEquals(seen_tab, true, "tab should reach useInput once focus is disabled")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. Unmounting the focused entry transfers focus to the neighbor; the
--    dropped id is no longer reachable via Tab.

function suite:test_unmount_transfers_focus()
    local set_show
    local function Child(props)
        tui.useFocus { id = props.id }
        return tui.Text { props.id }
    end
    local function App()
        local s, setS = tui.useState(true)
        set_show = setS
        local children = {
            flexDirection = "column",
            { kind = "component", fn = Child, props = { id = "a" } },
            { kind = "component", fn = Child, props = { id = "b" } },
        }
        if s then
            children[#children + 1] = { kind = "component", fn = Child, props = { id = "c" } }
        end
        return tui.Box(children)
    end

    local h = testing.render(App, { cols = 1, rows = 3 })
    lt.assertEquals(h:focus_id(), "a")

    h:press("tab"); lt.assertEquals(h:focus_id(), "b")
    h:press("tab"); lt.assertEquals(h:focus_id(), "c")

    set_show(false)                         -- unmount "c"
    h:rerender()

    -- "c" was focused and is gone; transfer rule picks the entry now at
    -- c's old index. With c removed, index 3 clamps to #entries (=2) → "b".
    lt.assertEquals(h:focus_id(), "b")

    -- "c" must no longer appear in the chain.
    h:press("tab"); lt.assertEquals(h:focus_id(), "a")
    h:press("tab"); lt.assertEquals(h:focus_id(), "b")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 6. TextInput autoFocus default: after render, typing writes to the input
-- without any explicit focus setup by the test.

function suite:test_textinput_autofocus_default()
    local value = ""
    local function App()
        return tui.Box {
            width = 20, height = 1,
            tui.TextInput {
                value    = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:type("hi")
    lt.assertEquals(value, "hi")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 7. Two TextInputs + Tab: the second input only receives keys after Tab.

function suite:test_two_textinputs_tab_routes()
    local a, b = "", ""
    local function App()
        return tui.Box {
            flexDirection = "column",
            width = 20, height = 2,
            tui.TextInput {
                focusId  = "inA",
                value    = a,
                onChange = function(v) a = v end,
            },
            tui.TextInput {
                focusId  = "inB",
                value    = b,
                onChange = function(v) b = v end,
            },
        }
    end

    local h = testing.render(App, { cols = 20, rows = 2 })
    lt.assertEquals(h:focus_id(), "inA")
    h:type("x")
    lt.assertEquals(a, "x")
    lt.assertEquals(b, "")

    h:press("tab")
    lt.assertEquals(h:focus_id(), "inB")
    h:type("y")
    lt.assertEquals(a, "x")
    lt.assertEquals(b, "y")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 8. Tab order stays stable across rerenders triggered by unrelated state.
--
-- This is the critical regression for "useFocus must subscribe in
-- useEffect({}, []), not every render". If a component resubscribed on
-- every render, each rerender would append a new entry and the Tab
-- traversal would drift or duplicate.

function suite:test_tab_order_stable_across_rerenders()
    local bump
    local function Child(props)
        tui.useFocus { id = props.id }
        return tui.Text { props.id }
    end
    local function App()
        local n, setN = tui.useState(0)
        bump = function() setN(n + 1) end
        return tui.Box {
            flexDirection = "column",
            tui.Text { ("n=%d"):format(n) },
            { kind = "component", fn = Child, props = { id = "p" } },
            { kind = "component", fn = Child, props = { id = "q" } },
        }
    end

    local h = testing.render(App, { cols = 5, rows = 3 })
    lt.assertEquals(h:focus_id(), "p")

    -- Force three rerenders via unrelated state. If useFocus's subscription
    -- ran every render, each rerender would re-append p and q and the chain
    -- length would balloon.
    for _ = 1, 3 do bump(); h:rerender() end

    local entries = require("tui.focus")._entries()
    lt.assertEquals(#entries, 2, "chain must not grow under rerenders, got " .. #entries)
    lt.assertEquals(entries[1].id, "p")
    lt.assertEquals(entries[2].id, "q")

    -- Tab traversal still cleanly flips p ↔ q.
    h:press("tab"); lt.assertEquals(h:focus_id(), "q")
    h:press("tab"); lt.assertEquals(h:focus_id(), "p")
    h:unmount()
end
