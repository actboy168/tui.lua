# 组件

tui.lua 提供两类组件：核心组件和高级控件。

## 核心组件

核心组件由 `tui/init.lua` 导出，无需额外加载：

| 组件 | 说明 |
|------|------|
| `tui.Box` | 布局容器（Flexbox） |
| `tui.Text` | 文本显示（样式、截断、换行） |
| `tui.Transform` | 对子树输出做 cell/region 级后处理 |
| `tui.RawAnsi` | 预渲染 ANSI 行片段（支持 SGR / OSC 8） |
| `tui.ErrorBoundary` | 错误边界（捕获子树渲染错误） |

核心组件的完整属性签名参见 [核心 API - 组件](../api/core.md#组件)。

### Text

```lua
tui.Text { "普通文本" }

-- 样式
tui.Text { color = "red", bold = true, "样式化文本" }

-- 截断
tui.Text { wrap = "truncate", width = 10, "这是一段很长的文本" }
```

### Box

```lua
tui.Box {
    flexDirection = "row",
    justifyContent = "center",
    alignItems = "center",
    gap = 1,
    padding = 2,
    borderStyle = "single",
    tui.Text { "内容" }
}
```

> Box 的布局属性详解参见 [布局系统](02-layout.md)。

### ErrorBoundary

```lua
tui.ErrorBoundary {
    fallback = function(error)
        return tui.Box {
            borderStyle = "single",
            borderColor = "red",
            tui.Text { color = "red", "错误: " .. error }
        }
    end,
    RiskyComponent {}
}
```

### Transform

```lua
tui.Transform {
    transform = function(region)
        region:setHyperlink("https://example.com")
    end,
    tui.Text { "docs" },
}
```

`Transform` 适合对子树做输出级后处理。这里处理的是渲染后的 cell/region，而不是字符串。`Link` 的 rich children 原生超链接就是建立在它之上的。

### RawAnsi

```lua
tui.RawAnsi {
    lines = {
        "\27[32mOK:\27[0m \27]8;;https://example.com/raw\27\\raw-docs\27]8;;\27\\",
    },
    width = 12,
}
```

`RawAnsi` 适合承载外部已经生成好的 ANSI 输出。它保留 SGR 样式和 OSC 8 超链接，但要求调用方提前拆好行，不负责 wrap。完整示例见 [`examples/raw_ansi.lua`](../../examples/raw_ansi.lua)。

## 高级控件

高级控件位于 `tui/extra/`，需要显式加载：

```lua
local extra = require "tui.extra"
extra.TextInput { ... }
```

| 组件 | 说明 |
|------|------|
| `extra.TextInput` | 单行文本输入 |
| `extra.Textarea` | 多行文本编辑器 |
| `extra.Link` | 高层超链接组件（`href` + 可选 `onClick`） |
| `extra.Button` | 带边框的可点击按钮 |
| `extra.Select` | 选项列表 |
| `extra.Spinner` | 加载动画 |
| `extra.ProgressBar` | 进度条 |
| `extra.Static` | 静态列表 |
| `extra.Newline` | 换行 |
| `extra.Spacer` | 弹性空间 |

高级控件的完整属性、示例和键盘操作参见 [高级控件](../api/extra.md)。如果你只需要普通可交互超链接，优先用 `extra.Link`；如果你要添加可点击操作按钮，使用 `extra.Button`；如果你要承载外部预渲染 ANSI/OSC 8 输出，使用 `tui.RawAnsi`；如果你要给任意子树附加输出级效果，使用 `tui.Transform`。`extra.Link` 示例见 [`examples/link.lua`](../../examples/link.lua)，`extra.Button` 示例见 [`examples/button.lua`](../../examples/button.lua)。

## 自定义组件

### 函数组件

```lua
local function Card(props)
    return tui.Box {
        borderStyle = "round",
        borderColor = props.color or "white",
        padding = 1,
        width = props.width or 30,
        tui.Text { bold = true, props.title },
        tui.Text { props.children }
    }
end

-- 使用
Card { title = "提示", color = "blue", "这是卡片内容" }
```

### tui.component 工厂

```lua
local Card = tui.component(function(props)
    return tui.Box {
        borderStyle = "round",
        tui.Text { props.title }
    }
end)

-- 使用
Card { title = "标题" }
```

### 组件组合示例

```lua
local extra = require "tui.extra"

local function App()
    return tui.Box {
        flexDirection = "column",
        padding = 2,

        tui.Box {
            justifyContent = "center",
            tui.Text { bold = true, "用户管理系统" }
        },

        extra.Newline {},

        tui.Box {
            flexDirection = "column",
            gap = 1,
            tui.Text { "用户名:" },
            extra.TextInput { placeholder = "输入用户名", width = 30 },
            tui.Text { "邮箱:" },
            extra.TextInput { placeholder = "输入邮箱", width = 30 }
        },

        extra.Newline {},

        tui.Box {
            flexDirection = "row",
            gap = 1,
            tui.Box { borderStyle = "single", padding = { left = 2, right = 2 }, tui.Text { "保存" } },
            tui.Box { borderStyle = "single", padding = { left = 2, right = 2 }, tui.Text { "取消" } }
        }
    }
end
```
