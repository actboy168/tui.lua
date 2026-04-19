# tui.lua 项目指令

项目决策详情见 @docs/decisions/_index.md

## 项目定义

Lua + C 终端 UI 框架，灵感来自 Ink。下游 AI 聊天 CLI 不在本仓库范围。API 偏向通用原语，不偏向聊天专用抽象。

## 技术栈

- Lua 5.5 + luamake 构建
- Yoga 布局引擎，属性命名对齐 Ink
- React-like 组件模型，Lua table 构造器即 DSL（不引入自定义语法/模板/JSX-for-Lua）
- bee.lua 可用

## C 层与 Lua 层划分

C 层负责 5 项，落在这 5 项里的默认走 C：

1. 终端 I/O（raw mode、ANSI/VT、resize、Windows VT）
2. 字符宽度 / Unicode（wcwidth + grapheme cluster）
3. 布局计算（Yoga）
4. 渲染后端（双缓冲 + 行级 diff + ANSI 输出）
5. 按键解析（转义序列 → 语义按键）

颜色名/属性位/默认值回退属于业务逻辑走 Lua，C 只做 cell buffer + diff + ANSI 生成。

## 代码风格

- 不用分号，用换行分隔语句
- `local <const>` 只用于基本类型（number/string/boolean），table/function/userdata 不加
- 测试文件不加 `lt.run()`
- 不引入自定义 DSL / 模板语法 / JSX-for-Lua

## Yoga 绑定

- 只用 `flexGrow` / `flexShrink` / `flexBasis`，没有 `flex` shorthand
- `PointScaleFactor=1`，布局坐标为整数，不需要 `math.floor` 补救
- `overflowX` / `overflowY` 在 layout.lua fallback 到 `overflow`
- `border` prop 接受字符串，per-edge border 只接受数字
- 未知 key 报错

## API 设计

- 新增 API 前先检查 Ink 同类 API 的命名和签名，对齐但不照搬
- 组件名用 PascalCase（Box/Text/TextInput），hook 名用 camelCase（useState/useInput）
- prop 名用 camelCase（flexDirection/autoFocus），和 Ink 保持一致
- 公开 API 写 LuaDoc 注释（---@class / ---@type / ---@param / ---@return）
- 新增组件必须写对应的测试文件（test/test_<module>.lua）

## 编码流程

- 修改了 C 代码后必须先 PowerShell 执行 `luamake` 编译，再运行测试
- 编码完成后必须运行测试：PowerShell 执行 `luamake test`，确保全部通过
- 遇到不确定的设计决定（API 命名、语义选择、是否该做等），必须先问我，不能自行做决定
- 已有代码的改动先读懂上下文再动手，不要基于猜测修改

## 构建与验证

- 本机 luamake 必须走 PowerShell，不能走 bash/cmd
- 不要用 stdin 管道验证 TUI demo，用离屏渲染 + 手动驱动定时器
- 写 example 前：先抄已有参照、检查已知约束、写完 harness dump

## 组件语义要点

- reconciler 已支持函数自动包装为组件，但 plain function 里直接调 hook 仍会挂错 instance
- Spinner 无 isActive prop，用条件渲染控制生命周期
- useAnimation delta 用真实虚拟时钟差
- useRef（不刷新）vs useLatestRef（每次 render 刷新）
- useCallback 返回稳定身份 wrapper，deps 变时替换内部 fn
- useReducer 返回原 state 时 rawequal 相等则 bail-out
- Provider 是 structural-only（无 instance、无 hooks、无 effects）
- `[tui:fatal]` 前缀的错误绕过 ErrorBoundary
- Dev-mode 默认关，测试时强开，key 告警阈值 3+

## Roadmap 规范

- Stage 用递增整数，不加字母后缀
- 一个 stage = 一组相关能力，不是每个组件/hook 单独一个
- 已完成特性写 features.md，不写 roadmap
- 简化方案的待办不要括注来源 stage
- 不默认每 stage 归档决策，只记代码和 features.md 表达不出来的
