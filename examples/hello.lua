-- examples/hello.lua - Hello World 示例
-- 运行: luamake lua examples/hello.lua
-- 退出: Ctrl+C, Ctrl+D, q, 或 Esc

local tui = require "tui"

local function App()
    local app = tui.useApp()

    tui.useInput(function(input, key)
        if input == "q" or key.name == "escape" then
            app:exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 2,
        tui.Text { bold = true, "Hello, tui.lua!" },
        tui.Newline {},
        tui.Text { "按 q 或 Esc 退出" }
    }
end

tui.render(App)
