# Hooks 指南

Hooks 是 tui.lua 中管理状态和副作用的核心机制。

## 规则

1. **只在顶层调用** - 不要在循环、条件或嵌套函数中调用
2. **只在函数组件中调用** - 不要在普通函数中调用

## useState - 状态管理

```lua
local function Counter()
    local count, setCount = tui.useState(0)

    tui.useInput(function()
        setCount(count + 1)
    end)

    return tui.Text { "Count: " .. count }
end
```

### 函数式更新

当新状态依赖旧状态时：

```lua
setCount(function(prev)
    return prev + 1
end)
```

### 延迟初始化

```lua
-- 避免每次渲染都创建初始值
local state, setState = tui.useState(function()
    return expensiveComputation()
end)
```

## useEffect - 副作用

### 每次渲染后执行

```lua
tui.useEffect(function()
    print("组件渲染完成")
end)
```

### 依赖特定状态

```lua
tui.useEffect(function()
    print("count 变化为:", count)
end, { count })
```

### 仅挂载/卸载时

```lua
tui.useEffect(function()
    print("组件挂载")

    -- 返回清理函数
    return function()
        print("组件卸载")
    end
end, {})  -- 空依赖数组
```

### 实际示例

```lua
local function DataFetcher()
    local data, setData = tui.useState(nil)
    local loading, setLoading = tui.useState(false)

    tui.useEffect(function()
        setLoading(true)

        -- 模拟异步请求
        local timer = tui.setTimeout(function()
            setData({ name = "John" })
            setLoading(false)
        end, 1000)

        -- 清理函数
        return function()
            tui.clearTimer(timer)
        end
    end, {})  -- 仅在挂载时执行

    if loading then
        return tui.Spinner { label = "加载中..." }
    end

    return tui.Text { data and data.name or "无数据" }
end
```

## useMemo - 记忆化计算

缓存昂贵计算结果：

```lua
local function ExpensiveList(props)
    local sorted = tui.useMemo(function()
        local result = {}
        for _, item in ipairs(props.items) do
            table.insert(result, item)
        end
        table.sort(result, function(a, b) return a.value > b.value end)
        return result
    end, { props.items })  -- 仅在 items 变化时重新计算

    return tui.Static {
        items = sorted,
        render = function(item)
            return tui.Text { item.name }
        end
    }
end
```

## useCallback - 记忆化回调

避免子组件不必要的重渲染：

```lua
local function Parent()
    local count, setCount = tui.useState(0)

    -- 每次渲染都创建新函数
    local handleClick_bad = function()
        setCount(count + 1)
    end

    -- 仅在 count 变化时创建新函数
    local handleClick_good = tui.useCallback(function()
        setCount(count + 1)
    end, { count })

    return ChildComponent {
        onClick = handleClick_good
    }
end
```

## useRef - 可变引用

```lua
local function Timer()
    local intervalRef = tui.useRef(nil)
    local count, setCount = tui.useState(0)

    local start = function()
        intervalRef.current = tui.setInterval(function()
            setCount(function(c) return c + 1 end)
        end, 1000)
    end

    local stop = function()
        if intervalRef.current then
            tui.clearTimer(intervalRef.current)
            intervalRef.current = nil
        end
    end

    tui.useEffect(function()
        return stop  -- 卸载时清理
    end, {})

    return tui.Text { "Count: " .. count }
end
```

## useReducer - 复杂状态逻辑

```lua
local function reducer(state, action)
    if action.type == "increment" then
        return { count = state.count + 1 }
    elseif action.type == "decrement" then
        return { count = state.count - 1 }
    elseif action.type == "reset" then
        return { count = 0 }
    end
    return state
end

local function Counter()
    local state, dispatch = tui.useReducer(reducer, { count = 0 })

    tui.useInput(function(_, key)
        if key.name == "up" then
            dispatch { type = "increment" }
        elseif key.name == "down" then
            dispatch { type = "decrement" }
        elseif key.name == "r" then
            dispatch { type = "reset" }
        end
    end)

    return tui.Text { "Count: " .. state.count }
end
```

## useContext - 上下文

### 创建上下文

```lua
local ThemeContext = tui.createContext("light")
```

### 提供值

```lua
local function App()
    local theme = tui.useState("dark")

    return ThemeContext.Provider {
        value = theme,
        children = {
            ChildComponent {}
        }
    }
end
```

### 消费值

```lua
local function ChildComponent()
    local theme = tui.useContext(ThemeContext)

    return tui.Text {
        color = theme == "dark" and "white" or "black",
        "当前主题: " .. theme
    }
end
```

## useInterval / useTimeout - 定时器

```lua
local function Clock()
    local time, setTime = tui.useState(os.date("%H:%M:%S"))

    tui.useInterval(function()
        setTime(os.date("%H:%M:%S"))
    end, 1000)  -- 每秒更新

    return tui.Text { time }
end
```

```lua
local function Notification()
    local visible, setVisible = tui.useState(true)

    tui.useTimeout(function()
        setVisible(false)
    end, 3000)  -- 3秒后消失

    if not visible then return nil end

    return tui.Box {
        borderStyle = "single",
        tui.Text { "3秒后消失的消息" }
    }
end
```

## useInput - 输入处理

```lua
local function InputHandler()
    tui.useInput(function(input, key)
        -- key.name 可以是：
        -- "char", "enter", "return", "escape", "tab"
        -- "up", "down", "left", "right"
        -- "home", "end", "pageup", "pagedown"
        -- "f1"-"f12", 等等

        if key.name == "char" then
            print("输入字符:", input)
        elseif key.name == "enter" then
            print("按下回车")
        elseif key.ctrl then
            print("Ctrl+", key.name)
        end
    end)

    return tui.Text { "按任意键..." }
end
```

## useWindowSize - 窗口大小

```lua
local function ResponsiveLayout()
    local size = tui.useWindowSize()

    return tui.Box {
        tui.Text { ("宽度: %d, 高度: %d"):format(size.width, size.height) }
    }
end
```

## useApp - 应用控制

```lua
local function ExitButton()
    local app = tui.useApp()

    tui.useInput(function(_, key)
        if key.name == "q" then
            app:exit()  -- 退出应用
        end
    end)

    return tui.Text { "按 q 退出" }
end
```

## 自定义 Hook

```lua
-- 创建自定义 Hook
local function useCounter(initial)
    local count, setCount = tui.useState(initial or 0)

    local increment = tui.useCallback(function()
        setCount(function(c) return c + 1 end)
    end, {})

    local decrement = tui.useCallback(function()
        setCount(function(c) return c - 1 end)
    end, {})

    return count, increment, decrement
end

-- 使用
local function Counter()
    local count, inc, dec = useCounter(0)

    tui.useInput(function(_, key)
        if key.name == "up" then inc() end
        if key.name == "down" then dec() end
    end)

    return tui.Text { "Count: " .. count }
end
```

## 常见错误

### 1. 条件调用 Hook

❌ 错误：
```lua
if props.enabled then
    local state = tui.useState(0)  -- Hook count mismatch!
end
```

✅ 正确：
```lua
local state = tui.useState(props.enabled and 0 or nil)
```

### 2. 循环调用 Hook

❌ 错误：
```lua
for i = 1, 3 do
    local state = tui.useState(0)  -- Hook count mismatch!
end
```

✅ 正确：
```lua
local states = tui.useState({ 0, 0, 0 })
```

### 3. 过时的闭包

❌ 错误：
```lua
tui.useEffect(function()
    local timer = tui.setInterval(function()
        setCount(count + 1)  -- count 始终是初始值
    end, 1000)
end, {})
```

✅ 正确：
```lua
tui.useEffect(function()
    local timer = tui.setInterval(function()
        setCount(function(c) return c + 1 end)  -- 使用函数式更新
    end, 1000)
end, {})
```
