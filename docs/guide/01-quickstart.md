# 快速开始

项目安装与编译说明参见 [README](../../README.md)。可运行的完整示例参见 [examples/](../../examples/)。

## 第一个应用

创建 `hello.lua`：

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

运行：

```bash
luamake lua hello.lua
```

> **注意**：必须使用 `luamake lua` 运行脚本，它会正确设置 Lua 路径以加载 tui 模块。

> 💡 **提示**：完整代码在 [examples/hello.lua](../../examples/hello.lua)，可以直接运行。

## 交互式应用

添加状态和用户输入：

```lua
local tui = require "tui"

-- 加载扩展组件
local extra = require "tui.extra"

local function Counter()
    local count, setCount = tui.useState(0)

    tui.useInput(function(_, key)
        if key.name == "up" then
            setCount(count + 1)
        elseif key.name == "down" then
            setCount(count - 1)
        elseif key.name == "q" then
            tui.useApp():exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 2,
        tui.Text { bold = true, "计数器" },
        tui.Text { "当前值: " .. count },
        extra.Newline {},
        tui.Text { dim = true, "↑ 增加  ↓ 减少  q 退出" }
    }
end

tui.render(Counter)
```

## 组件化

将 UI 拆分为可复用组件：

```lua
local tui = require "tui"

-- 按钮组件
local function Button(props)
    return tui.Box {
        borderStyle = props.active and "double" or "single",
        borderColor = props.active and "blue" or nil,
        padding = { left = 1, right = 1 },
        tui.Text { props.label }
    }
end

-- 主应用
local function App()
    local active, setActive = tui.useState(1)
    local buttons = {"保存", "取消", "帮助"}

    tui.useInput(function(_, key)
        if key.name == "left" then
            setActive(math.max(1, active - 1))
        elseif key.name == "right" then
            setActive(math.min(#buttons, active + 1))
        elseif key.name == "q" then
            tui.useApp():exit()
        end
    end)

    return tui.Box {
        flexDirection = "row",
        gap = 1,
        padding = 2,
        tui.map(buttons, function(label, i)
            return Button {
                key = i,
                label = label,
                active = i == active
            }
        end)
    }
end

tui.render(App)
```

## 下一步

- [布局系统](02-layout.md) - 学习 Flexbox 布局
- [组件详解](03-components.md) - 了解所有内置组件
- [Hooks 指南](04-hooks.md) - 掌握状态管理
- [焦点系统](05-focus.md) - 处理用户输入

## API 参考

- [核心 API](../api/core.md) - `tui/init.lua` 导出的组件、Hooks、工具函数
- [高级控件](../api/extra.md) - `tui/extra/` 交互组件
- [测试套件](../api/testing.md) - `tui/testing.lua` 离屏渲染与快照测试
