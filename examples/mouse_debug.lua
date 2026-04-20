-- examples/mouse_debug.lua - 鼠标事件调试工具
-- 运行: luamake lua examples/mouse_debug.lua
-- 点击/拖拽鼠标，观察事件。按 q/Esc 退出。

local tui = require "tui"

local function MouseDebug()
    local events, setEvents = tui.useState({})
    local app = tui.useApp()

    tui.useInput(function(_, key)
        if key.name == "q" or key.name == "escape" then
            app:exit()
        end
    end)

    tui.useMouse(function(ev)
        local entry = ("%s  btn=%-4s  x=%-3d y=%-3d"):format(
            (ev.type .. "      "):sub(1, 8),
            tostring(ev.button),
            ev.x or 0,
            ev.y or 0
        )
        local list = {}
        -- Keep last 10 events (newest first)
        table.insert(events, 1, entry)
        for i = 1, math.min(10, #events) do
            list[i] = events[i]
        end
        setEvents(list)
    end)

    local rows = { tui.Text { bold = true, "鼠标事件 (q/Esc 退出)" } }
    table.insert(rows, tui.Text { dim = true, "--- 点击、拖拽、滚轮 ---" })
    if #events == 0 then
        table.insert(rows, tui.Text { dim = true, "(等待事件...)" })
    end
    for _, line in ipairs(events) do
        table.insert(rows, tui.Text { line })
    end

    return tui.Box {
        flexDirection = "column",
        padding = 1,
        table.unpack(rows),
    }
end

tui.render(MouseDebug)
