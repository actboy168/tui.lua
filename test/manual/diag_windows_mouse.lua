-- test/manual/diag_windows_mouse.lua
-- Windows 鼠标事件诊断脚本
--
-- 在真实 Windows 控制台（cmd / PowerShell / Windows Terminal）中运行：
--   luamake lua test/manual/diag_windows_mouse.lua
--
-- 目的：检测鼠标事件是否能被底层 terminal.read_raw() 读取到，并观察其原始字节格式。
--
-- 预期问题（供参考）：
--   当前 Windows 下的 l_read_raw() 只处理 KEY_EVENT，未处理 MOUSE_EVENT；
--   且 l_set_raw() 未启用 ENABLE_VIRTUAL_TERMINAL_INPUT / ENABLE_MOUSE_INPUT。
--   因此鼠标事件可能完全无法到达应用程序。

local tui_core = require "tui_core"
local terminal = tui_core.terminal
local keys     = tui_core.keys
local time     = tui_core.time

local ESC = "\x1b"

local function hex_dump(s)
    return s:gsub(".", function(c) return string.format("%02X ", c:byte()) end):gsub(" $", "")
end

local function enable_mouse()
    terminal.write(ESC .. "[?1006h")  -- SGR extended coordinates
    terminal.write(ESC .. "[?1000h")  -- click reporting
end

local function disable_mouse()
    terminal.write(ESC .. "[?1000l")
    terminal.write(ESC .. "[?1006l")
end

local function main()
    io.stdout:write("Windows Mouse Event Diagnostic\n")
    io.stdout:write("==============================\n")
    io.stdout:write("Please run this inside a real console window (not a pipe).\n")
    io.stdout:write("Click inside the window with your mouse, or press 'q' to quit.\n\n")

    -- Enable VT processing on stdout
    local ok = terminal.windows_vt_enable()
    if not ok then
        io.stdout:write("Warning: windows_vt_enable() returned false. VT sequences may not work.\n")
    end

    -- Enter raw mode
    terminal.set_raw(true)

    -- Enable mouse reporting in the terminal
    enable_mouse()

    local running = true
    local event_count = 0

    while running do
        local data = terminal.read_raw()
        if data and #data > 0 then
            event_count = event_count + 1
            io.stdout:write(string.format("[#%d] Raw bytes (%d): %s\n",
                event_count, #data, hex_dump(data)))

            local evs = keys.parse(data)
            for _, ev in ipairs(evs) do
                if ev.name == "mouse" then
                    io.stdout:write(string.format(
                        "      -> Parsed mouse: type=%s button=%s x=%d y=%d shift=%s ctrl=%s meta=%s\n",
                        tostring(ev.type),
                        tostring(ev.button),
                        ev.x, ev.y,
                        tostring(ev.shift),
                        tostring(ev.ctrl),
                        tostring(ev.meta)
                    ))
                elseif ev.name == "char" and ev.input == "q" and not ev.ctrl and not ev.meta then
                    io.stdout:write("      -> Quit key detected\n")
                    running = false
                else
                    io.stdout:write(string.format(
                        "      -> Parsed event: name=%s input=%s ctrl=%s shift=%s\n",
                        tostring(ev.name),
                        tostring(ev.input),
                        tostring(ev.ctrl),
                        tostring(ev.shift)
                    ))
                end
            end
            io.stdout:flush()
        else
            time.sleep(10)
        end
    end

    -- Cleanup
    disable_mouse()
    terminal.set_raw(false)

    io.stdout:write("\nDiagnostic complete.\n")
    io.stdout:write(string.format("Total raw reads with data: %d\n", event_count))
    if event_count == 0 then
        io.stdout:write("\nNOTE: No mouse data was received at all.\n")
        io.stdout:write("This confirms mouse events are not reaching the application on Windows.\n")
    end
end

main()
