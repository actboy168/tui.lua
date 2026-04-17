-- test/test_reconciler_keys.lua — sibling identity via `key` prop.
--
-- Semantics under test:
--   * `key` on an element lifts its reconciler path out of the positional
--     scheme (`parent/i`) into a keyed namespace (`parent/#<key>`). Among
--     siblings, re-ordering / insertion / deletion preserves instance
--     identity as long as the key is stable.
--   * Elements without a `key` keep the original positional semantics
--     (regression: existing behavior is untouched).
--   * The two namespaces do not collide, so mixing keyed and unkeyed
--     siblings is allowed.
--   * Duplicate keys among the same parent are a render-time error.
--   * A child whose key changes (at the same array position) is treated as
--     a new element: the old instance unmounts (cleanup runs), a fresh one
--     mounts.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "reconciler_keys"

local function comp(fn, props, key)
    local e = { kind = "component", fn = fn, props = props or {} }
    if key ~= nil then e.key = key end
    return e
end

-- Build a component whose render captures its current state into `log[id]`
-- and a setter into `setters[id]`. This lets a test detect whether the
-- instance was preserved across renders (by watching if the setter still
-- mutates the same displayed value) or remounted (state resets to 0).
local function make_tagger(log, setters)
    return function(props)
        local id = props.id
        local n, setN = tui.useState(0)
        log[id] = n
        setters[id] = setN
        return tui.Text { tostring(id) .. "=" .. tostring(n) }
    end
end

-- ---------------------------------------------------------------------------
-- 1. Reorder preserves instance identity when keys are stable.

function suite:test_reorder_preserves_state_via_key()
    local log, setters = {}, {}
    local Tagger = make_tagger(log, setters)

    local order = { "a", "b" }
    local function App()
        local kids = {}
        for _, id in ipairs(order) do
            kids[#kids + 1] = comp(Tagger, { id = id }, id)
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.render(App, { cols = 5, rows = 2 })
    setters.a(7)
    setters.b(9)
    h:rerender()
    lt.assertEquals(log.a, 7)
    lt.assertEquals(log.b, 9)

    -- Swap order. Without key, each position's instance would be reused (so
    -- "a=7" would move to position 2 but keep its state), which *accidentally*
    -- looks the same in this test. To actually verify key-based matching, we
    -- assert the rendered row order changes AND the states follow the ids.
    order = { "b", "a" }
    h:rerender()
    lt.assertEquals(log.a, 7, "a's state must survive reorder")
    lt.assertEquals(log.b, 9, "b's state must survive reorder")
    lt.assertEquals(h:row(1), "b=9  ")
    lt.assertEquals(h:row(2), "a=7  ")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 2. Inserting at the head doesn't remount the existing keyed child.

function suite:test_insert_at_head_preserves_existing()
    local log, setters = {}, {}
    local Tagger = make_tagger(log, setters)

    local items = { "a" }
    local function App()
        local kids = {}
        for _, id in ipairs(items) do
            kids[#kids + 1] = comp(Tagger, { id = id }, id)
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.render(App, { cols = 5, rows = 2 })
    setters.a(3)
    h:rerender()
    lt.assertEquals(log.a, 3)

    items = { "new", "a" }
    h:rerender()
    lt.assertEquals(log.a, 3, "a must keep its state after head insertion")
    lt.assertEquals(log.new, 0, "new child mounts with initial state")
    lt.assertEquals(h:row(1), "new=0")
    lt.assertEquals(h:row(2), "a=3  ")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 3. Deleting the middle keyed child runs its cleanup; siblings untouched.

function suite:test_delete_middle_cleans_up_only_that_one()
    local cleanups = {}
    local function Tagger(props)
        local id = props.id
        tui.useEffect(function()
            return function() cleanups[#cleanups + 1] = id end
        end, {})
        return tui.Text { id }
    end

    local items = { "a", "b", "c" }
    local function App()
        local kids = {}
        for _, id in ipairs(items) do
            kids[#kids + 1] = comp(Tagger, { id = id }, id)
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.render(App, { cols = 2, rows = 3 })
    lt.assertEquals(#cleanups, 0)

    items = { "a", "c" }
    h:rerender()
    lt.assertEquals(cleanups, { "b" }, "only b's cleanup should run")
    lt.assertEquals(h:row(1), "a ")
    lt.assertEquals(h:row(2), "c ")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 4. Regression: without keys, the original positional behavior holds.
--    Reordering siblings REMOUNTS because positions swap (React pre-key
--    behavior). State resets to the initial value at each new position.

function suite:test_no_key_positional_regression()
    local log, setters = {}, {}
    local Tagger = make_tagger(log, setters)

    local order = { "a", "b" }
    local function App()
        local kids = {}
        for _, id in ipairs(order) do
            -- no key
            kids[#kids + 1] = comp(Tagger, { id = id })
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.render(App, { cols = 5, rows = 2 })
    setters.a(5); setters.b(6)
    h:rerender()
    lt.assertEquals(log.a, 5)
    lt.assertEquals(log.b, 6)

    -- Swap order. Positions 1 and 2 keep their instances; props.id changes
    -- under them, so the captured state at each slot stays (5, 6) but the
    -- displayed id flips. (That is: slot-1's instance now writes log["b"]=5
    -- because it re-ran with id="b".)
    order = { "b", "a" }
    h:rerender()
    lt.assertEquals(log.b, 5, "slot 1's instance persisted; id label changed")
    lt.assertEquals(log.a, 6, "slot 2's instance persisted; id label changed")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 5. Mixed keyed + unkeyed siblings coexist (separate namespaces).

function suite:test_mixed_keyed_and_unkeyed()
    local log, setters = {}, {}
    local Tagger = make_tagger(log, setters)

    local function App()
        return tui.Box {
            flexDirection = "column",
            comp(Tagger, { id = "a" }, "a"),   -- keyed
            comp(Tagger, { id = "X" }),         -- unkeyed at index 2
            comp(Tagger, { id = "c" }, "c"),   -- keyed
        }
    end

    local h = testing.render(App, { cols = 5, rows = 3 })
    setters.a(1); setters.X(2); setters.c(3)
    h:rerender()
    lt.assertEquals(log.a, 1)
    lt.assertEquals(log.X, 2)
    lt.assertEquals(log.c, 3)
    -- All three instances still work on next rerender.
    h:rerender()
    lt.assertEquals(log.a, 1)
    lt.assertEquals(log.X, 2)
    lt.assertEquals(log.c, 3)

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 6. Duplicate keys in the same parent raise a render-time error.

function suite:test_duplicate_key_errors()
    local function Noop() return tui.Text { "x" } end

    local function App()
        return tui.Box {
            comp(Noop, {}, "same"),
            comp(Noop, {}, "same"),
        }
    end

    local ok, err = pcall(function()
        testing.render(App, { cols = 2, rows = 2 })
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("duplicate key", 1, true) ~= nil, true,
        "expected 'duplicate key' in error, got: " .. tostring(err))
    lt.assertEquals(err:find("'same'", 1, true) ~= nil, true,
        "error should name the offending key")
end

-- ---------------------------------------------------------------------------
-- 7. Changing a key at a fixed position unmounts the old instance and
--    mounts a fresh one.

function suite:test_key_change_forces_remount()
    local cleanups = {}
    local function Child(props)
        tui.useEffect(function()
            return function() cleanups[#cleanups + 1] = props.id end
        end, {})
        return tui.Text { props.id }
    end

    local current_key = "k1"
    local function App()
        return tui.Box {
            comp(Child, { id = current_key }, current_key),
        }
    end

    local h = testing.render(App, { cols = 2, rows = 1 })
    lt.assertEquals(#cleanups, 0)

    current_key = "k2"
    h:rerender()
    lt.assertEquals(cleanups, { "k1" }, "old-key instance must cleanup")
    lt.assertEquals(h:frame(), "k2")

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 8. Keys on host elements stabilize their component descendants' identity.
--    Without a key on the wrapping Box, reordering the Boxes would change
--    the path of the inner component and remount it. With the key, the
--    inner component's state survives the reorder.

function suite:test_host_key_stabilizes_descendants()
    local log, setters = {}, {}
    local Tagger = make_tagger(log, setters)

    local order = { "a", "b" }
    local function App()
        local rows = {}
        for _, id in ipairs(order) do
            rows[#rows + 1] = tui.Box {
                key = id,
                comp(Tagger, { id = id }),
            }
        end
        return tui.Box { flexDirection = "column", table.unpack(rows) }
    end

    local h = testing.render(App, { cols = 5, rows = 2 })
    setters.a(11); setters.b(22)
    h:rerender()
    lt.assertEquals(log.a, 11)
    lt.assertEquals(log.b, 22)

    order = { "b", "a" }
    h:rerender()
    -- If identity survived, the displayed numbers follow the ids. If it did
    -- not, both would have reset or swapped to the other slot's value.
    lt.assertEquals(log.a, 11, "a's descendant state survives host reorder")
    lt.assertEquals(log.b, 22, "b's descendant state survives host reorder")
    lt.assertEquals(h:row(1), "b=22 ")
    lt.assertEquals(h:row(2), "a=11 ")

    h:unmount()
end
