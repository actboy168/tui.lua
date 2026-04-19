-- examples/login_form.lua - 登录表单示例
-- 运行: luamake lua examples/login_form.lua
-- 按键: Tab 切换字段, Enter 提交, Esc 退出

local tui = require "tui"

local function LoginForm()
    local username, setUsername = tui.useState("")
    local password, setPassword = tui.useState("")
    local error, setError = tui.useState(nil)
    local app = tui.useApp()

    local function submit()
        if #username == 0 then
            setError("请输入用户名")
            return
        end
        if #password == 0 then
            setError("请输入密码")
            return
        end

        -- 登录成功，显示信息并退出
        print(("\n登录成功! 用户名: %s, 密码: %s"):format(username, password))
        app:exit()
    end

    tui.useInput(function(_, key)
        if key.name == "escape" then
            app:exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 2,
        gap = 1,

        tui.Text { bold = true, "用户登录" },
        tui.Newline {},

        error and tui.Box {
            borderStyle = "single",
            borderColor = "red",
            padding = { left = 1, right = 1 },
            tui.Text { color = "red", error }
        } or nil,

        tui.Text { "用户名" },
        tui.TextInput {
            value = username,
            onChange = setUsername,
            onSubmit = function() end,  -- Enter 移动到下一个
            placeholder = "输入用户名",
            width = 30
        },

        tui.Text { "密码" },
        tui.TextInput {
            value = password,
            onChange = setPassword,
            onSubmit = submit,  -- Enter 提交
            placeholder = "输入密码",
            mask = "*",
            width = 30
        },

        tui.Newline {},

        tui.Box {
            flexDirection = "row",
            gap = 1,
            tui.Box {
                borderStyle = "single",
                padding = { left = 2, right = 2 },
                tui.Text { "登录" }
            },
            tui.Box {
                borderStyle = "single",
                padding = { left = 2, right = 2 },
                tui.Text { "取消" }
            }
        },

        tui.Newline {},
        tui.Text { dim = true, "Tab 切换  Enter 提交  Esc 退出" }
    }
end

tui.render(LoginForm)
