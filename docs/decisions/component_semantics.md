# 组件与 Hook 语义决策

代码和 API 本身表达不出来的非显然选择、否决备选、外部约束。

## Focus 系统

**重复 focus id 硬失败。** 旧行为是静默追加 `#seq` 后缀，掩盖了用户 bug。现在直接 `error("duplicate focus id")`。沉默降级伤害比报错大。如果将来有"合法的重复 id"场景再改回；目前没有。

**显式 autoFocus，否决 implicit single-entry grab。** 旧版只有一个 useFocus 注册时会自动聚焦；现在要求显式 `autoFocus = true`。Ink 语义就是显式；implicit grab 让"增删 sibling 改变 focus 行为"成为隐患。

**`suppress_initial` 未实现。** 曾提议 `focus.subscribe { suppress_initial = true }`；最终用 `isActive = false` 覆盖了 disabled-TextInput 场景。一个字段能做的事别加两个。除非出现"先静默注册再激活"的真实用例再加。

**`autoFocus` 不 hot-update。** 只在每次 subscribe 时读一次。`id` / `isActive` 都 hot-update，唯独 `autoFocus` 不 — autoFocus 是"初次注册时抢不抢"，不是"此刻是否该被聚焦"。要运行时抢焦点用 `useFocusManager().focus(id)`。

## ErrorBoundary

**`[tui:fatal]` 前缀协议。** 错误消息以 `[tui:fatal] ` 开头的会被 ErrorBoundary 级 pcall 识别并继续上抛（绕过 boundary 兜底）。有些错误（重复 focus id、重复 reconciler key）是结构性 bug，不应被 boundary 吞掉。抛这类错时用 `reconciler.fatal(msg)`；`is_fatal(err)` 检查 rethrow。

**fallback 函数抛错降级为空 box。** `fallback = function(err, reset) ... end` 里如果 throw，结果是渲染空 box 而非再次冒泡。fallback 代码出错不该让整个应用挂掉；但 fatal 前缀仍保留上抛能力 — fallback 里要"更严重的错"走 `reconciler.fatal()`。

**reset 闭包必须 reference-stable。** React 语义要求 reset 可作 `useEffect` dep；每次渲染重建 dep 会假阳性变化，导致 `useEffect(fn, {reset})` 无限循环。实现上懒创建并缓存到 `inst._reset`。

**`useErrorBoundary` 无祖先时返回 noop reset 而非 nil。** 调用方不用 `if reset then reset() end`。

**caught_error 粘性，只有 reset() 清除。** 进 boundary 分支刷 `inst.dirty` 但不清 caught_error。用户可能在 boundary 内自己写条件分支决定何时重试，框架不该替他决定。

## Hook 语义

### useRef vs useLatestRef

- `useRef(initial)` — 用户版，`.current` 首次挂载时 eager-init，后续 render 不会从新参数刷新。等价 React `useRef`。
- `useLatestRef(value)` — 每次渲染都刷 `.current = value`，防止长生命周期订阅闭包抓旧值。已公开为 `tui.useLatestRef`。

搞混会导致 timer 抓不到新 state 或 ref 被意外覆盖。一个存"写什么是什么"，一个存"永远最新"。

### useCallback 的 identity trick

返回的不是 `slot.fn` 本身，而是一个常驻 wrapper `function(...) return slot.fn(...) end`；`slot.fn` 在 deps 变时替换。用户看到的 callback 身份永远稳定（可作 useEffect dep 不触发循环），内部 body 随 deps 更新。这和 `useMemo(() => fn, deps)` 不等价 — 后者 deps 变时返回的 fn 本身身份会变。

### useReducer bail-out

`reducer(state, action) == state`（rawequal）时 dispatch 直接 no-op，不 `inst.dirty = true` 也不 `requestRedraw()`。和 React 一致。reducer 里想要"此 action 无效果"就返回原 state，别 `return { ...state }` 造新对象 — 那样框架会误以为状态变了并重渲染。

### Provider 是 structural-only

`ctx.Provider { value=X, children }` 不创建 instance、不走 hooks、没有 effects。reconciler 里展开时把 `{context, value}` 压进 `state.context_stack`，递归子树完后弹出。Provider 没有自身状态，加 instance 白浪费 hooks 数组；structural-only 还避免了"Provider 自己 rerender 但 value 没变也触发子树 rerender"的伪依赖。

## Dev-mode

**`tui.setDevMode(bool)`，默认关，无环境变量。** `tui.testing.render` / `mount_bare` 进入时强开，unmount 时复位。生产零开销（每个检查就是一次早退分支），测试路径全覆盖。

**Key 告警阈值 3+ 而非 2+。** `#children >= 3` AND `elem_count >= 3` AND 任一 element 无 key 才告警。对齐 Ink / React DevTools 先例 — 手写的静态 2 孩子 `Box { A, B }` 几乎从不是 keying bug 的现场；真正出问题的是迭代生成的 3+ 列表。

**Fail-on-warn 在 unmount 时触发，不在每次 write 触发。** 测试 harness 挂钩 `io.stderr`，未预期的 `[tui:dev]` 累积到数组；unmount 时若非空就抛 `[tui:fatal]`。抛错需要 pcall 安全的触发点，unmount 是自然的"测试结束"边界。

**Component factory 必须 hoist `key` 到 element 顶层。** 写新 component factory 时：`local key = props.key; props.key = nil; return { kind="component", fn=..., props=props, key=key }`。

**框架内部迭代产生的 3+ 子节点自行分配索引 key。** 如 `Static` 内部 Box 自己分配 `"static:"..i`，不让框架内部的迭代泄漏到用户告警流。

## 动画与 Spinner

**useAnimation `delta` 用真实虚拟时钟差，不是固定 `interval`。** 固定 interval 方案在 `harness:advance(N)` 大步推进会丢失真实时间尺度。实现读 `scheduler.now()`。未来任何帧驱动 hook（useFrame、useTween 等）都按真实时钟给 delta。

**Spinner 无 `isActive` prop — 用条件渲染控制生命周期。** 对齐 Ink ink-spinner。`isActive` 只是重复 mount/unmount；React-style 的地道写法就是 `isLoading and Spinner{} or nil`。给组件加 prop 会让用户误以为"停止但保留"有意义。Hook 层的 `useAnimation` 仍保留 `isActive`，因为 hook 粒度用户可能想在 render 内动态暂停而不拆解树形。其它外层组件（ProgressBar、Select 的 loading 态等）同理：能用条件渲染表达的就不加 prop flag。

## useEffect vs useLayoutEffect

**useLayoutEffect 在绘制前同步执行，useEffect 在绘制后异步执行。** TUI 中没有浏览器 DOM 的"闪烁"问题，但同步修正状态仍然重要：TextInput/Textarea 的 caret/selection clamping、Textarea 的 scroll_top 同步、Select 的 highlight clamping 都需要在返回 tree 前完成，否则会导致一帧延迟。

**两者共享同一 slot 结构（`kind = "effect"` / `"layout_effect"`），但使用不同 pending 队列。** `_flush_layout_effects` 在 reconciler stabilization 后、返回 tree 前执行；`_flush_effects` 在同一位置之后执行。这样 layout effects 和普通 effects 在同一组件上保持正确顺序（layout 先）。

**useLayoutEffect 中的 setState 仍然延迟到下一帧。** 虽然 effect 是同步执行的，但 stabilization 循环已经结束，所以 `setState` 触发的 dirty 不会在同一次 `render()` 中消费。这和 React 行为一致：layout effect 可以读取最新布局，但状态更新仍进入下一次调度。

## Harness 测试框架

**泄漏 harness 自动恢复而非硬报错。** `hijack_terminal` 发现 HIJACKED=true 时选择 `restore_terminal()` + 发 `[tui:test]` 警告。硬报错会让 ltest 报告里"第一个真正失败的测试"被淹没在后续 N 个 "another harness is already active" 里。但也不能无声恢复 — 那会掩盖"忘记 :unmount()"的真 bug。未来若改成"多 harness 并存"，此块整段删除，而不是放宽。

**Harness CSI 校验只抓浮点参数。** fake terminal 的 `check_csi_integers` 只找 `\d\.\d` 拒收，没做完整 ANSI parser。本次 bug 场景单一（Yoga float 参数 → 真终端静默丢弃 CUP），窄捕获 10 行解决真问题。遇到新场景再扩规则，不要主动升级成"严格 ANSI 解析器"。

## TextInput 批量输入

`h:dispatch("中文")` 已正确工作（ctxRef eager update）。Bracketed-paste 协议（`\x1b[200~` / `\x1b[201~`）由 `keys.c` 识别为 `paste_start` / `paste_end` 事件，`input.lua` 累加器合并为单一 `paste` 事件再分发；TextInput 的 `onInput` 处理 `name=="paste"` 分支批量插入，`usePaste(fn)` 对外暴露为 `tui.usePaste`。

## 点击语义

**宿主层用 `onMouseDown`，语义组件用 `onClick`。** hit-test 层上报的是原始左键按下，不等于“激活”。`Link` 这类组件可能由鼠标或键盘 `Enter` 触发，所以高层 API 保留 `onClick` 表示语义激活，底层 host prop 改名 `onMouseDown` 避免歧义。未来 `Button` 等组件沿用同一约定。

**`href` / OSC 8 和 `onClick` 分离。** 终端原生超链接是否真的被打开对应用不可观测；`onClick` 只表示框架收到了鼠标或键盘激活。需要本地桥接、自定义跳转或埋点时，用组件层回调；需要终端自行处理时，提供 `href`。

## Transform 语义

**`Transform` 采用 region/cell 语义，不做 string transform。** `Transform` 操作的是渲染后的 cell/region。原因是本项目的主渲染链是 `element tree -> layout -> screen cell buffer -> diff`，字符串级 transform 会破坏样式、超链接元数据和裁剪语义。

**rich-children `Link` 建在 `Transform` 之上。** plain-label `Link` 仍可走 `RawAnsi` 快路径；当 `Link` 包裹任意子树时，通过 `Transform` 给整棵子树附加 hyperlink metadata，而不是把子树 flatten 成字符串再重解析。

## `ref` 和 `key` 必须显式传播

**Element schema：** `element.lua` 创建 element 时会把 `ref` 和 `key` **从 props 里取出**，放到 element 的顶层字段（`element.ref`、`element.key`），props 里不再含有它们。因此任何对 element 做结构性复制（clone、expand 等）的代码，**必须显式拷贝 `ref` 和 `key`**，不能只拷贝 `props`。

`reconciler.lua` 的 `expand()` 在重建 host element 时曾遗漏这两个字段，导致 `layout.fire_measure_refs` 找不到 ref 回调，`useMeasure` 永远收不到正确的 `scroll_window`，Textarea 滚动计算错误。修复：`{ kind=..., key=element.key, ref=element.ref, props=..., children={} }`。

写新的 element 结构变换时，检查清单：
1. `kind` — element 类型
2. `key` — reconciler 身份（diffing 用）
3. `ref` — useMeasure / 外部 DOM 引用
4. `props` — 组件自定义属性（已不含 key/ref）
5. `children` — 子节点
