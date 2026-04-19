# 示例程序

这些示例展示了 tui.lua 的各种功能。所有示例都可以通过以下方式运行：

```bash
luamake lua examples/示例名.lua
```

## 基础示例

### [hello.lua](hello.lua) - Hello World

最简单的 tui.lua 程序，展示基本的 Box 和 Text 组件。

```bash
luamake lua examples/hello.lua
```

### [counter.lua](counter.lua) - 计数器

带状态管理的计数器，展示 useState 和 useInput。

```bash
luamake lua examples/counter.lua
# 按键: ↑ 增加, ↓ 减少, q/Esc 退出
```

## 表单示例

### [login_form.lua](login_form.lua) - 登录表单

完整的登录表单，展示 TextInput、焦点系统和表单验证。

```bash
luamake lua examples/login_form.lua
# 按键: Tab 切换字段, Enter 提交, Esc 退出
```

### [wizard_form.lua](wizard_form.lua) - 多步骤向导

三步注册向导，展示条件渲染和多步骤流程。

```bash
luamake lua examples/wizard_form.lua
# 按键: Enter 继续, Esc 退出
```

## 列表示例

### [todo_list.lua](todo_list.lua) - 待办事项

可添加任务的待办列表，展示 Static 组件和列表渲染。

```bash
luamake lua examples/todo_list.lua
# 按键: 输入任务后 Enter 添加, Esc 退出
```

### [select_menu.lua](select_menu.lua) - 选项菜单

可选择的菜单列表，展示 Select 组件。

```bash
luamake lua examples/select_menu.lua
# 按键: ↑↓ 移动, Enter 选择, Esc 退出
```

## 数据展示

### [progress_demo.lua](progress_demo.lua) - 进度演示

进度条和加载动画，展示 ProgressBar 和 Spinner 组件。

```bash
luamake lua examples/progress_demo.lua
# 按键: Esc 退出
```

### [dashboard.lua](dashboard.lua) - 仪表盘

实时更新的系统监控面板，展示 useInterval 和动态数据。

```bash
luamake lua examples/dashboard.lua
# 按键: Esc 退出
```

### [chat_mock.lua](chat_mock.lua) - 聊天界面

模拟聊天应用，展示复杂布局和实时更新。

```bash
luamake lua examples/chat_mock.lua
```

## 学习路径

### 初学者

1. [hello.lua](hello.lua) - 了解基本结构
2. [counter.lua](counter.lua) - 学习状态和事件
3. [login_form.lua](login_form.lua) - 掌握表单和焦点

### 进阶

4. [todo_list.lua](todo_list.lua) - 列表渲染
5. [wizard_form.lua](wizard_form.lua) - 多步骤流程
6. [dashboard.lua](dashboard.lua) - 实时数据

## 创建自己的示例

参考模板：

```lua
-- my_example.lua
local tui = require "tui"

local function MyApp()
    local app = tui.useApp()

    tui.useInput(function(_, key)
        if key.name == "escape" then
            app:exit()
        end
    end)

    return tui.Box {
        tui.Text { "Hello!" }
    }
end

tui.render(MyApp)
```

运行：

```bash
luamake lua my_example.lua
```

## 文档对应

| 示例 | 相关文档 |
|------|----------|
| hello.lua | [快速开始](../docs/guide/01-quickstart.md) |
| counter.lua | [Hooks 指南](../docs/guide/04-hooks.md) |
| login_form.lua, wizard_form.lua | [焦点系统](../docs/guide/05-focus.md) |
| todo_list.lua, select_menu.lua | [组件详解](../docs/guide/03-components.md) |
| dashboard.lua, progress_demo.lua | [布局系统](../docs/guide/02-layout.md) |
| chat_mock.lua | 综合示例 |
