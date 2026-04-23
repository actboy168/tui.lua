-- tui/builtin/cursor.lua — Cursor declaration API (Ink-compatible single-writer model)
--
-- Components declare cursor position via useCursor({x, y, active}),
-- which returns a tagger function. Apply the tagger to your Text element
-- before returning it:
--
--   local tui = require "tui"
--   function MyInput(props)
--       local isFocused = tui.useFocus()
--       local cursor = tui.useCursor {
--           x = props.caretColumn,
--           y = 0,
--           active = isFocused,
--       }
--       local el = tui.Text { "hello" }
--       cursor(el)
--       return el
--   end
--
-- The tagger writes _cursor_offset and _cursor_focused metadata onto the
-- element. After layout, find_cursor() in init.lua resolves these to
-- absolute screen coordinates using the element's Yoga rect.
--
-- This matches Ink's useCursor:
--   https://github.com/vadimdemedes/ink/blob/master/src/hooks/use-declared-cursor.ts
-- Ink uses a ref callback + CursorDeclarationContext; we use direct
-- element tagging (simpler, no context or nodeCache needed).

local M = {}

--- useCursor({x, y, active}) -> tagger function
-- Declares a cursor position within the component's output element.
--
-- Parameters (table):
--   x      - column offset within the element (0-based, display width)
--   y      - row offset within the element (0-based; single-line inputs use 0)
--   active - whether this declaration is currently active
--
-- Returns a function that tags a Text element with cursor metadata.
-- Only call the tagger when active=true; inactive declarations leave
-- the element untagged so a sibling can claim the cursor.
function M.useCursor(opts)
    local x = opts.x or 0
    local y = opts.y or 0
    local active = opts.active

    if active then
        return function(el)
            el._cursor_offset = x
            el._cursor_focused = true
        end
    end

    -- Inactive: no-op tagger
    return function() end
end

return M
