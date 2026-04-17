-- tui/focus.lua — focus chain state (Ink-compatible).
--
-- Model
-- -----
-- * Any component that calls useFocus() adds one "entry" to the chain.
-- * Entries are ordered by subscription time == reconciler DFS preorder
--   == user's visual top-down / left-to-right tree walk, which is the
--   intuitive Tab traversal order.
-- * At most one entry is focused at a time, by id.
-- * Tab/Shift-Tab are intercepted by tui/input.lua dispatch and translated
--   into focus_next / focus_prev here; other keys are dispatched to the
--   focused entry's on_input handler via dispatch_focused.
--
-- Invariants
-- ----------
-- * `subscribe()` MUST be called from a `useEffect({}, [])` (mount-once),
--   never from a component render body. Otherwise the Tab order drifts
--   every frame. The useFocus hook enforces this internally.
-- * On unmount of the currently-focused entry, focus transfers to the
--   entry now occupying the same index (or the last one if we were at
--   the end); chain empty → focused_id = nil.
--
-- Simplifications (see docs/roadmap.md for upgrade paths)
-- ------------------------------------------------------
-- * id conflicts are suffixed with "#<seq>" rather than hard-failed.
-- * A single-entry chain auto-focuses even without autoFocus=true,
--   so that writing a lone <TextInput> "just works". Ink is stricter.
-- * No per-entry isActive flag; use unmount (or in the future, a
--   `useFocus({ isActive = false })` extension).

local M = {}

-- -- state --------------------------------------------------------------------

local entries         = {}    -- array; order == Tab traversal order
local by_id           = {}    -- id -> entry
local focused_id      = nil
local enabled         = true
local seq_counter     = 0
local auto_id_counter = 0

-- -- internals ----------------------------------------------------------------

local function set_focused(new_entry)
    local new_id = new_entry and new_entry.id or nil
    if focused_id == new_id then return end
    local old = focused_id and by_id[focused_id] or nil
    focused_id = new_id
    if old and old.on_change then old.on_change(false) end
    if new_entry and new_entry.on_change then new_entry.on_change(true) end
end

-- -- public API ---------------------------------------------------------------

--- subscribe(opts) -> entry, unsubscribe
-- opts = {
--   id        = string?,     -- optional; auto-generated "f1"/"f2"/... otherwise
--   autoFocus = bool?,       -- force-take focus on registration
--   on_change = fn(bool),    -- called when this entry's focused state flips
--   on_input  = fn(input, key),  -- invoked when a key is dispatched to us
-- }
function M.subscribe(opts)
    opts = opts or {}
    seq_counter = seq_counter + 1
    local id = opts.id
    if not id then
        auto_id_counter = auto_id_counter + 1
        id = "f" .. auto_id_counter
    end
    if by_id[id] then
        -- Non-fatal conflict: suffix. See "更完善方案" note in roadmap.
        id = id .. "#" .. seq_counter
    end

    local entry = {
        id        = id,
        seq       = seq_counter,
        on_change = opts.on_change,
        on_input  = opts.on_input,
    }
    entries[#entries + 1] = entry
    by_id[id] = entry

    -- Ink semantics: explicit autoFocus → take focus. Additional
    -- convenience: if this is the only focusable and nobody else is
    -- focused, take it too — makes single-TextInput demos just work.
    if focused_id == nil and (opts.autoFocus or #entries == 1) then
        set_focused(entry)
    end

    local active = true
    return entry, function()
        if not active then return end
        active = false
        local removed_idx
        for i = #entries, 1, -1 do
            if entries[i] == entry then
                removed_idx = i
                table.remove(entries, i)
                break
            end
        end
        by_id[id] = nil
        if focused_id == id then
            if #entries == 0 then
                focused_id = nil
            else
                -- Transfer to the entry now at the same index (or last one).
                local next_idx = math.min(removed_idx or 1, #entries)
                set_focused(entries[next_idx])
            end
        end
    end
end

--- focus(id): jump to the named entry. No-op if absent.
function M.focus(id)
    local e = by_id[id]
    if e then set_focused(e) end
end

--- focus_next / focus_prev: wrap-around. No-op when disabled or chain empty.
function M.focus_next()
    if not enabled or #entries == 0 then return end
    local cur = focused_id and by_id[focused_id] or nil
    local idx = 1
    if cur then
        for i, e in ipairs(entries) do if e == cur then idx = i; break end end
        idx = (idx % #entries) + 1
    end
    set_focused(entries[idx])
end

function M.focus_prev()
    if not enabled or #entries == 0 then return end
    local cur = focused_id and by_id[focused_id] or nil
    local idx = 1
    if cur then
        for i, e in ipairs(entries) do if e == cur then idx = i; break end end
        idx = ((idx - 2) % #entries) + 1
    end
    set_focused(entries[idx])
end

function M.enable()      enabled = true  end
function M.disable()     enabled = false end
function M.is_enabled()  return enabled  end

function M.get_focused_id()
    return focused_id
end

function M.get_focused_entry()
    return focused_id and by_id[focused_id] or nil
end

--- dispatch_focused(input, key): deliver a key event to the focused entry's
-- on_input handler. Returns true if a handler was invoked, false otherwise.
function M.dispatch_focused(input, key)
    if not enabled then return false end
    local e = focused_id and by_id[focused_id] or nil
    if not e or not e.on_input then return false end
    e.on_input(input, key)
    return true
end

-- -- introspection / teardown -------------------------------------------------

function M._entries() return entries end

function M._reset()
    entries         = {}
    by_id           = {}
    focused_id      = nil
    enabled         = true
    seq_counter     = 0
    auto_id_counter = 0
end

return M
