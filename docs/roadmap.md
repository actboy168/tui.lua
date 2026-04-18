# tui.lua 路线图

本文件是 tui.lua 的主路线图，由用户与助手共同维护。**新增/调整规划时先改这里**，
实施完毕再回来打勾。当前待办的细项由会话内任务列表（TaskCreate）辅助跟踪，不在
此处重复罗列。

---

## 已完成

### Stage 1 — 骨架：静态渲染
- luamake 构建接入 `yoga` 和 `tui_core` C 模块
- `tui.Box` / `tui.Text` / `tui.render` 可跑 hello 示例

### Stage 2 — 状态与重绘
- `scheduler` / `reconciler` / `screen` 三件套
- `useState` / `useEffect` / `useInterval` / `useTimeout` / `useApp`

### Stage 3 — 键盘输入
- C 层按键解析（CSI / SS3 / UTF-8 / 修饰符）
- `tui/input.lua` 订阅总线 + `useInput` hook
- `useEffect` 任意依赖数组 + 浅比较

### Stage 4 — 文本与内置组件
- C 层 wcwidth（Unicode 15.1 EastAsianWidth + emoji）
- 软包装 + 两遍 Yoga 布局
- 内置 `Static` / `TextInput`（含 IME 跟随）
- `useWindowSize` + chat_mock 示例

### Stage 5A — 离屏测试 harness
- `tui/testing.lua`：render / type / press / frame / advance / resize / unmount / tree / ansi 等
- 现有测试迁移到 harness + `test_chat_flow` 端到端用例

### Stage 5B — 快照测试
- `Harness:match_snapshot(name)` + `__snapshots__/` 目录
- 带 context 的逐行 diff，`TUI_UPDATE_SNAPSHOTS=1` 覆写

### Stage 6 — 焦点管理（Ink 兼容）
- `useFocus` / `useFocusManager`，Tab / Shift-Tab 切换
- `TextInput` 走 useFocus，新增 `focusId` / `autoFocus` prop

### Stage 7 — ErrorBoundary 错误隔离
- `tui.ErrorBoundary { fallback, ... }`；fallback 再崩降级为空
- 顶层兜底错误屏，不会崩事件循环

### Stage 8 — 基于 key 的 reconciler diff
- Box / Text / ErrorBoundary 支持 `key` prop，同层重排不 remount
- 同父同 key 硬报错

### Stage 9 — 渲染后端下沉到 C
- `tui_core.screen`：cell 缓冲、双缓冲、行 ring pool
- cell 级 diff + 段合并，`rows()` 零拷贝返回

### Stage 10 — Text SGR / 颜色
- Text/Box 接受 `color` / `backgroundColor` / `bold` / `dim` / `underline` / `inverse`
- ANSI-16 前/背景色

### Stage 11 — SGR 增量 diff
- 按属性位增量 emit，状态跨 CUP 继承
- 末尾保留一次 reset 做安全网

### Stage 12 — Grapheme cluster
- C 层 `grapheme_next`（Hangul / ZWJ / regional-indicator / VS15/16）
- `text.iter` / `TextInput` 方向键与 backspace 按 cluster 跳

### Stage 13 — 焦点系统完善
- `useFocus` 重复 id 硬报错（去掉静默 `#seq` 后缀）
- 严格 Ink 语义：只有显式 `autoFocus=true` 才获焦
- 新增 `isActive` prop，支持 `id` / `isActive` 热更新
- `TextInput` `focus=false` 合并到 useFocus 单一路径

### Stage 14 — ErrorBoundary 完善
- `[tui:fatal]` 前缀协议（`reconciler.fatal` / `is_fatal`），编程 bug 不再被 boundary 吞掉
- `useEffect` body / cleanup / `_unmount` 错误冒泡到最近 boundary
- `useInput` / `useFocus` 回调错误冒泡
- `fallback` 支持 `function(err, reset)` 形式，reset 清错 + 触发重绘
- `useErrorBoundary()` 读最近祖先 Boundary 状态

---

## 正在进行

_暂无_

---

## 未完成 · 按类别

### 功能增强

**高阶组件**
- `useStdout` / `useStderr`
- `form.lua`：多输入框 + 导航

**reconciler 增强**
- 组件身份清洁性的测试覆盖（行为已实现：同一位置 `inst.fn ~= fn` 时 unmount 旧实例 + new，但目前没专门的单元测试）

### 渲染性能与稳定性

- alternate screen buffer（类 vim 进出全屏）
- `put` 的 cluster 长度校验（防止恶意长字符串爆 slab）
- truecolor / 256 色扩展：cell_t 扩到 16 字节 or 引入独立 style pool，给 `fg / bg` 加 16/24 bit 值
- Text per-run inline style：`Text { "plain ", {text="red", color="red"} }` 形式，wrap 需沿 run 边界切片
- Ink 式颜色继承：父 Box 的 color prop 自动透到子 Text（当前每个 Text 独立）

### 开发者体验

- dev-mode hook 调用顺序校验：对比上次 render 的 hook 类型序列，错位告警
- render 期间 setState 卫兵：设标志位，render 中调 setter 发 warn（避免死循环）
- `Harness:_paint` 稳定化循环改为基于 dirty 集合收敛的严格终止条件（当前硬编码 4 轮上限）
- `tui/testing.lua` `resolve_key` 支持通用 `shift+<key>` 前缀（当前只硬编码 `shift+tab`）

### 架构改进（非阻塞，穿插推进）

- **`scheduler.step()` 正式 API**：当前 `tui.testing:advance(ms)` 借用 `scheduler._timers()` 私表做 timer 循环。应提升为公共 `scheduler.step(now)`，消除重复、给用户一个正式的"外部驱动"入口。
- **paint 链路显式 terminal 注入**：`tui_core.terminal` 是进程单例，`tui.testing` 靠整表替换+还原来做 mock，限制了同进程内多 harness 并存。改为 `paint(root, ctx)` 接受 `ctx.terminal`，让测试 harness 直接传 fake，无需全局劫持。
- **ltest 并行 runner 兼容**：若未来 ltest 改并行，上面两项必须已完成，否则测试互相踩单例。目前在 `tui/testing.lua` 文件头注释里记录警告。
- **`input.dispatch` 中间件链**：当前用 `handled_by_focus_nav` bool 手动串 `pre → focus → broadcast`。改为可插拔中间件链，方便将来插入 mouse / bracketed-paste / 日志中间件。

### 文档

- README、入门教程、API 文档

### 定时器数据结构（仅当成为瓶颈再做）

- 当前每帧扫全表所有 timers，O(n) 线性。数量多时升级为最小堆，按"最近到期"优先触发。

---

## 非目标（明确不做）

- **setState 批处理升级到 React 18 transition/priority 模型**：当前 dirty flag 同优先级即可；真要 priority 控制，待接入 ltask 后重新设计。
- **事件驱动调度器**：当前固定帧轮询（bee.time.monotonic + thread.sleep）够用。生产场景请外接 ltask 或 bee-io，本框架保留简易实现。

---

## 维护约定

- 新增计划项：直接编辑本文件，在"未完成"相应类别下加条目
- 进入实施：移到"正在进行"，同时 TaskCreate 拆会话级子任务
- 完成：移到"已完成"，只写做了什么
- 不做的想法记到"非目标"，避免反复纠结
- 开新 stage 前先对照技术路线的 C 层 scope（Terminal I/O / wcwidth / Yoga / Render 后端 / Key parser）—— 落在这 5 项里的工作默认走 C，要改成 Lua 实现需要显式在 roadmap 里说明原因
