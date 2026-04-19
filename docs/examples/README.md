# 示例集合

## 基础示例

### Hello World

```lua
local tui = require "tui"

local function App()
    return tui.Box {
        justifyContent = "center",
        alignItems = "center",
        tui.Text { "Hello, tui.lua!" }
    }
end

tui.render(App)
```

### 计数器

```lua
local tui = require "tui"

local function Counter()
    local count, setCount = tui.useState(0)

    tui.useInput(function(_, key)
        if key.name == "up" then
            setCount(count + 1)
        elseif key.name == "down" then
            setCount(count - 1)
        elseif key.name == "q" then
            tui.useApp():exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        gap = 1,

        tui.Text { bold = true, "计数器" },
        tui.Text { ("%d"):format(count) },
        tui.Text { dim = true, "↑ 增加  ↓ 减少  q 退出" }
    }
end

tui.render(Counter)
```

## 表单示例

### 登录表单

```lua
local tui = require "tui"

local function LoginForm()
    local username, setUsername = tui.useState("")
    local password, setPassword = tui.useState("")
    local error, setError = tui.useState(nil)

    local function submit()
        if #username == 0 then
            setError("请输入用户名")
            return
        end
        if #password == 0 then
            setError("请输入密码")
            return
        end

        print(("登录成功: %s / %s"):format(username, password))
        tui.useApp():exit()
    end

    tui.useInput(function(_, key)
        if key.name == "escape" then
            tui.useApp():exit()
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
            onSubmit = function() end,
            placeholder = "输入用户名",
            width = 30
        },

        tui.Text { "密码" },
        tui.TextInput {
            value = password,
            onChange = setPassword,
            onSubmit = submit,
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
```

### 注册向导

```lua
local tui = require "tui"

local function Wizard()
    local step, setStep = tui.useState(1)
    local form, setForm = tui.useState({})
    local submitted, setSubmitted] = tui.useState(false)

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
            tui.useApp():exit()
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

    -- 所有步骤都注册 useInput
    tui.useInput(function(_, key)
        if step == 3 and key.name == "enter" then
            nextStep()
        end
    end)

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
```

## 列表示例

### 待办事项列表

```lua
local tui = require "tui"

local function TodoApp()
    local todos, setTodos] = tui.useState({
        { text = "学习 tui.lua", done = false },
        { text = "编写文档", done = false },
        { text = "发布项目", done = false },
    })
    local input, setInput = tui.useState("")

    local function addTodo()
        if #input > 0 then
            setTodos({ ...todos, { text = input, done = false } })
            setInput("")
        end
    end

    local function toggleTodo(index)
        local newTodos = {}
        for i, todo in ipairs(todos) do
            newTodos[i] = {
                text = todo.text,
                done = i == index and not todo.done or todo.done
            }
        end
        setTodos(newTodos)
    end

    tui.useInput(function(_, key)
        if key.name == "escape" then
            tui.useApp():exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 2,

        tui.Text { bold = true, "待办事项" },
        tui.Newline {},

        tui.Box {
            flexDirection = "row",
            gap = 1,
            tui.TextInput {
                value = input,
                onChange = setInput,
                onSubmit = addTodo,
                placeholder = "添加新任务...",
                flex = 1
            }
        },

        tui.Newline {},

        #todos == 0 and tui.Text { dim = true, "暂无任务" } or nil,

        tui.Static {
            items = todos,
            render = function(todo, i)
                return tui.Box {
                    flexDirection = "row",
                    gap = 1,
                    tui.Text {
                        todo.done and color = "green" or nil,
                        (todo.done and "[x] " or "[ ] ") .. todo.text
                    }
                }
            end
        },

        tui.Newline {},
        tui.Text { dim = true, "Enter 添加  Esc 退出" }
    }
end

tui.render(TodoApp)
```

### 文件浏览器

```lua
local tui = require "tui"

local function FileBrowser()
    local files = tui.useState({
        { name = "documents/", type = "dir" },
        { name = "downloads/", type = "dir" },
        { name = "README.md", type = "file" },
        { name = "main.lua", type = "file" },
        { name = "config.json", type = "file" },
    })

    return tui.Box {
        flexDirection = "column",
        padding = 1,

        tui.Box {
            borderStyle = "single",
            padding = { left = 1, right = 1 },
            tui.Text { "~/projects/myapp" }
        },

        tui.Newline {},

        tui.Select {
            items = tui.map(files, function(f)
                return {
                    label = (f.type == "dir" and "📁 " or "📄 ") .. f.name,
                    value = f
                }
            end),
            onSelect = function(item)
                print("选中:", item.value.name)
            end
        }
    }
end

tui.render(FileBrowser)
```

## 数据展示示例

### 仪表盘

```lua
local tui = require "tui"

local function Dashboard()
    local metrics, setMetrics = tui.useState({
        cpu = 45,
        memory = 60,
        requests = 1234
    })

    -- 模拟实时更新
    tui.useInterval(function()
        setMetrics({
            cpu = math.random(30, 80),
            memory = math.random(40, 70),
            requests = metrics.requests + math.random(1, 10)
        })
    end, 1000)

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
        }
    }
end

tui.render(Dashboard)
```

## 交互示例

### 确认对话框

```lua
local function ConfirmDialog(props)
    return tui.Box {
        borderStyle = "double",
        borderColor = "yellow",
        padding = 2,

        tui.Text { bold = true, props.title or "确认" },
        tui.Newline {},
        tui.Text { props.message },
        tui.Newline {},

        tui.Box {
            flexDirection = "row",
            gap = 2,
            justifyContent = "center",

            tui.Box {
                borderStyle = props.selected == "ok" and "double" or "single",
                padding = { left = 2, right = 2 },
                tui.Text { "确定" }
            },
            tui.Box {
                borderStyle = props.selected == "cancel" and "double" or "single",
                padding = { left = 2, right = 2 },
                tui.Text { "取消" }
            }
        }
    }
end
```

## 更多示例

- [表格视图](table.md)
- [树形控件](tree.md)
- [编辑器](editor.md)
- [图表](charts.md)
- [游戏](games.md)
