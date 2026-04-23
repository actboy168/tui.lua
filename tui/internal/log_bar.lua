-- tui/internal/log_bar.lua — implicit bottom log bar extension.

local element = require "tui.internal.element"
local log_mod = require "tui.internal.log"

local M = {}

function M.decorate(tree, ctx)
    local message = log_mod.peek()
    if message == nil then
        return tree
    end

    local w = ctx.width
    local badge_w = math.min(w, 5)
    local body_w = math.max(0, w - badge_w)

    return element.Box {
        width = w,
        flexDirection = "column",
        tree,
        element.Box {
            key = "__tui_log_bar_box",
            width = w,
            flexDirection = "row",
            element.Text {
                key = "__tui_log_badge",
                width = badge_w,
                wrap = "truncate",
                color = "black",
                backgroundColor = "yellow",
                bold = true,
                " LOG ",
            },
            body_w > 0 and element.Text {
                key = "__tui_log_bar",
                width = body_w,
                wrap = "truncate",
                color = "white",
                backgroundColor = "brightBlack",
                message,
            } or nil
        },
    }
end

function M.subscribe(request_redraw)
    return log_mod.subscribe(function()
        request_redraw()
    end)
end

function M.reset()
    log_mod._reset()
end

return M
