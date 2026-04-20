# 核心组件

tui.lua 核心组件无需额外加载，直接使用 `tui.Xxx` 访问。

## Text - 文本

基础文本显示：

```lua
tui.Text { "普通文本" }

-- 样式
tui.Text {
    color = "red",
    backgroundColor = "blue",
    bold = true,
    italic = true,
    underline = true,
    "样式化文本"
}

-- 文本截断
tui.Text {
    wrap = "truncate",  -- wrap | truncate | truncate-start | truncate-middle
    width = 10,
    "这是一段很长的文本"
}
```

## Box - 容器

布局容器，支持 Flexbox：

```lua
tui.Box {
    flexDirection = "row",
    justifyContent = "center",
    alignItems = "center",
    gap = 1,
    padding = 2,
    borderStyle = "single",
    borderColor = "green",

    tui.Text { "内容" }
}
```

## ErrorBoundary - 错误边界

捕获子树错误：

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

---

# 扩展组件

扩展组件位于 `tui/extra/` 目录，需要显式加载：

```lua
local extra = require "tui.extra"

-- 使用
extra.TextInput { ... }
extra.Spinner { ... }
```

## TextInput - 文本输入

```lua
local extra = require "tui.extra"

local function Form()
    local value, setValue = tui.useState("")

    return extra.TextInput {
        value = value,
        onChange = setValue,
        onSubmit = function()
            print("提交:", value)
        end,
        placeholder = "请输入...",
        width = 30,
        mask = "*",  -- 密码输入
    }
end
```

### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `value` | string | 当前值（受控组件） |
| `onChange` | function | 值变化回调 |
| `onSubmit` | function | 回车提交回调 |
| `placeholder` | string | 占位文本 |
| `width` | number | 宽度 |
| `mask` | string | 掩码字符（如密码输入） |
| `autoFocus` | boolean | 自动获得焦点 |

## Textarea - 多行文本输入

```lua
local extra = require "tui.extra"

extra.Textarea {
    value = text,
    onChange = setText,
    onSubmit = function()
        print("提交:", text)
    end,
    placeholder = "输入多行文本...",
    minHeight = 3,
    maxHeight = 10,
}
```

## Select - 选择列表

```lua
local extra = require "tui.extra"

local function Menu()
    local items = {
        { label = "选项1", value = 1 },
        { label = "选项2", value = 2 },
        { label = "选项3", value = 3 },
    }

    return extra.Select {
        items = items,
        limit = 5,              -- 显示行数限制
        indicator = ">",        -- 选中指示器
        onSelect = function(item)
            print("选中:", item.label)
        end,
        onHighlight = function(item)
            print("高亮:", item.label)
        end,
    }
end
```

### 键盘控制

- `↑/↓` - 移动高亮
- `Enter` - 选中
- `Home/End` - 跳转到首尾

## Spinner - 加载动画

```lua
local extra = require "tui.extra"

-- 默认类型
extra.Spinner { label = "加载中..." }

-- 指定类型
extra.Spinner {
    type = "dots",      -- dots | line | pointer | simple
    label = "处理中"
}

-- 自定义帧
extra.Spinner {
    frames = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
    interval = 80,
    label = "加载中"
}
```

### 预设类型

| 类型 | 效果 |
|------|------|
| `dots` | ⠋ ⠙ ⠹ ⠸ |
| `line` | \ \| / - |
| `pointer` | ◐ ◓ ◑ ◒ |
| `simple` | ← ↖ ↑ ↗ → ↘ ↓ ↙ |

## ProgressBar - 进度条

```lua
local extra = require "tui.extra"

-- 基础用法
extra.ProgressBar { value = 0.5 }  -- 50%

-- 完整配置
extra.ProgressBar {
    value = 0.75,
    width = 40,
    color = "green",
    backgroundColor = "gray",
    char = "█",           -- 填充字符
    left = "[",           -- 左边框
    right = "]",          -- 右边框
}
```

## Static - 静态列表

渲染大量静态内容：

```lua
local extra = require "tui.extra"

extra.Static {
    items = { "行1", "行2", "行3" },
    render = function(item, index)
        return tui.Text {
            color = index % 2 == 0 and "white" or "gray",
            ("%d. %s"):format(index, item)
        }
    end
}
```

## Newline - 换行

```lua
local extra = require "tui.extra"

tui.Box {
    flexDirection = "column",
    tui.Text { "第一行" },
    extra.Newline {},      -- 空行
    tui.Text { "第二行" }
}
```

## Spacer - 弹性空间

```lua
local extra = require "tui.extra"

tui.Box {
    flexDirection = "row",
    tui.Text { "左侧" },
    extra.Spacer {},       -- 推开两侧
    tui.Text { "右侧" }
}
```

---

# 自定义组件

创建可复用组件：

```lua
-- 定义组件
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
Card {
    title = "提示",
    color = "blue",
    "这是卡片内容"
}
```

或使用 `tui.component`：

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

---

# 组件组合示例

```lua
local extra = require "tui.extra"

local function App()
    return tui.Box {
        flexDirection = "column",
        padding = 2,

        -- 标题
        tui.Box {
            justifyContent = "center",
            tui.Text { bold = true, "用户管理系统" }
        },

        extra.Newline {},

        -- 表单
        tui.Box {
            flexDirection = "column",
            gap = 1,

            tui.Text { "用户名:" },
            extra.TextInput {
                placeholder = "输入用户名",
                width = 30
            },

            tui.Text { "邮箱:" },
            extra.TextInput {
                placeholder = "输入邮箱",
                width = 30
            }
        },

        extra.Newline {},

        -- 按钮行
        tui.Box {
            flexDirection = "row",
            gap = 1,
            tui.Box {
                borderStyle = "single",
                padding = { left = 2, right = 2 },
                tui.Text { "保存" }
            },
            tui.Box {
                borderStyle = "single",
                padding = { left = 2, right = 2 },
                tui.Text { "取消" }
            }
        }
    }
end
```
