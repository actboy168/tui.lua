-- examples/link.lua - Link 组件示例
-- 运行: luamake lua examples/link.lua
-- 按键: Enter 激活聚焦链接, q/Esc 退出

local tui = require "tui"
local extra = require "tui.extra"

local function App()
    local app = tui.useApp()
    local status, setStatus = tui.useState("状态: 尚未激活")

    tui.useInput(function(_, key)
        if key.name == "q" or key.name == "escape" then
            app:exit()
        end
    end)

    local function handleClick(ev)
        setStatus(("状态: %s -> %s"):format(ev.source, ev.href))
    end

    return tui.Box {
        flexDirection = "column",
        padding = 1,
        gap = 0,
        tui.Text { bold = true, "Link 示例" },
        tui.Text { dim = true, "高层超链接组件：终端 href + 应用 onClick。" },
        extra.Link {
            href = "https://example.com/docs",
            autoFocus = true,
            onClick = handleClick,
            "可激活链接",
        },
        extra.Link {
            href = "https://example.com/plain",
            "纯终端链接",
        },
        extra.Link {
            href = "https://example.com/disabled",
            isDisabled = true,
            onClick = function()
                setStatus("状态: disabled 不应触发")
            end,
            "禁用链接",
        },
        tui.Text { status },
        tui.Text { dim = true, "Enter 触发聚焦链接；鼠标点击会记录 source=mouse。" },
    }
end

tui.render(App)
