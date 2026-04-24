# 代码风格

## 不用自定义 DSL

tui.lua 用 Lua table 构造器（`Box { padding=1, Text { "hi" } }`）作为元素描述的 "DSL"。不要引入自定义语法、模板语言或外部解析器。

**Why:** Ink 用 JSX，这是宿主语言扩展且零运行时开销。Lua 的 `f { ... }` 语法天然提供相同的人体工程学 — hash key 做 props，array key 做 children（`split_props_children` 已处理）。加自定义 DSL 需要词法/语法分析器、会扭曲错误堆栈、阻断自然的动态组合（如 `for` 循环构建 children、`cond and node or nil`）。

**How to apply:**
- 遇到"DSL"、"模板语法"、"HTML-like markup"、"JSX for Lua"类需求 — 拒绝，解释 table 构造器就是 DSL
- 改进方向：`split_props_children` 语义、EmmyLua `---@class` 注解（IDE 补全）、运行时 prop 校验 — 不做新的语法层

## 不用分号

Lua 代码中不使用 `;` 分隔语句，用换行代替。

**Why:** 项目代码风格统一，所有现有代码均不使用分号。

**How to apply:** 每条语句独占一行。如 `ctxRef.setCaret(c - 1); ctxRef.caret = c - 1` 应拆成两行。

## local \<const\> 的使用

`local <const>` 只用于基本类型（number、string、boolean），table/function/userdata 类型的变量不加。

**Why:** Lua 5.5 的 `<const>` 只阻止变量重新赋值，不阻止修改对象内容。对 table（含 `M = {}` 模块表）、function、userdata 加 `<const>` 实际意义不大，反而增加噪音。

**How to apply:**
- 加 `<const>`：`local <const> MAX_PAINT_PASSES = 4`、`local <const> ESC = "\27"`
- 不加 `<const>`：`local M = {}`、`local NOOP = function() end`、`local tui_core = require "tui.core"`、`local COLORS = { ... }`

## 测试文件不加 lt.run()

测试文件（`test/test_*.lua`）末尾不应包含 `lt.run()`。

**Why:** `luamake test` 自动发现并运行所有测试套件。单个文件里的 `lt.run()` 会干扰，导致重复执行或聚合问题。

**How to apply:** 测试文件只定义 suite 和其函数，不调用 `lt.run()`。

## 组件 children 中的条件渲染

在组件构造器（`Box`、`Text` 等）的 children 列表中，用 `cond and Element{}` 即可，**不要**写成 `cond and Element{} or nil`。

**Why:**
- Lua 的 array table 中间插入 `nil` 会产生空洞，破坏 `#` 运算符和 `ipairs` 的连续性。虽然框架的 `split_props_children` 会通过 `pairs` + 压缩来容错，但依赖这种容错不是好做法。
- `cond and Element{}` 在 `cond` 为 `false` 时会在 array 中留下 `false`（不是 `nil`），这是合法值。reconciler 的 `expand` 已显式处理 `false`（视为无内容跳过），所以完全不需要 `or nil`。

**How to apply:**
- 推荐：`step == 2 and tui.Box { ... }`
- 避免：`step == 2 and tui.Box { ... } or nil`
- 此规则仅适用于 **children array** 中的条件表达式；普通表达式（如局部变量赋值、prop 默认值）中的 `or nil` 不受限制。
