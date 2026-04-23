# 工作流约束

## 构建必须走 PowerShell

本机 `luamake` 必须从 PowerShell 调用，不能通过 bash/cmd。

**Why:** Git Bash / `cmd //c ...` 下 `luamake` 在 spawn ninja 时报 `subprocess::spawn: (sys:2) 系统找不到指定的文件` — 继承的 PATH 找不到 `ninja.exe`。PowerShell 下 luamake 能从 MSVC 的 `CommonExtensions/.../CMake/Ninja` 目录正确解析。

**How to apply:** 任何 `luamake`、`luamake remake`、`luamake lua …`、`luamake test` — 走 PowerShell。Bash 仍可用于 git、ls、文件查看等；只有 luamake 构建管线必须走 PowerShell。

## 不要在 Windows 上用 stdin 管道验证 TUI demo

不要用 `"q" | luamake lua examples/foo.lua` 之类的 shell 管道驱动主循环。应使用离屏渲染 + 手动驱动定时器来验证。

**Why:** tui.lua 主循环通过 `terminal.set_raw(true)` 启用 raw mode 并每帧轮询 `terminal.read()`。Windows 上当 stdin 是管道（非真实 console）时，`ReadConsoleInput` 语义与 TTY 模式不同 — 'q' 字节经常无法到达 `read`，导致无限循环必须 `taskkill`。

**How to apply:** 验证 demo 时，写一个临时脚本：
1. `require` 组件（mirror examples/<demo>.lua body）
2. 通过 `reconciler.render` 生成 host tree
3. 强制 `tree.props.width/height = W, H` 后调用 `layout.compute(tree)`
4. 调用 `renderer.render_rows(tree, W, H)` 检查输出
5. 模拟时间：遍历 `scheduler._timers()` 调用各 `t.fn()`

需要交互式按键行为时，绕过主循环直接调用 input parser 传入合成字节串。此方式也适用于任何平台的 CI。

## 写 Example 的验证清单

写 example / demo / 组合多个 builtin 的代码时必须走以下 3 步，否则高概率出错。

### 1. 写代码前先抄参照

在 `examples/` 里找一个最接近目标的已有脚本（chat_mock.lua / counter.lua / hello.lua），先把 prop 名抄下来，而不是凭 "Ink 一般怎么叫" 写。

本框架对齐 Ink 但不完全一致：
- `border` 不是 `borderStyle`
- `color` 既是文本色也是边框色，没有 `borderColor`
- Yoga 默认 `flexDirection="column"`，要横排必须显式写 `flexDirection="row"`
- `flex=N` 不支持，必须用 `flexGrow=1`

### 2. 写代码前检查已知约束

`docs/decisions/` 里的约束往往正是容易被忽略的。尤其注意：
- 只能用 `flexGrow` / `flexShrink` / `flexBasis`，没有 `flex` shorthand
- TextInput 测试里用 `h:type` 而不是单发 dispatch
- dev-mode：3+ 子节点必须每个带 key
- Spinner 无 isActive，用条件渲染控制生命周期

### 3. 写完立即 harness dump 一次

`loadfile` 只能挡语法错，逮不到布局 / hook 顺序 / API 名字静默失效。写完 example 后立即用 testing harness 渲染并 dump 24 行，肉眼过一遍再交给用户。

### hook-in-function 注意事项

reconciler 已支持函数自动包装为组件（`Box { MyComponent }` 中的函数会自动被识别为组件元素）。但如果你在 plain function 里直接调用 hook（`useState` / `useContext` 等），hook slot 会挂到调用方 instance 上，条件渲染时触发 hook count mismatch fatal。

安全做法是用 `tui.component(fn)` 或 `{ kind = "component", fn = Impl, props = props }` 显式包装含 hook 的函数。
