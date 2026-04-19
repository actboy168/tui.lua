# tui.lua 特性

---

## 组件

- **Box** — 布局容器，支持 `flexGrow` / `flexShrink` / `flexBasis` / `flexDirection` / `justifyContent` / `alignItems` / `alignContent` / `alignSelf` / `overflow` / `boxSizing` / `borderStyle` / `borderColor` / `borderDimColor` / `padding` / `margin` / `gap` 等 Yoga 属性
- **Text** — 文本渲染，支持 `color` / `backgroundColor` / `bold` / `dim` / `underline` / `inverse` / `wrap`
- **TextInput** — 受控文本输入，支持 `value` / `onChange` / `onSubmit` / `placeholder` / `mask` / `focus` / `autoFocus` / `focusId` / `width`；IME 光标跟随；批量 dispatch 正确处理
- **Select** — 列表选择，支持 `items` / `onSelect` / `onChange` / `initialIndex` / `indicator` / `highlightColor` / `renderItem` / `limit` / `isDisabled`
- **Spinner** — 加载动画，内置 `dots` / `line` 等帧集，支持自定义 `frames` / `interval`
- **ProgressBar** — 进度条，支持 `value` / `width` / `color` / `chars`
- **ErrorBoundary** — 错误隔离，支持 `fallback` 元素或函数、`useErrorBoundary()`
- **Static** — 跨渲染保持内容
- **Newline** — 垂直空行，`{ count = n }` 创建 n 个空行（默认 1）
- **Spacer** — 弹性占位，自动填充父容器剩余空间

## Hook

- `useState` / `useReducer` — 状态管理
- `useEffect` — 副作用（`{}` 挂载一次 / `nil` 每次渲染 / `{dep1,dep2}` 依赖变化）
- `useMemo` / `useCallback` — 计算缓存
- `useRef` / `useLatestRef` — 引用
- `useContext` / `createContext` + `ctx.Provider` — 跨组件传值
- `useFocus` / `useFocusManager` — Tab/Shift-Tab 焦点链，`isActive` / `autoFocus` / `focusId`
- `useInput` — 全局键盘监听
- `useAnimation` — 帧动画（`interval` / `isActive` → `frame` / `time` / `delta` / `reset`）
- `useInterval` / `useTimeout` — 定时器
- `useWindowSize` — 终端尺寸
- `useApp` — `.exit()` 退出

## 测试 harness

- `testing.render(App, {cols, rows, now})` — 离屏渲染
- `testing.mount_bare(App)` — 轻量模式（仅 reconciler + hooks，无布局/渲染）
- `h:type(str)` / `h:press(name)` / `h:dispatch(bytes)` — 模拟输入
- `h:press(name)` 支持 `shift+<key>` / `ctrl+<letter>` / F1-F12 / 单字符回落
- `h:advance(ms)` — 驱动虚拟时钟
- `h:resize(cols, rows)` — 模拟终端缩放
- `h:frame()` / `h:row(n)` / `h:rows()` — 查看渲染输出
- `h:cursor()` — 光标位置
- `h:tree()` — 元素树
- `h:ansi()` / `h:clear_ansi()` — ANSI 输出
- `h:render_count()` / `h:reset_render_count()` / `h:expect_renders(n)` — 渲染次数追踪
- `h:match_snapshot(name)` — 快照测试
- `h:focus_id()` / `h:focus_next()` / `h:focus_prev()` / `h:focus(id)` — 焦点驱动
- `testing.capture_stderr(fn)` — 捕获 dev 警告
- `testing.find_text_with_cursor(tree)` — 查找带光标的 Text 元素
- `testing.find_by_kind(tree, kind)` — 查找首个指定类型节点
- `testing.find_all_by_kind(tree, kind)` — 收集所有指定类型节点
- `testing.text_content(tree)` — 收集所有 Text 节点文本
- `luamake lua test.lua --coverage` — 测试覆盖率报告（ltest 内置，自动注册 tui.* 模块）

## Dev-mode

- `tui.setDevMode(bool)` 开关
- Hook 顺序校验
- render 期 `setState` / `dispatch` 警告
- 3+ 子节点缺 `key` 警告
- hook 在非 component 函数里调用 → `[tui:fatal]`
- 测试中未预期 dev 警告升级为 fatal

## Box 样式

- `borderStyle`: `"single"` / `"double"` / `"round"` / `"bold"` / `"singleDouble"` / `"doubleSingle"` / `"classic"`
- `borderColor`: 边框前景色（优先级高于 `color`）
- `borderDimColor`: 边框暗色（自动设置 `dim` 属性）

## C 层

- `tui_core.wcwidth` — Unicode 15.1 显示宽度 + `grapheme_next` 字素簇迭代（Hangul/ZWJ/RI/VS15/16）
- `tui_core.keys.parse` — 按键解析（CSI/SS3/UTF-8/修饰符）
- `tui_core.screen` — cell 双缓冲 + 增量 diff + 段合并
- `tui_core.terminal` — 终端 I/O + IME 候选窗定位（Windows）
- `tui_core.text.wrap` — C 实现软换行
- Yoga 布局集成
- `tui.intrinsicSize(element)` — 查询元素树的最小所需尺寸 (cols, rows)
