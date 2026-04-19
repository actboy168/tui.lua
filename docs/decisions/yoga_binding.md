# Yoga 绑定决策

luayoga.c 已完成大修，属性命名对齐 Ink。

## 已完成的绑定

- `flexGrow` / `flexShrink` / `flexBasis` 独立 prop（`flex` shorthand 已删除，不兼容）
- `aspectRatio` / `overflow` / `boxSizing` setter
- per-edge border：`borderTop` / `borderBottom` / `borderLeft` / `borderRight`
- 新增枚举：`Align.Stretch` / `Overflow.Visible|Hidden|Scroll` / `BoxSizing.BorderBox|ContentBox`
- `PointScaleFactor=1`（设于 `YGConfigGetDefault()`），`node_get` 返回 `lua_pushinteger`
- 未知 key 报错（不再静默忽略）

## 否决的选项

- **保留 `flex` shorthand 兼容**：用户明确要求去掉，不保留 alias。Ink 不暴露 `flex` shorthand，只有独立的 `flexGrow`/`flexShrink`/`flexBasis`。之前 `flexGrow=1` 静默失效是高频坑。
- **`YGNodeSetPointScaleFactor`**：此版本 Yoga 没有此 API，改用 `YGConfigSetPointScaleFactor(YGConfigGetDefault(), 1.0f)` 在模块加载时设一次。
- **C 层加 `overflowX`/`overflowY` setter**：Yoga 不分轴，只有 `YGNodeStyleSetOverflow`。在 layout.lua 做 fallback 到 `overflow`，C 只暴露 `overflow`。
- **`border` 进 passthrough 列表**：`border` prop 接受字符串（`"round"` 等），传给 C 会报 "Invalid number"。只走手动转换（`style.border = 1`），per-edge border 进 passthrough。

## 如何应用

- 用 `flexGrow = 1` 代替 `flex = 1`（shorthand 已删）
- `border` prop 仍接受字符串（`"round"` / `"single"` 等），在 layout.lua 转为数字 `1` 传给 Yoga；per-edge border 只接受数字
- `overflowX` / `overflowY` 在 layout.lua 做 fallback 到 `overflow`（Yoga 不分轴）
- 布局坐标已是整数，不需要 `math.floor` 补救
- 性能优化不是此轮目标（passthrough 数组重构不做），属性命名和 Ink 保持一致
