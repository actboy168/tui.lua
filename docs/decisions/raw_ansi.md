# RawAnsi 组件语义

## 决策

`RawAnsi` 作为独立 host leaf 接入现有 screen backend，公开 API 对齐 Ink：`tui.RawAnsi { lines = {...}, width = n }`。`lines` 只接收已经按行拆好的字符串，布局尺寸由 `width` 与 `#lines` 决定。当前版本支持 SGR 样式序列和 OSC 8 超链接；其他 OSC、光标移动、擦除、清屏等控制序列直接报错。`lines = {}` 返回 `nil`，不渲染节点。

## Why

- 现有渲染架构是 `layout -> screen cell buffer -> diff -> ANSI 输出`。如果直接把原始 ANSI 字节写到 stdout，会绕过布局、裁剪、双缓冲、行级 diff 和测试 harness。
- 只接收 `lines` + `width`，让 RawAnsi 保持“原样渲染但仍受布局约束”的定位，不重新发明带 ANSI 感知的换行器。
- ANSI 通常是终端输出格式，不是上游的原始数据模型；真正的分段、分行边界应该在生成 ANSI 之前就由原始格式决定，而不是在 ANSI 层二次猜测。
- SGR 覆盖颜色和文字属性，OSC 8 覆盖终端原生超链接，这两类都能稳定映射到现有 cell buffer / diff 语义；其他控制序列会改变光标或屏幕状态，半支持比直接报错更危险。

## How to apply

- 适合承载外部已渲染好的 ANSI 行片段，例如彩色 diff、日志片段、带样式的流式输出。
- 调用方应先在原始格式层完成分段/分行，再把每一行转换成 ANSI 交给 `RawAnsi`；`RawAnsi` 不做 wrap，也不接收 children。
- 需要终端原生超链接时，可在行内放 OSC 8；超链接元数据会跟随 screen backend 的 cell buffer 和 diff 一起走。
- 若未来要支持其他 OSC、光标移动或擦除，不要静默放宽解析器；先补决策，明确它们如何映射到 screen backend 和测试语义。
