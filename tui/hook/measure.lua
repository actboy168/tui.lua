-- tui/hook/measure.lua — measurement, app, clipboard, and error boundary hooks.
--
-- useMeasure, useWindowSize, useApp, useClipboard, useErrorBoundary.

local core       = require "tui.hook.core"
local state_mod  = require "tui.hook.state"
local effect_mod = require "tui.hook.effect"

local M = {}

-- ---------------------------------------------------------------------------
-- useErrorBoundary() -> { caught_error, reset }
-- Read the nearest ancestor ErrorBoundary's current state from inside a
-- descendant component. Useful for rendering custom recovery UI without
-- declaring a fallback function: e.g. a toast next to normal content that
-- offers a retry button.
--
-- Semantics:
--   * caught_error : the error value the boundary currently holds, or nil
--                    if it hasn't tripped. This is a snapshot at render
--                    time; the component won't automatically re-render
--                    when caught_error changes unless another mechanism
--                    (the boundary itself flipping, a parent rerender)
--                    forces a pass. In practice that's fine because the
--                    boundary's fallback branch replaces this subtree
--                    when tripped, so callers read `caught_error` mainly
--                    inside that fallback's own children.
--   * reset        : stable closure clearing the boundary's caught_error
--                    and requesting a redraw. No-op if no ancestor
--                    boundary exists (we still return a function so
--                    callers don't need to nil-check).
--
-- Returns nil `caught_error` and a no-op `reset` when there is no ancestor
-- ErrorBoundary. Consumers that need to detect that case can check
-- `result.boundary ~= nil`.
local NOOP = function() end

local reconciler_mod

function M.useErrorBoundary()
    local inst = core._current()
    local boundary = inst.nearest_boundary
    if not boundary then
        return { caught_error = nil, reset = NOOP, boundary = nil }
    end
    reconciler_mod = reconciler_mod or require "tui.internal.reconciler"
    return {
        caught_error = boundary.caught_error,
        reset        = reconciler_mod._get_boundary_reset(boundary),
        boundary     = boundary,
    }
end

-- ---------------------------------------------------------------------------
-- useWindowSize() -> { cols, rows }
-- Returns the current terminal size. Re-renders when the terminal is resized.

local resize_mod

function M.useWindowSize()
    if not resize_mod then resize_mod = require "tui.internal.resize" end
    local w0, h0 = resize_mod.current()
    local size, setSize = state_mod.useState({ cols = w0 or 80, rows = h0 or 24 })
    effect_mod.useEffect(function()
        -- Seed initial size in case it wasn't known when useState ran.
        local cw, ch = resize_mod.current()
        if cw and ch and (cw ~= size.cols or ch ~= size.rows) then
            setSize({ cols = cw, rows = ch })
        end
        return resize_mod.subscribe(function(w, h)
            setSize({ cols = w, rows = h })
        end)
    end, {})
    return size
end

-- ---------------------------------------------------------------------------
-- useApp: exposes a handle with .exit(); provided by reconciler each render.

function M.useApp()
    local inst = core._current()
    assert(inst.app, "no app handle available on instance")
    return inst.app
end

-- ---------------------------------------------------------------------------
-- useMeasure() -> ref, { w, h }
--
-- Lets a component read the post-layout size (in cells) of one of its host
-- (Box / Text) elements.  Usage:
--
--   local measureRef, size = tui.useMeasure()
--   return Box { ref = measureRef, ... }
--   -- size.w / size.h are the Yoga-allocated dims; 0 on the first frame.
--
-- After each layout pass the framework calls `ref._measure(w, h)`.  When the
-- dimensions differ from the previous frame, setSize is called, the component
-- is marked dirty and re-renders with accurate dimensions on the next frame.
-- Multiple `useMeasure` calls in the same component are independent: each
-- call gets its own ref/setSize pair.

function M.useMeasure()
    local size, setSize = state_mod.useState({ w = 0, h = 0 })
    local ref = state_mod.useRef(nil)
    -- Attach the update callback to the ref so the post-layout pass can call
    -- it without re-allocating a closure on every render (ref is stable).
    ref._measure = function(w, h)
        if size.w ~= w or size.h ~= h then
            setSize({ w = w, h = h })
        end
    end
    return ref, size
end

-- ---------------------------------------------------------------------------
-- useClipboard() → { write = fn(text), read = fn() → string|nil }
--
-- write(text) copies text to the clipboard via the same priority chain used
-- by the framework (OSC 52 → wl-copy → xclip → xsel → pbcopy).
-- read()      reads the clipboard via xclip / pbcopy / xsel -o / wl-paste.
--             Returns nil if no tool is available or the clipboard is empty.
--
-- Unlike clipboard.copy() which is called at the framework level, the hook
-- exposes clipboard access directly to components.
function M.useClipboard()
    core._current()
    local clipboard_mod = require "tui.internal.clipboard"

    local handle = state_mod.useMemo(function()
        return {
            write = function(text) clipboard_mod.copy(text) end,
            read  = function() return clipboard_mod.read() end,
        }
    end, {})

    return handle
end

return M
