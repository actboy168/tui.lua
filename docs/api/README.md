# API 参考

## 全局 API

### tui.render(root)

启动应用主循环。

```lua
tui.render(App)
tui.render(tui.Box { ... })
```

### tui.component(fn, props?)

创建组件工厂。

```lua
local Button = tui.component(function(props)
    return tui.Box { ... }
end)

-- 使用
Button { label = "Click" }
```

### tui.setDevMode(enabled)

启用开发模式（检查 hook 顺序、缺失 key 等）。

```lua
tui.setDevMode(true)
```

### tui.createContext(defaultValue)

创建上下文。

```lua
local ThemeContext = tui.createContext("light")
```

## 组件

### Box

布局容器。

```lua
tui.Box {
    -- 尺寸
    width = number | string,      -- "50%" 或 40
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
    marginTop = number,
    marginBottom = number,
    marginLeft = number,
    marginRight = number,

    -- 边框
    borderStyle = "single" | "double" | "round" | "bold",
    borderColor = string,
    borderTop = boolean,
    borderBottom = boolean,
    borderLeft = boolean,
    borderRight = boolean,

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

错误边界。

```lua
tui.ErrorBoundary {
    fallback = function(error) -> element,
    children
}
```

## 扩展组件

扩展组件位于 `tui.extra`，需要显式加载：

```lua
local extra = require "tui.extra"
extra.TextInput { ... }
```

### TextInput

文本输入组件。

```lua
local extra = require "tui.extra"
extra.TextInput {
    value = string,
    onChange = function(value),
    onSubmit = function(),
    placeholder = string,
    width = number,
    mask = string,           -- 密码掩码字符
    autoFocus = boolean,     -- 默认 true
    focusId = string,        -- 焦点标识
    focus = boolean,         -- false 禁用焦点
}
```

### Textarea

多行文本编辑器。

```lua
local extra = require "tui.extra"
extra.Textarea {
    value = string,
    onChange = function(value),
    onSubmit = function(),
    placeholder = string,
    width = number,
    minHeight = number,
    maxHeight = number,
}
```

### Select

选项列表。

```lua
local extra = require "tui.extra"
extra.Select {
    items = { { label, value }, ... },
    onSelect = function(item),
    onHighlight = function(item),
    limit = number,          -- 显示行数
    indicator = string,      -- 选中指示器，默认 "❯"
}
```

### Spinner

加载动画。

```lua
local extra = require "tui.extra"
extra.Spinner {
    type = "dots" | "line" | "pointer" | "simple",
    label = string,
    frames = { string },     -- 自定义帧
    interval = number,       -- 帧间隔（毫秒）
}
```

### ProgressBar

进度条。

```lua
local extra = require "tui.extra"
extra.ProgressBar {
    value = number,          -- 0.0 ~ 1.0
    width = number,
    color = string,
    backgroundColor = string,
    char = string,           -- 填充字符
    left = string,           -- 左边界
    right = string,          -- 右边界
}
```

### Static

静态列表。

```lua
local extra = require "tui.extra"
extra.Static {
    items = { ... },
    render = function(item, index) -> element,
}
```

### Newline / Spacer

换行和弹性空间。

```lua
local extra = require "tui.extra"
extra.Newline { count = 1 }  -- 换行
extra.Spacer {}              -- 弹性空间
```

## Hooks

### useState

```lua
local state, setState = tui.useState(initialValue)
local state, setState = tui.useState(function() return initialValue end)

-- 函数式更新
setState(function(prev) return newValue end)
```

### useEffect

```lua
tui.useEffect(effect: function(): (cleanup?: function))
tui.useEffect(effect: function(): (cleanup?: function), deps: table?)
```

### useMemo

```lua
local value = tui.useMemo(fn: function(): any, deps: table)
```

### useCallback

```lua
local callback = tui.useCallback(fn: function, deps: table)
```

### useRef

```lua
local ref = tui.useRef(initialValue)
-- ref.current 可读可写
```

### useReducer

```lua
local state, dispatch = tui.useReducer(reducer: function, initialState: any)
local state, dispatch = tui.useReducer(reducer: function, initialArg: any, init: function)
```

### useContext

```lua
local value = tui.useContext(Context)
```

### useInterval

```lua
tui.useInterval(callback: function, delayMs: number)
```

### useTimeout

```lua
tui.useTimeout(callback: function, delayMs: number)
```

### useInput

```lua
tui.useInput(handler: function(input: string, key: KeyEvent))

-- KeyEvent 结构：
-- {
--     name = string,      -- "char", "enter", "up", etc.
--     ctrl = boolean,
--     shift = boolean,
--     alt = boolean,
--     input = string,     -- 原始输入字符
-- }
```

### useWindowSize

```lua
local size = tui.useWindowSize()
-- returns { width = number, height = number }
```

### useFocus

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

### useFocusManager

```lua
local manager = tui.useFocusManager()
-- manager.focusNext()
-- manager.focusPrevious()
-- manager.focus(id: string)
```

### useApp

```lua
local app = tui.useApp()
app:exit()  -- 退出应用
```

### useAnimation

```lua
tui.useAnimation(render: function(t: number): element, options: {
    duration = number,
    easing = "linear" | "easeIn" | "easeOut" | "easeInOut",
    onComplete = function?,
})
```

### useErrorBoundary

```lua
local boundary = tui.useErrorBoundary()
-- boundary.caught_error: string?
-- boundary.reset(): function
-- boundary.boundary: table?
```

## 工具函数

### 定时器

```lua
local id = tui.setInterval(fn, ms)
local id = tui.setTimeout(fn, ms)
tui.clearTimer(id)
```

### 文本处理

```lua
local width = tui.displayWidth(str)           -- 计算显示宽度
local wrapped = tui.wrap(str, width)          -- 自动换行
local wrapped = tui.wrapHard(str, width)      -- 强制换行
local truncated = tui.truncate(str, width)    -- 截断（末尾...）
local truncated = tui.truncateStart(str, width)   -- 截断（开头...）
local truncated = tui.truncateMiddle(str, width)  -- 截断（中间...）
```

### 布局

```lua
local size = tui.intrinsicSize(element)       -- 计算元素固有尺寸
```

## 焦点管理

使用 `useFocusManager` hook：

```lua
local focusMgr = tui.useFocusManager()

focusMgr.enableFocus()      -- 启用焦点系统
focusMgr.disableFocus()     -- 禁用焦点系统

focusMgr.focus(id: string)           -- 聚焦指定元素
focusMgr.focusNext()                 -- 下一个可聚焦元素
focusMgr.focusPrevious()             -- 上一个可聚焦元素
```

使用 `useFocus` hook 创建可聚焦组件：

```lua
local focus = tui.useFocus {
    id = "myInput",
    autoFocus = true,
    on_input = function(input, key) ... end
}

-- focus.isFocused  - 是否有焦点
-- focus.focus()    - 主动获取焦点
```

## 测试工具

```lua
local testing = require "tui.testing"

-- 渲染
local h = testing.render(Component, { cols = 80, rows = 24 })

-- 操作
h:type(string)              -- 输入文本
h:press(key)                -- 按键（"enter", "tab", "up", 等）
h:advance(ms)               -- 推进时间
h:resize(cols, rows)        -- 调整窗口大小
h:focusNext()               -- 下一个焦点
h:focusPrev()               -- 上一个焦点
h:focus(id)                 -- 聚焦指定元素

-- 断言
h:expect_output(pattern)
h:expect_renders(count)
h:match_snapshot(name)

-- 清理
h:unmount()
```

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
