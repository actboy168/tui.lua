# tui.lua 路线图

本文件是 tui.lua 的主路线图，由用户与助手共同维护。**新增/调整规划时先改这里**，
实施完毕再回来打勾。当前待办的细项由会话内任务列表（TaskCreate）辅助跟踪，不在
此处重复罗列。

---

## 已完成

### Stage 1 — 骨架：静态渲染
- luamake 构建系统接入，`lm:lua_dll "yoga"` + `lm:lua_dll "tui_core"`
- `tui_core.c` 聚合入口 + `terminal.c`（Win/POSIX raw I/O + IME）
- Lua 框架层最小版：`tui.Box` / `tui.Text` / `tui.render`
- `examples/hello.lua` 冒烟

### Stage 2 — 状态与重绘
- `tui/scheduler.lua`：可注入 now/sleep 的平台无关调度器
- `tui/hooks.lua`：`useState` / `useEffect` / `useInterval` / `useTimeout` / `useApp`
- `tui/reconciler.lua`：React-like 重渲染 + 实例复用
- `tui/screen.lua`：行级 diff 输出增量 ANSI
- 计数器示例

### Stage 3 — 键盘输入：useInput + 按键解析
- `src/tui_core/keys.c`：CSI / SS3 / UTF-8 / 修饰符解析
- `tui/input.lua`：订阅/派发总线；`tui.useInput` hook
- 主循环串联 read_raw → keys.parse → dispatch
- 带键盘的计数器示例
- `useEffect` 任意依赖数组 + 浅比较；cleanup 在新 effect 前调用（对齐 React 语义）

### Stage 4 — 文本测宽 + 软包装 + Static + TextInput + useWindowSize
- `src/tui_core/wcwidth.c`：Unicode 15.1 EastAsianWidth + emoji 硬编码表
- `tui/text.lua`：UTF-8 iter / display_width / soft-wrap
- 两遍 Yoga 布局支持 wrap 后高度反写
- `tui/builtin/static.lua`：Ink 风格只增日志区
- `tui/builtin/text_input.lua`：内置 TextInput + `_cursor_offset` + IME 跟随
- `tui/resize.lua` + `useWindowSize`
- `examples/chat_mock.lua`：模拟 AI chat

### Stage 5A — 统一离屏测试 harness `tui.testing`
- `tui/testing.lua`：`render / rerender / type / press / dispatch / frame / row / rows / width / height / tree / ansi / clear_ansi / advance / resize / unmount` + `mount_bare` + `find_text_with_cursor`
- 现有测试全部迁移到新 harness（test_static / test_text_input / test_reconciler）
- 新增 `test/test_chat_flow.lua` 端到端集成测试
- 修掉 `tui/element.lua` 的 Box children nil 截断 bug（table constructor 里 `cond and X or nil` 会让后续孩子被 ipairs 丢弃）

### Stage 5B — 快照测试
- `Harness:match_snapshot(name)` → `test/__snapshots__/<name>.txt`
- 首次运行写入并通过；后续运行逐行对比，不匹配时输出带上下文的 diff
- `TUI_UPDATE_SNAPSHOTS=1` 环境变量强制覆盖所有快照
- 纯文本格式，每行一屏幕行，git diff 友好
- `test/test_snapshots.lua`：chat idle / typed / streaming / resized 四个用例

### Stage 6 — 焦点管理（Ink 兼容）
- `tui/focus.lua` 焦点链状态机：entries 按订阅序 == Tab 次序，`focused_id` 单值
- `useFocus { autoFocus, id, on_input }` / `useFocusManager`
- `tui/input.lua` 拦截 Tab / Shift-Tab 切焦点；其他键先派 focused entry 再广播
- `TextInput` 内置走 `useFocus`，新增 `focusId` / `autoFocus` props；`Harness:focus*` 辅助
- 前置修复：`inst.dirty` 在调用组件前清零 + Harness `_paint` 稳定化循环（上限 4 轮）

### Stage 7 — ErrorBoundary 错误隔离
- `tui.ErrorBoundary { fallback = ..., children... }`：reconciler 用 pcall 包 children，失败时切 fallback，fallback 再崩降级为空 box
- 未声明 boundary 时 `tui.init.produce_tree` 兜底，画 `[tui] render error: ...` 错误屏而非崩事件循环

### Stage 8 — 基于 key 的 reconciler diff
- Box / Text / ErrorBoundary 构造器支持 `key` prop；同层重排 / 前插 / 删中间元素不再 remount 兄弟，state/effect 保留
- 同父同 key render 期硬报错；无 key 时维持位置语义（零回归）

### Stage 9 — 渲染后端下沉到 C（技术路线 #4 兑现）
- C 模块 `tui_core.screen`：12 字节 cell_t 缓冲、双缓冲、帧级 slab、row 字符串 ring pool（4 代）；`new / resize / clear / put / put_border / draw_line / diff / rows` API
- 首帧/invalidate/resize 全画，其余走 cell 级比较 + `MERGE_GAP=3` 段合并
- C 侧 `put_border` 三套样式（single / double / round）、`draw_line` 码点级 wcwidth
- `rows()` 用 Lua 5.5 `lua_pushexternalstring` 零拷贝

### Stage 10 — Text SGR / 颜色支持
- `cell_t` 扩出 `fg_bg` + `attrs`（ANSI-16 前/背景 + bold/dim/underline/inverse）
- Lua 侧 `tui.sgr`：Text/Box 接受 `color / backgroundColor / bold / dim / underline / inverse` props
- `draw_line / put_border` 接受 style 参数；diff 在每个要 emit 的 cell 前发 `ESC[0;p1;p2;...m`，行末 reset

### Stage 11 — SGR 增量 diff
- `emit_sgr` 改为纯增量：只 emit 变化的属性位（bold/dim 共享 22m、underline 4/24、inverse 7/27、fg 39m、bg 49m、色码 30-37/40-47/90-97/100-107）
- 行末不再强制 reset，SGR 状态按 ECMA-48 跨 CUP 继承；diff 末尾保留一次 `ESC[0m` 安全网
- 首帧 `ESC[H\x1b[2J\x1b[0m` 硬基线保持不变

### Stage 12 — Grapheme cluster
- C 层新增 `grapheme_next`：GB6/7/8 Hangul L/V/T/LV/LVT 合并、GB9/9a extend、GB11 近似 ZWJ、GB12/13 regional-indicator 偶数对；VS16 触发宽化、VS15 保持 base 宽
- `screen.draw_line` 按 cluster 写 cell（combining mark / ZWJ 家庭 / 国旗 / Hangul jamo / VS16 heart 都占单元格）
- `wcwidth.grapheme_next(s, i)` Lua 绑定；`wcwidth.string_width` 改用 grapheme 累加，与渲染列数一致
- `tui.text.iter` 和 `TextInput.to_chars` 切到 grapheme，方向键 / backspace 按 cluster 跳

### Stage 13 — 焦点系统完善
- `useFocus` 重复 id 在 `focus.subscribe` 内硬 assert（替换掉静默追加 `#seq` 后缀的行为）
- 严格 Ink 语义：移除"单 entry 自动获焦"的便利规则，只有 `autoFocus=true` 触发；`TextInput` 默认 `autoFocus=true` 不受影响
- `useFocus({ isActive = false })` 支持：entry 保留在 Tab 链但被 `focus_next / focus_prev` 跳过；inactive 时即便 `autoFocus=true` 也不获焦
- `useFocus` 支持 `id` 与 `isActive` 的热更新：`id` 变化走 unsubscribe + resubscribe 到链尾；`isActive` 变化通过 `focus.set_active(id, flag)` 原地更新，变 inactive 时持焦者自动转给下一个 active entry
- `TextInput` `focus=false` 合回 useFocus 单一路径：注册成 `isActive=false` 的 entry，Tab 跳过 + autoFocus 忽略，hook 调用顺序在两种路径下一致

---

## 正在进行

_暂无_

---

## 未完成 · 按类别

### 功能增强

**高阶组件**
- `useStdout` / `useStderr`
- `form.lua`：多输入框 + 导航

**错误隔离**
- `useEffect` body / cleanup 抛错冒泡到最近 ErrorBoundary（当前仅 render 阶段捕获）
- `useInput` 回调抛错被最近 ErrorBoundary 吞掉（需要记录 entry → boundary 映射）
- `ErrorBoundary` 的 `fallback` 支持 `function(err, reset)` 形式 + `reset` 显式复位 API
- `useErrorBoundary` hook：组件读取最近祖先 Boundary 的 `caught_error`，用于自定义错误展示
- ErrorBoundary 不应吞 fatal 类型 error（例如 reconciler 的 duplicate key assert）：引入 `[tui:fatal]` 错误前缀或特殊 sentinel，Boundary pcall 识别后 rethrow

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
