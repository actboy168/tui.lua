-- tui/input.lua — input dispatcher for tui.lua.
--
-- Two channels:
--   * broadcast_handlers — plain `tui.useInput(fn)` registrations; every
--     non-intercepted key event is delivered to all of them.
--   * focus channel     — a single "focused" component receives keys via
--     tui.focus.dispatch_focused; interception of Tab / Shift-Tab is done
--     here as well (focus navigation is a framework-level concern).
--
-- Key flow for each parsed event:
--   1. If focus is enabled and ev is Tab / Shift-Tab → focus_next/prev,
--      swallow (no further dispatch).
--   2. Hand ev to the currently focused entry's on_input (if any).
--   3. Broadcast ev to every plain useInput subscriber.
--
-- The focused handler and the broadcast handlers are NOT mutually exclusive:
-- a focused component sees the key, and plain `useInput` also sees it. This
-- mirrors Ink's behavior for non-focus keys.

local tui_core  = require "tui_core"
local focus_mod = require "tui.focus"
local keys      = tui_core.keys

local M = {}

-- Broadcast subscribers (plain useInput).
local broadcast_handlers = {}

--- subscribe(fn) -> unsubscribe
-- Registers a broadcast handler. `fn` is called as fn(input_str, key_table)
-- for each non-intercepted parsed event.
function M.subscribe(fn)
    broadcast_handlers[#broadcast_handlers + 1] = fn
    local active = true
    return function()
        if not active then return end
        active = false
        for i = #broadcast_handlers, 1, -1 do
            if broadcast_handlers[i] == fn then
                table.remove(broadcast_handlers, i)
                break
            end
        end
    end
end

--- dispatch(bytes) -> should_exit
-- Parses `bytes` into key events and routes them. Returns `true` if any
-- event is a Ctrl+C or Ctrl+D so the outer loop can tear down cleanly;
-- returns `false` otherwise. Events are still broadcast to useInput
-- subscribers either way (Ink parity — handlers can observe Ctrl+C).
function M.dispatch(bytes)
    if not bytes or #bytes == 0 then return false end
    local events = keys.parse(bytes)
    local should_exit = false
    for _, ev in ipairs(events) do
        if ev.ctrl and ev.name == "char"
            and (ev.input == "c" or ev.input == "d") then
            should_exit = true
        end

        local handled_by_focus_nav = false
        if focus_mod.is_enabled() then
            if ev.name == "tab" and not ev.shift then
                focus_mod.focus_next()
                handled_by_focus_nav = true
            elseif ev.name == "backtab" or (ev.name == "tab" and ev.shift) then
                focus_mod.focus_prev()
                handled_by_focus_nav = true
            end
        end

        if not handled_by_focus_nav then
            -- Focused component sees it first (order within a single event:
            -- focused → broadcast).
            focus_mod.dispatch_focused(ev.input or "", ev)

            -- Snapshot broadcast list so mid-dispatch unsubscribe doesn't
            -- skew iteration.
            local snapshot = {}
            for i, h in ipairs(broadcast_handlers) do snapshot[i] = h end
            for _, h in ipairs(snapshot) do
                h(ev.input or "", ev)
            end
        end
    end
    return should_exit
end

-- Introspection for tests.
function M._handlers() return broadcast_handlers end

-- Reset broadcast channel only. focus is a separate singleton; callers
-- (tui/init.lua and tui/testing.lua) reset both explicitly.
function M._reset()
    broadcast_handlers = {}
end

return M
