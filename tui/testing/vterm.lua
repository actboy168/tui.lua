-- tui/testing/vterm.lua — Lua wrapper around C vterm implementation.
--
-- Delegates ANSI parsing to tui_core.vterm (C). Write log, input queue,
-- and clipboard log are managed entirely in Lua — the C layer has no
-- registry refs for these tables.

local vterm_c = require("tui.core").vterm

local M = {}

-- ---------------------------------------------------------------------------
-- Creation

function M.new(cols, rows)
    local vt = vterm_c.new(cols, rows)
    vt.write_log    = {}
    vt.input_queue  = {}
    vt.clipboard_log = {}
    return vt
end

-- ---------------------------------------------------------------------------
-- CSI integer validation

-- Validate CSI numeric parameters — catch framework bugs that emit float
-- coordinates (e.g. \27[73.0;3.0H) which real terminals silently reject.
function M.check_csi_integers(s)
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

-- ---------------------------------------------------------------------------
-- Write (wraps C write, appends to Lua write_log)

function M.write(vt, s)
    vt.write_log[#vt.write_log + 1] = s
    return vt:write(s)
end

-- ---------------------------------------------------------------------------
-- Cell / screen queries (delegated to C)

M.cell         = function(vt, col, row) return vt:cell(col, row) end
M.row          = function(vt, r)        return vt:row(r) end
M.screen       = function(vt)           return vt:screen() end
M.cursor       = function(vt)           return vt:cursor() end
M.mode         = function(vt)           return vt:mode() end
M.has_mode     = function(vt, num)      return vt:has_mode(num) end
M.mouse_level  = function(vt)           return vt:mouse_level() end
M.sync_depth   = function(vt)           return vt:sync_depth() end
M.screen_string = function(vt)          return vt:screen_string() end
M.row_string   = function(vt, r)        return vt:row_string(r) end
M.resize       = function(vt, cols, rows) return vt:resize(cols, rows) end

-- ---------------------------------------------------------------------------
-- Write log queries (pure Lua)

M.write_log = function(vt) return vt.write_log end

M.has_sequence = function(vt, pattern)
    for _, s in ipairs(vt.write_log) do
        if s:find(pattern, 1, true) then return true end
    end
    return false
end

M.has_sequence_pattern = function(vt, pattern)
    for _, s in ipairs(vt.write_log) do
        if s:find(pattern) then return true end
    end
    return false
end

M.last_sequence = function(vt)
    local log = vt.write_log
    return log[#log]
end

-- ---------------------------------------------------------------------------
-- Clipboard log (pure Lua)

M.clipboard_log = function(vt) return vt.clipboard_log end

-- ---------------------------------------------------------------------------
-- Input queue (pure Lua)

M.enqueue_input = function(vt, bytes)
    vt.input_queue[#vt.input_queue + 1] = bytes
end

M.clear_input = function(vt)
    vt.input_queue = {}
end

M.enqueue_paste = function(vt, text)
    vt.input_queue[#vt.input_queue + 1] = "\x1b[200~" .. text .. "\x1b[201~"
end

M.enqueue_focus_in = function(vt)
    vt.input_queue[#vt.input_queue + 1] = "\x1b[I"
end

M.enqueue_focus_out = function(vt)
    vt.input_queue[#vt.input_queue + 1] = "\x1b[O"
end

-- ---------------------------------------------------------------------------
-- Input simulation (enqueue bytes into the vterm input queue)
--
-- These methods encode high-level input actions as terminal bytes and
-- push them into the vterm input queue.  The next read() / loop_once()
-- will pick them up and feed them through the production input pipeline
-- (onInput → input_mod.dispatch), matching the real terminal path.

function M.press(vt, name)
    local testing_input = require "tui.testing.input"
    local raw = testing_input.resolve_key(name)
    if raw == nil then
        M.type(vt, name)
        return
    end
    M.enqueue_input(vt, raw)
end

function M.type(vt, str)
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local n = b < 0x80 and 1 or b < 0xC0 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
        M.enqueue_input(vt, str:sub(i, i + n - 1))
        i = i + n
    end
end

M.paste = M.enqueue_paste

function M.dispatch(vt, bytes)
    if bytes and #bytes > 0 then
        M.enqueue_input(vt, bytes)
    end
end

function M.mouse(vt, ev_type, btn, x, y, mods)
    local testing_mouse = require "tui.testing.mouse"
    M.enqueue_input(vt, testing_mouse.harness(ev_type, btn, x, y, mods))
end

-- ---------------------------------------------------------------------------
-- Terminal interface (Lua, uses write_log and input_queue)
--
-- opts (optional):
--   ansi_buf     — table to additionally log writes to
--   validate_csi — bool, enable CSI integer parameter validation

function M.as_terminal(vt, opts)
    opts = opts or {}
    local ansi_buf     = opts.ansi_buf
    local validate_csi = opts.validate_csi
    local capabilities = opts.capabilities

    return {
        init = function()
            return true
        end,
        write = function(s)
            if validate_csi then
                local bad = M.check_csi_integers(s)
                if bad then
                    error("[tui:fatal] harness terminal: " .. bad, 0)
                end
            end
            vt.write_log[#vt.write_log + 1] = s
            if ansi_buf then ansi_buf[#ansi_buf + 1] = s end
            vt:write(s)
        end,
        get_size = function()
            return vt.cols, vt.rows
        end,
        read = function()
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
        resize = function(cols, rows)
            vt:resize(cols, rows)
        end,
        capabilities = capabilities,
    }
end

return M
