-- examples/raw_ansi.lua - RawAnsi 超链接示例
-- 运行: luamake lua examples/raw_ansi.lua
-- 按键: q/Esc 退出

local tui = require "tui"

local function App()
    local app = tui.useApp()
    local<const> width = tui.displayWidth("SGR + OSC 8, already split into lines")

    tui.useInput(function(_, key)
        if key.name == "q" or key.name == "escape" then
            app:exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 1,
        gap = 1,
        tui.Text { bold = true, "RawAnsi 示例" },
        tui.Text { dim = true, "低层能力：输入必须是已拆行、已格式化好的 ANSI。" },
        tui.RawAnsi {
            lines = {
                "\27[32mOK:\27[0m \27]8;;https://example.com/raw\27\\raw-docs\27]8;;\27\\",
                "\27[36mSGR\27[0m + OSC 8, already split into lines",
            },
            width = width,
        },
        tui.Text { dim = true, "这里演示的是 screen backend 内的 ANSI/OSC 8 渲染。" },
    }
end

tui.render(App)
