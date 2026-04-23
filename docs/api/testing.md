# 测试套件

对应源码 `tui/testing.lua` 与 `tui/testing/` 子模块，提供离屏渲染、输入模拟、快照测试等功能。

```lua
local testing = require "tui.testing"
```

---

## 两种渲染模式

### 完整渲染模式 `testing.render`

用于测试组件的视觉输出、布局、交互效果。运行完整的 reconciler + layout + renderer + screen 管线。

```lua
local h = testing.render(App, { cols = 40, rows = 10 })
```

**适用场景**：
- 测试组件是否正确渲染到屏幕
- 验证布局计算结果
- 测试用户输入的视觉反馈
- 快照测试

### 裸渲染模式 `testing.mount_bare`

仅运行 reconciler + hooks，跳过 layout/renderer/screen。

```lua
local b = testing.mount_bare(App)
```

**适用场景**：
- 测试 useState/useEffect 等 hooks 的行为
- 验证组件重渲染逻辑
- 测试组件身份识别（key/组件类型变化）

---

## Harness API（完整渲染）

### 初始化与清理

```lua
-- 创建离屏渲染实例
local h = testing.render(App, { cols = 80, rows = 24 })

-- 测试结束后必须清理
h:unmount()
```

`render` 选项：

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `cols` | number | 80 | 虚拟终端宽度 |
| `rows` | number | 24 | 虚拟终端高度 |
| `now` | number | 0 | 虚拟起始时间（毫秒） |

### 屏幕内容读取

```lua
-- 获取第 n 行的内容（1-based）
local line = h:row(1)

-- 获取所有行，返回 table
local rows = h:rows()

-- 获取完整帧（多行字符串，用 \n 连接）
local frame = h:frame()

-- 获取终端尺寸
local w, h = h:width(), h:height()

-- 获取渲染树（包含布局信息）
local tree = h:tree()
```

### 输入模拟

```lua
-- 输入字符串（逐字符输入，每字符触发一次渲染）
h:type("hello")

-- 按特定键
h:press("enter")
h:press("ctrl+c")       -- Ctrl+C
h:press("shift+enter")  -- Shift+Enter
h:press("up")           -- 方向键

-- 发送通过 helper 构造的输入字节
h:dispatch(testing.input.raw("\x1b[13;2u"))  -- Kitty风格的 Shift+Enter
h:dispatch(testing.input.paste("hello\n"))   -- bracketed paste
h:dispatch(testing.mouse.sgr {
    type = "down", button = 1, x = 5, y = 3,
})

-- 发送已解析的按键事件（绕过 ANSI 解析器）
h:dispatch_event({
    name = "enter", input = "\r", raw = "\r",
    ctrl = false, shift = false, alt = false, meta = false,
})
```

**支持的特殊键名**：

| 键名 | 说明 |
|------|------|
| `enter`, `return` | 回车 |
| `escape`, `esc` | Esc |
| `tab` | Tab |
| `shift+tab`, `backtab` | Shift+Tab |
| `backspace` | 退格 |
| `up`, `down`, `left`, `right` | 方向键 |
| `home`, `end` | Home/End |
| `insert`, `delete` | Insert/Delete |
| `pageup`, `pagedown` | Page Up/Down |
| `f1` - `f12` | 功能键 |
| `ctrl+<字母>` | Ctrl 组合键（如 `ctrl+c`、`^c`） |
| `shift+<键名>` | Shift 组合键 |

### 输入测试约定

- **普通组件/集成测试**：优先使用 `testing.input` / `testing.mouse` 构造输入，而不是在测试里直接拼协议字节。
- **平台夹具测试**：Windows 输入归一化统一走 `testing.input.windows { ... }`。
- **paste 测试**：优先使用 `testing.input.paste(text)` 或 `h:paste(text)`。
- **mouse 测试**：优先使用 `testing.mouse.sgr(...)`、`testing.mouse.x10(...)`，或者 `h:mouse(...)`。
- **保留字节字面量的场景**：只限 parser / ANSI / 协议常量专项测试，例如 `keys.parse()`、Kitty Keyboard、ANSI builder、OSC 输出断言。

### IME 输入模拟

```lua
-- 模拟输入法组合中状态
h:type_composing("ni")

-- 模拟输入法确认
h:type_composing_confirm("你")

-- 获取组合中文本
local text = h:composing()

-- 获取光标位置
local col, row = h:cursor()
```

### 焦点控制

```lua
-- 获取当前聚焦的ID
local id = h:focus_id()

-- 切换聚焦
h:focus_next()   -- Tab
h:focus_prev()   -- Shift+Tab
h:focus("my-id") -- 聚焦到指定ID
```

### 光标位置

```lua
-- 获取光标位置（1-based）
local col, row = h:cursor()

-- 返回 nil 表示没有聚焦的输入框
if col then
    print("光标在 " .. col .. "," .. row)
end
```

### 时间控制

```lua
-- 推进虚拟时间（毫秒）
h:advance(100)   -- 推进100ms

-- useInterval/useTimeout 的回调会在此期间触发
-- interval 定时器会自动追赶（advance(1000) + 100ms间隔 = 触发10次）
```

### 窗口大小调整

```lua
-- 调整终端尺寸
h:resize(60, 20)

-- 这会触发 useWindowSize 订阅者更新
```

### ANSI 序列捕获

```lua
-- 获取渲染产生的所有ANSI序列
local ansi = h:ansi()

-- 清空ANSI缓冲区
h:clear_ansi()

-- 用途: 验证是否发送了正确的控制序列
```

### 重渲染控制

```lua
-- 手动触发重渲染（通常不需要，输入操作会自动触发）
h:rerender()

-- 获取渲染次数
local count = h:render_count()

-- 重置渲染计数
h:reset_render_count()

-- 断言渲染次数
h:expect_renders(1, "应该只渲染一次")
```

### 快照测试

```lua
-- 保存当前帧到快照文件，首次运行创建，后续运行对比
h:match_snapshot("chat_after_submit")

-- 快照存储在: test/__snapshots__/<name>.txt
-- 更新快照: TUI_UPDATE_SNAPSHOTS=1 luamake test
```

快照格式：每行对应屏幕一行，LF 连接，末尾 LF。尾部空格在比较前自动去除（git/editor 友好）。CRLF 自动归一化为 LF。

---

## Bare API（裸渲染）

裸渲染模式不自动触发重渲染，输入/时间操作后需手动调用 `rerender()`。

```lua
local b = testing.mount_bare(App)
```

### 可用方法

| 方法 | 说明 |
|------|------|
| `b:rerender()` | 手动触发重渲染 |
| `b:dispatch(bytes)` | 发送原始字节（不自动 rerender） |
| `b:type(str)` | 输入字符串（不自动 rerender） |
| `b:press(name)` | 按键（不自动 rerender） |
| `b:advance(ms)` | 推进虚拟时间（不自动 rerender） |
| `b:focus_id()` | 获取当前焦点 ID |
| `b:focus_next()` | 下一个焦点（不自动 rerender） |
| `b:focus_prev()` | 上一个焦点（不自动 rerender） |
| `b:focus(id)` | 聚焦指定 ID（不自动 rerender） |
| `b:tree()` | 获取渲染树 |
| `b:state()` | 获取 reconciler 状态 |
| `b:render_count()` | 渲染次数 |
| `b:reset_render_count()` | 重置渲染计数 |
| `b:expect_renders(n, msg)` | 断言渲染次数 |
| `b:unmount()` | 清理 |

---

## 模块级工具函数

### 输入 / 鼠标 helper

```lua
local bytes = testing.input.resolve_key("shift+up")
local paste = testing.input.paste("hello")
local win   = testing.input.windows {
    { vk = 0xE5, char = "" },
    { vk = 0,    char = "中" },
}

local sgr = testing.mouse.sgr {
    type = "scroll", scroll = -1, x = 1, y = 1,
}
```

| Helper | 用途 |
|--------|------|
| `testing.input.raw(bytes)` | 标记“原始输入字节”并走统一归一化入口 |
| `testing.input.posix(bytes)` | 标记 POSIX 来源输入 |
| `testing.input.windows(events)` | Windows 键事件夹具 → 归一化字节 |
| `testing.input.parse(spec)` | 归一化后直接喂给 `keys.parse()` |
| `testing.input.paste(text)` | 构造 bracketed paste 序列 |
| `testing.input.resolve_key(name)` | 生成 `press()` 同款命名键字节 |
| `testing.mouse.sgr(spec)` | 构造 SGR 鼠标协议字节 |
| `testing.mouse.x10(spec)` | 构造 legacy X10 鼠标协议字节 |
| `testing.mouse.harness(...)` | 构造与 `h:mouse(...)` 一致的字节 |

### capture_stderr

捕获 `[tui:dev]` 和 `[tui:test]` 警告到字符串，阻止其触发 fail-on-warn。

```lua
local warnings = testing.capture_stderr(function()
    -- 这里执行会产生警告的操作
    local h = testing.render(BadComponent)
    h:unmount()
end)
lt.assertTrue(warnings:find("expected warning") ~= nil)
```

### 诊断工具

```lua
-- 当前注册的定时器数量
testing.timer_count()

-- 当前输入处理器数量
testing.input_handler_count()

-- 当前焦点注册表条目
testing.focus_entries()

-- 触发 [tui:fatal] 错误（ErrorBoundary 测试用）
testing.fatal(msg)
```

### 树查询工具

```lua
-- 查找第一个特定类型的节点
local box = testing.find_by_kind(tree, "box")

-- 查找所有特定类型的节点
local all_texts = testing.find_all_by_kind(tree, "text")

-- 获取所有文本内容
local texts = testing.text_content(tree)
for _, t in ipairs(texts) do
    print("Text: " .. t)
end

-- 查找带光标标记的 Text 节点
local text_node = testing.find_text_with_cursor(tree)
```

---

## 常见测试模式

### 模式1: 验证渲染输出

```lua
function suite:test_renders_hello()
    local function App()
        return tui.Text { "Hello World" }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    lt.assertTrue(h:row(1):find("Hello World") ~= nil)
    h:unmount()
end
```

### 模式2: 测试用户输入

```lua
function suite:test_typing_updates_value()
    local value = ""
    local function App()
        return extra.TextInput {
            value = value,
            onChange = function(v) value = v end,
        }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    h:type("hello")
    lt.assertEquals(value, "hello")
    h:unmount()
end
```

### 模式3: 测试键盘导航

```lua
function suite:test_tab_navigation()
    local function App()
        return tui.Box {
            extra.TextInput { focusId = "a" },
            extra.TextInput { focusId = "b" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5 })
    lt.assertEquals(h:focus_id(), "a")
    h:press("tab")
    lt.assertEquals(h:focus_id(), "b")
    h:unmount()
end
```

### 模式4: 测试定时器

```lua
function suite:test_interval_fires()
    local count = 0
    local function App()
        tui.useInterval(function()
            count = count + 1
        end, 100)
        return tui.Text { "test" }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    lt.assertEquals(count, 0)
    h:advance(100)
    lt.assertEquals(count, 1)
    h:advance(100)
    lt.assertEquals(count, 2)
    h:unmount()
end
```

### 模式5: 测试窗口大小变化

```lua
function suite:test_responsive_layout()
    local function App()
        local size = tui.useWindowSize()
        return tui.Text { tostring(size.cols) .. "x" .. tostring(size.rows) }
    end
    local h = testing.render(App, { cols = 40, rows = 10 })
    lt.assertTrue(h:row(1):find("40x10") ~= nil)
    h:resize(60, 20)
    lt.assertTrue(h:row(1):find("60x20") ~= nil)
    h:unmount()
end
```

### 模式6: 使用 Bare 模式测试 Hooks

```lua
function suite:test_use_state()
    local captured
    local setter
    local function App()
        local n, setN = tui.useState(42)
        captured = n
        setter = setN
        return tui.Text { tostring(n) }
    end
    local b = testing.mount_bare(App)
    lt.assertEquals(captured, 42)

    setter(100)
    b:rerender()  -- Bare模式需要手动触发重渲染
    lt.assertEquals(captured, 100)

    b:unmount()
end
```

### 模式7: 捕获警告

```lua
function suite:test_dev_warning()
    local warnings = testing.capture_stderr(function()
        local h = testing.render(BadComponent)
        h:unmount()
    end)
    lt.assertTrue(warnings:find("expected warning") ~= nil)
end
```

---

## 测试文件模板

```lua
-- test/<category>/test_<feature>.lua
local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "feature_name"

function suite:test_basic_render()
    local function App()
        return tui.Text { "Hello" }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    lt.assertTrue(h:row(1):find("Hello") ~= nil)
    h:unmount()
end
```

---

## 注意事项

1. **总是调用 unmount()**: 每个测试结束时必须调用 `h:unmount()` 或 `b:unmount()`，否则会有状态泄漏
2. **Dev 模式自动启用**: 测试套件自动开启 dev-mode，`[tui:dev]` 警告会导致测试失败（除非用 `capture_stderr` 捕获）
3. **Bare 模式不自动渲染**: `type/press/advance` 不会自动触发重渲染，需要手动调用 `rerender()`
4. **屏幕行号**: `h:row(n)` 是 1-based，从顶部开始
5. **光标位置**: `h:cursor()` 返回的坐标也是 1-based
6. **快照文件**: 首次运行会创建快照，后续运行会对比。不要随意删除快照文件
7. **并发安全**: Harness 实例是独立的，多个测试可以并行运行
8. **CSI 完整性**: harness 会自动检查输出中的 CSI 序列参数是否为整数，非整数参数（如 `73.0`）会触发 fatal 错误
