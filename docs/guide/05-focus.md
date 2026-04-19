# 焦点系统指南

tui.lua 的焦点系统用于管理可交互元素的键盘导航。

## 核心概念

**重要：焦点系统与 React 状态是独立的**

- `useState` 管理的是**数据状态**（如边框样式、颜色）
- `useFocus` 管理的是**焦点状态**（哪个元素接收键盘输入）
- 改变状态变量**不会**自动切换焦点

## 基本用法

### TextInput 自动焦点

```lua
tui.TextInput {
    value = text,
    onChange = setText,
    onSubmit = submit,
    autoFocus = true  -- 自动获得焦点
}
```

### 键盘导航

| 按键 | 行为 |
|------|------|
| `Tab` | 下一个可聚焦元素 |
| `Shift+Tab` | 上一个可聚焦元素 |
| `Enter` | 触发当前元素的 `onSubmit` |

## 焦点顺序

焦点顺序由组件注册顺序决定：

```lua
local function Form()
    return tui.Box {
        -- 第一个 TextInput 获得焦点
        tui.TextInput { key = "input1", autoFocus = true },

        -- 按 Tab 会到这里
        tui.TextInput { key = "input2" },

        -- 再按 Tab 到这里
        tui.TextInput { key = "input3" }
    }
end
```

## useFocus Hook

创建自定义可聚焦组件：

```lua
local function CustomInput(props)
    local value, setValue = tui.useState("")

    local focus = tui.useFocus {
        autoFocus = props.autoFocus,
        on_input = function(input, key)
            if key.name == "char" then
                setValue(value .. input)
            elseif key.name == "backspace" then
                setValue(value:sub(1, -2))
            elseif key.name == "enter" then
                props.onSubmit(value)
            end
        end
    }

    return tui.Box {
        borderStyle = focus.isFocused and "double" or "single",
        borderColor = focus.isFocused and "blue" or nil,
        tui.Text { value }
    }
end
```

### useFocus 选项

| 选项 | 类型 | 说明 |
|------|------|------|
| `id` | string | 焦点标识符 |
| `autoFocus` | boolean | 自动获得焦点 |
| `isActive` | boolean | 是否可聚焦 |
| `on_change` | function(isFocused) | 焦点变化回调 |
| `on_input` | function(input, key) | 输入处理回调 |

### 返回值

```lua
local focus = tui.useFocus {...}

focus.isFocused  -- 布尔值，是否有焦点
focus.focus()    -- 方法：主动获取焦点
```

## 手动控制焦点

```lua
local focus = require "tui.focus"

-- 聚焦指定元素
focus.focus("myInputId")

-- 导航
focus.focus_next()   -- 下一个
focus.focus_prev()   -- 上一个

-- 获取当前焦点
local id = focus.get_focused_id()
```

## 禁用焦点元素

```lua
tui.TextInput {
    value = text,
    focus = false,  -- 禁用焦点（isActive = false）
}
```

## 表单示例

### 简单表单

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
            onSubmit = function() end,  -- Tab 会自动移动到下一个
            width = 30
        },

        tui.Text { "密码" },
        tui.TextInput {
            value = password,
            onChange = setPassword,
            onSubmit = submit,  -- Enter 提交
            mask = "*",
            width = 30
        },

        tui.Text { dim = true, "按 Tab 切换，Enter 提交" }
    }
end
```

### 多步骤向导

```lua
local function Wizard()
    local step, setStep = tui.useState(1)
    local data, setData = tui.useState({})

    local function nextStep()
        if step < 3 then
            setStep(step + 1)
        else
            submit(data)
        end
    end

    -- 所有步骤都调用 useInput，保持 hook 数量一致
    tui.useInput(function(_, key)
        if step == 3 and key.name == "enter" then
            nextStep()
        end
    end)

    if step == 1 then
        return tui.Box {
            tui.Text { "步骤 1/3" },
            tui.TextInput {
                value = data.name or "",
                onChange = function(v)
                    setData({ ...data, name = v })
                end,
                onSubmit = nextStep,  -- Enter 进入下一步
                placeholder = "姓名"
            }
        }
    elseif step == 2 then
        return tui.Box {
            tui.Text { "步骤 2/3" },
            tui.TextInput {
                value = data.email or "",
                onChange = function(v)
                    setData({ ...data, email = v })
                end,
                onSubmit = nextStep,
                placeholder = "邮箱"
            }
        }
    else
        return tui.Box {
            tui.Text { "步骤 3/3 - 确认" },
            tui.Text { "姓名: " .. data.name },
            tui.Text { "邮箱: " .. data.email },
            tui.Text { "按 Enter 提交" }
        }
    end
end
```

## 测试焦点

```lua
local testing = require "tui.testing"

function suite:test_focus_flow()
    local h = testing.render(Form)

    -- 第一个输入框自动聚焦
    h:type("用户名")

    -- Tab 切换到下一个
    h:press("tab")
    h:type("密码")

    -- Enter 提交
    h:press("return")

    -- 验证结果
    lt.assertNotEquals(submitted, nil)
end
```

## 焦点与样式的区别

```lua
local function ConfusingExample()
    -- 这是状态变量，只影响显示
    local focusedField, setFocusedField = tui.useState("username")

    return tui.Box {
        tui.Box {
            -- 改变边框样式
            borderStyle = focusedField == "username" and "single" or nil,
            tui.TextInput {
                -- 但这是独立的焦点系统！
                -- 即使边框样式变了，实际焦点可能还在这里
            }
        }
    }
end
```

**正确做法**：

```lua
local function CorrectExample()
    return tui.Box {
        tui.TextInput {
            -- 焦点系统自动控制边框样式
            -- 无需手动管理
        },
        tui.TextInput {
            -- 按 Tab 自动切换
        }
    }
end
```

## 常见错误

### 1. 用状态变量切换焦点

❌ 错误：
```lua
setFocused("password")  -- 只更新了状态，没切换实际焦点
```

✅ 正确：
```lua
-- 方法1：按 Tab
h:press("tab")

-- 方法2：使用 onSubmit
tui.TextInput {
    onSubmit = function()
        -- 进入下一步
    end
}
```

### 2. 条件分支中使用 useInput

❌ 错误：
```lua
if step == 3 then
    tui.useInput(...)  -- Hook count mismatch!
end
```

✅ 正确：
```lua
tui.useInput(function(_, key)
    if step == 3 then
        -- 处理输入
    end
end)
```

### 3. 忘记 Tab 导航

❌ 错误：
```lua
h:type("username")
h:type("password")  -- 输入到同一个字段了！
```

✅ 正确：
```lua
h:type("username")
h:press("tab")      -- 切换焦点
h:type("password")
```
