# tui.lua

一个用于 Lua 的 React 风格终端 UI 框架。

## 技术特性

- **Yoga 布局引擎**：完整 CSS Flexbox 支持
- **Unicode 15.1**：正确处理 Emoji、CJK、组合字符
- **增量渲染**：双缓冲 + diff 算法，60fps 流畅
- **焦点系统**：Tab 导航、自动焦点管理
- **测试框架**：完整的测试 harness，支持快照测试
- **IME 支持**：输入法候选框跟随光标

## 安装与编译

```bash
git clone https://github.com/yourusername/tui.lua.git
cd tui.lua
luamake
```

运行脚本：

```bash
luamake lua myapp.lua
```

## 最小示例

```lua
local tui = require "tui"

local function App()
    return tui.Box {
        flexDirection = "column",
        padding = 2,
        tui.Text { bold = true, "Hello, tui.lua!" },
        tui.Text { "按 Ctrl+C 退出" }
    }
end

tui.render(App)
```

> 更多示例参见 [examples/](examples/)

## 文档

### 教程

| 文档 | 说明 |
|------|------|
| [快速开始](docs/guide/01-quickstart.md) | 安装、第一个应用、组件化 |
| [布局系统](docs/guide/02-layout.md) | Flexbox 布局详解 |
| [组件](docs/guide/03-components.md) | 核心组件概述与自定义组件 |
| [Hooks 指南](docs/guide/04-hooks.md) | 状态管理与副作用 |
| [焦点系统](docs/guide/05-focus.md) | 键盘导航与表单 |

### API 参考

| 文档 | 对应源码 | 说明 |
|------|----------|------|
| [核心 API](docs/api/core.md) | `tui/init.lua` | 组件、Hooks、工具函数完整签名 |
| [高级控件](docs/api/extra.md) | `tui/extra/` | TextInput、Select、Spinner 等交互组件 |
| [测试套件](docs/api/testing.md) | `tui/testing.lua` | 离屏渲染、输入模拟、快照测试 |

## 许可证

MIT
