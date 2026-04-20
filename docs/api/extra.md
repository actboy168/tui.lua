# 高级控件

对应源码 `tui/extra/`，提供常用的交互组件。需要显式加载：

```lua
local extra = require "tui.extra"
```

---

## TextInput

单行文本输入。

```lua
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

### 示例

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
| `autoFocus` | boolean | 自动获得焦点（默认 true） |
| `focusId` | string | 焦点标识 |
| `focus` | boolean | false 禁用焦点 |

---

## Textarea

多行文本编辑器。

```lua
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

### 示例

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

---

## Select

选项列表，支持键盘导航。

```lua
extra.Select {
    items = { { label, value }, ... },
    onSelect = function(item),
    onHighlight = function(item),
    limit = number,          -- 显示行数
    indicator = string,      -- 选中指示器，默认 "❯"
}
```

### 示例

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
        limit = 5,
        indicator = ">",
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

| 按键 | 行为 |
|------|------|
| `↑/↓` | 移动高亮 |
| `Enter` | 选中当前项 |
| `Home/End` | 跳转到首尾 |

---

## Spinner

加载动画。

```lua
extra.Spinner {
    type = "dots" | "line" | "pointer" | "simple",
    label = string,
    frames = { string },     -- 自定义帧
    interval = number,       -- 帧间隔（毫秒）
}
```

### 示例

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

---

## ProgressBar

进度条。

```lua
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

### 示例

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
    char = "█",
    left = "[",
    right = "]",
}
```

---

## Static

静态列表，渲染大量静态内容。

```lua
extra.Static {
    items = { ... },
    render = function(item, index) -> element,
}
```

### 示例

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

---

## Newline

换行，在垂直布局中插入空行。

```lua
extra.Newline { count = 1 }  -- 默认换1行
```

### 示例

```lua
tui.Box {
    flexDirection = "column",
    tui.Text { "第一行" },
    extra.Newline {},      -- 空行
    tui.Text { "第二行" }
}
```

---

## Spacer

弹性空间，占据剩余空间推开两侧元素。

```lua
extra.Spacer {}
```

### 示例

```lua
tui.Box {
    flexDirection = "row",
    tui.Text { "左侧" },
    extra.Spacer {},       -- 推开两侧
    tui.Text { "右侧" }
}
```
