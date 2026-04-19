# tui.lua

一个用于 Lua 的 React 风格终端 UI 框架。

## 安装

```bash
git clone https://github.com/yourusername/tui.lua.git
cd tui.lua
```

## 编译

使用 luamake 编译项目：

```bash
luamake
```

这将编译 C 扩展模块并生成必要的构建产物。

## 运行脚本

使用 `luamake lua` 运行 tui.lua 脚本：

```bash
luamake lua examples/counter.lua
```

或者创建自己的脚本：

```lua
-- myapp.lua
local tui = require "tui"

local function App()
    local count, setCount = tui.useState(0)

    tui.useInput(function(_, key)
        if key.name == "q" then
            tui.useApp():exit()
        elseif key.name == "up" then
            setCount(count + 1)
        end
    end)

    return tui.Box {
        flexDirection = "column",
        tui.Text { "计数器: " .. count },
        tui.Text { "按 ↑ 增加, q 退出" }
    }
end

tui.render(App)
```

运行：

```bash
luamake lua myapp.lua
```

## 快速开始示例

查看 [examples/README.md](examples/README.md) 了解所有示例。

## 核心概念

### 组件

tui.lua 使用函数组件，类似 React：

```lua
local function Greeting(props)
    return tui.Text { "Hello, " .. props.name .. "!" }
end

-- 使用
Greeting { name = "World" }
```

### 内置组件

| 组件 | 用途 | 示例 |
|------|------|------|
| `Box` | 布局容器 | `tui.Box { flexDirection = "row", children }` |
| `Text` | 文本显示 | `tui.Text { color = "red", "Hello" }` |
| `TextInput` | 文本输入 | `tui.TextInput { value = text, onChange = fn }` |
| `Select` | 选项列表 | `tui.Select { items = {...}, onSelect = fn }` |
| `Spinner` | 加载动画 | `tui.Spinner { type = "dots" }` |
| `ProgressBar` | 进度条 | `tui.ProgressBar { value = 0.5 }` |
| `Static` | 静态列表 | `tui.Static { items = {...}, render = fn }` |
| `ErrorBoundary` | 错误捕获 | `tui.ErrorBoundary { fallback = ..., children }` |

### Hooks

#### useState

```lua
local state, setState = tui.useState(initialValue)

-- 函数式更新
setState(function(prev) return prev + 1 end)
```

#### useEffect

```lua
-- 每次渲染后执行
tui.useEffect(function()
    print("渲染完成")
end)

-- 依赖变化时执行
tui.useEffect(function()
    print("count 变化为", count)
end, { count })

-- 仅挂载/卸载时执行
tui.useEffect(function()
    print("挂载")
    return function() print("卸载") end
end, {})
```

#### useInput

处理键盘输入：

```lua
tui.useInput(function(input, key)
    if key.name == "enter" then
        print("按下回车")
    elseif key.name == "char" then
        print("输入字符:", input)
    end
end)
```

支持的按键名称：
- `char`, `enter`, `return`, `escape`, `tab`, `backtab`
- `up`, `down`, `left`, `right`
- `home`, `end`, `insert`, `delete`
- `pageup`, `pagedown`
- `f1` - `f12`
- `backspace`

#### useInterval / useTimeout

```lua
-- 定时器
tui.useInterval(function()
    print("每秒执行")
end, 1000)

-- 延迟执行
tui.useTimeout(function()
    print("1秒后执行")
end, 1000)
```

#### useWindowSize

```lua
local size = tui.useWindowSize()
print("终端大小:", size.width, size.height)
```

#### useFocus

创建可聚焦元素：

```lua
local focus = tui.useFocus {
    autoFocus = true,
    on_input = function(input, key)
        -- 处理输入
    end
}

-- 检查焦点状态
if focus.isFocused then
    -- 当前元素有焦点
end
```

#### useContext

```lua
-- 创建上下文
local ThemeContext = tui.createContext("light")

-- 提供值
ThemeContext.Provider {
    value = "dark",
    children = { ... }
}

-- 消费值
local theme = tui.useContext(ThemeContext)
```

## 布局系统

基于 CSS Flexbox：

```lua
tui.Box {
    flexDirection = "row",      -- row | column
    justifyContent = "center",  -- flex-start | center | flex-end | space-between
    alignItems = "center",      -- flex-start | center | flex-end | stretch
    flexWrap = "wrap",          -- wrap | nowrap
    gap = 1,                    -- 子元素间距

    width = 40,
    height = 10,
    padding = { top = 1, bottom = 1, left = 2, right = 2 },

    borderStyle = "single",     -- single | double | round | bold
    borderColor = "blue",

    -- 子元素
    tui.Text { "内容" }
}
```

### 尺寸单位

```lua
-- 固定尺寸
width = 40, height = 10

-- 百分比
width = "50%"

-- 自动
flex = 1  -- 占据剩余空间
```

## 文本样式

### 颜色

```lua
tui.Text {
    color = "red",
    backgroundColor = "blue",
    "彩色文本"
}
```

支持的颜色：
- 基本色：`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`
- 亮色：`brightRed`, `brightGreen`, 等
- 256色：`color = 208`
- RGB：`color = "#ff8800"`

### 文本属性

```lua
tui.Text {
    bold = true,
    italic = true,
    underline = true,
    strikethrough = true,
    inverse = true,      -- 反色
    dim = true,          -- 暗淡
}
```

### 文本截断

```lua
-- 长文本处理
tui.Text {
    wrap = "wrap",       -- wrap | truncate | truncate-start | truncate-middle
    "这是一段很长的文本..."
}
```

## 焦点系统

### 自动焦点

```lua
tui.TextInput {
    autoFocus = true,    -- 自动获得焦点
    value = text,
    onChange = setText,
    onSubmit = submit,
}
```

### 键盘导航

| 按键 | 行为 |
|------|------|
| `Tab` | 下一个可聚焦元素 |
| `Shift+Tab` | 上一个可聚焦元素 |
| `Enter` | 触发 `onSubmit` |

### 手动控制焦点

```lua
local focus = require "tui.focus"

focus.focus("inputId")   -- 聚焦指定元素
focus.focus_next()       -- 下一个
focus.focus_prev()       -- 上一个
```

## 表单示例

```lua
local function LoginForm()
    local username, setUsername = tui.useState("")
    local password, setPassword = tui.useState("")

    local function submit()
        print("登录:", username, password)
    end

    return tui.Box {
        flexDirection = "column",
        width = 40,
        tui.Text { "用户名" },
        tui.TextInput {
            value = username,
            onChange = setUsername,
            onSubmit = function() end,  -- Tab 会自动移动到下一个
            width = 30,
        },
        tui.Newline {},
        tui.Text { "密码" },
        tui.TextInput {
            value = password,
            onChange = setPassword,
            onSubmit = submit,  -- Enter 提交
            mask = "*",         -- 密码掩码
            width = 30,
        },
    }
end
```

## 列表选择

```lua
local function Menu()
    local items = {
        { label = "新建", value = "new" },
        { label = "打开", value = "open" },
        { label = "保存", value = "save" },
        { label = "退出", value = "quit" },
    }

    return tui.Select {
        items = items,
        onSelect = function(item)
            print("选中:", item.label)
        end,
        onHighlight = function(item)
            print("高亮:", item.label)
        end,
    }
end
```

## 错误处理

```lua
local function SafeComponent()
    local boundary = tui.useErrorBoundary()

    if boundary.caught_error then
        return tui.Text {
            color = "red",
            "出错了: " .. boundary.caught_error
        }
    end

    return tui.Box {
        tui.Text { "正常内容" }
    }
end

-- 或使用 ErrorBoundary 包裹子树
return tui.ErrorBoundary {
    fallback = function(error)
        return tui.Text { "错误: " .. error }
    end,
    MyComponent {}
}
```

## 动画

```lua
tui.useAnimation(function(t)
    -- t 从 0 到 1
    local x = math.floor(t * 10)
    return tui.Box {
        marginLeft = x,
        tui.Text { "移动的文本" }
    }
end, {
    duration = 1000,
    easing = "easeInOut",
})
```

## 测试

```lua
local testing = require "tui.testing"
local lt = require "ltest"

local suite = lt.test "my_app"

function suite:test_counter()
    local App = function()
        local count, setCount = tui.useState(0)

        tui.useInput(function()
            setCount(count + 1)
        end)

        return tui.Text { tostring(count) }
    end

    local h = testing.render(App, { cols = 40, rows = 10 })

    -- 模拟按键
    h:press("space")
    h:press("space")

    -- 验证输出
    h:expect_output("2")

    h:unmount()
end
```

## API 参考

### 组件

- `tui.Box(props)` - 布局容器
- `tui.Text(props)` - 文本
- `tui.TextInput(props)` - 文本输入
- `tui.Select(props)` - 选择列表
- `tui.Spinner(props)` - 加载动画
- `tui.ProgressBar(props)` - 进度条
- `tui.Static(props)` - 静态列表
- `tui.Newline()` - 换行
- `tui.Spacer()` - 弹性空间
- `tui.ErrorBoundary(props)` - 错误边界

### Hooks

- `tui.useState(initial)` - 状态
- `tui.useEffect(fn, deps)` - 副作用
- `tui.useMemo(fn, deps)` - 记忆化计算
- `tui.useCallback(fn, deps)` - 记忆化回调
- `tui.useRef(initial)` - 可变引用
- `tui.useReducer(reducer, initial)` - Reducer
- `tui.useContext(ctx)` - 上下文
- `tui.useInterval(fn, ms)` - 定时器
- `tui.useTimeout(fn, ms)` - 延迟器
- `tui.useInput(fn)` - 输入处理
- `tui.useWindowSize()` - 窗口大小
- `tui.useFocus(opts)` - 焦点管理
- `tui.useAnimation(fn, opts)` - 动画
- `tui.useApp()` - 应用控制

### 工具函数

- `tui.render(root)` - 渲染应用
- `tui.component(fn)` - 创建组件工厂
- `tui.createContext(default)` - 创建上下文
- `tui.displayWidth(str)` - 计算显示宽度
- `tui.truncate(str, width)` - 截断文本

## 完整示例

```lua
local tui = require "tui"

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
        flexDirection = "column",
        padding = 1,

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
                flex = 1,
            },
        },

        tui.Newline {},

        tui.Static {
            items = todos,
            render = function(todo, i)
                return tui.Text {
                    (todo.done and "[x] " or "[ ] ") .. todo.text
                }
            end
        }
    }
end

tui.render(TodoApp)
```

## 开发模式

启用开发模式以获取运行时检查：

```lua
tui.setDevMode(true)
```

开发模式检查项：
- Hook 顺序校验（防止条件分支中调用 hook）
- Render 期间 `setState` 警告
- 缺失 `key` prop 警告（3+ 子元素时）
- Hook 在非组件函数中调用时 fatal 错误

## 技术特性

- **Yoga 布局引擎**：完整 CSS Flexbox 支持
- **Unicode 15.1**：正确处理 Emoji、CJK、组合字符
- **增量渲染**：双缓冲 + diff 算法，60fps 流畅
- **焦点系统**：Tab 导航、自动焦点管理
- **测试框架**：完整的测试 harness，支持快照测试
- **IME 支持**：输入法候选框跟随光标

## 许可证

MIT
