-- examples/dashboard.lua - 仪表盘示例
-- 运行: luamake lua examples/dashboard.lua
-- 按键: Esc 退出

local tui = require "tui"

local function Dashboard()
    local metrics, setMetrics] = tui.useState({
        cpu = 45,
        memory = 60,
        requests = 1234
    })
    local app = tui.useApp()

    -- 模拟实时更新
    tui.useInterval(function()
        setMetrics({
            cpu = math.random(30, 80),
            memory = math.random(40, 70),
            requests = metrics.requests + math.random(1, 10)
        })
    end, 1000)

    tui.useInput(function(_, key)
        if key.name == "escape" then
            app:exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 2,
        gap = 1,

        tui.Text { bold = true, "系统监控" },
        tui.Newline {},

        tui.Box {
            flexDirection = "row",
            gap = 2,

            -- CPU
            tui.Box {
                borderStyle = "single",
                padding = 1,
                width = 20,
                tui.Text { "CPU" },
                tui.Text { bold = true, ("%d%%"):format(metrics.cpu) },
                tui.ProgressBar {
                    value = metrics.cpu / 100,
                    width = 18,
                    color = metrics.cpu > 70 and "red" or "green"
                }
            },

            -- 内存
            tui.Box {
                borderStyle = "single",
                padding = 1,
                width = 20,
                tui.Text { "内存" },
                tui.Text { bold = true, ("%d%%"):format(metrics.memory) },
                tui.ProgressBar {
                    value = metrics.memory / 100,
                    width = 18,
                    color = metrics.memory > 70 and "red" or "blue"
                }
            },

            -- 请求数
            tui.Box {
                borderStyle = "single",
                padding = 1,
                width = 20,
                tui.Text { "请求数" },
                tui.Text { bold = true, tostring(metrics.requests) },
                tui.Spinner { type = "simple" }
            }
        },

        tui.Newline {},
        tui.Text { dim = true, "Esc 退出" }
    }
end

tui.render(Dashboard)
