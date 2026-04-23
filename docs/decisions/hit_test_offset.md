# Hit Test 坐标偏移

## 决策

`do_hit_test` 接收 SGR 鼠标坐标（1-based 终端绝对坐标），但元素 rect 是内容坐标（0-based 从内容顶部算起）。交互模式下内容可能不在终端顶部，存在行偏移。通过 `hit_test.set_row_offset()` 在每帧 paint 时设置偏移量，在 hit_test 内部把终端坐标转换为内容坐标。

## Why

SGR 鼠标事件报告的是终端绝对坐标（从终端左上角 1-based）。`diff_main` 使用相对移动（CUU/CUD），TUI 不知道内容在终端中的绝对位置。假设光标在终端底部启动（最常见场景），内容 y=0 对应终端行 `terminal_h - content_h`。不做偏移转换时，内容高度 < 终端高度的点击全部偏移甚至无法命中。

## How to apply

- `hit_test.set_row_offset(n)` 在 `app_base.paint_fn` 中每帧调用，n = `interactive and (h - content_h) or 0`
- Harness 使用与生产相同的公式（`interactive = true`，短内容时 offset = `rows - content_h`）；vterm 从 (0,0) 开始，内容高度等于终端高度时 offset = 0
- 测试通过 `h:sgr(x, y)` 封装坐标转换，无需手动计算 offset
- `localRow` 回调参数也基于内容坐标：`localRow = ((sgg_row - 1) - _row_offset) - rect.y`
- 未来若需要精确偏移（不假设光标在底部），可在首次渲染前用 DSR 查询光标位置替代当前假设
