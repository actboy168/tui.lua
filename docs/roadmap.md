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

### Hook 家族补齐（Ink 对齐 P1）

- `useStdout()` / `useStderr()`

### 内置组件扩充

- `Newline { count }` / `Spacer` / `Transform { transform=fn }`
- `form.lua`：多输入框 + 导航
- Markdown / syntax-highlight（AI chat 核心诉求，Stage 靠后）

### 渲染性能与稳定性

- Box prop 命名对齐 Ink：当前 `border` / `color`（兼边框与文本色）与 Ink 的 `borderStyle` / `borderColor` 不一致，迁移成本会越积越重。改为：
  - `borderStyle` 取代 `border`（保留 `border` 作 alias 若干版本）
  - 新增 `borderColor` / `borderDimColor`（每边独立颜色选配）
  - 边框样式扩充：`bold` / `singleDouble` / `doubleSingle` / `classic`
- alternate screen buffer（类 vim 进出全屏）
- truecolor / 256 色扩展：`cell_t` 扩到 16 字节 or 独立 style pool，给 `fg / bg` 加 16/24 bit 值
- Text 样式补齐：`italic` / `strikethrough` / `dimColor` / `wrap` 模式（`wrap` / `hard` / `truncate` / `truncate-start` / `truncate-middle` / `truncate-end`）
- Text per-run inline style：`Text { "plain ", {text="red", color="red"} }`，wrap 沿 run 边界切片
- Ink 式颜色继承：父 Box 的 color prop 自动透到子 Text
- `focus` 链表 entry→idx 映射（当前 Tab 切换做线性搜索）
- Yoga 属性预处理：apply_box_style 每节点遍历 38 个 passthrough key + Yoga 绑定再遍历一次，改为扁平数字数组按固定索引传入

### 开发者体验

- **组件自动包装** —— 当前规则："调 hook 的函数必须显式包装为 `{ kind="component", fn=..., props=... }`"，写 example 时极易翻车（plain function 调用把 hook 挂到父 instance，条件渲染时触发 hook count mismatch）。两种方向取一：
  - A) reconciler 在 children 归一化时发现 function，自动包成 component element（对齐 React 直觉，但 helper function 误塞进 children 会被误认为组件）
  - B) 提供 `tui.component(fn)` 工厂助手到框架层（显式、可 grep、1 行 boilerplate）
  - 若选 A，还需 dev-mode 检测"hook 在未注册为 component 的函数里被调用"给早期报错，而不是等 hook count mismatch 才炸
- `Harness:_paint` 稳定化循环改为基于 dirty 集合收敛的严格终止条件（当前硬编码 4 轮上限）
- `tui/testing.lua` `resolve_key` 支持通用 `shift+<key>` 前缀（当前只硬编码 `shift+tab`）；同时让 `h:press(ch)` 在 `ch` 是单个可打印字符时回落为 `type(ch)`，避免"unknown key '?'"这类翻车
- ErrorBoundary 保留 `debug.traceback(err, 2)`，fallback 函数接收 `{message, trace}` 而不只是字符串
- `tui._VERSION` 字符串常量
- `make.lua` 加 `lm:conf_debug` / `lm:conf_release` 区分（asan / NDEBUG 开关）
- `ltest.assertEquals` 长字符串比较输出 multiline diff 而不是整串 dump

### 测试覆盖

- TextInput IME composition 状态转换、cursor 越界（当前只覆盖 commit 后的正常输入路径）

### 架构改进（非阻塞，穿插推进）

- **paint 链路显式 terminal 注入**：`tui_core.terminal` 是进程单例，`tui.testing` 靠整表替换+还原来做 mock，限制了同进程内多 harness 并存。改为 `paint(root, ctx)` 接受 `ctx.terminal`，让测试 harness 直接传 fake，无需全局劫持。
- **ltest 并行 runner 兼容**：若未来 ltest 改并行，上面一项必须已完成，否则测试互相踩单例。目前在 `tui/testing.lua` 文件头注释里记录警告。
- **`input.dispatch` 中间件链**：当前用 `handled_by_focus_nav` bool 手动串 `pre → focus → broadcast`。改为可插拔中间件链，方便将来插入 mouse / bracketed-paste / 日志中间件。
- **订阅总线工具化**：input / resize / focus 三处重复实现 "订阅表 + dispatch"，提 `make_subscription_bus()`
- **C 层 assert 走 `[tui:fatal]` 前缀**：当前 C 层 `luaL_error` 会被 ErrorBoundary 吞掉，不变式违反应该 bypass

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

---

## 维护约定

- 新增计划项：直接编辑本文件，在"未完成"相应类别下加条目
- 进入实施：移到"正在进行"，同时 TaskCreate 拆会话级子任务
- 完成：把 stage bullet 挪到 `changelog.md`，roadmap 这里只保留规划
- 不做的想法记到"非目标"，避免反复纠结
- 开新 stage 前先对照技术路线的 C 层 scope（Terminal I/O / wcwidth / Yoga / Render 后端 / Key parser）—— 落在这 5 项里的工作默认走 C，要改成 Lua 实现需要显式在 roadmap 里说明原因
