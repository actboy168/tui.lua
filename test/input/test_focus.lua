-- test/test_focus.lua — unit tests for the focus chain and useFocus /
-- useFocusManager hooks.
--
-- Every test drives the tree through tui.testing; we assert against
-- h:focus_id() (which reads tui.focus.get_focused_id) and, where relevant,
-- against the rendered text to verify isFocused reflects back into state.

local lt      = require "ltest"
local tui     = require "tui"
local extra = require "tui.extra"
local testing = require "tui.testing"

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
    lt.assertEquals(h:focus_id(), nil)
    lt.assertEquals(h:frame(), "N")
    h:unmount()
end

function suite:test_autofocus_true_takes_focus()
    local function App()
        local f = tui.useFocus { id = "only", autoFocus = true }
        return tui.Text { f.isFocused and "Y" or "N" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(h:focus_id(), "only")
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
        tui.useFocus { id = "only", autoFocus = true }
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
            extra.TextInput {
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
    lt.assertEquals(h:focus_id(), "p")

    -- Force three rerenders via unrelated state. If useFocus's subscription
    -- ran every render, each rerender would re-append p and q and the chain
    -- length would balloon.
    for _ = 1, 3 do bump(); h:rerender() end

    local entries = require("tui.internal.focus")._entries()
    lt.assertEquals(#entries, 2, "chain must not grow under rerenders, got " .. #entries)
    lt.assertEquals(entries[1].id, "p")
    lt.assertEquals(entries[2].id, "q")

    -- Tab traversal still cleanly flips p ↔ q.
    h:press("tab"); lt.assertEquals(h:focus_id(), "q")
    h:press("tab"); lt.assertEquals(h:focus_id(), "p")
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
    lt.assertEquals(h:focus_id(), "a")

    -- Tab skips the inactive "b" and lands on "c".
    h:press("tab");       lt.assertEquals(h:focus_id(), "c")
    h:press("tab");       lt.assertEquals(h:focus_id(), "a")   -- wraps, still skipping b
    h:press("shift+tab"); lt.assertEquals(h:focus_id(), "c")   -- wrap back, skip b
    h:press("shift+tab"); lt.assertEquals(h:focus_id(), "a")

    -- Explicit focus(id) still lands on an inactive entry (user intent).
    require("tui.internal.focus").focus("b")
    lt.assertEquals(h:focus_id(), "b")
    h:unmount()
end

function suite:test_inactive_does_not_autofocus()
    local function App()
        local f = tui.useFocus { id = "only", autoFocus = true, isActive = false }
        return tui.Text { f.isFocused and "Y" or "N" }
    end

    local h = testing.render(App, { cols = 1, rows = 1 })
    lt.assertEquals(h:focus_id(), nil, "autoFocus should be ignored when isActive=false")
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
    lt.assertEquals(h:focus_id(), "b")

    -- Deactivate b: focus should walk forward to c (next active neighbor).
    set_b_active(false)
    h:rerender()
    lt.assertEquals(h:focus_id(), "c")

    -- Tab now skips b.
    h:press("tab"); lt.assertEquals(h:focus_id(), "a")
    h:press("tab"); lt.assertEquals(h:focus_id(), "c")    -- skips b

    -- Reactivating b does not steal focus, but b is reachable via Tab again.
    set_b_active(true)
    h:rerender()
    lt.assertEquals(h:focus_id(), "c")
    h:press("shift+tab"); lt.assertEquals(h:focus_id(), "b")
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
    lt.assertEquals(h:focus_id(), "only")
    set_active(false)
    h:rerender()
    lt.assertEquals(h:focus_id(), nil, "focus clears when the only entry goes inactive")
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
    lt.assertEquals(h:focus_id(), "top")
    -- Tab skips the inactive middle input.
    h:press("tab"); lt.assertEquals(h:focus_id(), "bottom")
    h:press("tab"); lt.assertEquals(h:focus_id(), "top")
    h:unmount()
end
