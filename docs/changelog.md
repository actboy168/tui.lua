# tui.lua changelog

每个 stage 列"外部可见能力"，不写实现细节（细节见代码、git log 和
`memory/stage*.md`）。路线图见 [roadmap.md](roadmap.md)。

---

## Stage 19 — Select + ProgressBar
- `Select { items, onSelect, onChange?, initialIndex?, indicator?, highlightColor?, renderItem?, limit?, focusId?, autoFocus?, isDisabled? }`
- `ProgressBar { value, width?, color?, chars? }`

## Stage 18 — Spinner + useAnimation
- `useAnimation({ interval, isActive }) -> { frame, time, delta, reset }`
- `Spinner { type="dots"|"line", label, color, frames=?, interval=? }`
- `scheduler.now()` / `scheduler.step(now)` 公开

## Stage 17 — Dev-mode 三件套
- `tui.setDevMode(bool)`
- Hook 顺序校验；render 期 `setState` / `dispatch` 警告；3+ 子节点缺 `key` 警告
- `testing.capture_stderr(fn)`；测试 harness 未预期 dev 警告升级为 fatal

## Stage 16 — Hook 家族补齐
- `useMemo` / `useCallback` / `useRef` / `useReducer`
- `createContext` + `ctx.Provider` + `useContext`
- `useLatestRef` 公开

## Stage 15 — 技术债清理
- `test/test_*.lua` 自动注册
- `screen.c` 业务解析下沉到 Lua
- `tui_core.text.wrap`（C 实现软换行）
- Ctrl+C / Ctrl+D 退出改为语义 key 匹配
- `screen.put` cluster 长度校验 + slab 支持 >8 字节字符
- `array_remove` / `array_insert` util
- hooks / reconciler 统一 `_ensure_deps()`

## Stage 14 — ErrorBoundary 完善
- `[tui:fatal]` 前缀协议
- `useEffect` / `useInput` / `useFocus` 回调错误冒泡到最近 boundary
- `fallback` 支持 `function(err, reset)`
- `useErrorBoundary()`

## Stage 13 — 焦点系统完善
- `useFocus` 重复 id 硬报错
- 严格 Ink `autoFocus` 语义
- `isActive` prop；`id` / `isActive` 热更新

## Stage 12 — Grapheme cluster
- C 层 `grapheme_next`（Hangul / ZWJ / regional-indicator / VS15/16）
- `text.iter` / `TextInput` 方向键与 backspace 按 cluster 跳

## Stage 11 — SGR 增量 diff
- 属性位增量 emit；状态跨 CUP 继承；末尾 reset 安全网

## Stage 10 — Text SGR / 颜色
- Text/Box `color` / `backgroundColor` / `bold` / `dim` / `underline` / `inverse`
- ANSI-16 前/背景色

## Stage 9 — 渲染后端下沉到 C
- `tui_core.screen`：cell 缓冲、双缓冲、行 ring pool
- cell 级 diff + 段合并

## Stage 8 — 基于 key 的 reconciler diff
- Box / Text / ErrorBoundary 支持 `key`
- 同父同 key 硬报错

## Stage 7 — ErrorBoundary 错误隔离
- `tui.ErrorBoundary { fallback, ... }`
- 顶层兜底错误屏

## Stage 6 — 焦点管理（Ink 兼容）
- `useFocus` / `useFocusManager`；Tab / Shift-Tab
- `TextInput` `focusId` / `autoFocus`

## Stage 5B — 快照测试
- `Harness:match_snapshot(name)` + `__snapshots__/`
- `TUI_UPDATE_SNAPSHOTS=1` 覆写

## Stage 5A — 离屏测试 harness
- `tui/testing.lua`：`render` / `type` / `press` / `frame` / `advance` / `resize` / `unmount` / `tree` / `ansi`

## Stage 4 — 文本与内置组件
- C 层 wcwidth（Unicode 15.1 + emoji）
- 软包装 + 两遍 Yoga 布局
- `Static` / `TextInput`（含 IME 跟随）
- `useWindowSize`

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
