-- examples/button.lua - Button 组件示例
-- 运行: luamake lua examples/button.lua
-- 按键: Enter 激活聚焦按钮, q/Esc 退出

local tui = require "tui"
local extra = require "tui.extra"

local function App()
    local app = tui.useApp()
    local status, setStatus = tui.useState("状态: 尚未点击")

    tui.useInput(function(_, key)
        if key.name == "q" or key.name == "escape" then
            app:exit()
        end
    end)

    local function handleClick(ev)
        setStatus(("状态: %s"):format(ev.source))
    end

    return tui.Box {
        flexDirection = "column",
        padding = 1,
        gap = 1,
        tui.Text { bold = true, "Button 示例" },
        extra.Button {
            label = "保存",
            autoFocus = true,
            onClick = handleClick,
        },
        extra.Button {
            onClick = handleClick,
            "继续 ",
            tui.Text { color = "cyan", "下一步" },
        },
        extra.Button {
            label = "禁用按钮",
            isDisabled = true,
            onClick = function()
                setStatus("状态: disabled 不应触发")
            end,
        },
        tui.Text { status },
        tui.Text { dim = true, "Enter 激活聚焦按钮；鼠标点击会记录 source=mouse。" },
    }
end

tui.render(App)
