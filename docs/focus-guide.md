# 焦点系统使用指南

## 概述

tui.lua 的焦点系统采用**显式导航**设计：
- 焦点状态独立于组件的 React 状态（`useState`）
- 按 `Tab`/`Shift+Tab` 在可聚焦元素间切换
- `Enter` 触发当前聚焦元素的 `onSubmit`

## 基本用法

### 使用 useFocus

```lua
local function MyInput(props)
    local focus = tui.useFocus {
        autoFocus = true,              -- 自动获得焦点
        on_input = function(input, key)
            if key.name == "enter" then
                props.onSubmit()
            elseif key.name == "char" then
                props.onChange(props.value .. input)
            end
        end
    }

    return tui.Text {
        focus.isFocused and "> " or "  ",  -- 焦点指示器
        props.value
    }
end
```

### 标准组件（TextInput）

```lua
tui.TextInput {
    value = text,
    onChange = setText,
    onSubmit = function() print("提交:", text) end,
    -- autoFocus = true  -- 默认自动聚焦
}
```

## 焦点导航

### 键盘控制

| 按键 | 行为 |
|------|------|
| `Tab` | 下一个可聚焦元素 |
| `Shift+Tab` | 上一个可聚焦元素 |
| `Enter` | 触发 `onSubmit` |
| `Esc` | 取消当前操作 |

### 测试中的焦点控制

```lua
local h = testing.render(App)

-- Tab 切换到下一个输入框
h:press("tab")

-- Shift+Tab 返回上一个
h:press("shift+tab")

-- 直接聚焦指定元素（需设置 focusId）
h:focus("myInputId")
```

## 重要概念：状态 ≠ 焦点

### ❌ 错误理解

```lua
local focused, setFocused = tui.useState("username")

-- 这只是更新状态变量，不会切换实际焦点！
setFocused("password")  
```

### ✅ 正确做法

```lua
-- 方法1：按 Tab 键导航
h:press("tab")

-- 方法2：使用 onSubmit 进入下一步
tui.TextInput {
    onSubmit = function()
        goToNextStep()  -- 可以更新状态或切换焦点
    end
}
```

## 多步骤表单示例

```lua
local function WizardForm()
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
            tui.TextInput {
                value = data.name or "",
                onChange = function(v) 
                    setData({...data, name = v}) 
                end,
                onSubmit = nextStep,  -- Enter 进入下一步
                placeholder = "Name"
            },
            tui.Text "按 Enter 继续"
        }
    elseif step == 2 then
        return tui.Box {
            tui.TextInput {
                value = data.email or "",
                onChange = function(v) 
                    setData({...data, email = v}) 
                end,
                onSubmit = nextStep,
                placeholder = "Email"
            },
            tui.Text "按 Enter 继续"
        }
    else
        return tui.Box {
            tui.Text("确认: " .. data.name),
            tui.Text("邮箱: " .. data.email),
            tui.Text "按 Enter 提交"
        }
    end
end
```

## 常见陷阱

### 1. 条件分支中的 Hooks

❌ **错误**：条件分支中调用 `useInput`

```lua
if step == 3 then
    tui.useInput(...)  -- Hook count mismatch!
end
```

✅ **正确**：顶层调用，回调内判断条件

```lua
tui.useInput(function(_, key)
    if step == 3 then
        -- 处理输入
    end
end)
```

### 2. 焦点与样式的混淆

❌ **错误**：用状态变量控制焦点

```lua
local focused, setFocused = tui.useState("input1")
-- 更新状态不会自动切换焦点！
```

✅ **正确**：样式和焦点分别处理

```lua
-- 样式用状态
local borderStyle = isActive and "single" or nil

-- 焦点用 Tab/Enter 控制
```

### 3. 忘记启用焦点系统

```lua
-- 在应用入口处启用焦点
focus.enable()
```

## 测试最佳实践

```lua
function suite:test_form_flow()
    local h = testing.render(App)

    -- 1. 第一个输入框自动聚焦，直接输入
    h:type("用户名")

    -- 2. Tab 切换到密码框
    h:press("tab")
    h:type("密码")

    -- 3. Enter 提交
    h:press("return")

    -- 验证结果
    lt.assertNotEquals(submitted, nil)
end
```

## API 参考

### useFocus 选项

```lua
tui.useFocus {
    id = "uniqueId",           -- 可选，焦点标识
    autoFocus = true,          -- 默认 true
    isActive = true,           -- 是否可聚焦
    on_change = function(isFocused) end,  -- 焦点变化回调
    on_input = function(input, key) end,  -- 输入处理回调
}
```

### 焦点管理

使用 `useFocusManager` hook：

```lua
local focusMgr = tui.useFocusManager()

focusMgr.focus("inputId")       -- 聚焦指定元素
focusMgr.focusNext()            -- 下一个
focusMgr.focusPrevious()        -- 上一个
```

## 总结

1. **焦点是独立的系统**，与 React 状态（`useState`）分离
2. 使用 `Tab`/`Enter` 导航和提交，而非状态变量
3. 所有 Hooks 必须在顶层调用，不能在条件分支中
4. 用 `onSubmit` 实现步骤间的自然流转
