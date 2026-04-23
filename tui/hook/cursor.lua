-- tui/hook/cursor.lua — Ink-style cursor hook adapted to tui.lua.
--
-- Ink reference:
--   https://github.com/vadimdemedes/ink/blob/master/src/hooks/use-cursor.ts
--
-- API:
--   local cursor = tui.useCursor()
--   cursor.setCursorPosition { x = 3, y = 0 }
--   cursor.setCursorPosition(nil)  -- hide cursor
--
-- In tui.lua the position is relative to the component's rendered host root.
-- The reconciler hoists the declaration onto that host root after expansion,
-- and app_base.find_cursor() resolves it to absolute screen coordinates.

local core = require "tui.hook.core"
local effect_mod = require "tui.hook.effect"
local state_mod = require "tui.hook.state"

local M = {}

local function is_integer(v)
    return type(v) == "number" and v == math.floor(v)
end

local function normalize_position(position)
    if position == nil then return nil end
    if type(position) ~= "table" then
        error("useCursor: expected position table or nil", 3)
    end

    local x = position.x or 0
    local y = position.y or 0
    if not is_integer(x) then
        error("useCursor: position.x must be an integer", 3)
    end
    if not is_integer(y) then
        error("useCursor: position.y must be an integer", 3)
    end
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end
    return { x = x, y = y }
end

---@class tui.CursorPosition
---@field x integer
---@field y integer

---@class tui.CursorHandle
---@field setCursorPosition fun(position: tui.CursorPosition|nil)

---Return an Ink-style cursor handle for the current component.
---@return tui.CursorHandle
function M.useCursor()
    local inst = core._current()

    -- Each render starts with no declared cursor. Callers opt in by invoking
    -- setCursorPosition() during render; if they stop calling it, the cursor
    -- disappears on the next frame instead of leaking stale coordinates.
    inst._cursor_position = nil

    local set_cursor_position = state_mod.useCallback(function(position)
        inst._cursor_position = normalize_position(position)
    end, {})

    effect_mod.useEffect(function()
        return function()
            inst._cursor_position = nil
        end
    end, {})

    return state_mod.useMemo(function()
        return {
            setCursorPosition = set_cursor_position,
        }
    end, {})
end

return M
