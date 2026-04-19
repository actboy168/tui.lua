-- examples/wizard_form.lua - 多步骤向导表单示例
-- 运行: luamake lua examples/wizard_form.lua
-- 按键: Enter 继续, Esc 退出

local tui = require "tui"

local function Wizard()
    local step, setStep = tui.useState(1)
    local form, setForm = tui.useState({})
    local submitted, setSubmitted = tui.useState(false)
    local app = tui.useApp()

    local function updateField(key, value)
        local newForm = {}
        for k, v in pairs(form) do newForm[k] = v end
        newForm[key] = value
        setForm(newForm)
    end

    local function nextStep()
        if step < 3 then
            setStep(step + 1)
        else
            setSubmitted(true)
        end
    end

    tui.useInput(function(_, key)
        if key.name == "escape" then
            app:exit()
        elseif step == 3 and key.name == "enter" then
            nextStep()
        end
    end)

    if submitted then
        return tui.Box {
            flexDirection = "column",
            padding = 2,
            tui.Text { bold = true, "注册成功!" },
            tui.Newline {},
            tui.Text { ("用户名: %s"):format(form.username) },
            tui.Text { ("邮箱: %s"):format(form.email) },
            tui.Newline {},
            tui.Text { dim = true, "按 Esc 退出" }
        }
    end

    return tui.Box {
        flexDirection = "column",
        padding = 2,
        gap = 1,

        tui.Text { bold = true, ("注册 (%d/3)"):format(step) },
        tui.Newline {},

        step == 1 and tui.Box {
            tui.Text { "步骤 1: 设置用户名" },
            tui.TextInput {
                value = form.username or "",
                onChange = function(v) updateField("username", v) end,
                onSubmit = nextStep,
                placeholder = "用户名",
                width = 30
            }
        } or nil,

        step == 2 and tui.Box {
            tui.Text { "步骤 2: 设置邮箱" },
            tui.TextInput {
                value = form.email or "",
                onChange = function(v) updateField("email", v) end,
                onSubmit = nextStep,
                placeholder = "邮箱",
                width = 30
            }
        } or nil,

        step == 3 and tui.Box {
            tui.Text { "步骤 3: 确认信息" },
            tui.Text { ("用户名: %s"):format(form.username) },
            tui.Text { ("邮箱: %s"):format(form.email) },
            tui.Newline {},
            tui.Text { "按 Enter 确认注册" }
        } or nil,

        tui.Newline {},
        tui.Text { dim = true, "Enter 继续  Esc 退出" }
    }
end

tui.render(Wizard)
