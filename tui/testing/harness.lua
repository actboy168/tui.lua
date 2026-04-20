local element       = require "tui.internal.element"
local layout        = require "tui.internal.layout"
local renderer      = require "tui.internal.renderer"
local screen_mod    = require "tui.internal.screen"
local reconciler    = require "tui.internal.reconciler"
local scheduler     = require "tui.internal.scheduler"
local input_mod     = require "tui.internal.input"
local resize_mod    = require "tui.internal.resize"
local focus_mod     = require "tui.internal.focus"
local ansi_mod      = require "tui.internal.ansi"
local hooks         = require "tui.internal.hooks"
local testing_input = require "tui.testing.input"
local testing_mouse = require "tui.testing.mouse"
local capture       = require "tui.testing.capture"

local M = {}

-- Validate CSI numeric parameters before storing them in the fake terminal log.
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

local function make_fake_terminal(h)
    return {
        get_size          = function() return h._w, h._h end,
        write             = function(s)
            local bad = check_csi_integers(s)
            if bad then
                error("[tui:fatal] harness terminal: " .. bad ..
                      " (real terminals silently reject these)", 0)
            end
            h._ansi_buf[#h._ansi_buf + 1] = s
        end,
        read_raw          = function() return nil end,
        set_raw           = function() end,
        windows_vt_enable = function() return true end,
    }
end

local Harness = {}
Harness.__index = Harness

--- Re-render, diff, and commit one harness frame.
function Harness:_paint()
    resize_mod.observe(self._w, self._h)

    local function render_and_layout()
        self._render_count = (self._render_count or 0) + 1
        local t = reconciler.render(self._state, self._App, self._app_handle)
        if not t then
            t = element.Box { width = self._w, height = self._h }
        end
        if t.kind == "box" then
            t.props = t.props or {}
            if t.props.width  == nil then t.props.width  = self._w end
            if t.props.height == nil then t.props.height = self._h end
        end
        reconciler.clear_dirty(self._state)
        layout.compute(t, self._h)
        return t
    end

    local tree = render_and_layout()

    for _ = 1, 8 do
        if not reconciler.has_dirty(self._state) then break end
        if self._tree then layout.free(self._tree) end
        self._tree = tree
        tree = render_and_layout()
    end

    screen_mod.clear(self._screen)
    renderer.paint(tree, self._screen)
    local ansi = screen_mod.diff(self._screen)
    if #ansi > 0 then
        self._terminal.write(ansi)
    end

    local ccol, crow
    do
        local first_candidate = nil
        local focused_candidate = nil
        local root_w = tree.rect and tree.rect.w
        local root_h = tree.rect and tree.rect.h

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

        walk(tree)
        local chosen = focused_candidate or first_candidate
        if chosen then
            ccol, crow = chosen.col, chosen.row
        end
    end

    if ccol and crow then
        self._terminal.write(ansi_mod.cursorShow() .. ansi_mod.cursorPosition(ccol, crow))
        self._last_cursor_col, self._last_cursor_row = ccol, crow
        self._ime = { col = ccol, row = crow }
    end

    if self._tree then layout.free(self._tree) end
    self._tree = tree
end

function Harness:rerender()
    self:_paint()
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

function Harness:type_composing(text)
    input_mod._dispatch_event({
        name  = "composing",
        input = text or "",
        raw   = text or "",
        ctrl  = false,
        meta  = false,
        shift = false,
    })
    self:_paint()
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
    self:_paint()
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

--- Dispatch raw bytes through tui.internal.input and repaint.
function Harness:dispatch(bytes)
    if bytes and #bytes > 0 then
        input_mod.dispatch(bytes)
    end
    self:_paint()
    return self
end

--- Simulate a bracketed paste burst and repaint.
function Harness:paste(text)
    input_mod.dispatch(testing_input.paste(text))
    self:_paint()
    return self
end

--- Simulate a mouse event through the shared testing.mouse encoder and repaint.
function Harness:mouse(ev_type, btn, x, y, mods)
    input_mod.dispatch(testing_mouse.harness(ev_type, btn, x, y, mods))
    self:_paint()
    return self
end

--- Simulate user typing, dispatching one UTF-8 codepoint per repaint.
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
        input_mod.dispatch(chunk)
        self:_paint()
        i = i + n
    end
    return self
end

--- Simulate a named key via testing.input.resolve_key() and repaint.
function Harness:press(name)
    local raw = testing_input.resolve_key(name)
    if raw == nil then
        return self:type(name)
    end
    input_mod.dispatch(raw)
    self:_paint()
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

--- Resize the harness screen and repaint.
function Harness:resize(cols, rows)
    assert(type(cols) == "number" and cols > 0, "resize: cols must be positive number")
    assert(type(rows) == "number" and rows > 0, "resize: rows must be positive number")
    self._w, self._h = cols, rows
    screen_mod.resize(self._screen, cols, rows)
    self:_paint()
    return self
end

function Harness:focus_id()
    return focus_mod.get_focused_id()
end

function Harness:focus_next()
    focus_mod.focus_next()
    self:_paint()
    return self
end

function Harness:focus_prev()
    focus_mod.focus_prev()
    self:_paint()
    return self
end

function Harness:focus(id)
    focus_mod.focus(id)
    self:_paint()
    return self
end

function Harness:unmount()
    if self._dead then return end
    self._dead = true
    reconciler.shutdown(self._state)
    if self._tree then
        layout.free(self._tree)
        self._tree = nil
    end
    layout.reset()
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(false)
    if self._ansi_restore then
        self._ansi_restore()
        self._ansi_restore = nil
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

    local ansi_restore = nil
    if opts.term_type ~= nil then
        ansi_restore = ansi_mod.override(opts.term_type)
    end

    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    layout.reset()
    hooks._set_dev_mode(true)

    local h = setmetatable({
        _App             = App,
        _w               = W,
        _h               = H,
        _fake_now        = now0,
        _ansi_buf        = {},
        _state           = reconciler.new(),
        _screen          = screen_mod.new(W, H),
        _tree            = nil,
        _dead            = false,
        _ime             = nil,
        _composing       = "",
        _render_count    = 0,
        _last_cursor_col = 1,
        _last_cursor_row = 1,
        _ansi_restore    = ansi_restore,
    }, Harness)
    h._app_handle = { exit = function() h._dead = true end }

    local screen_c = require "tui_core".screen
    screen_c.set_color_level(h._screen, 2)
    h._terminal = make_fake_terminal(h)

    scheduler.configure {
        now   = function() return h._fake_now end,
        sleep = function() end,
    }

    local ok, err = pcall(function() h:_paint() end)
    if not ok then
        if ansi_restore then ansi_restore() end
        input_mod._reset()
        resize_mod._reset()
        focus_mod._reset()
        scheduler._reset()
        error(err, 2)
    end
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
