local tui_core = require "tui_core"

local M = {}

local real_stderr           = io.stderr
local stderr_hook_installed = false
local unexpected_warnings   = {}
local capture_buffer        = nil

local function install_stderr_hook()
    if stderr_hook_installed then return end
    stderr_hook_installed = true
    real_stderr = io.stderr
    io.stderr = {
        write = function(self, ...)
            local s = table.concat({ ... })
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

function M.drain_and_fatal_if_any()
    if #unexpected_warnings == 0 then return end
    local msg = table.concat(unexpected_warnings)
    unexpected_warnings = {}
    error("[tui:fatal] unexpected dev warning(s) (wrap the offending work "
        .. "in testing.capture_stderr if expected):\n" .. msg, 0)
end

function M.capture_stderr(fn)
    local prev = capture_buffer
    capture_buffer = {}
    local ok, err = pcall(fn)
    local s = table.concat(capture_buffer)
    capture_buffer = prev
    if not ok then error(err, 2) end
    return s
end

function M.capture_writes(fn)
    local buf = {}
    local orig = tui_core.terminal.write
    tui_core.terminal.write = function(s) buf[#buf + 1] = s end
    local ok, err = pcall(fn)
    tui_core.terminal.write = orig
    if not ok then error(err, 2) end
    return table.concat(buf)
end

install_stderr_hook()

return M
