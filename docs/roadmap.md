# tui.lua 路线图

本文件是 tui.lua 的主路线图，由用户与助手共同维护。**新增/调整规划时先改这里**，
实施完毕再把条目挪到 [features.md](features.md)。当前会话的细项由 TaskCreate 辅助
跟踪，不在此处重复罗列。

已支持特性见 [features.md](features.md)。

---

## 正在进行

_暂无_

---

## 未完成 · 按类别

### 内置组件扩充

- `Transform { transform=fn }`
- `form.lua`：多输入框 + 导航
- **Ansi**：解析 ANSI 转义序列（SGR / OSC）渲染为带样式 Text，用于外部工具输出（`git diff --color`）
- Markdown / syntax-highlight（AI chat 核心诉求，Stage 靠后）

### 渲染性能与稳定性

- truecolor / 256 色扩展：`cell_t` 扩到 16 字节 or 独立 style pool，给 `fg / bg` 加 16/24 bit 值
- Text per-run inline style：`Text { "plain ", {text="red", color="red"} }`，wrap 沿 run 边界切片
- `focus` 链表 entry→idx 映射（当前 Tab 切换做线性搜索 O(n) → O(1)）
- **焦点栈（Focus Stack）**：节点移除时自动恢复前一个焦点（Ink 行为），解决动态 UI（弹窗关闭后焦点丢失）问题
- **焦点事件**：Box/组件级别 `onFocus` / `onBlur` 事件（当前只有 entry 级 `on_change`）
- **StylePool 缓存**：Ink 的 style_id → SGR 会话级缓存，避免每帧重复计算 ANSI 序列。方案：独立 style pool，cell_t 存 style_id (uint16_t) 索引到 pool，首次 interning 后续直接查找。前置工作已完成：`sgr.pack_border_bytes` 已内联 border 颜色逻辑，入口处预留缓存插入点
- **CharPool 字符串去重**：相同文本共享存储，减少内存占用
- **shift() 滚动优化**：纯滚动场景用 DECSTBM + SU/SD 序列，零重绘内容
- **screen.c fill_space 冗余消除**：diff 后 fill_space 清空 next 缓冲，但下一帧 clear() 又会清一遍，可以跳过 diff 后的 fill_space
- **光标 shape 支持**：`\x1B[n q` 切换 bar / block / underline（TextInput 可声明 `cursorShape` prop）
- **超链接 HyperlinkPool（OSC 8）**：终端超链接支持，URL 去重存储

### 开发者体验

- ErrorBoundary fallback 接收 `{message, trace}` 而不只是字符串（保留 `debug.traceback(err, 2)`）
- `screen.c` full-redraw 模式下行末加 `reset_sgr`，避免 SGR 状态跨行继承导致视觉 bug
- `tui._VERSION` 字符串常量
- `make.lua` 加 `lm:conf_debug` / `lm:conf_release` 区分（asan / NDEBUG 开关）
- `testing.lua` `io.stderr` 全局替换改为生命周期受限的拦截（`render` 到 `unmount` 之间），避免并行测试风险

### 测试覆盖

- ErrorBoundary 嵌套场景
- 并发 setState 导致的稳定化循环边界（MAX_STABILIZE_PASSES）
- 无覆盖核心模块入门测试：init.lua、renderer.lua、input.dispatch 中间件链（pre → focus → broadcast）
- 集成测试场景扩展：表单提交（TextInput + Select + useFocus Tab 导航）、实时监控仪表盘（useInterval + ProgressBar + Spinner）、错误恢复流程（ErrorBoundary + useInput）、终端缩放（useWindowSize + Box 动态 resize）
- helpers 工具库扩展：make_form_app、make_async_app、with_dev_mode wrapper、assert_no_warnings 便利函数

### 架构改进（非阻塞，穿插推进）

- **`input.dispatch` 中间件链**：当前用 `handled_by_focus_nav` bool 手动串 `pre → focus → broadcast`。改为可插拔中间件链，方便将来插入 mouse / bracketed-paste / 日志中间件。
- **C 层 assert 走 `[tui:fatal]` 前缀**：当前 C 层 `luaL_error` 会被 ErrorBoundary 吞掉，不变式违反应该 bypass
- **`put_cell` OOM 检测**：当前 OOM 时静默丢弃 grapheme cluster，建议 dev-mode 下报错或记录标志位

### 输入扩展

- bracketed paste（`usePaste(handler)`）—— 同时修掉 TextInput 在单次 dispatch 下粘贴 N 字节只留最后一个字符的问题（需 keys.c 走 `paste` 事件或 TextInput 闭包里本地累积 chars）
- 鼠标事件（SGR / X10）
- `useInput` key 结构补齐：`pageUp` / `pageDown` / `home` / `end` / `meta` / `super`

### 文档

- README、入门教程、API 文档
- 10 个 example 覆盖：hello / counter / form / chat / log / spinner / progress / static / error / theme

### 定时器数据结构（仅当成为瓶颈再做）

- 当前每帧扫全表所有 timers，O(n) 线性。数量多时升级为最小堆，按"最近到期"优先触发。


---

## 非目标（明确不做）

- **setState 批处理升级到 React 18 transition/priority 模型**：当前 dirty flag 同优先级即可；真要 priority 控制，待接入 ltask 后重新设计。
- **事件驱动调度器**：当前固定帧轮询（bee.time.monotonic + thread.sleep）够用。生产场景请外接 ltask 或 bee-io，本框架保留简易实现。
- **React Concurrent / Suspense**：我们自研 reconciler，没有 React Fiber 的成本收益曲线。
- **React DevTools 对接**：Lua 生态无对应工具链；dev-mode 校验走自己的路（hook 顺序、key 告警、setState 卫兵）。
- **ARIA / 屏幕阅读器支持**：Lua CLI 用户基本不碰屏幕阅读器，投入产出比低。
- **Ink `patchConsole`**：Lua 里 `print` 重定向一行 `_G.print = ...` 就够，不需要复杂机制。
- **kitty keyboard protocol 全套**：keys.c 解析复杂度大，对 AI chat CLI 场景收益低；先做鼠标 + bracketed paste 已足够。
- **Timer 最小堆搬进 C**：需要 C→Lua callback 回调，边界开销不划算；若要优化，继续在 Lua 侧改堆。
- **alternate screen buffer**：Ink 默认使用主屏幕，alt screen 不是其核心场景；tui.lua 同样聚焦主屏幕，通过 Static 组件实现跨渲染保持内容，无需 alt screen 的复杂进出管理。

---

## 维护约定

- 新增计划项：直接编辑本文件，在"未完成"相应类别下加条目
- 进入实施：移到"正在进行"，同时 TaskCreate 拆会话级子任务
- 完成：把 stage bullet 挪到 `changelog.md`，roadmap 这里只保留规划
- 不做的想法记到"非目标"，避免反复纠结
- 开新 stage 前先对照技术路线的 C 层 scope（Terminal I/O / wcwidth / Yoga / Render 后端 / Key parser）—— 落在这 5 项里的工作默认走 C，要改成 Lua 实现需要显式在 roadmap 里说明原因
