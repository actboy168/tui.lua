-- tui/testing/vterm.lua — Lua wrapper around C vterm implementation.
--
-- Delegates ANSI parsing to tui_core.vterm (C). Write log, input queue,
-- and clipboard log are managed entirely in Lua — the C layer has no
-- registry refs for these tables.

local vterm_c = require("tui_core").vterm

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
-- Terminal interface (Lua, uses write_log and input_queue)

function M.as_terminal(vt)
    return {
        write = function(s)
            vt.write_log[#vt.write_log + 1] = s
            vt:write(s)
        end,
        get_size = function()
            return vt.cols, vt.rows
        end,
        read_raw = function()
            if #vt.input_queue > 0 then
                return table.remove(vt.input_queue, 1)
            end
            return nil
        end,
        set_raw = function(on)
            vt:set_raw(on and true or false)
        end,
        windows_vt_enable = function()
            return true
        end,
    }
end

-- Internal scroll helpers (kept for compatibility)
M._scroll_up   = function() end
M._scroll_down = function() end

return M
