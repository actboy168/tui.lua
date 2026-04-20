# 焦点系统指南

tui.lua 的焦点系统用于管理可交互元素的键盘导航。API 签名参见 [核心 API - 焦点](../api/core.md#焦点)。

## 核心概念

**重要：焦点系统与 React 状态是独立的**

- `useState` 管理的是**数据状态**（如边框样式、颜色）
- `useFocus` 管理的是**焦点状态**（哪个元素接收键盘输入）
- 改变状态变量**不会**自动切换焦点

## 基本用法

### TextInput 自动焦点

```lua
extra.TextInput {
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

### 焦点顺序

焦点顺序由组件注册顺序决定：

```lua
local function Form()
    return tui.Box {
        extra.TextInput { key = "input1", autoFocus = true },  -- 第一个
        extra.TextInput { key = "input2" },                     -- Tab 到这里
        extra.TextInput { key = "input3" }                      -- 再 Tab 到这里
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

> `useFocus` 选项和返回值的完整定义参见 [核心 API](../api/core.md#usefocus)。

## 手动控制焦点

```lua
local focusMgr = tui.useFocusManager()

focusMgr.focus("myInputId")   -- 聚焦指定元素
focusMgr.focusNext()           -- 下一个
focusMgr.focusPrevious()       -- 上一个
```

## 禁用焦点元素

```lua
extra.TextInput {
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
        extra.TextInput {
            value = username,
            onChange = setUsername,
            onSubmit = function() end,  -- Tab 移动到下一个
            width = 30
        },

        tui.Text { "密码" },
        extra.TextInput {
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
            extra.TextInput {
                value = data.name or "",
                onChange = function(v) setData({ ...data, name = v }) end,
                onSubmit = nextStep,
                placeholder = "姓名"
            }
        }
    elseif step == 2 then
        return tui.Box {
            tui.Text { "步骤 2/3" },
            extra.TextInput {
                value = data.email or "",
                onChange = function(v) setData({ ...data, email = v }) end,
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

## 焦点与样式的区别

```lua
-- ❌ 混淆：状态变量只影响显示，不影响焦点
local focusedField, setFocusedField = tui.useState("username")
-- setFocusedField("password") 只更新了状态，没切换实际焦点！

-- ✅ 正确：焦点系统自动控制，无需手动管理
extra.TextInput {},   -- 按 Tab 自动切换
extra.TextInput {}
```

## 常见错误

### 1. 用状态变量切换焦点

❌ 错误：
```lua
setFocused("password")  -- 只更新了状态，没切换实际焦点
```

✅ 正确：使用 `onSubmit` 实现步骤流转，或按 Tab 导航。

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

### 3. 测试中忘记 Tab 导航

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

> 测试 harness 完整 API 参见 [测试套件](../api/testing.md)。
