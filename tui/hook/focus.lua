-- tui/hook/focus.lua — focus hooks.
--
-- useFocus, useFocusManager.

local core       = require "tui.hook.core"
local state_mod  = require "tui.hook.state"
local effect_mod = require "tui.hook.effect"

local M = {}

-- ---------------------------------------------------------------------------
-- useFocus(opts) — register this component into the focus chain.
--
-- opts = {
--   autoFocus = bool?,       -- explicitly take focus on mount / re-subscribe
--   id        = string?,     -- manual id; generated otherwise
--   isActive  = bool?,       -- default true. When false, entry is registered
--                            --   but skipped by Tab navigation and never
--                            --   auto-focuses.
--   onInput   = fn?,         -- called when a key is delivered to us
--   onFocus   = fn?,         -- called when this entry receives focus
--   onBlur    = fn?,         -- called when this entry loses focus
-- }
--
-- Hot-update semantics:
--   * id        — changing the explicit id triggers a re-subscribe (old
--                 entry unmounts, new entry appended at the tail). autoFocus
--                 is re-evaluated against the new entry.
--   * isActive  — hot-updates in place via focus_mod.set_active(); the
--                 entry's position in the Tab order is preserved.
--   * autoFocus — read at each subscribe time only; toggling it alone on
--                 a rerender is a no-op (matches Ink: autoFocus is a mount
--                 intent, not an imperative command — use the returned
--                 focus() instead).
--   * onInput   — always sees latest closure via useLatestRef.
--   * onFocus   — always sees latest closure via useLatestRef.
--   * onBlur    — always sees latest closure via useLatestRef.
--
-- returns { isFocused : bool, focus : fn }
--
-- Implementation note: subscription happens inside a useEffect whose deps
-- are the sanitized id. Registering on every render would re-append the
-- entry each frame, permanently shifting Tab order.

local focus_mod

function M.useFocus(opts)
    opts = opts or {}
    if not focus_mod then focus_mod = require "tui.internal.focus" end

    local isFocused, setFocused = state_mod.useState(false)
    local onInputRef = state_mod.useLatestRef(opts.onInput)
    local onFocusRef = state_mod.useLatestRef(opts.onFocus)
    local onBlurRef  = state_mod.useLatestRef(opts.onBlur)

    -- A dedicated slot holds the live focus entry so the returned `focus()`
    -- closure can reach it even though subscribe happens in a later effect.
    local inst, i = core.require_instance("focus")
    local slot = inst.hooks[i]
    if not slot then
        slot = { kind = "focus", entry = nil }
        inst.hooks[i] = slot
    end

    local auto     = opts.autoFocus
    local id       = opts.id
    local isActive = opts.isActive

    -- Capture the owning instance once so the focus onInput wrapper can
    -- route handler errors through the same nearest_boundary path useInput
    -- uses. The instance's .nearest_boundary is refreshed each render.
    local inst_outer = inst

    -- Effect 1: (re-)subscribe when id changes. deps={id} — a nil id stays
    -- stable across rerenders (shallow-equal), so auto-id entries never
    -- remount; a string id change triggers cleanup + new subscribe.
    effect_mod.useEffect(function()
        local entry, unsub = focus_mod.subscribe {
            id        = id,
            autoFocus = auto,
            isActive  = isActive,
            onChange = function(b) setFocused(b) end,
            onInput  = core.wrap_handler_for_boundary(inst_outer, function(input, key)
                if onInputRef.current then onInputRef.current(input, key) end
            end),
            onFocus = function()
                if onFocusRef.current then onFocusRef.current() end
            end,
            onBlur = function()
                if onBlurRef.current then onBlurRef.current() end
            end,
        }
        slot.entry = entry
        return function()
            slot.entry = nil
            unsub()
        end
    end, { id })

    -- Effect 2: hot-update isActive when it changes. No-op on first mount
    -- (subscribe already saw the initial value) but cheap to run.
    effect_mod.useEffect(function()
        if slot.entry then
            focus_mod.set_active(slot.entry.id, isActive)
        end
    end, { isActive })

    return {
        isFocused = isFocused,
        focus     = function()
            if slot.entry then focus_mod.focus(slot.entry.id) end
        end,
    }
end

-- ---------------------------------------------------------------------------
-- useFocusManager() — return the focus system's control surface.
--
-- Methods are direct pass-throughs to tui.focus; there is no component-
-- level state attached (hence no hook slot), but we still require the
-- call to happen during render so usage is consistent with other hooks.

function M.useFocusManager()
    core._current()  -- validates render context
    if not focus_mod then focus_mod = require "tui.internal.focus" end
    return {
        enableFocus   = focus_mod.enable,
        disableFocus  = focus_mod.disable,
        focus         = focus_mod.focus,
        focusNext     = focus_mod.focus_next,
        focusPrevious = focus_mod.focus_prev,
    }
end

return M
