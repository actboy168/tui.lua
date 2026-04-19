# 示例代码

本文档中的示例代码都可以在 [examples/](../../examples/) 目录找到对应的可运行文件。

## 快速链接

| 文档示例 | 可运行文件 |
|----------|------------|
| Hello World | [examples/hello.lua](../../examples/hello.lua) |
| 计数器 | [examples/counter.lua](../../examples/counter.lua) |
| 登录表单 | [examples/login_form.lua](../../examples/login_form.lua) |
| 待办事项 | [examples/todo_list.lua](../../examples/todo_list.lua) |
| 向导表单 | [examples/wizard_form.lua](../../examples/wizard_form.lua) |
| 选项菜单 | [examples/select_menu.lua](../../examples/select_menu.lua) |
| 进度演示 | [examples/progress_demo.lua](../../examples/progress_demo.lua) |
| 仪表盘 | [examples/dashboard.lua](../../examples/dashboard.lua) |

## 运行示例

```bash
# 运行指定示例
luamake lua examples/hello.lua
luamake lua examples/counter.lua
luamake lua examples/login_form.lua

# 查看所有示例
ls examples/
```

## 代码片段

### Hello World

```lua
local tui = require "tui"

local function App()
    return tui.Box {
        flexDirection = "column",
        padding = 2,
        tui.Text { bold = true, "Hello, tui.lua!" },
        tui.Text { "按 Ctrl+C 退出" }
    }
end

tui.render(App)
```

[在 examples/hello.lua 中查看完整代码](../../examples/hello.lua)

### 计数器

```lua
local function Counter()
    local count, setCount = tui.useState(0)
    local app = tui.useApp()

    tui.useInput(function(_, key)
        if key.name == "up" then
            setCount(count + 1)
        elseif key.name == "down" then
            setCount(count - 1)
        elseif key.name == "q" then
            app:exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        tui.Text { bold = true, "计数器" },
        tui.Text { tostring(count) },
        tui.Text { dim = true, "↑ 增加  ↓ 减少  q 退出" }
    }
end
```

[在 examples/counter.lua 中查看完整代码](../../examples/counter.lua)

### 登录表单

```lua
local function LoginForm()
    local username, setUsername = tui.useState("")
    local password, setPassword = tui.useState("")

    local function submit()
        print("登录:", username, password)
    end

    return tui.Box {
        flexDirection = "column",
        gap = 1,
        tui.Text { "用户名" },
        tui.TextInput {
            value = username,
            onChange = setUsername,
            width = 30
        },
        tui.Text { "密码" },
        tui.TextInput {
            value = password,
            onChange = setPassword,
            onSubmit = submit,
            mask = "*",
            width = 30
        }
    }
end
```

[在 examples/login_form.lua 中查看完整代码](../../examples/login_form.lua)

### 带 Tab 导航的表单

```lua
-- 第一个输入框自动聚焦
h:type("用户名")

-- Tab 切换到密码框
h:press("tab")
h:type("密码")

-- Enter 提交
h:press("return")
```

[在 examples/login_form.lua 中查看完整代码](../../examples/login_form.lua)

### 多步骤向导

```lua
local function Wizard()
    local step, setStep = tui.useState(1)

    local function nextStep()
        setStep(step + 1)
    end

    if step == 1 then
        return tui.Box {
            tui.TextInput {
                onSubmit = nextStep,
                placeholder = "步骤 1"
            }
        }
    elseif step == 2 then
        return tui.Box {
            tui.TextInput {
                onSubmit = nextStep,
                placeholder = "步骤 2"
            }
        }
    end
end
```

[在 examples/wizard_form.lua 中查看完整代码](../../examples/wizard_form.lua)

### 待办事项列表

```lua
local function TodoApp()
    local todos, setTodos = tui.useState({})
    local input, setInput = tui.useState("")

    local function addTodo()
        if #input > 0 then
            setTodos({ ...todos, { text = input, done = false } })
            setInput("")
        end
    end

    return tui.Box {
        tui.TextInput {
            value = input,
            onChange = setInput,
            onSubmit = addTodo,
            placeholder = "添加新任务..."
        },
        tui.Static {
            items = todos,
            render = function(todo)
                return tui.Text {
                    (todo.done and "[x] " or "[ ] ") .. todo.text
                }
            end
        }
    }
end
```

[在 examples/todo_list.lua 中查看完整代码](../../examples/todo_list.lua)

### 选项菜单

```lua
local items = {
    { label = "选项1", value = 1 },
    { label = "选项2", value = 2 },
}

return tui.Select {
    items = items,
    onSelect = function(item)
        print("选中:", item.label)
    end
}
```

[在 examples/select_menu.lua 中查看完整代码](../../examples/select_menu.lua)

### 进度条和加载动画

```lua
return tui.Box {
    tui.Spinner { type = "dots", label = "加载中" },
    tui.ProgressBar {
        value = 0.75,
        width = 40,
        color = "green"
    }
}
```

[在 examples/progress_demo.lua 中查看完整代码](../../examples/progress_demo.lua)

### 实时仪表盘

```lua
tui.useInterval(function()
    setMetrics({
        cpu = math.random(30, 80),
        memory = math.random(40, 70)
    })
end, 1000)
```

[在 examples/dashboard.lua 中查看完整代码](../../examples/dashboard.lua)

## 更多示例

查看 [examples/](../../examples/) 目录获取所有可运行的示例代码。
