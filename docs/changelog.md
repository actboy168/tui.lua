# tui.lua changelog

每个 stage 列"外部可见能力"，不写实现细节（细节见代码、git log 和
`memory/stage*.md`）。路线图见 [roadmap.md](roadmap.md)。

---

## Stage 17 — Dev-mode 三件套
- `tui.setDevMode(bool)` 开关（默认关，测试 harness 自动启用）
- Hook 顺序校验：hook 数量或类型在两次 render 间变化即抛 `[tui:fatal]`
- Render 期间 `setState` / `dispatch` 同步调用发 `[tui:dev]` stderr 警告
- 3+ element 子节点中任一缺 `key` 发 `[tui:dev]` stderr 警告（对齐 Ink/React DevTools；按父路径每次 render 去重）
- 所有 `[tui:dev]` 告警带源位置前缀 `basename.lua:NN:`（跳过框架与测试 runner 栈帧）
- Fail-on-warn：测试 harness 在 unmount 时把未预期的 dev 警告升级为 `[tui:fatal]`
- `testing.capture_stderr(fn)`：opt-in stderr 捕获器，用于断言预期警告（支持嵌套）

## Stage 16 — Hook 家族补齐
- `useMemo(fn, deps)` / `useCallback(fn, deps)` / `useRef(initial)` / `useReducer(reducer, initial[, init])`
- `createContext(default)` + `ctx.Provider { value=..., children }` + `useContext(ctx)`（支持嵌套就近优先、兄弟 context 独立）
- `useLatestRef` 公开化（原为 `hooks.lua` 内部工具）

## Stage 15 — 技术债清理
- `test/test_*.lua` glob 自动注册（新测试不再改两处）
- `screen.c` 业务解析下沉到 Lua：C 侧 `put` / `put_border` / `draw_line` 接收预打包的 `fg_bg` / `attrs`
- `text.wrap` 软换行改为 C 实现（`tui_core.text.wrap`），每帧热路径不再走 Lua
- Ctrl+C / Ctrl+D 退出改为语义 key 匹配（粘贴 0x03 字节不再误退出）
- `screen.put` cluster 长度 256B 校验；slab 路径完善（支持 >8 字节字符）
- `TextInput` 数组操作提 `array_remove` / `array_insert` util
- hooks / reconciler 统一 `_ensure_deps()`，去掉散落 lazy require

## Stage 14 — ErrorBoundary 完善
- `[tui:fatal]` 前缀协议（`reconciler.fatal` / `is_fatal`），编程 bug 不再被 boundary 吞掉
- `useEffect` body / cleanup / `_unmount` 错误冒泡到最近 boundary
- `useInput` / `useFocus` 回调错误冒泡
- `fallback` 支持 `function(err, reset)` 形式，reset 清错 + 触发重绘
- `useErrorBoundary()` 读最近祖先 Boundary 状态

## Stage 13 — 焦点系统完善
- `useFocus` 重复 id 硬报错（去掉静默 `#seq` 后缀）
- 严格 Ink 语义：只有显式 `autoFocus=true` 才获焦
- 新增 `isActive` prop，支持 `id` / `isActive` 热更新
- `TextInput` `focus=false` 合并到 useFocus 单一路径

## Stage 12 — Grapheme cluster
- C 层 `grapheme_next`（Hangul / ZWJ / regional-indicator / VS15/16）
- `text.iter` / `TextInput` 方向键与 backspace 按 cluster 跳

## Stage 11 — SGR 增量 diff
- 按属性位增量 emit，状态跨 CUP 继承
- 末尾保留一次 reset 做安全网

## Stage 10 — Text SGR / 颜色
- Text/Box 接受 `color` / `backgroundColor` / `bold` / `dim` / `underline` / `inverse`
- ANSI-16 前/背景色

## Stage 9 — 渲染后端下沉到 C
- `tui_core.screen`：cell 缓冲、双缓冲、行 ring pool
- cell 级 diff + 段合并，`rows()` 零拷贝返回

## Stage 8 — 基于 key 的 reconciler diff
- Box / Text / ErrorBoundary 支持 `key` prop，同层重排不 remount
- 同父同 key 硬报错

## Stage 7 — ErrorBoundary 错误隔离
- `tui.ErrorBoundary { fallback, ... }`；fallback 再崩降级为空
- 顶层兜底错误屏，不会崩事件循环

## Stage 6 — 焦点管理（Ink 兼容）
- `useFocus` / `useFocusManager`，Tab / Shift-Tab 切换
- `TextInput` 走 useFocus，新增 `focusId` / `autoFocus` prop

## Stage 5B — 快照测试
- `Harness:match_snapshot(name)` + `__snapshots__/` 目录
- 带 context 的逐行 diff，`TUI_UPDATE_SNAPSHOTS=1` 覆写

## Stage 5A — 离屏测试 harness
- `tui/testing.lua`：render / type / press / frame / advance / resize / unmount / tree / ansi 等
- 现有测试迁移到 harness + `test_chat_flow` 端到端用例

## Stage 4 — 文本与内置组件
- C 层 wcwidth（Unicode 15.1 EastAsianWidth + emoji）
- 软包装 + 两遍 Yoga 布局
- 内置 `Static` / `TextInput`（含 IME 跟随）
- `useWindowSize` + chat_mock 示例

## Stage 3 — 键盘输入
- C 层按键解析（CSI / SS3 / UTF-8 / 修饰符）
- `tui/input.lua` 订阅总线 + `useInput` hook
- `useEffect` 任意依赖数组 + 浅比较

## Stage 2 — 状态与重绘
- `scheduler` / `reconciler` / `screen` 三件套
- `useState` / `useEffect` / `useInterval` / `useTimeout` / `useApp`

## Stage 1 — 骨架：静态渲染
- luamake 构建接入 `yoga` 和 `tui_core` C 模块
- `tui.Box` / `tui.Text` / `tui.render` 可跑 hello 示例
