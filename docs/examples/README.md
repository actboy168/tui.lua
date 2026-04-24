# 示例代码

所有示例代码在 [examples/](../../examples/) 目录下，使用 `luamake lua` 运行。

## 快速链接

| 示例 | 文件 | 涉及 API |
|------|------|----------|
| Hello World | [examples/hello.lua](../../examples/hello.lua) | Box, Text, render |
| 计数器 | [examples/counter.lua](../../examples/counter.lua) | useState, useInput, useApp |
| 登录表单 | [examples/login_form.lua](../../examples/login_form.lua) | TextInput, useFocus |
| 待办事项 | [examples/todo_list.lua](../../examples/todo_list.lua) | TextInput, Static |
| 向导表单 | [examples/wizard_form.lua](../../examples/wizard_form.lua) | 多步骤焦点导航 |
| 选项菜单 | [examples/select_menu.lua](../../examples/select_menu.lua) | Select |
| 进度演示 | [examples/progress_demo.lua](../../examples/progress_demo.lua) | Spinner, ProgressBar |
| 仪表盘 | [examples/dashboard.lua](../../examples/dashboard.lua) | useInterval, 动态更新 |
| Link 组件 | [examples/link.lua](../../examples/link.lua) | extra.Link, href, onClick |
| RawAnsi 超链接 | [examples/raw_ansi.lua](../../examples/raw_ansi.lua) | RawAnsi, SGR, OSC 8 |

## 运行示例

```bash
luamake lua examples/hello.lua
luamake lua examples/counter.lua
luamake lua examples/link.lua
luamake lua examples/raw_ansi.lua
```
