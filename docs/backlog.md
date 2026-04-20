# tui.lua 待办清单

本文件记录计划实施但尚未完成的工作，由用户与助手共同维护。**新增/调整计划时先改这里**。
已完成特性通过代码和 LuaDoc 注释表达，不在此处列举。

优先级说明：**P0** 核心缺失 / **P1** 重要功能 / **P2** 改善提升 / **P3** 锦上添花 / **P4** 仅当瓶颈

---

## 正在进行

_暂无_

---

## 未完成 · 按类别

### Text 行内混合样式（已完成特性的后续）

- `P2` **Span 文本的 `wrap="hard"` / truncate 模式**：`element.runs` 目前仅在 `wrap="wrap"` 时走 `wrap_runs` 路径；其余模式 `element.line_runs = nil` 退回纯文本渲染，span 样式静默丢失
- `P2` **`wrap_runs` 不处理 span 内的 `\n`**：原始 `text.wrap` 会拆显式换行，`wrap_runs` 只在空格断行，span 中含 `\n` 时行为与纯文本不一致

### 鼠标交互扩展

- `P1` **命中测试 / `onClick` prop**：Box 持有 layout 坐标，框架层做 hit-test；在 Box 上暴露 `onClick` / `onMouseEnter` / `onMouseLeave` prop，是 Button、ScrollBox 等组件的基础（Lua 层为主）
- `P2` **`useHover()` hook**：依赖命中测试，返回 `{hovered=bool}`，组件内直接使用无需手算鼠标坐标（Lua 层）
- `P2` **鼠标框选 + 高亮**：以插件/中间件形式实现，不嵌入核心。主要步骤：① 用 `input_mod.subscribe_mouse` + `request_mouse_level(2)` 监听拖拽事件；② 维护选区状态（`selection.lua` 已有）；③ 在每帧 `paint()` 后调用 `tui_core.screen.overlay_selection()` 写入 ATTR_INVERSE；④ Esc 清除选区；⑤ mouseup 时通过 OSC 52 / clipboard.copy 复制文本。`tui/internal/selection.lua` 和 C 层 `overlay_selection` 已实现，可直接复用。
- `P3` **双击选词 / 三击选行**：依赖框选插件，300ms 内双击→选词，三击→选行
- `P3` `mouse_events.lua` 示例：演示 `useMouse`、click、scroll wheel

### 内置组件扩充

- `P0` **ScrollBox**：可滚动容器 + 命令式滚动 API（scrollTo/scrollBy）+ stickyScroll + 视口裁剪；复杂内容展示刚需（Lua 层为主，C 层可选加速）
- `P1` **Button**：焦点/悬停/点击/键盘激活；对比 Ink `Button` 组件（Lua 层）
- `P1` **`form.lua`**：多输入框 + 字段导航；表单/对话式应用刚需
- `P1` **Ansi**：解析 ANSI 转义序列（SGR / OSC）渲染为带样式 Text，用于外部工具输出（`git diff --color`）
- `P2` **`Transform { transform=fn }`**：对子树输出做后处理变换
- `P3` Markdown / syntax-highlight：AI chat 核心诉求，靠后实施

### 渲染性能与稳定性

- `P1` **焦点栈（Focus Stack）**：节点移除时自动恢复前一个焦点，解决弹窗关闭后焦点丢失问题
- `P1` **焦点事件**：Box/组件级别 `onFocus` / `onBlur` 事件（当前只有 entry 级 `on_change`）
- `P2` **光标 shape 支持**：`\x1B[n q` 切换 bar / block / underline；TextInput 暴露 `cursorShape` prop
- `P2` **超链接（OSC 8）**：终端超链接支持，URL 去重存储到 HyperlinkPool
- `P2` **RawAnsi 直通**：跳过 reconciler/layout/render 管线，直接输出预渲染 ANSI 序列；适合 `git diff --color`、LLM 流式输出等场景（C + Lua）
- `P3` **shift() 滚动优化**：纯滚动场景用 DECSTBM + SU/SD 序列，零重绘内容
- `P3` **ANSI 感知换行**：对含 ANSI 转义的原始字符串做宽度感知换行，与 Ansi 组件配合使用（Lua 层）
- `P3` **CharPool 字符串去重**：相同文本共享存储，减少内存占用
- `P3` **`focus` 链表 entry→idx 映射**：当前 Tab 切换线性搜索 O(n) → O(1)

### 开发者体验

- `P1` **`tui.Text` span 语法文档**：README / API 文档里尚无 span 子表语法（`{text="x", color="red"}`）的说明，需补充
- `P2` **`testing.lua` stderr 拦截**：`io.stderr` 全局替换改为生命周期受限的拦截（`render` 到 `unmount` 之间），避免并行测试风险
- `P2` **`make.lua` 调试/发布配置**：加 `lm:conf_debug` / `lm:conf_release` 区分（asan / NDEBUG 开关）
- `P3` **`tui._VERSION`**：字符串常量

### 测试覆盖

- `P2` **ErrorBoundary 嵌套场景**
- `P2` **并发 setState 稳定化循环边界**：MAX_STABILIZE_PASSES 边界行为
- `P2` **核心模块入门测试**：`init.lua`、`renderer.lua`、`input.dispatch` 中间件链（pre → focus → broadcast）
- `P2` **集成测试：监控仪表盘**：useInterval + ProgressBar + Spinner
- `P2` **集成测试：终端缩放**：useWindowSize + Box 动态 resize
- `P3` **`testing.simulate_mouse`**：测试套件里方便触发鼠标事件，通过 `input_mod._dispatch_event()` 分发，降低鼠标交互测试摩擦

### 架构改进

- `P2` **`put_cell` OOM 检测**：当前 OOM 时静默丢弃 grapheme cluster，dev-mode 下应报错或记录标志位

### 输入扩展

- `P1` **文本选择 + 剪贴板**：选择状态机（字符/词/行选择、键盘选择）+ 多路径剪贴板（pbcopy / wl-copy / xclip / OSC 52 fallback）（Lua + C）
  - ✅ 基础拖选 + wl-copy/xclip/pbcopy 已完成
  - 剩余：OSC 52 fallback（SSH/tmux 场景）
- `P2` **OSC 52 clipboard**：通过终端转义序列写剪贴板，无需 xclip/wl-copy，SSH/tmux/Kitty 均适用；加入 `clipboard.lua` 最高优先级
- `P2` **`useClipboard` hook**：组件内程序化读写剪贴板（`write(text)` / `read() → string`），暴露为 `tui.useClipboard()`
- `P2` **`useInput` key 结构补齐**：`pageUp` / `pageDown` / `home` / `end` / `meta` / `super`

### 终端兼容性

- `P2` **终端身份探测**：XTVERSION/DA1 查询，针对不同终端（iTerm2、Kitty、WezTerm、conhost 等）缓存能力并做兼容处理（C + Lua）
- `P2` **Windows 终端兼容**：检测并规避 conhost cursor-up viewport yank bug；其他 Windows Terminal 特定缺陷处理（C + Lua）
- `P2` **tmux/screen 穿透**：DCS 封装，使 OSC/DCS 序列在 tmux multiplexer 下正确透传（C + Lua）

### Kitty Keyboard Protocol 扩展（基础 KKP 已实现）

基础 KKP（flags=3：disambiguate + event types）已完成，以下是后续可选增强：

- `P3` **KKP flag 4 — Alternate keys**：上报"shifted key"与"base layout key"子字段，用于国际键盘布局的快捷键匹配（如 Cyrillic Ctrl+С → Ctrl+c）；需要扩展 `CSI u` 解析和事件表
- `P3` **KKP flag 8 — Report all keys as escape codes**：所有键（含普通字符）均以 `CSI u` 上报；解锁 press/repeat/release 对文本键的完整支持，是游戏类 TUI（WASD 移动）的基础；与现有 `name="char"` 路径冲突，需设计 API 兼容策略
- `P3` **KKP flag 16 — Associated text**：随 `CSI u` 附带关联文本码点；依赖 flag 8，单独无意义
- `P3` **tmux KKP 穿透**：tmux ≥ 3.5 支持 KKP，但需在 `tmux.conf` 中设置 `allow-passthrough on` 并使用 DCS 封装；检测并自动透传（C + Lua）
- `P3` **`useInput` 订阅 release/repeat 事件**：当前 `subscribe` 回调接收全部事件，应用需自行过滤 `event_type`；可扩展为 `useKeyDown` / `useKeyUp` / `useKeyRepeat` 等语义化 hook
- `P3` **`request_keyboard_flags(flags)` 引用计数**：类比 `request_mouse_level`，允许组件按需 push/pop KKP flags，而非 session 级全局设置

### 示例扩充

- `P2` `error.lua`：ErrorBoundary 错误捕获与恢复流程展示
- `P3` `theme.lua`：颜色、样式、border 综合展示
- `P3` `focus_animation.lua`：`useTerminalFocus` + `useInterval` 配合，失焦时暂停动画、恢复焦点时继续；`useTerminalFocus` 最典型使用场景

### 定时器数据结构（仅当成为瓶颈再做）

- `P4` **最小堆升级**：当前每帧扫全表所有 timers，O(n) 线性。数量多时升级为最小堆，按"最近到期"优先触发。

---

## 非目标（明确不做）

- **setState 批处理升级到 React 18 transition/priority 模型**：当前 dirty flag 同优先级即可；真要 priority 控制，待接入 ltask 后重新设计。
- **事件驱动调度器**：当前固定帧轮询（bee.time.monotonic + thread.sleep）够用。生产场景请外接 ltask 或 bee-io，本框架保留简易实现。
- **ARIA / 屏幕阅读器支持**：Lua CLI 场景投入产出比低。
- **Timer 最小堆搬进 C**：需要 C→Lua callback，边界开销不划算；若要优化，继续在 Lua 侧改堆。
- **BiDi 文本**：双向文本重排序（bidi.ts 级别），Lua CLI 场景基本不需要，复杂度高。

---

## 维护约定

- 新增计划项：直接编辑本文件，在"未完成"相应类别下加条目
- 进入实施：移到"正在进行"，同时在会话 SQL todos 表拆子任务
- 完成：从本文件删除对应条目，代码和 LuaDoc 即是最新特性文档
- 不做的想法记到"非目标"，避免反复纠结
- 开新 stage 前先对照技术路线的 C 层 scope（Terminal I/O / wcwidth / Yoga / Render 后端 / Key parser）—— 落在这 5 项里的工作默认走 C，要改成 Lua 实现需要显式说明原因
