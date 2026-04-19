-- tui/builtin/newline.lua — Newline and Spacer layout helpers.
--
-- Newline { count = n } — creates vertical space by rendering n empty lines.
-- Spacer { } — creates flexible empty space that expands to fill available area.

local element = require "tui.element"

local M = {}

--- Newline { count = n } -> element
-- Creates vertical space by rendering n empty lines.
-- Default count is 1 if not specified.
function M.Newline(t)
    t = t or {}
    local count = t.count or 1
    local key = t.key
    if count < 1 then count = 1 end
    -- Render as a Box with fixed height, no children.
    -- The Box will occupy the specified number of rows.
    return element.Box {
        key = key,
        height = count,
        flexShrink = 0,
    }
end

--- Spacer { } -> element
-- Creates flexible empty space that expands to fill available area.
-- Uses flexGrow=1 to consume remaining space in the parent container.
function M.Spacer(t)
    t = t or {}
    local key = t.key
    -- Spacer expands to fill available space.
    -- In a row: grows horizontally. In a column: grows vertically.
    return element.Box {
        key = key,
        flexGrow = 1,
    }
end

return M
