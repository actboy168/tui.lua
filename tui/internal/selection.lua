-- tui/internal/selection.lua — mouse text selection state machine.
--
-- This module tracks a single in-progress or committed text selection:
--   • start(col, row)       — begin a new selection (mousedown)
--   • update(col, row)      — extend the selection (mousemove)
--   • finish(col, row)      — commit the selection (mouseup)
--   • clear()               — discard the selection (e.g. on Esc or next mousedown)
--   • has()                 — true when a non-empty committed selection exists
--   • is_dragging()         — true between start() and finish()
--   • bounds()              — returns {c1,r1,c2,r2} (normalised, 0-based) or nil
--   • get_text(screen_c, screen_ud, h) — extract selected text from screen buffer
--   • subscribe(fn)         — fn() called whenever selection state changes

local bus_mod = require "tui.internal.bus"

local M = {}

local _anchor   = nil   -- {col, row} set on mousedown
local _focus    = nil   -- {col, row} updated on mousemove / mouseup
local _dragging = false -- true between mousedown and mouseup

local _change_bus = bus_mod.new()

--- subscribe(fn) -> unsubscribe
-- Registers a handler called (with no arguments) whenever the selection
-- state changes (start, update, finish, clear).
M.subscribe = _change_bus.subscribe

local function _notify()
    _change_bus.dispatch()
end

--- start(col, row)
-- Begin a new selection at the given 0-based cell position.
function M.start(col, row)
    _anchor   = {col = col, row = row}
    _focus    = nil
    _dragging = true
    _notify()
end

--- update(col, row)
-- Extend the active selection to the given position.
-- No-op if no selection is in progress or if anchor == focus (zero extent).
function M.update(col, row)
    if not _dragging or not _anchor then return end
    if _anchor.col == col and _anchor.row == row then return end
    _focus = {col = col, row = row}
    _notify()
end

--- finish(col, row)
-- Commit the selection.  If the focus never moved from the anchor the
-- selection is discarded (click without drag).
function M.finish(col, row)
    if not _dragging then return end
    _dragging = false
    if not _focus then
        -- No movement: discard
        _anchor = nil
    else
        _focus = {col = col, row = row}
    end
    _notify()
end

--- clear()
-- Discard the selection entirely.
function M.clear()
    _anchor   = nil
    _focus    = nil
    _dragging = false
    _notify()
end

--- has() -> bool
-- True when a committed (non-empty) selection exists.
function M.has()
    return _anchor ~= nil and _focus ~= nil and not _dragging
end

--- is_dragging() -> bool
-- True while the user is actively dragging (between start and finish).
function M.is_dragging()
    return _dragging
end

--- bounds() -> {c1,r1,c2,r2} | nil
-- Returns the normalised bounding rectangle (inclusive, 0-based) of the
-- current selection, or nil if no selection extent exists yet.
function M.bounds()
    if not _anchor or not _focus then return nil end
    local ac, ar = _anchor.col, _anchor.row
    local fc, fr = _focus.col,  _focus.row
    -- Normalise so (c1,r1) <= (c2,r2) in reading order.
    local c1, r1, c2, r2
    if ar < fr or (ar == fr and ac <= fc) then
        c1, r1, c2, r2 = ac, ar, fc, fr
    else
        c1, r1, c2, r2 = fc, fr, ac, ar
    end
    return {c1 = c1, r1 = r1, c2 = c2, r2 = r2}
end

--- get_text(screen_c, screen_ud, terminal_h) -> string | nil
-- Extract the text covered by the current selection from the screen buffer.
-- screen_c  = tui_core.screen  (the C module table)
-- screen_ud = the screen userdata
-- terminal_h = terminal height (for clamping)
function M.get_text(screen_c, screen_ud, terminal_h)
    local b = M.bounds()
    if not b then return nil end
    local rows = screen_c.rows(screen_ud)
    if not rows then return nil end

    local parts = {}
    for row = b.r1, b.r2 do
        local line = rows[row + 1]  -- rows is 1-based
        if not line then break end
        if b.r1 == b.r2 then
            -- Single row: slice character columns.
            -- `line` is a raw UTF-8 string; count graphemes naively by byte.
            -- For a simple approximation: extract the substring between the
            -- column byte offsets (works for ASCII; multibyte is approximate).
            local s = line:sub(b.c1 + 1, b.c2 + 1)
            parts[#parts + 1] = s
        else
            if row == b.r1 then
                parts[#parts + 1] = line:sub(b.c1 + 1)
            elseif row == b.r2 then
                parts[#parts + 1] = line:sub(1, b.c2 + 1)
            else
                parts[#parts + 1] = line
            end
            if row < b.r2 then parts[#parts + 1] = "\n" end
        end
    end
    local text = table.concat(parts)
    return #text > 0 and text or nil
end

--- _reset()  — called by tui.render() teardown and tests.
function M._reset()
    _anchor   = nil
    _focus    = nil
    _dragging = false
    _change_bus._reset()
end

return M
