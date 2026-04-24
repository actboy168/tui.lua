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
    local TaggerComp = tui.component(Tagger)

    local order = { "a", "b" }
    local function App()
        local kids = {}
        for _, id in ipairs(order) do
            kids[#kids + 1] = TaggerComp { id = id, key = id }
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.harness(App, { cols = 5, rows = 2 })
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
    local TaggerComp = tui.component(Tagger)

    local items = { "a" }
    local function App()
        local kids = {}
        for _, id in ipairs(items) do
            kids[#kids + 1] = TaggerComp { id = id, key = id }
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.harness(App, { cols = 5, rows = 2 })
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
    local TaggerComp = tui.component(Tagger)

    local items = { "a", "b", "c" }
    local function App()
        local kids = {}
        for _, id in ipairs(items) do
            kids[#kids + 1] = TaggerComp { id = id, key = id }
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.harness(App, { cols = 2, rows = 3 })
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
    testing.capture_stderr(function()
        local log, setters = {}, {}
        local Tagger = make_tagger(log, setters)
        local TaggerComp = tui.component(Tagger)

        local order = { "a", "b" }
        local function App()
            local kids = {}
            for _, id in ipairs(order) do
                -- no key
                kids[#kids + 1] = TaggerComp { id = id }
            end
            return tui.Box { flexDirection = "column", table.unpack(kids) }
        end

        local h = testing.harness(App, { cols = 5, rows = 2 })
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
    end)
end

-- ---------------------------------------------------------------------------
-- 5. Mixed keyed + unkeyed siblings coexist (separate namespaces).

function suite:test_mixed_keyed_and_unkeyed()
    testing.capture_stderr(function()
        local log, setters = {}, {}
        local Tagger = make_tagger(log, setters)
        local TaggerComp = tui.component(Tagger)

        local function App()
            return tui.Box {
                flexDirection = "column",
                TaggerComp { id = "a", key = "a" },   -- keyed
                TaggerComp { id = "X" },               -- unkeyed at index 2
                TaggerComp { id = "c", key = "c" },   -- keyed
            }
        end

        local h = testing.harness(App, { cols = 5, rows = 3 })
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
    end)
end

-- ---------------------------------------------------------------------------
-- 6. Duplicate keys in the same parent raise a render-time error.

function suite:test_duplicate_key_errors()
    local function Noop() return tui.Text { "x" } end
    local NoopComp = tui.component(Noop)

    local function App()
        return tui.Box {
            NoopComp { key = "same" },
            NoopComp { key = "same" },
        }
    end

    local ok, err = pcall(function()
        testing.harness(App, { cols = 2, rows = 2 })
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
    local ChildComp = tui.component(Child)

    local current_key = "k1"
    local function App()
        return tui.Box {
            ChildComp { id = current_key, key = current_key },
        }
    end

    local h = testing.harness(App, { cols = 2, rows = 1 })
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
    local TaggerComp = tui.component(Tagger)

    local order = { "a", "b" }
    local function App()
        local rows = {}
        for _, id in ipairs(order) do
            rows[#rows + 1] = tui.Box {
                key = id,
                TaggerComp { id = id },
            }
        end
        return tui.Box { flexDirection = "column", table.unpack(rows) }
    end

    local h = testing.harness(App, { cols = 5, rows = 2 })
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

-- ---------------------------------------------------------------------------
-- 9. Scale: 100 keyed children randomly reshuffled across two rerenders
--    must all retain their individual state. Coverage for the matching
--    path under many siblings (previously only exercised with <10).

function suite:test_large_random_reorder_preserves_all_state()
    local log, setters = {}, {}
    local Tagger = make_tagger(log, setters)
    local TaggerComp = tui.component(Tagger)

    local ids = {}
    for i = 1, 100 do ids[i] = "k" .. i end

    local order = {}
    for i, id in ipairs(ids) do order[i] = id end

    local function App()
        local kids = {}
        for _, id in ipairs(order) do
            kids[#kids + 1] = TaggerComp { id = id, key = id }
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.harness(App, { cols = 8, rows = 100 })
    -- Seed each child's state with its numeric index so we can verify the
    -- value still belongs to the same id after shuffling.
    for i, id in ipairs(ids) do setters[id](i * 3) end
    h:rerender()
    for i, id in ipairs(ids) do lt.assertEquals(log[id], i * 3) end

    -- Deterministic pseudo-random shuffle (Fisher-Yates with a fixed LCG)
    -- — test must be reproducible.
    local function shuffle(arr)
        local rng = 0x12345
        for i = #arr, 2, -1 do
            rng = (rng * 1103515245 + 12345) & 0x7fffffff
            local j = (rng % i) + 1
            arr[i], arr[j] = arr[j], arr[i]
        end
    end
    shuffle(order)
    h:rerender()
    for i, id in ipairs(ids) do
        lt.assertEquals(log[id], i * 3,
            "id " .. id .. " lost state after first shuffle")
    end

    shuffle(order)
    h:rerender()
    for i, id in ipairs(ids) do
        lt.assertEquals(log[id], i * 3,
            "id " .. id .. " lost state after second shuffle")
    end

    h:unmount()
end

-- ---------------------------------------------------------------------------
-- 10. Mixed keyed + unkeyed siblings survive interleaved insert/delete.
--     Keyed children match by key; unkeyed fall back to positional slot
--     *within* the unkeyed subsequence.

function suite:test_interleaved_insert_delete_mixed_keys()
    testing.capture_stderr(function()
        local log, setters = {}, {}
        local Tagger = make_tagger(log, setters)
        local TaggerComp = tui.component(Tagger)

        -- Each entry is { id, use_key }. If use_key is true the element has a
        -- `key` equal to its id; otherwise it is unkeyed.
        local items = {
            { "a", true  },
            { "x", false },
            { "b", true  },
            { "y", false },
            { "c", true  },
        }

        local function App()
            local kids = {}
            for _, it in ipairs(items) do
                local id, use_key = it[1], it[2]
                kids[#kids + 1] = TaggerComp { id = id, key = use_key and id or nil }
            end
            return tui.Box { flexDirection = "column", table.unpack(kids) }
        end

        local h = testing.harness(App, { cols = 5, rows = 10 })
        setters.a(1); setters.x(2); setters.b(3); setters.y(4); setters.c(5)
        h:rerender()
        lt.assertEquals(log.a, 1); lt.assertEquals(log.b, 3); lt.assertEquals(log.c, 5)

        -- Delete one keyed ("b") and one unkeyed ("y"), then insert a new keyed
        -- child ("d") at the front. Keyed survivors must retain state; the
        -- remaining unkeyed slot is now occupied by a relabeled instance, as
        -- per unkeyed-positional semantics from test #4.
        items = {
            { "d", true  },  -- new keyed, mounts fresh
            { "a", true  },
            { "x", false },
            { "c", true  },
        }
        h:rerender()
        lt.assertEquals(log.a, 1, "keyed 'a' survived delete+insert")
        lt.assertEquals(log.c, 5, "keyed 'c' survived delete+insert")
        lt.assertEquals(log.d, 0, "new keyed 'd' mounted fresh")

        h:unmount()
    end)
end

-- ---------------------------------------------------------------------------
-- 11. Key rename + order change at the same time. A child whose key changes
--     is a fresh instance regardless of position; other keys still match.

function suite:test_key_rename_plus_reorder()
    local log, setters = {}, {}
    local Tagger = make_tagger(log, setters)
    local TaggerComp = tui.component(Tagger)

    -- Original keys: a, b, c, d in order.
    local entries = {
        { id = "a", key = "a" },
        { id = "b", key = "b" },
        { id = "c", key = "c" },
        { id = "d", key = "d" },
    }

    local function App()
        local kids = {}
        for _, e in ipairs(entries) do
            kids[#kids + 1] = TaggerComp { id = e.id, key = e.key }
        end
        return tui.Box { flexDirection = "column", table.unpack(kids) }
    end

    local h = testing.harness(App, { cols = 6, rows = 4 })
    setters.a(10); setters.b(20); setters.c(30); setters.d(40)
    h:rerender()

    -- Rename keys a→z, b→x AND reverse the order to DCBA. c/d keep their
    -- keys, so only their instances survive; a/b are fresh mounts under
    -- their new keys.
    entries = {
        { id = "d", key = "d" },
        { id = "c", key = "c" },
        { id = "b", key = "x" },
        { id = "a", key = "z" },
    }
    h:rerender()
    lt.assertEquals(log.c, 30, "c survived reorder (key unchanged)")
    lt.assertEquals(log.d, 40, "d survived reorder (key unchanged)")
    -- The instances rendered under keys x/z are FRESH — so log[id="a"] and
    -- log[id="b"] are the most recent state pushes from the new instances.
    lt.assertEquals(log.a, 0, "key rename z: fresh instance with initial state")
    lt.assertEquals(log.b, 0, "key rename x: fresh instance with initial state")

    h:unmount()
end
