# Virtual Terminal 设计文档

`tui/testing/vterm.lua` — 为测试 harness 提供终端行为层模拟。vterm 已取代原来的 `make_fake_terminal`，成为 harness 的默认终端后端。

## 1. 背景与动机

原来的 harness 终端只在**接口层**记录字符串：

```lua
write = function(s) h._ansi_buf[#h._ansi_buf+1] = s end
```

它只记录字符串，**不解释 ANSI 序列、不维护终端状态**。这导致生产环境所有被 `ansi.interactive()` gate 的代码路径（光标相对移动、BSU/ESU、鼠标模式序列、content_h 裁剪、teardown 恢复等）在 harness 中完全 bypass，形成 14+ 条测试盲区。

**vterm 方案**：把终端模拟下沉到**行为层**——轻量 ANSI 终端模拟器，能解析序列、维护虚拟屏幕和终端状态。harness 默认使用 vterm，可选启用 interactive 模式走通 `interactive == true` 分支。

## 2. 设计目标

| 目标 | 说明 |
|------|------|
| **纯 Lua** | 无 C 依赖，不改动 tui_core |
| **够用即可** | 不需要完整的 VT500 模拟器，只覆盖 tui.lua 实际发出的序列 |
| **可断言** | 提供查询 API 供测试断言虚拟终端状态 |
| **默认启用** | 所有 harness 渲染自动获得 vterm，无需手动指定 |
| **可扩展** | 解析器用状态机实现，新增序列只需增加状态和动作 |

## 3. 架构

```
┌─────────────────────────────────────┐
│  Harness:_paint() / init.lua paint() │
│  ├─ screen_mod.clear()               │
│  ├─ renderer.paint()                 │
│  ├─ screen_mod.diff()                │
│  ├─ ansi.cursorMove() / cursorShow() │
│  └─ terminal.write(sequences)        │
└──────────────┬──────────────────────┘
               │
      ┌────────▼────────┐
      │  vterm:write()  │  ← ANSI 解析器（状态机）
      │  ├─ 更新 cells  │
      │  ├─ 移动 cursor │
      │  ├─ 切换 mode   │
      │  └─ 记录 log    │
      └────────┬────────┘
               │
      ┌────────▼────────┐
      │   虚拟终端状态   │
      │  cells, cursor, │
      │  mode, scroll   │
      │  region, input  │
      │  queue, ...     │
      └─────────────────┘
```

## 4. 数据模型

### 4.1 虚拟终端状态

```lua
{
    -- 几何
    cols = 80,
    rows = 24,

    -- 光标
    cursor = {
        col = 1,          -- 1-based
        row = 1,          -- 1-based
        visible = true,
        style = "block",  -- "block" | "bar" | "underline"
    },

    -- 滚动区域（DECSTBM）
    scroll_region = { top = 1, bottom = 24 },

    -- 屏幕缓冲区
    -- cells[row][col] = { char = "H", attrs = {...} }
    cells = {},

    -- 默认属性（新写入字符继承）
    attrs = {
        fg = nil,         -- nil = default, {type="rgb", r=255, g=0, b=0}, {type="indexed", idx=31}
        bg = nil,
        bold = false,
        dim = false,
        italic = false,
        underline = false,  -- "none" | "single" | "double"
        blink = false,
        inverse = false,
        hidden = false,
        strikethrough = false,
    },

    -- 保存的光标（DECSC / ESC 7）
    saved_cursor = nil,   -- { col, row, visible, attrs }

    -- 终端模式状态
    mode = {
        raw = false,
        mouse = 0,              -- ref-counted: 0=off, 1=click+scroll, 2=drag, 3=all
        bracketed_paste = false,
        focus_events = false,
        kkp = false,
        alternate_screen = false,
        synchronized_output = 0, -- BSU/ESU 嵌套计数
    },

    -- 输入队列（供 read 消费）
    input_queue = {},

    -- 原始写入记录（供 has_sequence 断言）
    write_log = {},

    -- 解析器状态
    parser = {
        state = "ground",
        buffer = "",
        params = {},
        intermediates = "",
        osc_string = "",
    },
}
```

### 4.2 单元格属性（SGR 子集）

| SGR 代码 | 属性 |
|---------|------|
| 0 | 重置所有属性 |
| 1 | bold = true |
| 2 | dim = true |
| 3 | italic = true |
| 4 | underline = "single" |
| 4:2 | underline = "double" |
| 5 | blink = true |
| 7 | inverse = true |
| 8 | hidden = true |
| 9 | strikethrough = true |
| 22 | bold=false, dim=false |
| 23 | italic = false |
| 24 | underline = "none" |
| 25 | blink = false |
| 27 | inverse = false |
| 28 | hidden = false |
| 29 | strikethrough = false |
| 30-37, 38:2, 38:5, 39 | fg 颜色 |
| 40-47, 48:2, 48:5, 49 | bg 颜色 |
| 90-97 | bright fg |
| 100-107 | bright bg |

## 5. ANSI 解析器（状态机）

采用简化 VT500 状态机，只处理 tui.lua 实际发出的序列类型。

### 5.1 状态转换

```
ground ──ESC──→ esc

esc ──[──→ csi_entry
esc ──]──→ osc_string
esc ──P──→ dcs_entry
esc ──_──→ apc_string
esc ──^──→ pm_string
esc ──c──→ action: RIS (reset)
esc ──7──→ action: DECSC (save cursor)
esc ──8──→ action: DECRC (restore cursor)
esc ──(──→ esc_intermediate
esc ──)──→ esc_intermediate
esc ──other──→ action: 忽略或记录

csi_entry ──0-9──→ csi_param
csi_entry ──:──→ csi_param
csi_entry ──;──→ csi_param
csi_entry ──?──→ csi_param
csi_entry ──intermediate──→ csi_intermediate
csi_entry ──final──→ action + ground

csi_param ──0-9:;──→ csi_param
csi_param ──intermediate──→ csi_intermediate
csi_param ──final──→ action + ground

csi_intermediate ──intermediate──→ csi_intermediate
csi_intermediate ──final──→ action + ground

osc_string ──BEL(0x07)──→ action + ground
osc_string ──ESC──→ osc_esc
osc_string ──other──→ osc_string

osc_esc ──\──→ action + ground
osc_esc ──other──→ osc_string

dcs_entry ──final──→ dcs_string (简化：消费到 ST)
```

### 5.2 需要支持的 CSI Final + Action

按优先级分组：

**P0 — tui.lua 核心路径（必须）**

| Final | 名称 | 动作 |
|-------|------|------|
| `m` | SGR | 更新当前 `attrs` |
| `H` | CUP | 光标绝对定位（默认 1,1） |
| `A` | CUU | 光标上移 |
| `B` | CUD | 光标下移 |
| `C` | CUF | 光标右移 |
| `D` | CUB | 光标左移 |
| `J` | ED | 擦除显示（0/1/2/3） |
| `K` | EL | 擦除行（0/1/2） |
| `S` | SU | 滚动上（默认 1） |
| `T` | SD | 滚动下（默认 1） |
| `r` | DECSTBM | 设置滚动区域 |
| `h` | SM/DECSET | 设置模式（含 `?` 前缀） |
| `l` | RM/DECRST | 重置模式（含 `?` 前缀） |
| `n` | DSR | 设备状态报告（可选，用于 cursor_pos 验证） |

**P1 — 常用但当前未直接测试**

| Final | 名称 | 动作 |
|-------|------|------|
| `E` | CNL | 光标下移 N 行，列归 1 |
| `F` | CPL | 光标上移 N 行，列归 1 |
| `G` | CHA | 光标水平绝对 |
| `d` | VPA | 光标垂直绝对 |
| `@` | ICH | 插入空白字符 |
| `P` | DCH | 删除字符 |
| `L` | IL | 插入行 |
| `M` | DL | 删除行 |

### 5.3 需要支持的 ESC 序列

| 序列 | 名称 | 动作 |
|------|------|------|
| `ESC 7` | DECSC | 保存光标位置和属性 |
| `ESC 8` | DECRC | 恢复光标位置和属性 |
| `ESC c` | RIS | 完全重置终端 |

### 5.4 需要支持的 OSC 序列

| 类型 | 动作 |
|------|------|
| OSC 0 / 2 | 设置标题（记录到 `title` 字段） |
| OSC 52 | 剪贴板（记录到 `clipboard_log`） |
| OSC 1337 | iTerm2 SetMark（记录，可选） |

### 5.5 DECSET/DECRST 模式表

| 编号 | 名称 | 状态字段 |
|------|------|---------|
| 1000 | Mouse (old) | `mode.mouse` 参与 ref-count |
| 1002 | Button event tracking | `mode.mouse` 参与 ref-count |
| 1003 | Any event tracking | `mode.mouse` 参与 ref-count |
| 1004 | Focus events | `mode.focus_events` |
| 1006 | SGR extended coordinates | `mode.sgr_mouse`（记录即可） |
| 2004 | Bracketed paste | `mode.bracketed_paste` |
| 2026 | Synchronized output | `mode.synchronized_output` ref-count |
| 1049 | Alternate screen buffer | `mode.alternate_screen` |

**注意**：鼠标模式是 ref-counted（`request_mouse_level`），不是布尔开关。vterm 需要跟踪 `mode.mouse` 为整数计数器。

## 6. 接口设计

### 6.1 创建

```lua
local vterm = require "tui.testing.vterm"

-- 创建虚拟终端
local vt = vterm.new(cols, rows)

-- 写入 ANSI 序列（解析并更新状态）
vterm.write(vt, "\x1b[31mhello\x1b[0m")
```

### 6.2 状态查询

```lua
-- 屏幕内容
local cell = vterm.cell(vt, col, row)     -- { char = "H", attrs = {...} }
local row_str = vterm.row_string(vt, row) -- "hello    "
local all = vterm.screen_string(vt)       -- LF-joined rows

-- 光标
local c = vterm.cursor(vt)                -- { col=5, row=3, visible=true, style="block" }

-- 终端模式
vterm.has_mode(vt, 1000)                  -- bool: DECSET 1000 是否启用
vterm.mouse_level(vt)                     -- 返回 mode.mouse 整数

-- 原始输出
vterm.write_log(vt)                       -- 所有 write() 的原始字符串数组
vterm.has_sequence(vt, pattern)           -- bool: 输出中是否包含某子串
vterm.has_sequence_pattern(vt, pattern)   -- bool: 输出中是否匹配 Lua pattern

-- 剪贴板
vterm.clipboard_log(vt)                   -- OSC 52 剪贴板操作记录

-- 同步输出
vterm.sync_depth(vt)                      -- BSU/ESU 嵌套计数
```

### 6.3 输入注入

```lua
-- 向输入队列追加字节（供 read 消费）
vterm.enqueue_input(vt, bytes)

-- 便捷方法
vterm.enqueue_paste(vt, text)             -- 括号粘贴序列
vterm.enqueue_focus_in(vt)               -- 焦点获得事件
vterm.enqueue_focus_out(vt)              -- 焦点失去事件

-- 一次性清空队列
vterm.clear_input(vt)
```

## 7. 与 Harness 集成

### 7.1 vterm 为默认终端后端

所有 `testing.render()` 调用自动创建 vterm 实例，h:vterm() 始终可用。

```lua
local h = testing.render(App, { cols = 20, rows = 5 })
local vt = h:vterm()           -- 始终返回 vterm 实例
vterm.has_sequence(vt, "\x1b[31m")  -- 可查询 ANSI 序列
```

### 7.2 interactive 模式

通过 `opts.interactive` 独立控制 paint 路径：

| 选项 | paint 路径 | 说明 |
|------|-----------|------|
| 默认（无选项） | 非交互式 | cursorPosition、无 BSU/ESU |
| `interactive = true` | 交互式 | cursorMove + BSU/ESU + 鼠标 + 剪贴板 + 焦点事件 |

```lua
-- 非交互式（默认）：生产环境 paint() 的非交互式路径
local h = testing.render(App, { cols = 20, rows = 5 })

-- 交互式：完整生产环境 paint() 路径
local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
local vt = h:vterm()
-- 验证 BSU/ESU
vterm.has_sequence(vt, "\x1b[?2026h")  -- true
vterm.has_sequence(vt, "\x1b[?2026l")  -- true
-- 验证鼠标模式
vterm.mouse_level(vt) > 0              -- true（当 tree 有 onMouseDown）
```

### 7.3 ansi.interactive() 注入

当 `interactive = true` 时，harness 通过 `ansi_mod.set_interactive_fn()` 让 `ansi.interactive()` 返回 `true`，使得生产代码中的 interactive 分支被完整走通。unmount 时自动恢复。

## 8. 实现状态

所有阶段已完成：

| 阶段 | 内容 | 状态 |
|------|------|------|
| **1** | 核心解析器：ground/esc/csi_entry/csi_param + 字符写入 + CUP/CUU/CUD/CUF/CUB | 完成 |
| **2** | SGR 解析 + ED/EL + SGR 21 双下划线 + DECSCUSR 光标形状 | 完成 |
| **3** | DECSET/DECRST 模式表 + 状态跟踪 + 输入队列 + 输入注入 | 完成 |
| **4** | DECSTBM + SU/SD + 滚动区域 + wrap_pending | 完成 |
| **5** | OSC 52 + BSU/ESU + 序列查询 API | 完成 |
| **6** | 与 harness 集成：vterm 为默认终端后端 + interactive 解耦 | 完成 |
| **7** | interactive paint 路径 + 初始化/拆除序列 | 完成 |

## 9. 示例

### 9.1 测试鼠标模式序列

```lua
function suite:test_mouse_mode_with_onclick()
    local function App()
        return tui.Box {
            onMouseDown = function() end,
            tui.Text { "click me" }
        }
    end

    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()

    -- 验证 mouse mode 序列已发出
    lt.assertEquals(vterm.mouse_level(vt) > 0, true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1000h"), true)

    h:unmount()
end
```

### 9.2 测试 BSU/ESU 同步刷新

```lua
function suite:test_sync_update()
    local function App()
        return tui.Text { "hello" }
    end

    local h = testing.render(App, { cols = 10, rows = 1, interactive = true })
    local vt = h:vterm()

    -- 验证每帧被 BSU/ESU 包裹
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2026h"), true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2026l"), true)
end
```

### 9.3 用 cells() 断言颜色（非交互式）

```lua
function suite:test_red_text()
    local function App()
        return tui.Box { width = 5, height = 1,
            tui.Text { color = "red", "hi" },
        }
    end
    local h = testing.render(App)
    local cells = h:cells(1)
    lt.assertEquals(cells[1].fg, 1, "cell should have red fg")
    h:unmount()
end
```

### 9.4 用 vterm 屏幕比较断言渲染稳定性

```lua
function suite:test_rerender_stable()
    local function App()
        return tui.Box { width = 20, height = 2,
            tui.Text { "key=", {text="value", color="cyan"} },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 2 })
    local vt = h:vterm()
    local before = vterm.screen_string(vt)
    h:rerender()
    local after = vterm.screen_string(vt)
    lt.assertEquals(after, before, "second render should not change screen content")
    h:unmount()
end
```

## 10. 已知限制

以下问题**不在 vterm 范围内**，需要其他测试策略：

- **真实终端兼容性**：xterm/iTerm2/Windows Terminal 对同一序列的解释差异（需要集成测试）
- **性能/内存**：长时间运行的压力测试
- **并发竞态**：信号中断、线程安全
- **网络终端延迟**：SSH/mosh 场景
- **C 层崩溃**：segfault、OOM

### 待实现

- **vterm resize 支持**：`vterm.new(W, H)` 创建固定尺寸终端；`Harness:resize()` 不更新 vterm 屏幕尺寸。需要 `vterm.resize()` 方法。

## 11. 相关文件

- `tui/testing/vterm.lua` — vterm 实现
- `tui/testing/harness.lua` — 集成点（vterm 为默认终端后端）
- `tui/internal/paint_frame.lua` — paint 逻辑提取（stabilize + find_cursor）
- `tui/internal/ansi.lua` — `set_interactive_fn()` 支持 interactive 注入
