# 组件与 Hook 语义决策

代码和 features.md 表达不出来的非显然选择、否决备选、外部约束。

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

## Harness 测试框架

**泄漏 harness 自动恢复而非硬报错。** `hijack_terminal` 发现 HIJACKED=true 时选择 `restore_terminal()` + 发 `[tui:test]` 警告。硬报错会让 ltest 报告里"第一个真正失败的测试"被淹没在后续 N 个 "another harness is already active" 里。但也不能无声恢复 — 那会掩盖"忘记 :unmount()"的真 bug。未来若改成"多 harness 并存"，此块整段删除，而不是放宽。

**Harness CSI 校验只抓浮点参数。** fake terminal 的 `check_csi_integers` 只找 `\d\.\d` 拒收，没做完整 ANSI parser。本次 bug 场景单一（Yoga float 参数 → 真终端静默丢弃 CUP），窄捕获 10 行解决真问题。遇到新场景再扩规则，不要主动升级成"严格 ANSI 解析器"。

## TextInput 批量输入

`h:dispatch("中文")` 已正确工作（ctxRef eager update）。剩余缺口：`keys.c` 缺少 bracketed-paste 协议（`\x1b[200~` / `\x1b[201~`）。真实终端粘贴以原始字节一次性到达 `read()`，`keys.parse` 会拆成单个事件。目前 ctxRef 已 eager update 所以功能正常，但 0x01–0x1A 范围的字节会被误解为 Ctrl+字母（keys.c 的另一个已知缺口）。
