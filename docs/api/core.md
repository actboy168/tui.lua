# 核心 API

对应源码 `tui/init.lua`，是 tui.lua 的基础运行时。所有核心组件、Hooks、工具函数均由此模块导出，无需额外加载。

```lua
local tui = require "tui"
```

---

## 全局 API

### tui.render(root)

启动应用主循环，阻塞直到调用 `useApp():exit()` 或收到 Ctrl+C/Ctrl+D。

```lua
tui.render(App)               -- 传入函数组件
tui.render(tui.Box { ... })   -- 传入宿主元素
```

### tui.component(fn, props?)

创建组件工厂或直接生成元素。

```lua
-- 工厂模式
local Button = tui.component(function(props)
    return tui.Box { tui.Text { props.label } }
end)
Button { label = "Click" }

-- 直接模式
tui.component(fn, { label = "Click" })
```

### tui.createContext(defaultValue)

创建上下文，配合 `useContext` 使用。

```lua
local ThemeContext = tui.createContext("light")
```

### tui.setDevMode(enabled)

启用开发模式（检查 hook 顺序、缺失 key、setState-during-render 等警告）。默认关闭，测试套件自动启用。

```lua
tui.setDevMode(true)
```

### tui.configureScheduler(opts)

替换调度器后端（在 `tui.render` 之前调用），用于集成 ltask / libuv 等事件循环。

```lua
tui.configureScheduler {
    now   = function() return platform.monotonic() end,
    sleep = function(ms) platform.sleep(ms) end,
}
```

---

## 组件

### Box

布局容器，支持 Flexbox。

```lua
tui.Box {
    -- 尺寸
    width = number | string,      -- 40 或 "50%"
    height = number | string,
    flex = number,                -- 弹性系数

    -- 布局
    flexDirection = "row" | "column",
    justifyContent = "flex-start" | "center" | "flex-end" | "space-between",
    alignItems = "flex-start" | "center" | "flex-end" | "stretch",
    flexWrap = "wrap" | "nowrap",
    gap = number,

    -- 间距
    padding = number | { top?, bottom?, left?, right? },
    margin = number | { top?, bottom?, left?, right? },
    marginTop = number, marginBottom = number,
    marginLeft = number, marginRight = number,

    -- 边框
    borderStyle = "single" | "double" | "round" | "bold",
    borderColor = string,
    borderTop = boolean, borderBottom = boolean,
    borderLeft = boolean, borderRight = boolean,

    -- 子元素
    children
}
```

### Text

文本显示。

```lua
tui.Text {
    -- 样式
    color = string | number,
    backgroundColor = string | number,
    bold = boolean,
    italic = boolean,
    underline = boolean,
    strikethrough = boolean,
    inverse = boolean,
    dim = boolean,

    -- 布局
    wrap = "wrap" | "truncate" | "truncate-start" | "truncate-middle" | "nowrap",
    width = number,
    height = number,

    -- 内容
    "文本内容"
}
```

### ErrorBoundary

错误边界，捕获子树渲染错误。

```lua
tui.ErrorBoundary {
    fallback = function(error) -> element,
    children
}
```

---

## Hooks

### 状态管理

#### useState

```lua
local state, setState = tui.useState(initialValue)
local state, setState = tui.useState(function() return initialValue end)  -- 延迟初始化

-- 函数式更新
setState(function(prev) return newValue end)
```

#### useReducer

```lua
local state, dispatch = tui.useReducer(reducer: function, initialState: any)
local state, dispatch = tui.useReducer(reducer: function, initialArg: any, init: function)
```

### 副作用

#### useEffect

```lua
tui.useEffect(effect: function(): (cleanup?: function))
tui.useEffect(effect: function(): (cleanup?: function), deps: table?)
```

### 记忆化

#### useMemo

```lua
local value = tui.useMemo(fn: function(): any, deps: table)
```

#### useCallback

```lua
local callback = tui.useCallback(fn: function, deps: table)
```

### 引用

#### useRef

```lua
local ref = tui.useRef(initialValue)
-- ref.current 可读可写
```

#### useLatestRef

```lua
local ref = tui.useLatestRef(value)
-- ref.current 始终指向最新值（不会触发重渲染）
```

### 上下文

#### useContext

```lua
local value = tui.useContext(Context)
```

### 定时器 Hooks

#### useInterval

```lua
tui.useInterval(callback: function, delayMs: number)
```

#### useTimeout

```lua
tui.useTimeout(callback: function, delayMs: number)
```

### 输入

#### useInput

```lua
tui.useInput(handler: function(input: string, key: KeyEvent))

-- KeyEvent 结构：
-- {
--     name = string,      -- "char", "enter", "up", etc.
--     ctrl = boolean,
--     shift = boolean,
--     alt = boolean,
--     meta = boolean,
--     input = string,     -- 原始输入字符
-- }
```

#### usePaste

```lua
tui.usePaste(handler: function(text: string))
```

### 焦点

#### useFocus

```lua
local focus = tui.useFocus {
    id = string?,
    autoFocus = boolean?,
    isActive = boolean?,
    on_change = function(isFocused: boolean)?,
    on_input = function(input: string, key: KeyEvent)?,
}

-- focus.isFocused: boolean
-- focus.focus(): function()  -- 主动获取焦点
```

#### useFocusManager

```lua
local manager = tui.useFocusManager()
-- manager.focusNext()
-- manager.focusPrevious()
-- manager.focus(id: string)
```

> 焦点系统详解参见 [焦点系统指南](../guide/05-focus.md)。

### 窗口与应用

#### useWindowSize

```lua
local size = tui.useWindowSize()
-- returns { width = number, height = number }
```

#### useApp

```lua
local app = tui.useApp()
app:exit()  -- 退出应用
```

#### useStdout

```lua
local stdout = tui.useStdout()
-- stdout.write(s)  -- 写入标准输出
```

#### useStderr

```lua
local stderr = tui.useStderr()
-- stderr.write(s)  -- 写入标准错误
```

### 测量

#### useMeasure

```lua
local rect = tui.useMeasure()
-- 返回元素布局矩形 { x, y, width, height }
-- 组件首次渲染后可用，布局变化时自动更新
```

### 动画

#### useAnimation

```lua
tui.useAnimation(render: function(t: number): element, options: {
    duration = number,
    easing = "linear" | "easeIn" | "easeOut" | "easeInOut",
    onComplete = function?,
})
```

### 光标

#### useDeclaredCursor

```lua
tui.useDeclaredCursor(col, row)
-- 声明光标位置（在渲染函数中调用）
```

### 错误边界

#### useErrorBoundary

```lua
local boundary = tui.useErrorBoundary()
-- boundary.caught_error: string?
-- boundary.reset(): function
-- boundary.boundary: table?
```

---

## 工具函数

### 定时器

```lua
local id = tui.setInterval(fn, ms)
local id = tui.setTimeout(fn, ms)
tui.clearTimer(id)
```

### 文本处理

```lua
local width = tui.displayWidth(str)           -- 计算显示宽度（考虑 CJK 等宽字符）
local wrapped = tui.wrap(str, width)          -- 自动换行
local wrapped = tui.wrapHard(str, width)      -- 强制换行
local truncated = tui.truncate(str, width)    -- 截断（末尾...）
local truncated = tui.truncateStart(str, width)   -- 截断（开头...）
local truncated = tui.truncateMiddle(str, width)  -- 截断（中间...）
for char, byte_pos in tui.iterChars(str) do ... end  -- 逐字符迭代（处理 UTF-8）
```

### 布局

```lua
local size = tui.intrinsicSize(element)       -- 计算元素固有尺寸
```

---

## 类型定义

### 颜色值

```lua
type Color = string | number

-- 字符串：基本色名
-- "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"
-- "brightRed", "brightGreen", ...
-- "#ff8800"  -- RGB

-- 数字：256色
-- 0-255
```

### 元素

```lua
type Element = {
    kind = "box" | "text" | "component" | ...,
    props = table,
    key = any?,  -- 用于 reconciler
}
```

### KeyEvent

```lua
type KeyEvent = {
    name = string,      -- "char", "enter", "return", "escape", "tab",
                        -- "up", "down", "left", "right",
                        -- "home", "end", "pageup", "pagedown",
                        -- "f1"-"f12", "backspace", "delete",
                        -- "composing", "composing_confirm"
    input = string,     -- 原始输入字符
    raw = string,       -- 原始字节序列
    ctrl = boolean,
    shift = boolean,
    alt = boolean,
    meta = boolean,
}
```
