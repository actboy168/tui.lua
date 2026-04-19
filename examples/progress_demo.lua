-- examples/progress_demo.lua - 进度条和加载动画示例
-- 运行: luamake lua examples/progress_demo.lua
-- 按键: Esc 退出

local tui = require "tui"

local function ProgressDemo()
    local progress, setProgress] = tui.useState(0)
    local app = tui.useApp()

    -- 模拟进度增长
    tui.useInterval(function()
        setProgress(function(p)
            if p >= 100 then
                return 0
            end
            return p + 2
        end)
    end, 100)

    tui.useInput(function(_, key)
        if key.name == "escape" then
            app:exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 2,
        gap = 1,

        tui.Text { bold = true, "进度演示" },
        tui.Newline {},

        -- 加载动画
        tui.Box {
            flexDirection = "row",
            gap = 1,
            tui.Spinner { type = "dots", label = "处理中" },
        },

        tui.Newline {},

        -- 进度条
        tui.Text { ("进度: %d%%"):format(progress) },
        tui.ProgressBar {
            value = progress / 100,
            width = 40,
            color = progress > 80 and "green" or "blue"
        },

        tui.Newline {},
        tui.Text { dim = true, "Esc 退出" }
    }
end

tui.render(ProgressDemo)
