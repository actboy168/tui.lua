-- tui/init.lua — public API entry for the tui framework.
--
-- Stage 1 API surface:
--   tui.Box { ... }
--   tui.Text { ... }
--   tui.render(element)    -- block until Ctrl+C / 'q'

local element  = require "tui.element"
local layout   = require "tui.layout"
local renderer = require "tui.renderer"
local tui_core = require "tui_core"
local thread   = require "bee.thread"

local terminal = tui_core.terminal

local M = {}

M.Box  = element.Box
M.Text = element.Text

-- ANSI helpers
local CLEAR    = "\27[2J\27[H"
local HIDE_CUR = "\27[?25l"
local SHOW_CUR = "\27[?25h"

-- Minimal blocking render loop for Stage 1:
--   1. enable raw mode + VT
--   2. measure terminal
--   3. compute layout + render once
--   4. poll for input; exit on Ctrl+C (0x03), Ctrl+D (0x04) or 'q'
--   5. always restore terminal on exit
function M.render(root)
    terminal.windows_vt_enable()
    terminal.set_raw(true)
    terminal.write(HIDE_CUR .. CLEAR)

    local ok, err = pcall(function()
        local w, h = terminal.get_size()

        -- Let the root Box fill the terminal if it hasn't set a size.
        if root.kind == "box" then
            root.props = root.props or {}
            if root.props.width  == nil then root.props.width  = w end
            if root.props.height == nil then root.props.height = h end
        end

        layout.compute(root)
        local ansi = renderer.render(root, w, h)
        terminal.write(ansi)
        layout.free(root)

        -- Poll until an exit key arrives. Non-blocking read → sleep briefly.
        while true do
            local s = terminal.read_raw()
            if s then
                for i = 1, #s do
                    local b = s:byte(i)
                    if b == 3 or b == 4 or s:sub(i, i) == "q" then
                        return
                    end
                end
            end
            -- Cheap idle via a short bee.thread sleep (in milliseconds).
            thread.sleep(20)
        end
    end)

    -- Always restore terminal state.
    terminal.write(SHOW_CUR .. "\r\n")
    terminal.set_raw(false)

    if not ok then error(err) end
end

return M
