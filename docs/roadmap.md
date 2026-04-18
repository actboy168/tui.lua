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
**前置修复 — `inst.dirty` 清零 + Harness 稳定化循环**
- `tui/reconciler.lua` 在调用组件 fn 之前清 `inst.dirty = false`，mount-effect 里调 setter 能被检测到
- `tui/testing.lua` `Harness:_paint` 加稳定化循环：render → 有 instance dirty 则重跑，上限 4 轮，超限 error
- `test/test_dirty.lua`：mount-effect 调 setter 首帧即反映；死循环 setter 触发稳定化报错

**焦点系统**
- `tui/focus.lua`：焦点链状态机（entries 按订阅序 == Tab 次序；`focused_id` 单值）
- `useFocus { autoFocus, id, on_input }` → `{ isFocused, focus }`；订阅走 `useEffect({}, [])` 挂载
- `useFocusManager()` → `{ enableFocus, disableFocus, focus, focusNext, focusPrevious }`
- `tui/input.lua` dispatch 拦截 Tab / Shift-Tab 转 `focus_next / focus_prev`；其他键先派给 focused entry，再广播给裸 `useInput`
- `TextInput` 内置走 `useFocus`；`props.focus = false` 保留 disabled 独立分支；新增 `focusId` / `autoFocus` props
- `Harness:focus_id / :focus_next / :focus_prev / :focus(id)`；`KEYS["shift+tab"] = "\27[Z"`
- `testing.render` 初始 paint 失败时恢复 hijack 的 terminal，避免后续用例报 "another harness is already active"
- `test/test_focus.lua`：8 个用例（autoFocus / Tab / FocusManager / disable / unmount 转焦点 / TextInput / 两个 TextInput Tab 切换 / rerender 不改变 Tab 顺序）

### Stage 7 — ErrorBoundary 错误隔离
- `tui/element.lua`：`ErrorBoundary { fallback = ..., children... }` 构造器，`kind = "error_boundary"`
- `tui/reconciler.lua`：`expand` 识别 error_boundary 节点，用 pcall 包住 children 循环；失败时切换到 `fallback`（fallback 自身也走 expand，支持组件）；inst 记录 `caught_error`；fallback 再失败降级为空 box 阻止错误继续传播
- `tui/init.lua`：`tui.ErrorBoundary` 导出；`produce_tree` 把 `reconciler.render` 包 pcall，失败时画"[tui] render error: <msg>"错误屏而非崩掉事件循环（未声明 boundary 时的框架级兜底）
- `test/test_error_boundary.lua`：6 个用例（catches_child_throw 含 rerender 稳定 / no_throw_passthrough / isolates_sibling_subtrees / nested_inner_catches_first / error_from_deeper_descendant_caught / no_boundary_error_propagates）

### Stage 8 — 基于 key 的 reconciler diff
- `tui/element.lua`：`pluck_key` 把 props.key 提升到 `element.key`，不泄漏到 Yoga；Box / Text / ErrorBoundary 构造器都挂 key
- `tui/reconciler.lua`：`child_path_for(parent, i, child, seen_keys)` —— 有 key 走 `parent/#<key>` 命名空间、无 key 走 `parent/<i>`；同父同 key render 期 error 硬失败；Box 与 ErrorBoundary children 循环都用新辅助
- 行为：同层重排 / 前插 / 删中间元素不再 remount 带 key 的兄弟，state/effect 保留；无 key 时维持原有位置语义（零回归）；key 换了按路径换算自然 unmount + mount
- `test/test_reconciler_keys.lua`：8 个用例（重排保身 / 前插 / 删中间 / 无 key 位置回归 / 混用 keyed+unkeyed / 重复 key 报错 / key 换位置强制 remount / host Box 带 key 稳定后代）

### Stage 9 — 渲染后端下沉到 C（技术路线 #4 兑现）
- 新增 `src/tui_core/screen.c`：cell 缓冲（12 字节 cell_t，8 字节内联 + slab 溢出 union）、双缓冲、帧级 slab（next/prev append-only + 指针交换稳态零分配）、ring pool (4 代) 的 row 字符串池
- Lua API `tui_core.screen.{new, size, resize, invalidate, clear, put, put_border, draw_line, diff, rows}`，state 作参数的函数式风格；`__gc` 负责 free 所有 C-owned 缓冲
- `diff` 实现：首帧 / invalidate / resize 后走 `\x1b[H\x1b[2J` 全画；后续走 cell 级比较 + 段合并（`MERGE_GAP=3` 以内连续改动合段，bridging 不变字节比再发一次 CUP 便宜）；WIDE_TAIL 语义在 C 端维护
- `draw_line` 在 C 侧直接调用 `wcwidth_cp + utf8_next`（`src/tui_core/wcwidth.h` 暴露，去掉 static）；组合标记 / 控制字符跳过；grapheme cluster 合并留给未来 stage
- `put_border` 三套样式（single / double / round）硬编码在 C，6 个 UTF-8 glyph 字节序列直出，一次画完边框
- `rows()` 用 Lua 5.5 `lua_pushexternalstring` + `ROW_POOL_GEN=4` 环形池：每次 `rows()` 调用轮转一代 buffer、`realloc` 按需、填完推出零拷贝字符串；调用方在 4 代内稳定，超出由下一轮 `rows()` 自然复用同代 buffer（测试 harness / 快照读法均在一帧内，安全）
- `tui/renderer.lua` 从 ~186 行收缩到 ~40 行：只走树调用 `screen.put_border / draw_line`；`render_rows / render / buffer_to_*` 全退役
- `tui/screen.lua` 退化为 ~55 行 wrapper；`tui/init.lua paint()` 改走 `size / resize / clear / paint / diff` 链路；`tui/testing.lua` 的 `:rows() / :row() / :frame()` 改读 `screen.rows(self._screen)`，移除 `self._rows` 字段
- `test/test_screen_diff.lua` 11 用例：首帧全画 / 幂等 / 单点局部更新 / MERGE_GAP 内合并 / MERGE_GAP 外拆段 / 宽字符 + WIDE_TAIL / 长 cluster 走 slab / slab 增长 / ring pool 4 代稳定 / resize 全画 / invalidate 全画
- 修掉 snprintf 用 `\27`（C 里是八进制 023，非 ESC）的 bug，改为 `\x1b`；全量 128 测试通过（117 老测 + 11 新测）

---

## 正在进行

_暂无_

---

## 未完成 · 按类别

### 技术路线未对齐（需回补到 C 层）

技术路线规定 C 层拥有 5 项职责（Terminal I/O / wcwidth + grapheme / Yoga 布局 / Render 后端 / Key parser），**第 4 项"渲染后端"** 已由 Stage 9 兑现；**第 2 项"wcwidth + grapheme"** 只做了字符宽度一半：

**grapheme cluster 处理**
- `src/tui_core/wcwidth.c` 当前只覆盖码点级 East Asian Width + emoji 宽度，grapheme cluster 边界（ZWJ emoji sequence / combining mark / regional indicator 国旗）尚未实现
- 影响：emoji 序列如 👨‍👩‍👧 被按 3 个独立 emoji 算宽、光标在组合字符中间停留、CJK 前后方向键按字符跳而非按 grapheme

### 功能增强

**焦点系统完善**
- `useFocus` id 冲突改为 render 期 assert 硬失败（当前仅后缀 `#seq`，易掩盖重复注册）
- `useFocus` 支持 opts 热更新（当前 id / autoFocus 在 mount 时固化，运行时改不生效）
- 严格按 Ink 语义：仅 `autoFocus=true` 才自动拿焦点（当前 `#entries==1` 也会自动，为 demo 方便）
- `useFocus({ isActive = false })` 支持临时禁用某 entry 而不 unmount
- `TextInput` 的 disabled 语义并回 useFocus：`focus.subscribe` 加 `suppress_initial`，移除独立分支

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
- Text 节点颜色 / SGR 属性：cell 结构扩属性位，C diff 端 emit SGR 前缀
- grapheme cluster 合并（combining mark 应粘附前 cell 而非独占）
- `put` 的 cluster 长度校验（防止恶意长字符串爆 slab）

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
