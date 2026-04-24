# 高级控件

对应源码 `tui/extra/`，提供常用的交互组件。需要显式加载：

```lua
local extra = require "tui.extra"
```

如果你要实现自定义输入控件，也可以直接复用共享编辑原语：

```lua
local editing = require "tui.extra.editing"
```

也可以从聚合入口获取同一个模块：

```lua
local extra = require "tui.extra"
local editing = extra.editing
```

## editing

`tui.extra.editing` 提供 grapheme-aware 的编辑原语，适合实现自定义输入控件，包括：
- 光标/按词移动
- 单行与多行删除/插入
- 选区判断、删除、替换
- 多行选区替换
- 选中文本提取与高亮 span 构造

### 最小示例

```lua
local tui = require "tui"
local editing = require "tui.extra.editing"

local function MiniInput(props)
    local value = props.value or ""
    local chars = editing.to_chars(value)
    local caret, setCaret = tui.useState(#chars)

    local f = tui.useFocus {
        on_input = function(input, key)
            if key.name == "left" then
                setCaret(math.max(0, caret - 1))
            elseif key.name == "right" then
                setCaret(math.min(#chars, caret + 1))
            elseif key.name == "char" and input ~= "" then
                local new_chars = editing.insert_text(chars, caret, input)
                if new_chars and props.onChange then
                    props.onChange(editing.chars_to_string(new_chars))
                end
            end
        end,
    }

    local cursor = tui.useCursor()
    if f.isFocused then
        cursor.setCursorPosition {
            x = editing.prefix_width(chars, caret),
            y = 0,
        }
    end
    local text = tui.Text { value }
    return text
end
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
    features = {
        undoRedo = boolean,      -- 默认 true
        copyCut = boolean,       -- 默认 true
        selectAll = boolean,     -- 默认 true
        wordOps = boolean,       -- 默认 true
        killOps = boolean,       -- 默认 true
        imeComposing = boolean,  -- 默认 true
        paste = boolean,         -- 默认 true
        submit = boolean,        -- 默认 true
        selection = boolean,     -- 默认 true
    },
    keymap = {
        ["ctrl+s"] = "submit",   -- 绑定到动作
        ["enter"] = false,       -- 移除默认绑定
    },
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
| `features.undoRedo` | boolean | 是否启用撤销/重做（默认 true） |
| `features.copyCut` | boolean | 是否启用复制/剪切快捷键（默认 true） |
| `features.selectAll` | boolean | 是否启用全选（默认 true） |
| `features.wordOps` | boolean | 是否启用按词移动/删除（默认 true） |
| `features.killOps` | boolean | 是否启用 `Ctrl+U / Ctrl+K`（默认 true） |
| `features.imeComposing` | boolean | 是否显示 IME 预编辑态（默认 true） |
| `features.paste` | boolean | 是否响应 Paste（默认 true） |
| `features.submit` | boolean | 是否响应提交按键（默认 true） |
| `features.selection` | boolean | 是否启用选区行为（默认 true） |
| `keymap` | table | 可选快捷键覆盖表，键是按键字符串，值是动作名或 `false` |

### 常用按键

| 按键 | 行为 |
|------|------|
| `Left / Right` | 左右移动光标 |
| `Shift+Left / Shift+Right` | 扩展或收缩选区 |
| `Shift+Home / Shift+End` | 选到行首 / 行尾 |
| `Home / End` | 跳到行首 / 行尾 |
| `Ctrl+A` | 全选 |
| `Ctrl+E` | 跳到行尾 |
| `Ctrl+Left / Ctrl+Right` | 按词移动 |
| `Ctrl+U / Ctrl+K` | 删除到行首 / 行尾 |
| `Ctrl+W / Ctrl+Backspace` | 删除前一个词 |
| `Ctrl+Delete` | 删除后一个词 |
| `输入 / Paste / IME confirm` | 有选区时替换选区 |
| `Ctrl+Shift+C / Meta+C` | 复制选区 |
| `Ctrl+X / Meta+X` | 剪切选区 |
| `Ctrl+Z / Ctrl+Y` | 撤销 / 重做 |
| `Enter` | 提交 |
| `Paste` | 粘贴，换行会被替换为空格 |

选区会直接以反色样式高亮显示。

可通过 `features` 分别关闭这些行为，例如：

```lua
features = {
    undoRedo = false,
    copyCut = false,
    selectAll = false,
    wordOps = false,
    killOps = false,
    imeComposing = false,
    paste = false,
    submit = false,
    selection = false,
}
```

也可以通过 `keymap` 覆盖默认快捷键。推荐使用 **`["按键"] = "动作"`** 的形式，这样同一个按键最终只能绑定到一个动作：

```lua
keymap = {
    ["ctrl+s"] = "submit",
    ["enter"] = false,
    ["ctrl+q"] = "selectAll",
}
```

支持的动作名包括：
`moveLeft`、`moveRight`、`moveUp`、`moveDown`、`lineStart`、`lineEnd`、`docStart`、`docEnd`、`deleteBackward`、`deleteForward`、`copy`、`cut`、`undo`、`redo`、`selectAll`、`wordLeft`、`wordRight`、`deleteWordLeft`、`deleteWordRight`、`killLeft`、`killRight`、`submit`、`newline`。

其中 `false` 表示移除某个默认绑定；`features` 仍然负责开关动作本身，`keymap` 只负责把按键映射到动作。

默认情况下，连续输入、连续删除会合并到更自然的 undo group；光标移动、提交、复制/剪切、undo/redo 等动作会切断当前合并段。

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
    enterBehavior = "submit" | "newline",
    features = {
        undoRedo = boolean,      -- 默认 true
        copyCut = boolean,       -- 默认 true
        selectAll = boolean,     -- 默认 true
        wordOps = boolean,       -- 默认 true
        killOps = boolean,       -- 默认 true
        imeComposing = boolean,  -- 默认 true
        paste = boolean,         -- 默认 true
        submit = boolean,        -- 默认 true
        selection = boolean,     -- 默认 true
    },
    keymap = {
        ["ctrl+s"] = "submit",
        ["ctrl+j"] = "newline",
        ["enter"] = false,
    },
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

### 常用按键

| 按键 | 行为 |
|------|------|
| `Left / Right` | 左右移动，跨行时自动跳转 |
| `Shift+Left / Shift+Right` | 扩展或收缩选区 |
| `Up / Down` | 按显示列上下移动 |
| `Shift+Up / Shift+Down` | 按显示列扩展多行选区 |
| `Home / End` | 跳到当前行行首 / 行尾 |
| `Shift+Home / Shift+End` | 选到当前行行首 / 行尾 |
| `Ctrl+Home / Ctrl+End` | 跳到全文开头 / 末尾 |
| `Ctrl+A` | 全选 |
| `Ctrl+E` | 跳到当前行行尾 |
| `Ctrl+Left / Ctrl+Right` | 在当前行内按词移动；跨行边界时跳到相邻行词边界 |
| `Ctrl+U / Ctrl+K` | 删除到当前行行首 / 行尾 |
| `Ctrl+W / Ctrl+Backspace` | 删除当前行中光标前一个词 |
| `Ctrl+Delete` | 删除当前行中光标后的一个词 |
| `输入 / Paste / IME confirm` | 有选区时替换选区 |
| `Ctrl+Shift+C / Meta+C` | 复制选区 |
| `Ctrl+X / Meta+X` | 剪切选区 |
| `Ctrl+Z / Ctrl+Y` | 撤销 / 重做 |
| `Enter` | 默认提交；`enterBehavior = "newline"` 时插入换行 |
| `Shift+Enter` | 插入换行 |
| `Ctrl+Enter` | 提交 |
| `IME composing / confirm / escape` | 显示预编辑、确认插入、取消预编辑 |

选区会直接以反色样式高亮显示。

`Textarea` 同样支持上面的 `features` 开关集合。

`Textarea` 也支持相同的 `keymap` 机制。默认情况下：
- `enterBehavior = "submit"` 时，`Enter` 和 `Ctrl+Enter` 触发 `submit`，`Shift+Enter` 触发 `newline`
- `enterBehavior = "newline"` 时，`Enter` 和 `Shift+Enter` 触发 `newline`，`Ctrl+Enter` 触发 `submit`
- 基础导航/编辑键（如 `Left/Right/Up/Down`、`Home/End`、`Backspace/Delete`）也可通过 `keymap` 重新绑定或移除

---

## Link

终端超链接组件。`href` 表示终端原生跳转目标，`onClick` 是应用层语义回调。plain-label 路径走 `RawAnsi`，rich-children 路径走 `Transform` 子树超链接处理。

```lua
extra.Link {
    href = "https://example.com",
    onClick = function(ev)
        -- ev.href
        -- ev.source == "mouse" or "keyboard"
    end,
    "docs",
}
```

### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `href` | string | 非空单行字符串；用于终端原生超链接 |
| `onClick` | function | 可选语义回调；鼠标按下和键盘 `Enter` 都会触发，`ev.source` 区分 `"mouse"` / `"keyboard"` |
| `label` | string | 显式单行文本；与 children 二选一 |
| `children` | string / element... | 可混合文本和元素子树，支持 richer children 写法 |
| `autoFocus` | boolean | 仅在存在 `onClick` 且未禁用时生效 |
| `focusId` / `id` | string | 焦点标识 |
| `isDisabled` | boolean | 禁用后不触发 `onClick`，也不输出 OSC 8 |
| `color` / `backgroundColor` / `bold` / `italic` / `underline` / `strikethrough` / `inverse` / `dim` / `dimColor` | mixed | plain-label 路径的文本样式，默认蓝色下划线；rich children 建议在子树内显式控制样式 |
| 其他 `Box` props | table | 透传给外层 `Box`，可用于布局 |

### 说明

- `href` 和 `label` 不能包含 ESC、BEL 或换行；rich children 里的直接字符串子节点不能包含 ESC/BEL
- `Link.onClick` 是高层语义回调；底层宿主鼠标事件名是 `onMouseDown`
- rich children 可写成类似 `"My ", tui.Text { color = "cyan", "Website" }`；终端原生超链接会覆盖整棵子树
- 应用只能知道组件收到了激活事件，不能知道终端是否真的打开了 `href`
- 示例见 [`examples/link.lua`](../../examples/link.lua)

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
