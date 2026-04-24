-- test/test_focus.lua — unit tests for the focus chain and useFocus /
-- useFocusManager hooks.
--
-- Every test drives the tree through tui.testing; we assert against
-- focus_mod.get_focused_id() (which reads tui.focus.get_focused_id) and, where relevant,
-- against the rendered text to verify isFocused reflects back into state.

local lt      = require "ltest"
local tui     = require "tui"
local extra = require "tui.extra"
local testing = require "tui.testing"
local focus_mod = require "tui.internal.focus"

local suite = lt.test "focus"

-- ---------------------------------------------------------------------------
-- 1. Bare useFocus (no autoFocus) does NOT auto-focus — strict Ink semantics.
-- Explicit autoFocus=true is required; the hook otherwise just registers
-- the entry into the Tab chain.

function suite:test_bare_useFocus_does_not_autofocus()
    local function App()
        local f = tui.useFocus { id = "only" }
        return tui.Text { f.isFocused and "Y" or "N" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(focus_mod.get_focused_id(), nil)
    lt.assertEquals(h:frame(), "N")
    h:unmount()
end

function suite:test_autofocus_true_takes_focus()
    local function App()
        local f = tui.useFocus { id = "only", autoFocus = true }
        return tui.Text { f.isFocused and "Y" or "N" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(focus_mod.get_focused_id(), "only")
    -- autoFocus sets focused_id synchronously, but isFocused state is
    -- consumed on the next paint.
    h:rerender()
    lt.assertEquals(h:frame(), "Y")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 2. Two entries + Tab / Shift-Tab cycle.
--
-- Entry ordering == subscription order == reconciler DFS preorder == Tab
-- order. Only "a" has autoFocus=true (strict Ink semantics); once it
-- grabs focus, Tab/Shift-Tab navigate between both.

function suite:test_tab_and_shift_tab_cycle()
    local function A() local f = tui.useFocus { id = "a", autoFocus = true }; return tui.Text { f.isFocused and "A*" or "A " } end
    local B_impl = function()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B_impl)
    local function App()
        return tui.Box {
            flexDirection = "column",
            AComp {},
            BComp {},
        }
    end

    local h = testing.render(App, { cols = 2, rows = 2 })
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    h:press("tab")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")
    h:press("tab")     -- wrap back to "a"
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")
    h:press("shift+tab")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")   -- prev from a wraps to last
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. useFocusManager().focus(id) can jump arbitrarily.

function suite:test_focus_manager_jump()
    local jump_to
    local function Child(props)
        tui.useFocus { id = props.id, autoFocus = props.autoFocus }
        return tui.Text { props.id }
    end
    local ChildComp = tui.component(Child)
    local function App()
        local fm = tui.useFocusManager()
        jump_to = fm.focus
        return tui.Box {
            flexDirection = "column",
            ChildComp { id = "x", autoFocus = true, key = "x" },
            ChildComp { id = "y", key = "y" },
            ChildComp { id = "z", key = "z" },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 3 })
    lt.assertEquals(focus_mod.get_focused_id(), "x")
    jump_to("z")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "z")
    jump_to("y")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "y")
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
        tui.useFocus { id = "only", autoFocus = true }
        tui.useInput(function(_, key)
            if key.name == "tab" then seen_tab = true end
        end)
        return tui.Text { "x" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(focus_mod.get_focused_id(), "only")

    h:press("tab")
    h:rerender()
    lt.assertEquals(seen_tab, false, "tab should be swallowed while focus is enabled")

    disable_it()
    h:press("tab")
    h:rerender()
    lt.assertEquals(seen_tab, true, "tab should reach useInput once focus is disabled")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. Unmounting the focused entry transfers focus to the neighbor; the
--    dropped id is no longer reachable via Tab.

function suite:test_unmount_transfers_focus()
    local set_show
    local function Child(props)
        tui.useFocus { id = props.id, autoFocus = props.autoFocus }
        return tui.Text { props.id }
    end
    local ChildComp = tui.component(Child)
    local function App()
        local s, setS = tui.useState(true)
        set_show = setS
        local children = {
            flexDirection = "column",
            ChildComp { id = "a", autoFocus = true, key = "a" },
            ChildComp { id = "b", key = "b" },
        }
        if s then
            children[#children + 1] = ChildComp { id = "c", key = "c" }
        end
        return tui.Box(children)
    end

    local h = testing.render(App, { cols = 1, rows = 3 })
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "b")
    h:rerender()
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "c")


    set_show(false)                         -- unmount "c"
    h:rerender()

    -- "c" was focused and is gone; transfer rule picks the entry now at
    -- c's old index. With c removed, index 3 clamps to #entries (=2) → "b".
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    -- "c" must no longer appear in the chain.
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "a")
    h:rerender()
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "b")
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
            extra.TextInput {
                value    = value,
                onChange = function(v) value = v end,
            },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 1 })
    h:type("hi")
    h:rerender()
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
            extra.TextInput {
                focusId  = "inA",
                value    = a,
                onChange = function(v) a = v end,
            },
            extra.TextInput {
                focusId  = "inB",
                value    = b,
                onChange = function(v) b = v end,
            },
        }
    end

    local h = testing.render(App, { cols = 20, rows = 2 })
    lt.assertEquals(focus_mod.get_focused_id(), "inA")
    h:type("x")
    h:rerender()
    lt.assertEquals(a, "x")
    lt.assertEquals(b, "")

    h:press("tab")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "inB")
    h:type("y")
    h:rerender()
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
        tui.useFocus { id = props.id, autoFocus = props.autoFocus }
        return tui.Text { props.id }
    end
    local ChildComp = tui.component(Child)
    local function App()
        local n, setN = tui.useState(0)
        bump = function() setN(n + 1) end
        return tui.Box {
            flexDirection = "column",
            tui.Text { ("n=%d"):format(n), key = "heading" },
            ChildComp { id = "p", autoFocus = true, key = "p" },
            ChildComp { id = "q", key = "q" },
        }
    end

    local h = testing.render(App, { cols = 5, rows = 3 })
    lt.assertEquals(focus_mod.get_focused_id(), "p")

    -- Force three rerenders via unrelated state. If useFocus's subscription
    -- ran every render, each rerender would re-append p and q and the chain
    -- length would balloon.
    for _ = 1, 3 do bump(); h:rerender() end

    local entries = require("tui.internal.focus")._entries()
    lt.assertEquals(#entries, 2, "chain must not grow under rerenders, got " .. #entries)
    lt.assertEquals(entries[1].id, "p")
    lt.assertEquals(entries[2].id, "q")

    -- Tab traversal still cleanly flips p ↔ q.
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "q")
    h:rerender()
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "p")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 9. Duplicate useFocus id must hard-fail, not silently suffix.
--
-- Two components registering the same explicit id is a user bug — the
-- previous behavior (append "#<seq>") masked it and produced surprising
-- focus targets. subscribe() now raises; the reconciler surfaces the
-- error out of render via the harness's pcall boundary.

function suite:test_duplicate_focus_id_raises()
    local function DupA()
        tui.useFocus { id = "dup" }
        return tui.Text { "a" }
    end
    local function DupB()
        tui.useFocus { id = "dup" }
        return tui.Text { "b" }
    end
    local DupAComp = tui.component(DupA)
    local DupBComp = tui.component(DupB)
    local function App()
        return tui.Box {
            flexDirection = "column",
            DupAComp {},
            DupBComp {},
        }
    end

    local ok, err = pcall(function()
        testing.render(App, { cols = 2, rows = 2 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("duplicate focus id", 1, true) ~= nil, true,
        "expected 'duplicate focus id' in error, got: " .. tostring(err))
    lt.assertEquals(err:find("\"dup\"", 1, true) ~= nil, true,
        "error should name the offending id")

    -- clean up module state so later tests aren't contaminated
    require("tui.internal.focus")._reset()
end

-- ---------------------------------------------------------------------------
-- 10. isActive=false: entry is registered (keeps its slot in Tab order) but
-- is skipped by focus_next / focus_prev, and never auto-focuses even with
-- autoFocus=true.

function suite:test_inactive_entry_is_skipped_by_tab()
    local function Child(props)
        tui.useFocus { id = props.id, autoFocus = props.autoFocus, isActive = props.isActive }
        return tui.Text { props.id }
    end
    local ChildComp = tui.component(Child)
    local function App()
        return tui.Box {
            flexDirection = "column",
            ChildComp { id = "a", autoFocus = true, key = "a" },
            ChildComp { id = "b", isActive = false, key = "b" },
            ChildComp { id = "c", key = "c" },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 3 })
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    -- Tab skips the inactive "b" and lands on "c".
    h:press("tab");       h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "c")
    h:rerender()
    h:press("tab");       h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "a")   -- wraps, still skipping b
    h:rerender()
    h:press("shift+tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "c")   -- wrap back, skip b
    h:rerender()
    h:press("shift+tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "a")


    -- Explicit focus(id) still lands on an inactive entry (user intent).
    require("tui.internal.focus").focus("b")
    lt.assertEquals(focus_mod.get_focused_id(), "b")
    h:unmount()
end

function suite:test_inactive_does_not_autofocus()
    local function App()
        local f = tui.useFocus { id = "only", autoFocus = true, isActive = false }
        return tui.Text { f.isFocused and "Y" or "N" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(focus_mod.get_focused_id(), nil, "autoFocus should be ignored when isActive=false")
    lt.assertEquals(h:frame(), "N")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 11. Hot-updating isActive.
-- Flipping the flag on a rerender updates the entry in place: Tab
-- navigation honors the new value and the focused entry transfers when
-- it goes inactive.

function suite:test_isactive_hot_update_transfers_focus()
    local set_b_active
    local function A() tui.useFocus { id = "a" }; return tui.Text { "a" } end
    local function B()
        local active, setActive = tui.useState(true)
        set_b_active = setActive
        tui.useFocus { id = "b", autoFocus = true, isActive = active }
        return tui.Text { "b" }
    end
    local function C() tui.useFocus { id = "c" }; return tui.Text { "c" } end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local CComp = tui.component(C)
    local function App()
        return tui.Box {
            flexDirection = "column",
            AComp { key = "a" },
            BComp { key = "b" },
            CComp { key = "c" },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 3 })
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    -- Deactivate b: focus should walk forward to c (next active neighbor).
    set_b_active(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "c")

    -- Tab now skips b.
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "a")
    h:rerender()
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "c")    -- skips b


    -- Reactivating b does not steal focus, but b is reachable via Tab again.
    set_b_active(true)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "c")
    h:press("shift+tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "b")
    h:unmount()
end

function suite:test_isactive_hot_update_clears_when_all_inactive()
    local set_active
    local function App()
        local a, setA = tui.useState(true)
        set_active = setA
        tui.useFocus { id = "only", autoFocus = true, isActive = a }
        return tui.Text { "x" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(focus_mod.get_focused_id(), "only")
    set_active(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), nil, "focus clears when the only entry goes inactive")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 12. Hot-updating id triggers re-subscribe (old entry unmounts, new entry
-- appends at the tail). The hot-updated component ends up last in Tab
-- order and its autoFocus is re-evaluated against the new registration.

function suite:test_id_hot_update_resubscribes()
    local set_id
    local function B()
        local id, setId = tui.useState("b")
        set_id = setId
        tui.useFocus { id = id }
        return tui.Text { id }
    end
    local function Static(props) tui.useFocus { id = props.id }; return tui.Text { props.id } end
    local StaticComp = tui.component(Static)
    local BComp = tui.component(B)
    local function App()
        return tui.Box {
            flexDirection = "column",
            StaticComp { id = "a", key = "a" },
            BComp { key = "b" },
            StaticComp { id = "c", key = "c" },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 3 })
    local ids = function()
        local out = {}
        for _, e in ipairs(testing.focus_entries()) do out[#out + 1] = e.id end
        return table.concat(out, ",")
    end
    lt.assertEquals(ids(), "a,b,c")

    set_id("b2")
    h:rerender()
    -- "b" unsubscribed; "b2" appended at tail.
    lt.assertEquals(ids(), "a,c,b2")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 13. TextInput with focus=false still registers as an inactive entry.
-- Tab navigation skips it; focus lands on the active siblings only.
-- This verifies the merged (single-branch) useFocus path in text_input.

function suite:test_textinput_disabled_is_inactive_entry()
    local function App()
        return tui.Box {
            flexDirection = "column",
            width = 20, height = 3,
            extra.TextInput { focusId = "top",    value = "",                  key = "top" },
            extra.TextInput { focusId = "middle", value = "", focus = false, key = "middle" },
            extra.TextInput { focusId = "bottom", value = "",                  key = "bottom" },
        }
    end

    local h = testing.render(App, { cols = 20, rows = 3 })
    -- All three are in the chain (stable hook call order).
    lt.assertEquals(#testing.focus_entries(), 3)
    -- First active one autoFocuses (TextInput default).
    lt.assertEquals(focus_mod.get_focused_id(), "top")
    -- Tab skips the inactive middle input.
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "bottom")
    h:rerender()
    h:press("tab"); h:rerender(); lt.assertEquals(focus_mod.get_focused_id(), "top")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 14. Focus stack: explicit focus() pushes the old focus; unmounting the
--     focused entry restores the previous one.
-- ---------------------------------------------------------------------------

function suite:test_focus_stack_restores_on_unmount()
    local set_show_b
    local function A()
        local f = tui.useFocus { id = "a", autoFocus = true }
        return tui.Text { f.isFocused and "A*" or "A " }
    end
    local function B()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local function App()
        local show, setShow = tui.useState(false)
        set_show_b = setShow
        return tui.Box {
            flexDirection = "column",
            AComp {},
            show and BComp {} or nil,
        }
    end

    local h = testing.render(App, { cols = 2, rows = 2 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    set_show_b(true)
    h:rerender()
    focus_mod.focus("b")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    set_show_b(false)
    h:rerender()
    -- b was focused and is gone; focus should be restored to a via the stack.
    lt.assertEquals(focus_mod.get_focused_id(), "a")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 15. Focus stack supports multiple layers (A -> B -> C).
-- ---------------------------------------------------------------------------

function suite:test_focus_stack_multiple_layers()
    local set_show_b, set_show_c
    local function A()
        local f = tui.useFocus { id = "a", autoFocus = true }
        return tui.Text { f.isFocused and "A*" or "A " }
    end
    local function B()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local function C()
        local f = tui.useFocus { id = "c" }
        return tui.Text { f.isFocused and "C*" or "C " }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local CComp = tui.component(C)
    local function App()
        local showB, setShowB = tui.useState(false)
        local showC, setShowC = tui.useState(false)
        set_show_b = setShowB
        set_show_c = setShowC
        return tui.Box {
            flexDirection = "column",
            AComp { key = "a" },
            showB and BComp { key = "b" } or nil,
            showC and CComp { key = "c" } or nil,
        }
    end

    local h = testing.render(App, { cols = 2, rows = 3 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    set_show_b(true)
    h:rerender()
    focus_mod.focus("b")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    set_show_c(true)
    h:rerender()
    focus_mod.focus("c")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "c")

    -- Pop c -> restore b
    set_show_c(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    -- Pop b -> restore a
    set_show_b(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 16. Focus stack skips entries that no longer exist.
-- ---------------------------------------------------------------------------

function suite:test_focus_stack_skips_removed_entries()
    local set_show_b, set_show_c
    local function A()
        local f = tui.useFocus { id = "a", autoFocus = true }
        return tui.Text { f.isFocused and "A*" or "A " }
    end
    local function B()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local function C()
        local f = tui.useFocus { id = "c" }
        return tui.Text { f.isFocused and "C*" or "C " }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local CComp = tui.component(C)
    local function App()
        local showB, setShowB = tui.useState(true)
        local showC, setShowC = tui.useState(false)
        set_show_b = setShowB
        set_show_c = setShowC
        return tui.Box {
            flexDirection = "column",
            AComp { key = "a" },
            showB and BComp { key = "b" } or nil,
            showC and CComp { key = "c" } or nil,
        }
    end

    local h = testing.render(App, { cols = 2, rows = 3 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    -- a -> b via focus(); stack = [a]
    focus_mod.focus("b")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    -- b -> c via focus(); stack = [a, b]
    set_show_c(true)
    h:rerender()
    focus_mod.focus("c")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "c")

    -- Remove b (middle of stack) while c is focused.
    set_show_b(false)
    h:rerender()
    -- b is gone but still in stack; c is still focused, nothing changes yet.
    lt.assertEquals(focus_mod.get_focused_id(), "c")

    -- Remove c; stack pop finds b (gone), then a (exists) -> restore a.
    set_show_c(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 17. Focus stack skips inactive entries and falls back to neighbor logic.
-- ---------------------------------------------------------------------------

function suite:test_focus_stack_skips_inactive_entries()
    local set_show_b, set_a_active
    local function A()
        local active, setActive = tui.useState(true)
        set_a_active = setActive
        local f = tui.useFocus { id = "a", autoFocus = true, isActive = active }
        return tui.Text { f.isFocused and "A*" or "A " }
    end
    local function B()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local function App()
        local showB, setShowB = tui.useState(false)
        set_show_b = setShowB
        return tui.Box {
            flexDirection = "column",
            AComp { key = "a" },
            showB and BComp { key = "b" } or nil,
        }
    end

    local h = testing.render(App, { cols = 2, rows = 2 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    set_show_b(true)
    h:rerender()
    focus_mod.focus("b")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    -- Make a inactive before removing b.
    set_a_active(false)
    h:rerender()

    -- Remove b; a is in stack but inactive -> skipped.
    -- No other entries -> focus clears.
    set_show_b(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), nil)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 18. Tab navigation does NOT push onto the focus stack.
-- ---------------------------------------------------------------------------

function suite:test_tab_does_not_push_focus_stack()
    local set_show_c
    local function A()
        local f = tui.useFocus { id = "a", autoFocus = true }
        return tui.Text { f.isFocused and "A*" or "A " }
    end
    local function B()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local function C()
        local f = tui.useFocus { id = "c" }
        return tui.Text { f.isFocused and "C*" or "C " }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local CComp = tui.component(C)
    local function App()
        local showC, setShowC = tui.useState(false)
        set_show_c = setShowC
        return tui.Box {
            flexDirection = "column",
            AComp { key = "a" },
            BComp { key = "b" },
            showC and CComp { key = "c" } or nil,
        }
    end

    local h = testing.render(App, { cols = 2, rows = 3 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    -- Tab from a to b; this should NOT push a onto the stack.
    h:press("tab")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    -- Open c and focus it explicitly; stack now has [b].
    set_show_c(true)
    h:rerender()
    focus_mod.focus("c")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "c")

    -- Remove c; if Tab had pushed a, we might get a. Instead stack pop
    -- finds b (the explicit focus() push) -> restore b.
    set_show_c(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 19. focus() on the already-focused entry does not push a duplicate.
-- ---------------------------------------------------------------------------

function suite:test_focus_same_id_no_duplicate_stack()
    local set_show_b
    local function A()
        local f = tui.useFocus { id = "a", autoFocus = true }
        return tui.Text { f.isFocused and "A*" or "A " }
    end
    local function B()
        local f = tui.useFocus { id = "b" }
        return tui.Text { f.isFocused and "B*" or "B " }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local function App()
        local showB, setShowB = tui.useState(false)
        set_show_b = setShowB
        return tui.Box {
            flexDirection = "column",
            AComp {},
            showB and BComp {} or nil,
        }
    end

    local h = testing.render(App, { cols = 2, rows = 2 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")

    set_show_b(true)
    h:rerender()
    focus_mod.focus("b")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    -- Calling focus("b") again should not push another "b" onto stack.
    focus_mod.focus("b")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")

    local stack = focus_mod._focus_stack()
    lt.assertEquals(#stack, 1)
    lt.assertEquals(stack[1], "a")

    set_show_b(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 20. onFocus / onBlur callbacks fire on focus transitions.
-- ---------------------------------------------------------------------------

function suite:test_onfocus_onblur_fire_on_transitions()
    local events = {}
    local function A()
        tui.useFocus {
            id = "a",
            autoFocus = true,
            onFocus = function() events[#events + 1] = "a:focus" end,
            onBlur  = function() events[#events + 1] = "a:blur" end,
        }
        return tui.Text { "A" }
    end
    local function B()
        tui.useFocus {
            id = "b",
            onFocus = function() events[#events + 1] = "b:focus" end,
            onBlur  = function() events[#events + 1] = "b:blur" end,
        }
        return tui.Text { "B" }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local function App()
        return tui.Box {
            flexDirection = "column",
            AComp { key = "a" },
            BComp { key = "b" },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 2 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")
    lt.assertEquals(table.concat(events, ","), "a:focus")

    -- Explicit focus() from a to b: a blurs, b focuses.
    focus_mod.focus("b")
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")
    lt.assertEquals(table.concat(events, ","), "a:focus,a:blur,b:focus")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 21. onFocus fires for autoFocus.
-- ---------------------------------------------------------------------------

function suite:test_onfocus_fires_for_autofocus()
    local events = {}
    local function App()
        tui.useFocus {
            id = "only",
            autoFocus = true,
            onFocus = function() events[#events + 1] = "focus" end,
            onBlur  = function() events[#events + 1] = "blur" end,
        }
        return tui.Text { "x" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "only")
    lt.assertEquals(table.concat(events, ","), "focus")

    -- Unmount triggers blur.
    h:unmount()
    lt.assertEquals(table.concat(events, ","), "focus,blur")
end

-- ---------------------------------------------------------------------------
-- 22. onBlur fires when focused entry is unmounted.
-- ---------------------------------------------------------------------------

function suite:test_onblur_fires_on_unmount()
    local events = {}
    local set_show
    local function A()
        tui.useFocus {
            id = "a",
            autoFocus = true,
            onFocus = function() events[#events + 1] = "a:focus" end,
            onBlur  = function() events[#events + 1] = "a:blur" end,
        }
        return tui.Text { "A" }
    end
    local function B()
        tui.useFocus {
            id = "b",
            onFocus = function() events[#events + 1] = "b:focus" end,
            onBlur  = function() events[#events + 1] = "b:blur" end,
        }
        return tui.Text { "B" }
    end
    local AComp = tui.component(A)
    local BComp = tui.component(B)
    local function App()
        local show, setShow = tui.useState(true)
        set_show = setShow
        return tui.Box {
            flexDirection = "column",
            show and AComp { key = "a" } or nil,
            BComp { key = "b" },
        }
    end

    local h = testing.render(App, { cols = 1, rows = 2 })
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "a")
    lt.assertEquals(table.concat(events, ","), "a:focus")

    -- Unmount a: a blurs, focus transfers to b (neighbor), b focuses.
    set_show(false)
    h:rerender()
    lt.assertEquals(focus_mod.get_focused_id(), "b")
    lt.assertEquals(table.concat(events, ","), "a:focus,a:blur,b:focus")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 23. onBlur fires when isActive flips to false.
-- ---------------------------------------------------------------------------

function suite:test_onblur_fires_when_isactive_goes_false()
    local events = {}
    local set_active
    local function App()
        local a, setA = tui.useState(true)
        set_active = setA
        tui.useFocus {
            id = "only",
            autoFocus = true,
            isActive = a,
            onFocus = function() events[#events + 1] = "focus" end,
            onBlur  = function() events[#events + 1] = "blur" end,
        }
        return tui.Text { "x" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    h:rerender()
    lt.assertEquals(table.concat(events, ","), "focus")

    set_active(false)
    h:rerender()
    lt.assertEquals(table.concat(events, ","), "focus,blur")

    -- Reactivating does not re-trigger onFocus (no auto-grab).
    set_active(true)
    h:rerender()
    lt.assertEquals(table.concat(events, ","), "focus,blur")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 24. onFocus / onBlur see the latest closure (useLatestRef semantics).
-- ---------------------------------------------------------------------------

function suite:test_onfocus_onblur_latest_closure()
    local counter = 0
    local bump
    local function App()
        local n, setN = tui.useState(0)
        bump = function() setN(n + 1) end
        tui.useFocus {
            id = "only",
            autoFocus = true,
            onFocus = function() counter = counter + n end,
            onBlur  = function() counter = counter - n end,
        }
        return tui.Text { ("n=%d"):format(n) }
    end

    local h = testing.render(App, { cols = 5, rows = 1 })
    h:rerender()
    lt.assertEquals(counter, 0)  -- onFocus fired with n=0

    bump()                       -- n becomes 1
    h:rerender()
    -- No focus change yet; counter unchanged.
    lt.assertEquals(counter, 0)

    -- Disable focus to trigger blur; closure should see n=1.
    focus_mod.set_active("only", false)
    h:rerender()
    lt.assertEquals(counter, -1)  -- 0 - 1

    -- Re-enable and explicitly focus; onFocus should see n=1.
    focus_mod.set_active("only", true)
    focus_mod.focus("only")
    h:rerender()
    lt.assertEquals(counter, 0)  -- -1 + 1

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 25. Focusing the already-focused entry does not re-fire onFocus.
-- ---------------------------------------------------------------------------

function suite:test_refocus_same_entry_no_duplicate_onfocus()
    local events = {}
    local function App()
        tui.useFocus {
            id = "only",
            autoFocus = true,
            onFocus = function() events[#events + 1] = "focus" end,
            onBlur  = function() events[#events + 1] = "blur" end,
        }
        return tui.Text { "x" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    h:rerender()
    lt.assertEquals(table.concat(events, ","), "focus")

    focus_mod.focus("only")
    h:rerender()
    -- No change — onFocus should not fire again.
    lt.assertEquals(table.concat(events, ","), "focus")

    h:unmount()
end
