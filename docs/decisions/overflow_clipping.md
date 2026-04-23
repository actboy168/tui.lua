# 内容溢出裁剪方向

## 决策

当 interactive 模式下内容高度（`tree.rect.h`）超过终端高度（`h`）时，显示**底部**的 `h` 行，顶部溢出内容随初次渲染的 `\r\n` 自然滚入终端滚动缓冲。

## Why

用户期望 TUI 程序像普通 shell 程序一样：内容超过终端时，最新/最底部的内容可见，历史内容可通过终端滚动条回看。截断顶部（保底部）比截断底部更符合直觉。

对于显式设了 `height > terminal_h` 的 Box，行为也相同——始终底部优先，不区分"自然溢出"和"显式超高 Box"。

## How to apply

- `app_base.paint_fn` 中：
  - `raw_h = tree.rect.h`（不 clamp）
  - `y_off = interactive and max(0, raw_h - h) or 0`（顶部跳过的行数）
  - `content_h = min(raw_h, h)`（实际 diff 的行数）
  - `row_offset = interactive and (h - raw_h) or 0`（统一公式，可为负）
  - `renderer.paint(tree, screen_state, y_off)`（渲染偏移）
- `renderer.lua`：`ry = r.y - y_off`，所有绘制 y 坐标用 `ry`
- `hit_test` 的 `_row_offset` 在溢出时为负值（`h - raw_h < 0`），命中计算 `content_row = (sgr_row - 1) - _row_offset` 仍然正确
- harness 是 interactive=true，同样遵循底部优先逻辑；非 interactive 模式 `y_off = 0`，不受影响
