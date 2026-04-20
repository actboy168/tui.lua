# 布局系统

tui.lua 使用基于 CSS Flexbox 的布局系统。Box 的完整属性签名参见 [核心 API - Box](../api/core.md#box)。

## Box 组件

`Box` 是所有布局的基础容器：

```lua
tui.Box {
    -- 尺寸
    width = 40,
    height = 10,

    -- 布局方向
    flexDirection = "row",  -- "row" | "column"

    -- 子元素
    tui.Text { "子元素1" },
    tui.Text { "子元素2" }
}
```

## Flex 布局

### 方向

```lua
-- 水平排列（默认）
tui.Box {
    flexDirection = "row",
    tui.Text { "A" },
    tui.Text { "B" },
    tui.Text { "C" }
}
-- 结果: A B C

-- 垂直排列
tui.Box {
    flexDirection = "column",
    tui.Text { "A" },
    tui.Text { "B" },
    tui.Text { "C" }
}
-- 结果:
-- A
-- B
-- C
```

### 对齐

```lua
tui.Box {
    flexDirection = "column",
    height = 10,

    -- 主轴对齐（flexDirection 方向）
    justifyContent = "center",  -- flex-start | center | flex-end | space-between

    -- 交叉轴对齐
    alignItems = "center",      -- flex-start | center | flex-end | stretch

    tui.Text { "居中内容" }
}
```

### 间距

```lua
tui.Box {
    flexDirection = "row",
    gap = 2,  -- 子元素之间的间距

    tui.Text { "A" },  -- 位置 0
    tui.Text { "B" },  -- 位置 2
    tui.Text { "C" }   -- 位置 4
}
```

### 弹性空间

```lua
tui.Box {
    flexDirection = "row",
    width = 40,

    tui.Box {
        width = 10,
        tui.Text { "固定宽度" }
    },

    tui.Box {
        flex = 1,  -- 占据剩余空间
        tui.Text { "弹性宽度" }
    },

    tui.Box {
        flex = 2,  -- 占据两倍剩余空间
        tui.Text { "更多弹性宽度" }
    }
}
```

## 尺寸

### 固定尺寸

```lua
width = 40      -- 40 列
height = 10     -- 10 行
```

### 百分比

```lua
width = "50%"   -- 父容器宽度的 50%
height = "100%" -- 父容器高度的 100%
```

### 自动

```lua
-- 未设置 width/height 时，根据内容自动调整
-- 在 flex 容器中可使用 flex 属性分配空间
```

## 间距

### 内边距

```lua
tui.Box {
    -- 统一设置
    padding = 2,

    -- 分别设置
    padding = { top = 1, bottom = 1, left = 2, right = 2 },

    -- 简写（CSS 风格）
    padding = { top = 1, bottom = 1 },  -- 上下 1，左右 0

    tui.Text { "内容与边框的间距" }
}
```

### 外边距

```lua
tui.Box {
    marginTop = 1,
    marginBottom = 1,
    marginLeft = 2,
    marginRight = 2,

    -- 简写
    margin = 1,
    margin = { top = 1, left = 2 }
}
```

## 边框

```lua
tui.Box {
    -- 边框样式
    borderStyle = "single",   -- "single" | "double" | "round" | "bold"

    -- 边框颜色
    borderColor = "blue",

    -- 单边边框
    borderTop = true,
    borderBottom = false,

    tui.Text { "带边框的内容" }
}
```

边框样式效果：

```
single:  ┌─┐  double:  ╔═╗  round:  ╭─╮  bold:  ┏━┓
         │ │           ║ ║         │ │         ┃ ┃
         └─┘           ╚═╝         ╰─╯         ┗━┛
```

## 完整示例

```lua
local function LayoutDemo()
    return tui.Box {
        flexDirection = "column",
        height = "100%",

        -- 头部
        tui.Box {
            height = 3,
            borderStyle = "single",
            justifyContent = "center",
            alignItems = "center",
            tui.Text { bold = true, "应用标题" }
        },

        -- 主体
        tui.Box {
            flex = 1,
            flexDirection = "row",

            -- 侧边栏
            tui.Box {
                width = 20,
                borderStyle = "single",
                tui.Text { "导航" }
            },

            -- 内容区
            tui.Box {
                flex = 1,
                padding = 1,
                tui.Text { "主要内容区域" }
            }
        },

        -- 底部
        tui.Box {
            height = 1,
            tui.Text { dim = true, "按 q 退出" }
        }
    }
end
```

## 响应式布局

使用 `useWindowSize` 响应终端尺寸变化：

```lua
local function ResponsiveLayout()
    local size = tui.useWindowSize()

    -- 小屏幕使用垂直布局
    local direction = size.width < 60 and "column" or "row"

    return tui.Box {
        flexDirection = direction,
        tui.Box { flex = 1, tui.Text { "区域1" } },
        tui.Box { flex = 1, tui.Text { "区域2" } }
    }
end
```

## 常见问题

### 元素被截断

```lua
-- 添加 flexWrap 允许换行
tui.Box {
    flexDirection = "row",
    flexWrap = "wrap"
}
```

### 垂直居中

```lua
tui.Box {
    justifyContent = "center",  -- 水平居中
    alignItems = "center"       -- 垂直居中
}
```

### 固定底部

```lua
tui.Box {
    flexDirection = "column",

    tui.Box { flex = 1 },           -- 占据剩余空间
    tui.Box { height = 3 }          -- 固定在底部
}
```
