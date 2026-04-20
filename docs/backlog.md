# tui.lua 待办清单

本文件记录计划实施但尚未完成的工作，由用户与助手共同维护。**新增/调整计划时先改这里**。
已完成特性通过代码和 LuaDoc 注释表达，不在此处列举。

---

## 正在进行

_暂无_

---

## 未完成 · 按类别

### 内置组件扩充

- `Transform { transform=fn }`
- `form.lua`：多输入框 + 导航
- **Ansi**：解析 ANSI 转义序列（SGR / OSC）渲染为带样式 Text，用于外部工具输出（`git diff --color`）
- Markdown / syntax-highlight（AI chat 核心诉求，靠后实施）

### 渲染性能与稳定性

- **Truecolor / 256 色**：`cell_t` 扩到 16 字节 or 独立 style pool，给 `fg / bg` 加 16/24 bit 值
- **Text 行内混合样式**：`Text { "plain ", {text="red", color="red"} }`，wrap 沿 run 边界切片
- **焦点栈（Focus Stack）**：节点移除时自动恢复前一个焦点，解决弹窗关闭后焦点丢失问题
- **焦点事件**：Box/组件级别 `onFocus` / `onBlur` 事件（当前只有 entry 级 `on_change`）
- **StylePool 缓存**：style_id → SGR 会话级缓存，避免每帧重复计算 ANSI 序列。方案：`cell_t` 存 `style_id (uint16_t)` 索引到独立 pool，首次 interning 后续直接查找
- **CharPool 字符串去重**：相同文本共享存储，减少内存占用
- **光标 shape 支持**：`\x1B[n q` 切换 bar / block / underline；TextInput 暴露 `cursorShape` prop
- **shift() 滚动优化**：纯滚动场景用 DECSTBM + SU/SD 序列，零重绘内容
- **超链接（OSC 8）**：终端超链接支持，URL 去重存储到 HyperlinkPool
- `focus` 链表 entry→idx 映射（当前 Tab 切换线性搜索 O(n) → O(1)）

### 开发者体验

- `tui._VERSION` 字符串常量
- `make.lua` 加 `lm:conf_debug` / `lm:conf_release` 区分（asan / NDEBUG 开关）
- `testing.lua` `io.stderr` 全局替换改为生命周期受限的拦截（`render` 到 `unmount` 之间），避免并行测试风险

### 测试覆盖

- ErrorBoundary 嵌套场景
- 并发 setState 稳定化循环边界（MAX_STABILIZE_PASSES）
- 核心模块入门测试：`init.lua`、`renderer.lua`、`input.dispatch` 中间件链（pre → focus → broadcast）
- 集成测试：实时监控仪表盘（useInterval + ProgressBar + Spinner）、终端缩放（useWindowSize + Box 动态 resize）

### 架构改进

- **`input.dispatch` 中间件链**：当前用 `handled_by_focus_nav` bool 手动串 `pre → focus → broadcast`，改为可插拔中间件链，方便插入 mouse / 日志等中间件
- **`put_cell` OOM 检测**：当前 OOM 时静默丢弃 grapheme cluster，dev-mode 下应报错或记录标志位

### 输入扩展

- 鼠标事件（SGR / X10）
- `useInput` key 结构补齐：`pageUp` / `pageDown` / `home` / `end` / `meta` / `super`

### 示例扩充

- `error.lua`：ErrorBoundary 错误捕获与恢复流程展示
- `theme.lua`：颜色、样式、border 综合展示

### 定时器数据结构（仅当成为瓶颈再做）

- 当前每帧扫全表所有 timers，O(n) 线性。数量多时升级为最小堆，按"最近到期"优先触发。

---

## 非目标（明确不做）

- **setState 批处理升级到 React 18 transition/priority 模型**：当前 dirty flag 同优先级即可；真要 priority 控制，待接入 ltask 后重新设计。
- **事件驱动调度器**：当前固定帧轮询（bee.time.monotonic + thread.sleep）够用。生产场景请外接 ltask 或 bee-io，本框架保留简易实现。
- **React Concurrent / Suspense**：自研 reconciler，没有 React Fiber 的成本收益曲线。
- **React DevTools 对接**：Lua 生态无对应工具链；dev-mode 校验走自己的路（hook 顺序、key 告警、setState 卫兵）。
- **ARIA / 屏幕阅读器支持**：Lua CLI 场景投入产出比低。
- **Ink `patchConsole`**：Lua 里 `print` 重定向一行 `_G.print = ...` 就够，不需要复杂机制。
- **kitty keyboard protocol 全套**：keys.c 解析复杂度大，对 AI chat CLI 场景收益低；先做鼠标已足够。
- **Timer 最小堆搬进 C**：需要 C→Lua callback，边界开销不划算；若要优化，继续在 Lua 侧改堆。
- **Alternate screen buffer**：tui.lua 聚焦主屏幕，通过 Static 组件保持跨渲染内容，无需 alt screen 进出管理。

---

## 维护约定

- 新增计划项：直接编辑本文件，在"未完成"相应类别下加条目
- 进入实施：移到"正在进行"，同时在会话 SQL todos 表拆子任务
- 完成：从本文件删除对应条目，代码和 LuaDoc 即是最新特性文档
- 不做的想法记到"非目标"，避免反复纠结
- 开新 stage 前先对照技术路线的 C 层 scope（Terminal I/O / wcwidth / Yoga / Render 后端 / Key parser）—— 落在这 5 项里的工作默认走 C，要改成 Lua 实现需要显式说明原因
