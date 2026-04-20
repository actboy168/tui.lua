# 项目概览与技术栈

## 项目定义

tui.lua 是一个 Lua + C 实现的终端 UI 框架，灵感来自 [Ink](https://github.com/vadimdemedes/ink)（React for CLI）。

- **定位**：通用 TUI 框架，不是具体的 CLI 应用。下游计划基于此框架构建类 Claude Code 的 AI 聊天 CLI，但该 CLI 不在本仓库范围内。
- **设计倾向**：API 偏向通用原语（Box/Text/Input/List），而非聊天专用抽象。拿不准时问"这个能力属于框架还是属于下游 CLI？"
- **平台**：Windows 11 开发环境（Git Bash），需保持跨平台终端处理的意识。
- **参考实现**：`E:\claude-code\src\ink` — Ink 本地源码副本，对照参考用。关键文件：`src/write-synchronized.ts`（BSU/ESU）、`src/ink.tsx`（主渲染循环）。

## 技术栈

- **运行时**：Lua 5.5（luamake 附带版本）。构建工具：luamake，通过仓库根目录 `make.lua` 构建。
- **布局引擎**：Yoga（通过 vendored C++ 源码 + C 绑定 `luayoga.c`）。
- **组件模型**：类 React — 组件是返回元素树的函数，通过 Lua table 构造。状态通过 `useState` 等 hook 管理。不用 JSX，直接用 Lua table 构造。
- **可用基础库**：bee.lua（子进程/文件系统/套接字/线程/通道/IO）可用。

## C 层与 Lua 层的划分

C 层负责以下 5 项，落在其中的工作默认走 C，除非待办清单中显式说明暂时走 Lua 的理由：

1. **终端 I/O**：raw mode、ANSI/VT 设置、resize 通知、Windows VT
2. **字符宽度 / Unicode**：wcwidth + grapheme cluster 处理（CJK/emoji 对齐）
3. **布局计算**：Yoga
4. **渲染后端**：双缓冲虚拟屏幕 + 行级 diff + ANSI 输出生成
5. **按键解析**：转义序列 → 语义按键（枚举：up/down/ctrl-c/meta-x/...）

颜色名、属性位定义、默认值回退等属于**业务逻辑**，不属于 C 层 scope。C 层只承担 cell buffer + diff + ANSI 生成。每次加一个新 attr 都要改 C 会让 scope 蔓延——应先扩 Lua `sgr.lua` 的位布局，C 侧不用改签名。

**如何应用**：
- 提议任何涉及 render / layout / 终端 / 按键 / 字符宽度的新工作前，先明确"这块在 C 还是 Lua？为什么？"
- 如果现存 Lua 实现（如 `tui/screen.lua` 的行级 diff）本来就该在 C，升级时不要继续往 Lua 加，而是把下沉到 C 本身列进待办清单
- hot-loop（每帧 w*h 级别）相关代码下沉到 C 的门槛是"每帧跑几百次"，而不是"感觉 C 更快"
- 设计 API 时，倾向匹配 Ink 的命名（`<Box>`、`<Text>`、`useInput`、`useState`）转为 Lua 惯例（`tui.box{}`、`tui.text{}`、`tui.use_input(...)`、`tui.use_state(...)`）
