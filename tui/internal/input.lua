-- tui/input.lua — input dispatcher for tui.lua.
--
-- Two channels:
--   * broadcast_handlers — plain `tui.useInput(fn)` registrations; every
--     non-intercepted key event is delivered to all of them.
--   * focus channel     — a single "focused" component receives keys via
--     tui.focus.dispatch_focused; interception of Tab / Shift-Tab is done
--     here as well (focus navigation is a framework-level concern).
--
-- Key flow for each parsed event:
--   1. If focus is enabled and ev is Tab / Shift-Tab → focus_next/prev,
--      swallow (no further dispatch).
--   2. Hand ev to the currently focused entry's on_input (if any).
--   3. Broadcast ev to every plain useInput subscriber.
--
-- The focused handler and the broadcast handlers are NOT mutually exclusive:
-- a focused component sees the key, and plain `useInput` also sees it. This
-- mirrors Ink's behavior for non-focus keys.

local tui_core  = require "tui_core"
local focus_mod = require "tui.internal.focus"
local bus_mod   = require "tui.internal.bus"
local keys      = tui_core.keys

local M = {}

-- Broadcast channel (plain useInput subscribers).
local _broadcast = bus_mod.new()

-- Paste channel (usePaste subscribers).
local _paste_bus = bus_mod.new()

-- Focus-event channel (useTerminalFocus subscribers).
-- Receives the event name: "focus_in" or "focus_out".
local _focus_bus = bus_mod.new()

-- Mouse-event channel (useMouse subscribers).
-- Receives the full mouse event table: { name="mouse", type, button, x, y, ... }
local _mouse_bus = bus_mod.new()

-- ---------------------------------------------------------------------------
-- Mouse mode level management (ref-counted).
--
-- Levels: 1 = click (?1000h), 2 = drag (?1002h), 3 = any (?1003h).
-- SGR extended coordinates (?1006h) are enabled alongside any non-zero level.
-- The writer function is injected by init.lua (terminal.write).
-- Components request a level via request_mouse_level(); the highest currently
-- demanded level is active at all times.
local _mouse_writer  = nil   -- injected by set_mouse_mode_writer()
local _mouse_level   = 0     -- currently active terminal level
local _mouse_refs    = {0, 0, 0}  -- ref counts for levels 1, 2, 3

local _mm  -- forward declaration; defined below after ansi is loaded lazily
local function _get_mm()
    if not _mm then _mm = require("tui.internal.ansi").mouseMode end
    return _mm
end

local _LEVEL_ON  = { "click_on",  "drag_on",  "any_on"  }
local _LEVEL_OFF = { "click_off", "drag_off", "any_off" }

local function _mouse_level_needed()
    for i = 3, 1, -1 do
        if _mouse_refs[i] > 0 then return i end
    end
    return 0
end

local function _apply_mouse_level(needed)
    if needed == _mouse_level then return end
    if not _mouse_writer then _mouse_level = needed; return end
    local mm = _get_mm()
    if needed > _mouse_level then
        -- Upgrading: enable SGR + click base on first activation, then add levels.
        if _mouse_level == 0 then
            _mouse_writer(mm.sgr_on)
            _mouse_writer(mm.click_on)
            for i = 2, needed do
                _mouse_writer(mm[_LEVEL_ON[i]])
            end
        else
            for i = _mouse_level + 1, needed do
                _mouse_writer(mm[_LEVEL_ON[i]])
            end
        end
    else
        -- Downgrading: disable extra levels from top down.
        for i = _mouse_level, math.max(needed + 1, 2), -1 do
            _mouse_writer(mm[_LEVEL_OFF[i]])
        end
        if needed == 0 then
            _mouse_writer(mm.click_off)
            _mouse_writer(mm.sgr_off)
        end
    end
    _mouse_level = needed
end

-- User-registered middleware functions: fn(ev) -> bool.
-- Run after paste accumulation, before focus/mouse/key routing.
-- A middleware that returns true consumes the event (stops all further processing).
local _middlewares = {}

-- Hit-test handler: fn(ev) -> bool.
-- Set by init.lua during tui.render(). Called for mouse events before
-- _mouse_bus.dispatch. If it returns true, the event is consumed and
-- not forwarded to useMouse subscribers.
local _hit_test_handler = nil

--- set_hit_test_handler(fn | nil)
-- Injects the hit-test handler (called from init.lua render loop).
function M.set_hit_test_handler(fn)
    _hit_test_handler = fn
end

-- Bracketed-paste accumulator state (persists across dispatch() calls so
-- multi-chunk pastes — rare but possible — are assembled correctly).
local _pasting    = false
local _paste_buf  = {}

-- Partial escape-sequence buffer.
--
-- On Windows, ReadConsoleInputW sometimes delivers the bytes of an ANSI escape
-- sequence across separate read_raw calls: ESC arrives alone in one call and
-- "[A" arrives in the next.  Without buffering, keys.parse treats the lone ESC
-- as {name="escape"} and the "[A" as two char insertions — corrupting the
-- focused component's text.
--
-- After each dispatch(), if the byte string ends with an incomplete escape
-- prefix (lone ESC, unterminated CSI "ESC [", or unterminated SS3 "ESC O"),
-- those bytes are held here and prepended to the *next* dispatch() call.
local _pending_bytes = ""

-- Returns how many bytes at the END of `s` form an incomplete ANSI escape
-- prefix that should be buffered rather than parsed now.
local function incomplete_esc_tail(s)
    local n = #s
    -- Scan backward up to 8 bytes for a possible ESC starter.
    for j = n, math.max(1, n - 7), -1 do
        if s:byte(j) == 0x1B then
            local next_b = (j + 1 <= n) and s:byte(j + 1) or nil
            if next_b == nil then
                return n - j + 1          -- lone ESC
            elseif next_b == 0x5B then    -- '[' → CSI
                -- CSI is complete only when it contains a final byte (0x40-0x7E).
                for k = j + 2, n do
                    if s:byte(k) >= 0x40 and s:byte(k) <= 0x7E then
                        -- Legacy X10 mouse: bare ESC[M (k == j+2, byte == 0x4D)
                        -- needs 3 more raw bytes after the 'M'. Buffer until complete.
                        if s:byte(k) == 0x4D and k == j + 2 and (n - k) < 3 then
                            return n - j + 1
                        end
                        return 0          -- complete CSI before end of buffer
                    end
                end
                return n - j + 1          -- incomplete CSI
            elseif next_b == 0x4F then    -- 'O' → SS3
                if j + 2 <= n then return 0 end   -- ESC O <c> — complete
                return n - j + 1          -- incomplete SS3
            else
                return 0                  -- ESC + other byte: always complete
            end
        end
    end
    return 0
end

--- subscribe(fn) -> unsubscribe
-- Registers a broadcast handler. `fn` is called as fn(input_str, key_table)
-- for each non-intercepted parsed event.
M.subscribe = _broadcast.subscribe

--- subscribe_paste(fn) -> unsubscribe
-- Registers a paste handler. `fn(text)` is called with the full pasted text
-- once a complete bracketed-paste sequence has been received.
M.subscribe_paste = _paste_bus.subscribe

--- subscribe_focus(fn) -> unsubscribe
-- Registers a terminal-focus handler. `fn(event_name)` is called with
-- "focus_in" or "focus_out" when the terminal gains/loses focus (DEC 1004).
M.subscribe_focus = _focus_bus.subscribe

--- subscribe_mouse(fn) -> unsubscribe
-- Registers a mouse handler. `fn(event)` is called with each mouse event
-- table: { name="mouse", type, button, x, y, scroll, shift, meta, ctrl }.
M.subscribe_mouse = _mouse_bus.subscribe

--- set_mouse_mode_writer(fn | nil)
-- Injects the function used to write terminal escape sequences for mouse mode
-- changes.  Pass `terminal.write` on startup and `nil` on teardown.
-- When set to nil, level changes are tracked in memory but no sequences are sent.
function M.set_mouse_mode_writer(fn)
    _mouse_writer = fn
    if fn == nil then
        -- Caller is responsible for sending disable sequences before clearing.
        _mouse_level = 0
    end
end

--- request_mouse_level(level) -> release_fn
-- Increments the ref count for the given level (1=click, 2=drag, 3=any).
-- If the highest needed level rises, the appropriate terminal sequences are
-- written via the configured writer.  Returns a release function; call it when
-- the mouse is no longer needed (e.g., on component unmount).
function M.request_mouse_level(level)
    assert(level >= 1 and level <= 3, "mouse level must be 1, 2, or 3")
    _mouse_refs[level] = _mouse_refs[level] + 1
    _apply_mouse_level(_mouse_level_needed())
    local released = false
    return function()
        if released then return end
        released = true
        _mouse_refs[level] = math.max(0, _mouse_refs[level] - 1)
        _apply_mouse_level(_mouse_level_needed())
    end
end

--- use_middleware(fn) -> unsubscribe
-- Inserts a middleware into the event pipeline. `fn(ev)` is called for every
-- parsed event that survives paste accumulation. If `fn` returns a truthy
-- value the event is consumed and no further processing occurs (focus routing,
-- mouse bus, broadcast — all skipped). Middlewares run in registration order.
-- Returns an unsubscribe function that removes the middleware.
function M.use_middleware(fn)
    _middlewares[#_middlewares + 1] = fn
    return function()
        for i, m in ipairs(_middlewares) do
            if m == fn then table.remove(_middlewares, i); break end
        end
    end
end

--- debug_log: when non-nil, each dispatch() call appends a line to this file.
-- Enable from Lua before tui.render:  require("tui.internal.input")._debug_log = "input_debug.txt"
M._debug_log = nil

local function _dbg(msg)
    if not M._debug_log then return end
    local f = io.open(M._debug_log, "a")
    if f then f:write(msg .. "\n"); f:close() end
end

-- Process one event through the unified chain.
-- Chain order: [user middlewares] → [built-in routing]
-- Returns true if the event signals Ctrl+C / Ctrl+D (caller should exit).
local function _process_event(ev)
    -- ── User middleware chain ─────────────────────────────────────────────
    for _, mw in ipairs(_middlewares) do
        if mw(ev) then return false end
    end
    -- ── Kitty Keyboard Protocol: suppress release events ──────────────────
    -- With flags=3 (event types enabled), the terminal sends press, repeat,
    -- *and* release events.  Most TUI components only care about press/repeat.
    -- Filter releases here so no component receives accidental double-triggers.
    -- Middlewares registered above still see all events (advanced use).
    if ev.event_type == "release" then return false end
    -- ── Terminal focus events (DEC 1004) ─────────────────────────────────
    if ev.name == "focus_in" or ev.name == "focus_out" then
        _focus_bus.dispatch(ev.name)
        return false
    end
    -- ── Mouse events ──────────────────────────────────────────────────────
    if ev.name == "mouse" then
        -- Hit-test dispatch: framework-level hit testing (onClick, onScroll, etc.)
        -- takes priority over useMouse subscribers. If a handler consumes the
        -- event, it is not forwarded to the mouse bus.
        if _hit_test_handler then
            local ok, consumed = pcall(_hit_test_handler, ev)
            if ok and consumed then return false end
        end
        _mouse_bus.dispatch(ev)
        return false
    end
    -- ── Paste (assembled by dispatch(); also accepts pre-built paste ev) ──
    if ev.name == "paste" then
        local text = ev.input or ""
        focus_mod.dispatch_focused(text, ev)
        _broadcast.dispatch(text, ev)
        _paste_bus.dispatch(text)
        return false
    end
    -- ── Normal key routing ───────────────────────────────────────────────
    local exit = ev.ctrl and ev.name == "char"
                 and (ev.input == "c" or ev.input == "d")
    if focus_mod.is_enabled() then
        if ev.name == "tab" and not ev.shift then
            focus_mod.focus_next()
            return exit
        elseif ev.name == "backtab" or (ev.name == "tab" and ev.shift) then
            focus_mod.focus_prev()
            return exit
        end
    end
    focus_mod.dispatch_focused(ev.input or "", ev)
    _broadcast.dispatch(ev.input or "", ev)
    return exit
end

--- dispatch(bytes) -> should_exit
-- Parses `bytes` into key events and routes them. Returns `true` if any
-- event is a Ctrl+C or Ctrl+D so the outer loop can tear down cleanly;
-- returns `false` otherwise. Events are still broadcast to useInput
-- subscribers either way (Ink parity — handlers can observe Ctrl+C).
function M.dispatch(bytes)
    if not bytes or #bytes == 0 then return false end
    -- Re-attach any incomplete escape prefix buffered from the previous call.
    if _pending_bytes ~= "" then
        bytes = _pending_bytes .. bytes
        _pending_bytes = ""
    end
    -- If the buffer now ends with an incomplete escape sequence, hold those
    -- bytes for the next call so keys.parse never sees a truncated sequence.
    local tail_len = incomplete_esc_tail(bytes)
    if tail_len > 0 then
        _pending_bytes = bytes:sub(#bytes - tail_len + 1)
        bytes = bytes:sub(1, #bytes - tail_len)
        if #bytes == 0 then return false end
    end
    -- Pre-parse normalization: some terminal integrations (e.g. VS Code with a
    -- custom sendSequence binding) send "\" + CR/LF as a Shift+Enter substitute
    -- because real modifier information is lost through the PTY layer.
    -- Convert the pattern \x5C[\x0D\x0A]+ → ESC[13;2u (kitty Shift+Enter)
    -- so keys.parse produces {name="enter", shift=true} instead of a bare
    -- backslash char followed by newline events.
    -- IMPORTANT: skip this normalization when the buffer contains a bracketed-paste
    -- marker (\x1b[200~), because paste content may legitimately contain backslash
    -- followed by newline and must not be corrupted.
    if not bytes:find("\x1b%[200~") then
        bytes = bytes:gsub("\x5c[\x0d\x0a]+", "\x1b[13;2u")
    end
    -- Debug: log raw bytes and parsed events when _debug_log is set.
    if M._debug_log then
        local hex = bytes:gsub(".", function(c) return ("%02x "):format(c:byte()) end)
        _dbg("dispatch bytes=[" .. hex:gsub(" $","") .. "]")
    end
    local events = keys.parse(bytes)
    if M._debug_log then
        for _, ev in ipairs(events) do
            _dbg("  event name=" .. tostring(ev.name) ..
                 " input=" .. tostring(ev.input) ..
                 " ctrl=" .. tostring(ev.ctrl) ..
                 " meta=" .. tostring(ev.meta) ..
                 " shift=" .. tostring(ev.shift))
        end
    end
    local should_exit = false
    for _, ev in ipairs(events) do
        -- ── Bracketed-paste accumulation (stateful stream transform) ─────────
        if ev.name == "paste_start" then
            _pasting   = true
            _paste_buf = {}
            goto continue
        end
        if ev.name == "paste_end" then
            if _pasting then
                _pasting = false
                local text = table.concat(_paste_buf)
                _paste_buf = {}
                local paste_ev = { name = "paste", input = text,
                                   ctrl = false, meta = false, shift = false, raw = "" }
                _process_event(paste_ev)
            end
            goto continue
        end
        if _pasting then
            -- Accumulate char/enter text; suppress individual key dispatch.
            if ev.input and ev.input ~= "" then
                _paste_buf[#_paste_buf + 1] = ev.input
            elseif ev.name == "enter" then
                _paste_buf[#_paste_buf + 1] = "\n"
            end
            goto continue
        end
        -- All other events go through the unified chain.
        if _process_event(ev) then should_exit = true end
        ::continue::
    end
    return should_exit
end

-- Introspection for tests.
function M._handlers() return _broadcast._handlers() end
function M._paste_handlers() return _paste_bus._handlers() end
function M._focus_handlers() return _focus_bus._handlers() end
function M._mouse_handlers() return _mouse_bus._handlers() end
function M._middleware_list() return _middlewares end

--- Dispatch a single pre-built event table (for testing IME composing, etc.).
-- Routes through the same unified chain as dispatch(), but skips key parsing
-- and paste accumulation.
function M._dispatch_event(ev)
    _process_event(ev)
end

-- Reset broadcast channel only. focus is a separate singleton; callers
-- (tui/init.lua and tui/testing.lua) reset both explicitly.
function M._reset()
    _broadcast._reset()
    _paste_bus._reset()
    _focus_bus._reset()
    _mouse_bus._reset()
    _middlewares  = {}
    _hit_test_handler = nil
    _pasting      = false
    _paste_buf    = {}
    _pending_bytes = ""
    -- Reset mouse level state. The writer is intentionally NOT cleared here:
    -- init.lua manages the writer lifecycle explicitly around tui.render().
    _mouse_refs  = {0, 0, 0}
    _mouse_level = 0
end

--- _flush_pending() — force any buffered incomplete-escape bytes through the
-- parser right now (as if a short timeout elapsed). Used in tests to dispatch
-- a standalone Esc key without waiting for a follow-up byte.
function M._flush_pending()
    if _pending_bytes == "" then return false end
    local bytes = _pending_bytes
    _pending_bytes = ""
    local events = keys.parse(bytes)
    local should_exit = false
    for _, ev in ipairs(events) do
        if _process_event(ev) then should_exit = true end
    end
    return should_exit
end

return M
