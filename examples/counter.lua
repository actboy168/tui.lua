-- examples/counter.lua - 计数器示例
-- 运行: luamake lua examples/counter.lua
-- 按键: ↑ 增加, ↓ 减少, q/Esc 退出

local tui = require "tui"

local function Counter()
    local count, setCount = tui.useState(0)
    local app = tui.useApp()

    tui.useInput(function(_, key)
        if key.name == "q" or key.name == "escape" then
            app:exit()
        elseif key.name == "up" then
            setCount(count + 1)
        elseif key.name == "down" then
            setCount(count - 1)
        end
    end)

    return tui.Box {
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        gap = 1,

        tui.Text { bold = true, "计数器" },
        tui.Text { ("%d"):format(count) },
        tui.Newline {},
        tui.Text { dim = true, "↑ 增加  ↓ 减少  q 退出" }
    }
end

tui.render(Counter)
