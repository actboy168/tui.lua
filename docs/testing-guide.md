# TUI 测试编写指南（AI版）

本文档指导AI如何为 tui.lua 项目编写有效的测试，重点介绍离屏渲染测试和调试技巧。

## 测试框架概述

- **测试框架**: `3rd/ltest/ltest.lua` - 轻量级单元测试框架
- **测试入口**: `test.lua` - 自动收集并运行 `test/` 目录下所有 `test_*.lua` 文件
- **测试工具**: `tui/testing.lua` - 提供离屏渲染、输入模拟、快照测试等功能

## 两种测试模式

### 1. 完整渲染模式 (`testing.render`)

用于测试组件的视觉输出、布局、交互效果。

```lua
local testing = require "tui.testing"

local h = testing.render(App, { cols = 40, rows = 10 })
-- 现在你可以在虚拟终端中操作组件
```

**适用场景**:
- 测试组件是否正确渲染到屏幕
- 验证布局计算结果
- 测试用户输入的视觉反馈
- 快照测试

### 2. 裸渲染模式 (`testing.mount_bare`)

仅测试 reconciler + hooks，跳过 layout/renderer/screen。

```lua
local b = testing.mount_bare(App)
-- 只能测试 hooks 状态和 reconciler 行为，没有视觉输出
```

**适用场景**:
- 测试 useState/useEffect 等 hooks 的行为
- 验证组件重渲染逻辑
- 测试组件身份识别（key/组件类型变化）

## Harness API 详解

### 初始化与清理

```lua
-- 创建离屏渲染实例
local h = testing.render(App, { cols = 80, rows = 24 })

-- 测试结束后必须清理
h:unmount()
```

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

-- 发送原始字节序列
h:dispatch("\x1b[13;2u")  -- Kitty风格的Shift+Enter

-- 支持的特殊键名:
-- "enter", "return", "escape", "esc", "tab", "shift+tab", "backtab"
-- "backspace", "up", "down", "right", "left"
-- "home", "end", "insert", "delete", "pageup", "pagedown"
-- "f1" .. "f12"
-- "ctrl+<字母>", "^<字母>" (如 "ctrl+c" 或 "^c")
-- "shift+<键名>" (如 "shift+enter")
```

### 聚焦控制

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
```

### 窗口大小调整

```lua
-- 调整终端尺寸
h:resize(60, 20)

-- 这会触发 useWindowSize 订阅者更新
```

### ANSI序列捕获

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

-- 获取渲染次数（性能测试）
local count = h:render_count()
h:reset_render_count()
h:expect_renders(1, "应该只渲染一次")
```

## 快照测试

```lua
-- 保存当前帧到快照文件
-- 首次运行创建快照，后续运行对比
h:match_snapshot("chat_after_submit")

-- 快照存储在: test/__snapshots__/<name>.txt
-- 更新快照: TUI_UPDATE_SNAPSHOTS=1 luamake test
```

## 调试技巧

### 1. 打印当前屏幕内容

```lua
-- 打印整个帧
print(h:frame())

-- 打印特定行
for i = 1, h:height() do
    print(string.format("Row %2d: %q", i, h:row(i)))
end
```

### 2. 打印ANSI序列

```lua
h:clear_ansi()
-- ... 执行某些操作
print("ANSI output:")
print(h:ansi())
```

### 3. 打印组件树

```lua
-- 获取渲染树（包含布局信息）
local tree = h:tree()

-- 使用内置工具打印
local function print_tree(e, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    if e.kind == "text" then
        print(prefix .. "Text: " .. tostring(e.text):sub(1, 50))
    elseif e.kind == "box" then
        local r = e.rect or {}
        print(prefix .. string.format("Box [%dx%d at %d,%d]", r.w or 0, r.h or 0, r.x or 0, r.y or 0))
    end
    for _, c in ipairs(e.children or {}) do
        print_tree(c, indent + 1)
    end
end

print_tree(h:tree())
```

### 4. 使用树查询工具

```lua
-- 查找第一个特定类型的节点
local box = testing.find_by_kind(h:tree(), "box")

-- 查找所有特定类型的节点
local all_texts = testing.find_all_by_kind(h:tree(), "text")

-- 获取所有文本内容
local texts = testing.text_content(h:tree())
for _, t in ipairs(texts) do
    print("Text: " .. t)
end
```

## 常见测试模式

### 模式1: 验证渲染输出

```lua
function suite:test_renders_hello()
    local function App()
        return tui.Text { "Hello World" }
    end
    local h = testing.render(App, { cols = 20, rows = 3 })
    -- 第一行应该包含 "Hello World"
    lt.assertTrue(h:row(1):find("Hello World") ~= nil)
    h:unmount()
end
```

### 模式2: 测试用户输入

```lua
function suite:test_typing_updates_value()
    local value = ""
    local function App()
        return tui.TextInput {
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
            tui.TextInput { focusId = "a" },
            tui.TextInput { focusId = "b" },
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

### 模式6: 使用Bare模式测试Hooks

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
        -- 这里执行会产生[tui:dev]警告的操作
        local h = testing.render(BadComponent)
        h:unmount()
    end)
    lt.assertTrue(warnings:find("expected warning") ~= nil)
end
```

## 注意事项

1. **总是调用 unmount()**: 每个测试结束时必须调用 `h:unmount()` 或 `b:unmount()`，否则会有状态泄漏

2. **Dev模式警告**: 测试期间产生的 `[tui:dev]` 警告会导致测试失败，除非用 `capture_stderr` 捕获

3. **Bare模式不自动渲染**: Bare模式的 `type/press/advance` 不会自动触发重渲染，需要手动调用 `rerender()`

4. **屏幕行号**: `h:row(n)` 是1-based，从顶部开始

5. **光标位置**: `h:cursor()` 返回的坐标也是1-based

6. **快照文件**: 首次运行会创建快照，后续运行会对比。不要随意删除快照文件

7. **并发安全**: Harness实例是独立的，多个测试可以并行运行

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

-- 更多测试...

-- 调试时临时使用:
-- function suite:debug_print_tree()
--     local h = testing.render(MyApp)
--     print(h:frame())
--     h:unmount()
-- end
```
