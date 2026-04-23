-- tui/hook/input.lua — input event hooks.
--
-- useInput, usePaste, useMouse.

local core       = require "tui.hook.core"
local state_mod  = require "tui.hook.state"
local effect_mod = require "tui.hook.effect"

local M = {}

-- ---------------------------------------------------------------------------
-- useInput(handler) — subscribe to keyboard events for the lifetime of the
-- component. Handler signature: handler(input_str, key_table).
--
-- Stage 3: broadcasts to all subscribers (no focus yet — see Stage 5).

local input_mod -- lazy-loaded to avoid a static require cycle

function M.useInput(fn)
    if not input_mod then input_mod = require "tui.internal.input" end
    local ref = state_mod.useLatestRef(fn)
    local inst = core._current()
    effect_mod.useEffect(function()
        return input_mod.subscribe(core.wrap_handler_for_boundary(inst, function(input, key)
            ref.current(input, key)
        end))
    end, {})
end

-- ---------------------------------------------------------------------------
-- usePaste(handler) — subscribe to bracketed-paste events for the lifetime of
-- the component. Handler signature: handler(text: string).
-- Ink API parity: called once with the complete pasted text after the terminal
-- sends the closing ESC[201~ marker.

function M.usePaste(fn)
    if not input_mod then input_mod = require "tui.internal.input" end
    local ref = state_mod.useLatestRef(fn)
    local inst = core._current()
    effect_mod.useEffect(function()
        return input_mod.subscribe_paste(core.wrap_handler_for_boundary(inst, function(text)
            ref.current(text)
        end))
    end, {})
end

-- ---------------------------------------------------------------------------
--- useMouse(fn)
-- Registers a mouse-event handler for the lifetime of the component.
-- `fn(event)` is called with each mouse event:
--   { name="mouse", type, button, x, y, scroll, shift, meta, ctrl }
-- where:
--   type   = "down" | "up" | "move" | "scroll"
--   button = 1 (left) | 2 (middle) | 3 (right) | nil (scroll/move)
--   scroll = 1 (up) | -1 (down) | nil
--   shift/meta/ctrl = boolean modifier flags
function M.useMouse(fn)
    local inst = core._current()
    effect_mod.useEffect(function()
        if not input_mod then input_mod = require "tui.internal.input" end
        local unsub   = input_mod.subscribe_mouse(function(ev) fn(ev) end)
        local release = input_mod.request_mouse_level(2)  -- drag level
        return function() unsub(); release() end
    end, {})
end

return M
