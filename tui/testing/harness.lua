local layout        = require "tui.internal.layout"
local screen_mod    = require "tui.internal.screen"
local hooks         = require "tui.hook.core"
local app_base      = require "tui.internal.app_base"
local input_mod     = require "tui.internal.input"
local capture       = require "tui.testing.capture"
local vterm         = require "tui.testing.vterm"
local vclock        = require "tui.testing.vclock"
local terminal_mod  = require "tui.internal.terminal"
local log_bar       = require "tui.internal.log_bar"
local tui_core      = require "tui.core"

local M = {}

local Harness = {}
Harness.__index = Harness

--- Re-render through the production scheduler path.
function Harness:rerender()
    app_base.rerender(self)
end

function Harness:width()  return app_base.width(self) end
function Harness:height() return app_base.height(self) end
function Harness:size()   return app_base.size(self) end
function Harness:screen() return app_base.screen(self) end
function Harness:rows()
    return screen_mod.rows(self._screen)
end
function Harness:row(n)
    local rows = screen_mod.rows(self._screen)
    return rows[n]
end
--- Return the rendered frame as an LF-joined string.
function Harness:frame()
    return table.concat(screen_mod.rows(self._screen), "\n")
end
function Harness:tree()
    return self._tree
end

--- Return the current row offset (content y=0 maps to this terminal row, 0-based).
-- SGR mouse coordinates are terminal-absolute; use sgr() to convert
-- content-relative coordinates.
---@return integer row_offset 0-based terminal row where content y=0 starts
function Harness:row_offset()
    return self._row_offset or 0
end

--- Convert content-relative (x, y) to SGR mouse coordinates.
-- x, y are 0-based content coordinates (matching element rect values).
-- Returns col, row as 1-based terminal-absolute coordinates suitable for
-- h:mouse() calls.
---@param x integer 0-based content column
---@param y integer 0-based content row
---@return integer col 1-based terminal column (SGR)
---@return integer row 1-based terminal row (SGR)
function Harness:sgr(x, y)
    return x + 1, y + self:row_offset() + 1
end

function Harness:cells(row)
    return screen_mod.cells(self._screen, row)
end

function Harness:render_count()
    return self._render_count or 0
end

function Harness:reset_render_count()
    self._render_count = 0
end

function Harness:expect_renders(expected, msg)
    local actual = self._render_count or 0
    if actual ~= expected then
        error((msg or "render count mismatch") .. ": expected " .. expected ..
              ", got " .. actual, 2)
    end
end

function Harness:cursor()
    return app_base.find_cursor(self._tree)
end

function Harness:composing()
    return self._composing
end

function Harness:ansi()
    return table.concat(self._ansi_buf)
end

function Harness:clear_ansi()
    -- Clear in-place: term.write's closure still references the same table,
    -- so we must not replace it with a new one.
    for i = #self._ansi_buf, 1, -1 do
        self._ansi_buf[i] = nil
    end
end

--- Return the virtual terminal state.
function Harness:vterm()
    return self._vt
end

-- ---------------------------------------------------------------------------
-- Input simulation — byte-level (via vterm queue → read → onInput)

--- Simulate a key press (e.g. "enter", "left", "ctrl+c").
function Harness:press(name)
    vterm.press(self._vt, name)
end

--- Simulate typing a string (UTF-8, one codepoint at a time).
function Harness:type(str)
    vterm.type(self._vt, str)
end

--- Simulate a bracketed-paste event.
function Harness:paste(text)
    vterm.paste(self._vt, text)
end

--- Dispatch raw bytes through the vterm input queue.
function Harness:dispatch(bytes)
    if bytes and #bytes > 0 then
        vterm.enqueue_input(self._vt, bytes)
    end
end

--- Simulate a mouse event.
function Harness:mouse(ev_type, btn, x, y, mods)
    vterm.mouse(self._vt, ev_type, btn, x, y, mods)
end

-- ---------------------------------------------------------------------------
-- Input simulation — structured events (direct dispatch, no byte encoding)
--
-- These dispatch pre-built event tables directly through _process_event,
-- bypassing the vterm byte queue. Used for events that have no terminal
-- escape-sequence representation (e.g. IME composing).

--- Dispatch a pre-built event table directly.
function Harness:dispatch_event(event)
    input_mod._dispatch_event(event)
    self:paint()
end

--- Simulate an IME composing event.
function Harness:type_composing(text)
    input_mod._dispatch_event {
        name = "composing", input = text or "", raw = text or "",
        ctrl = false, meta = false, shift = false,
    }
end

--- Simulate an IME composing confirmation.
function Harness:type_composing_confirm(text)
    local fake = text or ""
    input_mod._dispatch_event {
        name = "composing_confirm", input = fake, raw = fake,
        ctrl = false, meta = false, shift = false,
    }
end

-- ---------------------------------------------------------------------------

--- Advance the virtual clock, run timers, and repaint.
function Harness:advance(ms)
    app_base.advance(self, ms)
end

--- Resize the harness terminal dimensions.
-- Delegates to app_base.resize() which updates _w/_h and
-- forwards to the vterm-backed terminal.
function Harness:resize(cols, rows)
    app_base.resize(self, cols, rows)
end

function Harness:unmount()
    if self._dead then return end
    self._dead = true
    app_base.unmount(self)
    -- harness-specific cleanup
    layout.reset()
    hooks._set_dev_mode(false)
    capture.drain_and_fatal_if_any()
end

--- Mount a full render/layout harness for component and integration tests.
function M.render(App, opts)
    opts = opts or {}
    local W    = opts.cols or 80
    local H    = opts.rows or 24
    local now0 = opts.now or 0
    local use_interactive = opts.interactive ~= false

    local caps = opts.term_type
        and terminal_mod.detect_capabilities(opts.term_type)
        or terminal_mod.default_vterm_capabilities

    -- harness-specific: pre-cleanup
    layout.reset()
    hooks._set_dev_mode(true)

    -- Create virtual clock
    local clock = vclock.new(now0)

    -- Create vterm + terminal
    local vt = vterm.new(W, H)
    local ansi_buf = {}
    local term = vterm.as_terminal(vt, {
        ansi_buf = ansi_buf,
        validate_csi = true,
        capabilities = caps,
    })

    -- Create screen
    local screen_state = screen_mod.new(W, H)
    tui_core.screen.set_color_level(screen_state, caps.color_level)

    -- Mount shared instance (inside pcall for error recovery)
    local h
    local ok, err = pcall(function()
        local inst = app_base.mount(term, screen_state, {
            root           = App,
            app_handle     = { exit = function() inst._dead = true end },
            capabilities   = caps,
            interactive    = use_interactive,
            use_kkp        = false,
            throw_on_error = true,
            clock          = vclock.as_backend(clock),
            extension      = log_bar,
        })

        -- Add harness-specific fields
        inst._vt = vt
        inst._ansi_buf = ansi_buf
        inst._clock = clock
        inst._dead = false
        inst._composing = ""

        h = setmetatable(inst, Harness)
    end)

    if not ok then
        app_base.reset_framework()
        error(err, 2)
    end

    return h
end

M.Harness = Harness

return M
