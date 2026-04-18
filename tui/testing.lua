-- tui/testing.lua — offscreen test harness for tui.lua.
--
-- This module exposes a small API that turns the framework's render/input/
-- timer loop into a step-driven rig suitable for unit tests. It replaces the
-- per-file `new_harness` helpers that each test module used to roll by hand.
--
-- USAGE
-- -----
--   local testing = require "tui.testing"
--
--   local h = testing.render(App, { cols = 40, rows = 10 })
--   h:type("hi"):press("enter")
--   h:advance(100)       -- drive timers forward 100ms of virtual time
--   h:resize(60, 20)
--   local frame = h:frame()
--   h:match_snapshot("chat_after_submit")  -- test/__snapshots__/<name>.txt
--   h:unmount()
--
-- For tests that only exercise reconciler/hooks without any layout concern,
-- use `testing.mount_bare(App)` instead — it skips layout + renderer and
-- exposes only :rerender / :dispatch / :unmount / :tree / :state.
--
-- CONCURRENCY NOTE
-- ----------------
-- The fake terminal lives on each harness instance (`h._terminal`). No
-- global state is touched. ltest parallel runner is safe.

local element    = require "tui.element"
local layout     = require "tui.layout"
local renderer   = require "tui.renderer"
local screen_mod = require "tui.screen"
local reconciler = require "tui.reconciler"
local scheduler  = require "tui.scheduler"
local input_mod  = require "tui.input"
local resize_mod = require "tui.resize"
local focus_mod  = require "tui.focus"
local hooks      = require "tui.hooks"
local tui_core   = require "tui_core"

local M = {}

-- ---------------------------------------------------------------------------
-- stderr interception for [tui:dev] warnings (fail-on-warn).
--
-- While a harness is mounted, any stderr write starting with "[tui:dev]" is
-- routed to either:
--   * capture_buffer, if the test wrapped its work in M.capture_stderr (the
--     test is asserting against the warning itself — expected); or
--   * unexpected_warnings, the shared module-level sink. When a harness
--     unmounts and this sink is non-empty, unmount raises a [tui:fatal] error
--     naming the warnings, so the test suite cannot silently drift past them.
--
-- Non-dev writes fall through to the real stderr unchanged so genuine errors
-- from the test runner (ltest output, stack traces) are still visible.

local real_stderr          = io.stderr
local stderr_hook_installed = false
local unexpected_warnings   = {}
local capture_buffer        = nil     -- non-nil ⇒ inside M.capture_stderr

local function install_stderr_hook()
    if stderr_hook_installed then return end
    stderr_hook_installed = true
    real_stderr = io.stderr
    io.stderr = {
        write = function(self, ...)
            local s = table.concat({ ... })
            -- Intercept framework diagnostics so they either surface as
            -- expected capture (tests asserting on them) or fail-on-warn
            -- at unmount. Two prefixes:
            --   [tui:dev]  — dev-mode warnings from hooks/reconciler
            --   [tui:test] — testing-harness warnings
            if s:sub(1, 9) == "[tui:dev]" or s:sub(1, 10) == "[tui:test]" then
                if capture_buffer then
                    capture_buffer[#capture_buffer + 1] = s
                else
                    unexpected_warnings[#unexpected_warnings + 1] = s
                end
                return self
            end
            return real_stderr:write(...)
        end,
    }
end

-- Called by mount/unmount paths to check-and-reset the unexpected warning
-- sink. If any warnings accumulated outside a capture_stderr scope, raise a
-- fatal error listing them so the test fails loudly.
local function drain_and_fatal_if_any()
    if #unexpected_warnings == 0 then return end
    local msg = table.concat(unexpected_warnings)
    unexpected_warnings = {}
    error("[tui:fatal] unexpected dev warning(s) (wrap the offending work " ..
          "in testing.capture_stderr if expected):\n" .. msg, 0)
end

install_stderr_hook()

-- ---------------------------------------------------------------------------
-- Named-key table used by Harness:press(). Values are the raw byte sequences
-- that would come from a real terminal; input_mod.dispatch -> keys.parse
-- handles the parsing.

local KEYS = {
    enter     = "\r",
    ["return"] = "\r",
    escape    = "\27",
    esc       = "\27",
    tab       = "\t",
    ["shift+tab"] = "\27[Z",
    backtab   = "\27[Z",
    backspace = "\127",
    up        = "\27[A",
    down      = "\27[B",
    right     = "\27[C",
    left      = "\27[D",
    home      = "\27[H",
    ["end"]   = "\27[F",
    insert    = "\27[2~",
    delete    = "\27[3~",
    pageup    = "\27[5~",
    pagedown  = "\27[6~",
    -- F1-F4: SS3 sequences (ESC O ...)
    f1        = "\27OP",
    f2        = "\27OQ",
    f3        = "\27OR",
    f4        = "\27OS",
    -- F5-F12: CSI tilde sequences
    f5        = "\27[15~",
    f6        = "\27[17~",
    f7        = "\27[18~",
    f8        = "\27[19~",
    f9        = "\27[20~",
    f10       = "\27[21~",
    f11       = "\27[23~",
    f12       = "\27[24~",
}


-- Translate one key spec ("enter" / "left" / "ctrl+c") into raw bytes.
-- Returns: raw_bytes or nil (if single printable char, let caller handle via type())
local function resolve_key(name)
    if type(name) ~= "string" or #name == 0 then
        error("press/keys: expected non-empty string, got " .. tostring(name), 3)
    end
    -- ctrl+<x> → C0 control byte (x - '`').
    local cx = name:match("^ctrl%+(.)$") or name:match("^%^(.)$")
    if cx then
        local b = cx:lower():byte()
        if b < 97 or b > 122 then
            error("press: ctrl+<letter> required, got " .. name, 3)
        end
        return string.char(b - 96)
    end
    -- shift+<key> → modifier suffix form.
    -- CSI modifier: mod = 1 + bitmask(shift=1, meta=2, ctrl=4)
    -- So shift adds ";2" before the final byte for CSI sequences.
    local sk = name:match("^shift%+(.+)$")
    if sk then
        local base = KEYS[sk:lower()]
        if not base then
            error("press: unknown key '" .. name .. "'", 3)
        end
        -- Convert base CSI to shift-modified form.
        -- ESC [ <params> <final> → ESC [ <params>;2 <final>
        -- ESC O <final> (SS3) → ESC [ 1;2 <final> (convert SS3 to CSI)
        if base:sub(1, 2) == "\27[" then
            -- Already CSI: insert ;2 before final byte
            return base:sub(1, -2) .. ";2" .. base:sub(-1)
        elseif base:sub(1, 2) == "\27O" then
            -- SS3: convert to CSI with 1;2 prefix
            return "\27[1;2" .. base:sub(3)
        end
        -- For non-CSI keys (like tab \t), fall through to normal lookup
        -- (shift+tab is already handled by KEYS["shift+tab"])
    end
    local raw = KEYS[name:lower()]
    if raw then
        return raw
    end
    -- Single printable char (ASCII or multi-byte UTF-8 like CJK) → use type()
    -- Check if it's a valid UTF-8 sequence (1-4 bytes, no control chars)
    if #name >= 1 and #name <= 4 then
        local b0 = name:byte(1)
        local expected_len
        if b0 >= 0x20 and b0 <= 0x7E then
            expected_len = 1  -- ASCII printable
        elseif b0 >= 0xC0 and b0 <= 0xDF then
            expected_len = 2  -- 2-byte UTF-8
        elseif b0 >= 0xE0 and b0 <= 0xEF then
            expected_len = 3  -- 3-byte UTF-8 (CJK)
        elseif b0 >= 0xF0 and b0 <= 0xF4 then
            expected_len = 4  -- 4-byte UTF-8
        end
        if expected_len and #name == expected_len then
            return nil  -- signal: use type() instead
        end
    end
    error("press: unknown key '" .. name .. "'", 3)
end

-- Validate that all numeric parameters in CSI sequences (`ESC [ ... <final>`)
-- are integers. Real terminals silently reject `\27[73.0;3.0H` and similar
-- malformed CUPs — harness-side enforcement catches the bug in tests
-- instead of only in a live terminal. Returns nil on success, error
-- message on violation.
local function check_csi_integers(s)
    -- Scan for CSI introducer (ESC [). Params are digits, `.`, `;`, `?`, `>`.
    -- Any `.` inside a numeric token is a float and thus invalid.
    local i = 1
    while i <= #s do
        local esc = s:find("\27%[", i)
        if not esc then return nil end
        -- Find the CSI final byte: 0x40..0x7E (@ through ~).
        local j = esc + 2
        while j <= #s do
            local b = s:byte(j)
            if b >= 0x40 and b <= 0x7E then break end
            j = j + 1
        end
        if j > #s then return nil end  -- incomplete; skip
        local params = s:sub(esc + 2, j - 1)
        if params:find("%d%.%d") then
            return ("malformed CSI parameter (non-integer) in sequence ESC[%s%s"):
                format(params, s:sub(j, j))
        end
        i = j + 1
    end
    return nil
end

-- Per-harness fake terminal. Stored as an instance field so _paint uses it
-- directly — no global state touched. Multiple harnesses can coexist in the
-- same process (unblocks future parallel ltest support).

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
        set_ime_pos       = function(c, r) h._ime = { col = c, row = r } end,
        windows_vt_enable = function() return true end,
    }
end

-- ---------------------------------------------------------------------------
-- Harness metatable.

local Harness = {}
Harness.__index = Harness

-- Produce + commit one frame. Called internally by render / rerender /
-- type / press / advance / resize.
--
-- Stabilization: if a mount effect (or any post-commit work) calls a setter,
-- the instance flips inst.dirty = true. In real tui.render the scheduler
-- loop picks this up on the next tick; in the harness we do the equivalent
-- inline — re-run render until no instance is dirty.  A hard upper bound
-- (MAX_STABILIZE_PASSES) guards against infinite setState loops.
local <const> MAX_STABILIZE_PASSES = 100

local function any_instance_dirty(state)
    for _, inst in pairs(state.instances) do
        if inst.dirty then return true end
    end
    return false
end

function Harness:_paint()
    -- Observe the (possibly changed) terminal size; triggers useWindowSize
    -- subscribers installed on prior renders.
    resize_mod.observe(self._w, self._h)

    self._render_count = (self._render_count or 0) + 1
    local tree
    for pass = 1, MAX_STABILIZE_PASSES do
        tree = reconciler.render(self._state, self._App, self._app_handle)
        if not any_instance_dirty(self._state) then break end
        self._render_count = self._render_count + 1
        if pass == MAX_STABILIZE_PASSES then
            error("tui.testing: render did not stabilize after " ..
                  MAX_STABILIZE_PASSES .. " passes — suspect infinite setState loop", 2)
        end
    end

    if not tree then
        tree = element.Box { width = self._w, height = self._h }
    end
    if tree.kind == "box" then
        tree.props = tree.props or {}
        if tree.props.width  == nil then tree.props.width  = self._w end
        if tree.props.height == nil then tree.props.height = self._h end
    end

    layout.compute(tree)
    screen_mod.clear(self._screen)
    renderer.paint(tree, self._screen)
    local ansi = screen_mod.diff(self._screen)
    if #ansi > 0 then
        self._terminal.write(ansi)
    end

    -- Emit the cursor-placement sequence through the fake terminal so the
    -- CSI integrity check (see `fake.write` in M.render) sees the exact
    -- bytes a real tui.render loop would send. This mirrors the post-paint
    -- block in tui/init.lua (Yoga uses PointScaleFactor=1 and the binding
    -- layer casts to int, so rect values are always whole numbers).
    local ccol, crow
    do
        local function walk(e)
            if not e then return nil end
            if e.kind == "text" and e._cursor_offset ~= nil then
                local r = e.rect or { x = 0, y = 0 }
                return r.x + e._cursor_offset + 1,
                       r.y + 1
            end
            for _, c in ipairs(e.children or {}) do
                local col, row = walk(c)
                if col then return col, row end
            end
        end
        ccol, crow = walk(tree)
    end
    if ccol and crow then
        self._terminal.write("\27[?25h\27[" .. crow .. ";" .. ccol .. "H")
        self._terminal.set_ime_pos(ccol, crow)
    end
    -- Note: real tui/init.lua also emits `\27[?25l` when no cursor is
    -- requested, but the harness deliberately skips that branch. The
    -- only reason we emit cursor bytes here is to feed them through
    -- fake.write's CSI integrity check; when there's nothing to check,
    -- we keep the ansi buffer clean so tests that assert "zero diff"
    -- still work without special-casing.

    -- Keep `tree` live for the caller (h:tree()) — don't layout.free it here,
    -- free on next paint or unmount.
    if self._tree then layout.free(self._tree) end
    self._tree = tree
end

function Harness:rerender()
    self:_paint()
    return self
end

-- Read access.
function Harness:width()  return self._w end
function Harness:height() return self._h end
function Harness:rows()
    return screen_mod.rows(self._screen)
end
function Harness:row(n)
    local rows = screen_mod.rows(self._screen)
    return rows[n]
end
function Harness:frame()
    return table.concat(screen_mod.rows(self._screen), "\n")
end
function Harness:tree()   return self._tree end

-- Performance testing: render count tracking.
-- Returns the total number of reconciler.render() calls since mount.
function Harness:render_count()
    return self._render_count or 0
end

-- Reset render counter to 0. Useful when you want to measure renders
-- starting from a specific point in the test.
function Harness:reset_render_count()
    self._render_count = 0
    return self
end

-- Assert that render count matches expected value.
-- On mismatch, raises with detailed error message.
function Harness:expect_renders(expected, msg)
    local actual = self._render_count or 0
    if actual ~= expected then
        error((msg or "render count mismatch") .. ": expected " .. expected ..
              ", got " .. actual, 2)
    end
    return self
end

-- Return (col, row) 1-based absolute coords of the focused TextInput's
-- caret, or nil if no input is focused. Mirrors `find_cursor` in
-- tui/init.lua's paint loop so tests can assert cursor placement and,
-- critically, that the coords are integers (non-integer coords produce
-- `\27[73.0;3.0H` CUP commands that real terminals silently reject — see
-- test/test_cursor_integer_coords.lua).
function Harness:cursor()
    local function walk(e)
        if not e then return nil end
        if e.kind == "text" and e._cursor_offset ~= nil then
            local r = e.rect or { x = 0, y = 0 }
            return r.x + e._cursor_offset + 1, r.y + 1
        end
        for _, c in ipairs(e.children or {}) do
            local col, row = walk(c)
            if col then return col, row end
        end
    end
    return walk(self._tree)
end

function Harness:ansi()
    return table.concat(self._ansi_buf)
end
function Harness:clear_ansi()
    self._ansi_buf = {}
    return self
end

-- Driving.

function Harness:dispatch(bytes)
    if bytes and #bytes > 0 then
        input_mod.dispatch(bytes)
    end
    self:_paint()
    return self
end

function Harness:type(str)
    if type(str) ~= "string" then
        error("type: expected string, got " .. type(str), 2)
    end
    -- Feed character by character so each insertion gets its own render,
    -- matching real keyboard behavior (one keystroke at a time).
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local n
        if b < 0x80     then n = 1
        elseif b < 0xC0 then n = 1             -- stray continuation; send as-is
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

function Harness:press(name)
    local raw = resolve_key(name)
    if raw == nil then
        -- Single printable char: delegate to type() for UTF-8 handling
        return self:type(name)
    end
    input_mod.dispatch(raw)
    self:_paint()
    return self
end

-- Advance the virtual clock and fire due timers.
-- Delegates to `scheduler.step(now)` for timer iteration; interval timers
-- self-catch-up within a single advance call, so advance(N) with N much
-- larger than a subscribed interval fires the interval N/interval times.
function Harness:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    self._fake_now = self._fake_now + ms
    scheduler.step(self._fake_now)
    self:_paint()
    return self
end

function Harness:resize(cols, rows)
    assert(type(cols) == "number" and cols > 0, "resize: cols must be positive number")
    assert(type(rows) == "number" and rows > 0, "resize: rows must be positive number")
    self._w, self._h = cols, rows
    -- resize() on the C-side screen invalidates the row ring pool and sets
    -- prev_valid=0 so the next diff is a full redraw. This mirrors what
    -- real tui/init does when the terminal size changes.
    screen_mod.resize(self._screen, cols, rows)
    self:_paint()
    return self
end

-- Focus helpers. These drive the focus chain directly without going through
-- input_mod.dispatch, so tests can assert focus state without caring about
-- key byte sequences. `:press("tab")` still works for end-to-end flows.
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
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(false)
    drain_and_fatal_if_any()
end

-- ---------------------------------------------------------------------------
-- Snapshot testing.
--
-- Plain-text format: one line per screen row, LF-joined, single trailing LF
-- so the file ends on a newline (git-diff friendly). Trailing spaces on each
-- row are preserved — the renderer pads with spaces and we want alignment
-- failures to surface rather than be silently normalized.
--
-- Path: <cwd>/test/__snapshots__/<name>.txt (created on first run). Set the
-- env var TUI_UPDATE_SNAPSHOTS=1 to overwrite all snapshots on a run (for
-- intentional updates).

local <const> SNAPSHOT_DIR = "test/__snapshots__"

local function snapshot_path(name)
    if type(name) ~= "string" or #name == 0 then
        error("match_snapshot: name must be non-empty string", 3)
    end
    if name:find("[/\\%s]") then
        error("match_snapshot: name must not contain slashes or whitespace, got " .. name, 3)
    end
    return SNAPSHOT_DIR .. "/" .. name .. ".txt"
end

local function file_read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function ensure_dir(path)
    -- Blind mkdir — both Windows `mkdir` and Unix `mkdir -p` are idempotent
    -- when the target exists; errors are silenced. We rely on the subsequent
    -- io.open() failing loudly if the directory really can't be created.
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
    end
end

local function file_write(path, content)
    ensure_dir(SNAPSHOT_DIR)
    local f, err = io.open(path, "wb")
    if not f then error("match_snapshot: cannot write " .. path .. ": " .. tostring(err), 3) end
    f:write(content)
    f:close()
end

local function split_lines(s)
    local out = {}
    local i = 1
    while i <= #s do
        local j = s:find("\n", i, true)
        if not j then
            out[#out + 1] = s:sub(i)
            break
        end
        out[#out + 1] = s:sub(i, j - 1)
        i = j + 1
    end
    if s:sub(-1) == "\n" then out[#out + 1] = "" end
    return out
end

-- Build a human-readable diff: show first differing row with ±3 lines of
-- surrounding context, and the full line-count / width delta.
local function format_diff(name, expected, actual)
    local e_lines = split_lines(expected)
    local a_lines = split_lines(actual)
    local n = math.max(#e_lines, #a_lines)
    local first = nil
    for i = 1, n do
        if e_lines[i] ~= a_lines[i] then
            first = i
            break
        end
    end
    if not first then
        return ("snapshot %s: contents differ but no line-level diff found"):format(name)
    end
    local lo = math.max(1, first - 3)
    local hi = math.min(n, first + 3)
    local buf = { ("snapshot mismatch: %s"):format(name) }
    buf[#buf + 1] = ("first diff at line %d (expected %d rows, got %d rows)"):format(first, #e_lines, #a_lines)
    buf[#buf + 1] = "context (lines " .. lo .. ".." .. hi .. "):"
    for i = lo, hi do
        local e = e_lines[i] or "<<missing>>"
        local a = a_lines[i] or "<<missing>>"
        if e == a then
            buf[#buf + 1] = ("  %3d  %s"):format(i, e)
        else
            buf[#buf + 1] = ("- %3d  %s"):format(i, e)
            buf[#buf + 1] = ("+ %3d  %s"):format(i, a)
        end
    end
    buf[#buf + 1] = "re-run with TUI_UPDATE_SNAPSHOTS=1 to accept the new output."
    return table.concat(buf, "\n")
end

function Harness:match_snapshot(name)
    local path = snapshot_path(name)
    local actual = self:frame() .. "\n"

    if os.getenv("TUI_UPDATE_SNAPSHOTS") == "1" then
        file_write(path, actual)
        return self
    end

    local expected = file_read(path)
    if not expected then
        -- First run: write and pass.
        file_write(path, actual)
        return self
    end

    if expected == actual then return self end

    error(format_diff(name, expected, actual), 2)
end

--- tui.testing.render(App, opts) -> Harness
-- opts:
--   cols (default 80), rows (default 24)
--   now  (default 0) — virtual start time in milliseconds
function M.render(App, opts)
    opts = opts or {}
    local W    = opts.cols or 80
    local H    = opts.rows or 24
    local now0 = opts.now  or 0

    -- Isolated globals. Any leftover state from a previous (possibly
    -- unclean) harness is wiped.
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(true)

    local h = setmetatable({
        _App         = App,
        _w           = W,
        _h           = H,
        _fake_now    = now0,
        _ansi_buf    = {},
        _state       = reconciler.new(),
        _screen      = screen_mod.new(W, H),
        _tree        = nil,
        _dead        = false,
        _ime         = nil,
        _render_count = 0,
    }, Harness)
    h._app_handle = { exit = function() h._dead = true end }

    -- Fake terminal stored on the harness instance — no global state touched.
    h._terminal = make_fake_terminal(h)

    -- Virtual clock. Every call to scheduler.setTimeout / setInterval reads
    -- `now` immediately to compute fire_at, so we must install this BEFORE
    -- the first render runs effects.
    scheduler.configure {
        now   = function() return h._fake_now end,
        sleep = function() end,
    }

    -- Initial paint — installs subscriptions, runs mount-effects.
    local ok, err = pcall(function() h:_paint() end)
    if not ok then
        input_mod._reset()
        resize_mod._reset()
        focus_mod._reset()
        scheduler._reset()
        error(err, 2)
    end
    return h
end

-- ---------------------------------------------------------------------------
-- Public: bare mode — reconciler + hooks only, no layout/renderer/screen.
-- For unit tests of hooks & component identity.

local Bare = {}
Bare.__index = Bare

function Bare:rerender()
    if self._tree then self._tree = nil end
    self._render_count = (self._render_count or 0) + 1
    self._tree = reconciler.render(self._state, self._App, self._app_handle)
    return self
end

-- Performance testing: render count tracking.
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

-- Type a string: each character/UTF-8 codepoint is dispatched separately.
-- Unlike Harness:type(), this does NOT auto-rerender after each char.
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

-- Press a named key ("enter", "ctrl+c", etc).
-- Unlike Harness:press(), this does NOT auto-rerender.
function Bare:press(name)
    local raw = resolve_key(name)
    if raw == nil then
        -- Single printable char: delegate to type() for UTF-8 handling
        return self:type(name)
    end
    input_mod.dispatch(raw)
    return self
end

-- Advance virtual clock and fire due timers.
-- Unlike Harness:advance(), this does NOT auto-rerender.
function Bare:advance(ms)
    assert(type(ms) == "number" and ms >= 0, "advance: non-negative ms required")
    self._fake_now = self._fake_now + ms
    scheduler.step(self._fake_now)
    return self
end

-- Focus helpers (drive focus chain directly, no rerender).
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

function Bare:tree()  return self._tree end
function Bare:state() return self._state end

function Bare:unmount()
    if self._dead then return end
    self._dead = true
    reconciler.shutdown(self._state)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(false)
    drain_and_fatal_if_any()
end

--- tui.testing.mount_bare(App) -> BareHarness
-- Minimal rig for reconciler/hooks tests. Does NOT hijack the terminal, does
-- NOT run layout or renderer.
function M.mount_bare(App)
    input_mod._reset()
    resize_mod._reset()
    focus_mod._reset()
    scheduler._reset()
    hooks._set_dev_mode(true)
    local b = setmetatable({
        _App         = App,
        _state       = reconciler.new(),
        _tree        = nil,
        _dead        = false,
        _fake_now    = 0,
        _render_count = 1,  -- initial render
    }, Bare)
    b._app_handle = { exit = function() b._dead = true end }
    scheduler.configure {
        now   = function() return b._fake_now end,
        sleep = function() end,
    }
    b._tree = reconciler.render(b._state, App, b._app_handle)
    return b
end

-- Capture [tui:dev] warnings emitted by fn() into a string, suppressing them
-- from both the real stderr AND the "unexpected" sink (declares "I expect
-- these warnings"). Nested capture_stderr calls are supported — inner calls
-- capture to their own buffer without leaking to the outer. Non-dev stderr
-- writes always pass through to the real stderr.
function M.capture_stderr(fn)
    local prev = capture_buffer
    capture_buffer = {}
    local ok, err = pcall(fn)
    local s = table.concat(capture_buffer)
    capture_buffer = prev
    if not ok then error(err, 2) end
    return s
end

-- Handy tree-walker exported for tests that need to locate a Text node by
-- its _cursor_offset marker (TextInput-tagged nodes).
function M.find_text_with_cursor(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "text" and e._cursor_offset ~= nil then return e end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c)
            if r then return r end
        end
    end
    return walk(tree)
end

-- ---------------------------------------------------------------------------
-- Tree query utilities.

-- Find the first node matching `kind` in a depth-first walk.
-- Returns the node table or nil.
function M.find_by_kind(tree, kind)
    local function walk(e)
        if not e then return nil end
        if e.kind == kind then return e end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c)
            if r then return r end
        end
    end
    return walk(tree)
end

-- Collect all nodes matching `kind` in depth-first order.
-- Returns a list of node tables.
function M.find_all_by_kind(tree, kind)
    local out = {}
    local function walk(e)
        if not e then return end
        if e.kind == kind then out[#out + 1] = e end
        for _, c in ipairs(e.children or {}) do walk(c) end
    end
    walk(tree)
    return out
end

-- Collect the text content of all Text nodes in depth-first order.
-- Returns a list of strings (one per Text node found).
function M.text_content(tree)
    local out = {}
    local function walk(e)
        if not e then return end
        if e.kind == "text" then
            out[#out + 1] = e.text or ""
        end
        for _, c in ipairs(e.children or {}) do walk(c) end
    end
    walk(tree)
    return out
end

return M
