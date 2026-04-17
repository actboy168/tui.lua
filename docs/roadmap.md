# tui.lua 路线图

本文件是 tui.lua 的主路线图，由用户与助手共同维护。**新增/调整规划时先改这里**，
实施完毕再回来打勾。当前待办的细项由会话内任务列表（TaskCreate）辅助跟踪，不在
此处重复罗列。

---

## 已完成

### Stage 1 — 骨架：静态渲染 (`e325939`)
- luamake 构建系统接入，`lm:lua_dll "yoga"` + `lm:lua_dll "tui_core"`
- `tui_core.c` 聚合入口 + `terminal.c`（Win/POSIX raw I/O + IME）
- Lua 框架层最小版：`tui.Box` / `tui.Text` / `tui.render`
- `examples/hello.lua` 冒烟

### Stage 2 — 状态与重绘 (`9f774f2`)
- `tui/scheduler.lua`：可注入 now/sleep 的平台无关调度器
- `tui/hooks.lua`：`useState` / `useEffect` / `useInterval` / `useTimeout` / `useApp`
- `tui/reconciler.lua`：React-like 重渲染 + 实例复用
- `tui/screen.lua`：行级 diff 输出增量 ANSI
- 计数器示例

### Stage 3 — 键盘输入：useInput + 按键解析 (`cd5841a`)
- `src/tui_core/keys.c`：CSI / SS3 / UTF-8 / 修饰符解析
- `tui/input.lua`：订阅/派发总线；`tui.useInput` hook
- 主循环串联 read_raw → keys.parse → dispatch
- 带键盘的计数器示例

### Stage 4 — 文本测宽 + 软包装 + Static + TextInput + useWindowSize (`91b37e2`)
- `src/tui_core/wcwidth.c`：Unicode 15.1 EastAsianWidth + emoji 硬编码表
- `tui/text.lua`：UTF-8 iter / display_width / soft-wrap
- 两遍 Yoga 布局支持 wrap 后高度反写
- `tui/builtin/static.lua`：Ink 风格只增日志区
- `tui/builtin/text_input.lua`：内置 TextInput + `_cursor_offset` + IME 跟随
- `tui/resize.lua` + `useWindowSize`
- `examples/chat_mock.lua`：模拟 AI chat
- 88/88 测试通过

### Stage 5A — 统一离屏测试 harness `tui.testing`
- `tui/testing.lua`：`render / rerender / type / press / dispatch / frame / row / rows / width / height / tree / ansi / clear_ansi / advance / resize / unmount` + `mount_bare` + `find_text_with_cursor`
- 4 个现有测试全部迁移到新 harness（test_static / test_text_input / test_reconciler）
- 新增 `test/test_chat_flow.lua` 端到端集成测试（替代临时的 `_chat_smoke.lua`）
- **顺带修掉 `tui/element.lua` 的 Box children nil 截断 bug**（table constructor 里 `cond and X or nil` 会让后续孩子被 ipairs 丢弃）
- 89/89 测试通过

---

## 正在进行

_暂无_

---

## 后续候选

### Stage 5B — 快照测试
- `h:match_snapshot(name)` → `test/__snapshots__/<name>.txt`
- 首次写入，二次 diff；`TUI_UPDATE_SNAPSHOTS=1` 批量更新
- 为 chat_mock 写 2~3 个快照用例
- 纯文本格式（每行一屏幕行），人肉可读，git diff 友好

### Stage 5C — 焦点与高阶组件
- `useFocus` / `useFocusManager`（Ink 兼容）
- `useStdout` / `useStderr`
- `form.lua`（TextInput 组合 + 导航）
- 基于 key prop 的 reconciler diff（S2.2，list 重排）
- `ErrorBoundary`（S2.3）
- 组件身份清洁性（S2.9）

### Stage 6 — 渲染性能与打磨
- cell-level diff（S2.5，比行级 diff 更细）
- alternate screen buffer
- README / API 文档
- S2.7 / S2.8 / S2.10（未决议细项）

---

## 架构改进项 backlog（非阻塞，穿插推进）

### R1. scheduler.step() 正式 API
当前 `tui.testing:advance(ms)` 借用 `scheduler._timers()` 私表做 timer 循环，
源码抄自 `test/test_scheduler.lua` 的 `tick_to()`。应当把这段提升为公共
`scheduler.step(now)`，消除重复、给用户一个正式的"外部驱动"入口。

### R2. paint 链路显式 terminal 注入
`tui_core.terminal` 是进程单例，`tui.testing` 靠整表替换+还原来做 mock，
限制了同进程内多 harness 并存。改为 `paint(root, ctx)` 接受 `ctx.terminal`，
让测试 harness 直接传 fake，无需全局劫持。

### R3. ltest 并行 runner 兼容
若未来 ltest 改并行，R1+R2 必须已完成，否则测试互相踩单例。目前在
`tui/testing.lua` 文件头注释里记录警告。

---

## 维护约定

- 新增 Stage/改进项：直接编辑本文件，在 "后续候选" / "backlog" 里加条目
- 进入实施：移到 "正在进行"，同时 TaskCreate 拆会话级子任务
- 完成：移到 "已完成"，标注 commit hash
- 不做的想法也记录（"非目标" 段），避免反复纠结
