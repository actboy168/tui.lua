local element       = require "tui.internal.element"
local layout        = require "tui.internal.layout"
local screen_mod    = require "tui.internal.screen"
local reconciler    = require "tui.internal.reconciler"
local scheduler     = require "tui.internal.scheduler"
local input_mod     = require "tui.internal.input"
local resize_mod    = require "tui.internal.resize"
local focus_mod     = require "tui.internal.focus"
local ansi_mod      = require "tui.internal.ansi"
local hooks         = require "tui.internal.hooks"
local hit_test      = require "tui.internal.hit_test"
local paint_frame   = require "tui.internal.paint_frame"
local testing_input = require "tui.testing.input"
local testing_mouse = require "tui.testing.mouse"
local capture       = require "tui.testing.capture"
local vterm         = require "tui.testing.vterm"

local M = {}

-- Validate CSI numeric parameters — catch framework bugs that emit float
-- coordinates (e.g. \27[73.0;3.0H) which real terminals silently reject.
local function check_csi_integers(s)
    local i = 1
    while i <= #s do
        local esc = s:find("\27%[", i)
        if not esc then return nil end
        local j = esc + 2
        while j <= #s do
            local b = s:byte(j)
            if b >= 0x40 and b <= 0x7E then break end
            j = j + 1
        end
        if j > #s then return nil end
        local params = s:sub(esc + 2, j - 1)
        if params:find("%d%.%d") then
            return ("malformed CSI parameter (non-integer) in sequence ESC[%s%s"):
                format(params, s:sub(j, j))
        end
        i = j + 1
    end
    return nil
end

local Harness = {}
Harness.__index = Harness

--- Re-render, diff, and commit one harness frame.
-- Delegates to paint_frame.frame() for the full production paint pipeline.
function Harness:_paint()
    -- Free the previous frame's tree before stabilizing the new one.
    -- hit_test must be cleared first to avoid dangling pointer access.
    if self._tree then
        hit_test.clear_tree()
    end

    local mouse_ref = { current = self._mouse_auto_release }
    local tree, passes = paint_frame.frame {
        rec_state  = self._state,
        root       = self._App,
        app_handle = self._app_handle,
        get_size   = self._terminal.get_size,
        screen     = self._screen,
        interactive = self._interactive,
        throw_on_error = true,
        prev_tree  = self._tree,
        write_fn   = self._terminal.write,
        on_cursor_move = function(col, row)
            self._last_cursor_col, self._last_cursor_row = col, row
            self._ime = { col = col, row = row }
        end,
        mouse_auto_release = mouse_ref,
    }

    self._render_count = (self._render_count or 0) + passes
    self._mouse_auto_release = mouse_ref.current
    self._tree = tree
end

--- Re-render through the production scheduler path.
-- Drains vterm input via read→on_input, then loop_once handles
-- tick_timers + paint-if-dirty, matching the production main loop.
function Harness:rerender()
    scheduler.requestRedraw()
    scheduler.loop_once(self._scheduler_opts, self._terminal, self._fake_now, true)
    return self
end

function Harness:width()  return self._w end
function Harness:height() return self._h end
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

function Harness:cells(row)
    return screen_mod.cells(self._screen, row)
end

function Harness:render_count()
    return self._render_count or 0
end

function Harness:reset_render_count()
    self._render_count = 0
    return self
end

function Harness:expect_renders(expected, msg)
    local actual = self._render_count or 0
    if actual ~= expected then
        error((msg or "render count mismatch") .. ": expected " .. expected ..
              ", got " .. actual, 2)
    end
    return self
end

function Harness:cursor()
    local first_candidate = nil
    local focused_candidate = nil
    local root_w = self._tree and self._tree.rect and self._tree.rect.w
    local root_h = self._tree and self._tree.rect and self._tree.rect.h

    local function walk(e)
        if not e then return end
        if e.kind == "text" and e._cursor_offset ~= nil then
            local r = e.rect or { x = 0, y = 0 }
            local offset = math.min(e._cursor_offset, r.w or e._cursor_offset)
            local col = r.x + offset + 1
            if root_w and col > root_w then col = root_w end
            local row = r.y + 1
            if root_h and row > root_h then row = root_h end
            local cand = { col = col, row = row }
            if not first_candidate then
                first_candidate = cand
            end
            if e._cursor_focused and not focused_candidate then
                focused_candidate = cand
            end
        end
        for _, c in ipairs(e.children or {}) do
            walk(c)
        end
    end

    walk(self._tree)
    local chosen = focused_candidate or first_candidate
    if chosen then
        return chosen.col, chosen.row
    end
    return nil
end

function Harness:ime_pos()
    local p = self._ime
    if not p then return nil end
    return p.col, p.row
end

--- Dispatch a pre-built event object directly through input_mod (no paint).
function Harness:dispatch_event(ev)
    input_mod._dispatch_event(ev)
    return self
end

function Harness:type_composing(text)
    input_mod._dispatch_event({
        name  = "composing",
        input = text or "",
        raw   = text or "",
        ctrl  = false,
        meta  = false,
        shift = false,
    })
    return self
end

function Harness:type_composing_confirm(text)
    local fake_input = text or ""
    input_mod._dispatch_event({
        name  = "composing_confirm",
        input = fake_input,
        raw   = fake_input,
        ctrl  = false,
        meta  = false,
        shift = false,
    })
    return self
end

function Harness:composing()
    return self._composing
end

function Harness:ansi()
    return table.concat(self._ansi_buf)
end

function Harness:clear_ansi()
    self._ansi_buf = {}
    return self
end

--- Return the virtual terminal state.
function Harness:vterm()
    return self._vt
end

--- Enqueue raw bytes to the vterm input queue.
function Harness:_enqueue_input(bytes)
    if bytes and #bytes > 0 then
        local vt = self._vt
        vt.input_queue[#vt.input_queue + 1] = bytes
    end
    return self
end

--- Dispatch raw bytes through the production input path.
-- Enqueues to vterm, then loop_once reads → on_input → dispatch + paint.
function Harness:dispatch(bytes)
    if bytes and #bytes > 0 then
        self:_enqueue_input(bytes)
        scheduler.requestRedraw()
        scheduler.loop_once(self._scheduler_opts, self._terminal, self._fake_now, true)
    end
    return self
end

--- Simulate a bracketed paste burst (enqueue only, no paint).
function Harness:paste(text)
    self:_enqueue_input(testing_input.paste(text))
    return self
end

--- Simulate a mouse event through the shared testing.mouse encoder (enqueue only, no paint).
function Harness:mouse(ev_type, btn, x, y, mods)
    self:_enqueue_input(testing_mouse.harness(ev_type, btn, x, y, mods))
    return self
end

--- Simulate a named key (enqueue only, no paint).
function Harness:press(name)
    local raw = testing_input.resolve_key(name)
    if raw == nil then
        return self:type(name)
    end
    self:_enqueue_input(raw)
    return self
end

--- Simulate typing a string, enqueueing one UTF-8 codepoint at a time.
function Harness:type(str)
    if type(str) ~= "string" then
        error("type: expected string, got " .. type(str), 2)
    end
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local n
        if b < 0x80     then n = 1
        elseif b < 0xC0 then n = 1
        elseif b < 0xE0 then n = 2
        elseif b < 0xF0 then n = 3
        else                 n = 4 end
        local chunk = str:sub(i, i + n - 1)
        self:_enqueue_input(chunk)
        i = i + n
    end
    return self
end

--- Advance the virtual clock, run timers, and repaint.
function Harness:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    self._fake_now = self._fake_now + ms
    scheduler.step(self._fake_now)
    self:_paint()
    return self
end

--- Resize the harness terminal dimensions.
-- Does not resize the screen or paint; _paint() detects the size change
-- (comparing screen size vs terminal size) and resizes automatically,
-- matching the production resize path in init.lua paint().
function Harness:resize(cols, rows)
    assert(type(cols) == "number" and cols > 0, "resize: cols must be positive number")
    assert(type(rows) == "number" and rows > 0, "resize: rows must be positive number")
    self._w, self._h = cols, rows
    self._vt:resize(cols, rows)
    return self
end

function Harness:focus_id()
    return focus_mod.get_focused_id()
end

function Harness:focus_next()
    focus_mod.focus_next()
    return self
end

function Harness:focus_prev()
    focus_mod.focus_prev()
    return self
end

function Harness:focus(id)
    focus_mod.focus(id)
    return self
end

function Harness:unmount()
    if self._dead then return end
    self._dead = true
    -- Release auto mouse mode before _reset clears everything
    self._mouse_auto_release = nil
    reconciler.shutdown(self._state)
    if self._tree then
        layout.free(self._tree)
        self._tree = nil
    end
    layout.reset()
    hit_test.clear_tree()
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(false)
    if self._ansi_restore then
        self._ansi_restore()
        self._ansi_restore = nil
    end
    if self._interactive then
        -- Interactive teardown (mirrors init.lua teardown)
        local clipboard = require "tui.internal.clipboard"
        self._terminal.write(ansi_mod.disableBracketedPaste .. ansi_mod.disableFocusEvents .. "\r" .. ansi_mod.cursorShow() .. "\n")
        input_mod.set_mouse_mode_writer(nil)
        clipboard._osc52_enabled = false
        clipboard.set_writer(nil)
        ansi_mod.set_interactive_fn(nil)
    end
    capture.drain_and_fatal_if_any()
end

local Bare = {}
Bare.__index = Bare

function Bare:rerender()
    if self._tree then self._tree = nil end
    self._render_count = (self._render_count or 0) + 1
    self._tree = reconciler.render(self._state, self._App, self._app_handle)
    return self
end

function Bare:render_count()
    return self._render_count or 0
end

function Bare:reset_render_count()
    self._render_count = 0
    return self
end

function Bare:expect_renders(expected, msg)
    local actual = self._render_count or 0
    if actual ~= expected then
        error((msg or "render count mismatch") .. ": expected " .. expected ..
              ", got " .. actual, 2)
    end
    return self
end

function Bare:dispatch(bytes)
    if bytes and #bytes > 0 then input_mod.dispatch(bytes) end
    return self
end

--- Simulate typing a string on Bare (dispatch only, no paint).
function Bare:type(str)
    if type(str) ~= "string" then
        error("type: expected string, got " .. type(str), 2)
    end
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local n
        if b < 0x80     then n = 1
        elseif b < 0xC0 then n = 1
        elseif b < 0xE0 then n = 2
        elseif b < 0xF0 then n = 3
        else                 n = 4 end
        local chunk = str:sub(i, i + n - 1)
        input_mod.dispatch(chunk)
        i = i + n
    end
    return self
end

function Bare:press(name)
    local raw = testing_input.resolve_key(name)
    if raw == nil then
        return self:type(name)
    end
    input_mod.dispatch(raw)
    return self
end

function Bare:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    self._fake_now = self._fake_now + ms
    scheduler.step(self._fake_now)
    return self
end

function Bare:focus_id()
    return focus_mod.get_focused_id()
end

function Bare:focus_next()
    focus_mod.focus_next()
    return self
end

function Bare:focus_prev()
    focus_mod.focus_prev()
    return self
end

function Bare:focus(id)
    focus_mod.focus(id)
    return self
end

function Bare:tree()
    return self._tree
end

function Bare:state()
    return self._state
end

function Bare:unmount()
    if self._dead then return end
    self._dead = true
    reconciler.shutdown(self._state)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(false)
    capture.drain_and_fatal_if_any()
end

--- Mount a full render/layout harness for component and integration tests.
function M.render(App, opts)
    opts = opts or {}
    local W    = opts.cols or 80
    local H    = opts.rows or 24
    local now0 = opts.now or 0
    local use_interactive = opts.interactive == true

    local ansi_restore = nil
    if opts.term_type ~= nil then
        ansi_restore = ansi_mod.override(opts.term_type)
    end

    -- When interactive mode is requested, patch ansi.interactive() to return
    -- true so that the production interactive code paths are exercised.
    if use_interactive then
        ansi_mod.set_interactive_fn(function() return true end)
    end

    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    layout.reset()
    hooks._set_dev_mode(true)

    local h = setmetatable({
        _App                 = App,
        _w                   = W,
        _h                   = H,
        _fake_now            = now0,
        _ansi_buf            = {},
        _state               = reconciler.new(),
        _screen              = screen_mod.new(W, H),
        _tree                = nil,
        _dead                = false,
        _ime                 = nil,
        _composing           = "",
        _render_count        = 0,
        _last_cursor_col     = 1,
        _last_cursor_row     = 1,
        _ansi_restore        = ansi_restore,
        _vt                  = nil,
        _interactive         = use_interactive,
        _mouse_auto_release  = nil,
    }, Harness)
    h._app_handle = { exit = function() h._dead = true end }

    local screen_c = require "tui_core".screen
    screen_c.set_color_level(h._screen, 2)

    -- Create vterm-backed terminal
    local vt = vterm.new(W, H)
    h._vt = vt
    h._terminal = {
        get_size = function() return h._w, h._h end,
        write = function(s)
            local bad = check_csi_integers(s)
            if bad then
                error("[tui:fatal] harness terminal: " .. bad, 0)
            end
            h._ansi_buf[#h._ansi_buf + 1] = s
            vt.write_log[#vt.write_log + 1] = s
            vt:write(s)
        end,
        read_raw = function()
            if #vt.input_queue > 0 then
                local all = table.concat(vt.input_queue)
                vt.input_queue = {}
                return all
            end
            return nil
        end,
        set_raw = function(on)
            vt:set_raw(on and true or false)
        end,
        windows_vt_enable = function() return true end,
    }

    scheduler.configure {
        now   = function() return h._fake_now end,
        sleep = function() end,
    }

    -- Wire the hit-test handler so that mouse events dispatched through
    -- the harness (h:mouse()) are routed through hit_test.dispatch_click
    -- and hit_test.dispatch_scroll, matching the production event pipeline.
    input_mod.set_hit_test_handler(function(ev)
        if ev.type == "down" and ev.button == 1 then
            return hit_test.dispatch_click(ev.x, ev.y)
        elseif ev.type == "scroll" then
            return hit_test.dispatch_scroll(ev.x, ev.y, ev.scroll)
        end
        return false
    end)

    -- Interactive mode initialization (mirrors init.lua render() preamble)
    if use_interactive then
        local clipboard = require "tui.internal.clipboard"
        h._terminal.write(ansi_mod.cursorHide() .. ansi_mod.enableBracketedPaste .. ansi_mod.enableFocusEvents)
        input_mod.set_mouse_mode_writer(h._terminal.write)
        clipboard.set_writer(h._terminal.write)
        clipboard._osc52_enabled = true
        screen_mod.set_mode(h._screen, "main")
    end

    local ok, err = pcall(function() h:_paint() end)
    if not ok then
        if ansi_restore then ansi_restore() end
        input_mod._reset()
        resize_mod._reset()
        focus_mod._reset()
        scheduler._reset()
        error(err, 2)
    end

    -- Set up scheduler opts for run(), then start the scheduler.
    h._scheduler_opts = {
        read = h._terminal.read_raw,
        on_input = function(bytes)
            return input_mod.dispatch(bytes)
        end,
        paint = function(terminal)
            h:_paint()
        end,
        terminal = h._terminal,
    }
    scheduler.start()

    return h
end

--- Mount a bare reconciler/hooks harness without layout or screen painting.
function M.mount_bare(App)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(true)
    local b = setmetatable({
        _App          = App,
        _state        = reconciler.new(),
        _tree         = nil,
        _dead         = false,
        _fake_now     = 0,
        _render_count = 1,
    }, Bare)
    b._app_handle = { exit = function() b._dead = true end }
    scheduler.configure {
        now   = function() return b._fake_now end,
        sleep = function() end,
    }
    b._tree = reconciler.render(b._state, App, b._app_handle)
    return b
end

M.Harness = Harness
M.Bare = Bare

return M
