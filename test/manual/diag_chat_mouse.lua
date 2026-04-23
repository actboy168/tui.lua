-- test/manual/diag_chat_mouse.lua
-- 诊断 chat.lua 鼠标事件路径的每一步。
--
-- 在真实 Windows 控制台（cmd / PowerShell / Windows Terminal）中运行：
--   luamake lua test/manual/diag_chat_mouse.lua
--
-- 设计思路：从底层到高层逐步验证鼠标事件链路，定位 chat.lua 中鼠标
-- 失效的具体环节。

local tui       = require "tui"
local input_mod = require "tui.internal.input"
local terminal_mod = require "tui.internal.terminal"
local tui_core  = require "tui.core"

local log_path  = "diag_chat_mouse_log.txt"
local log_f

local function open_log()
    log_f = io.open(log_path, "w")
    if not log_f then
        io.stderr:write("ERROR: cannot open " .. log_path .. "\n")
        os.exit(1)
    end
end

local function dbg(...)
    local msg = table.concat({...}, " ")
    if log_f then log_f:write(msg .. "\n"); log_f:flush() end
    io.stderr:write(msg .. "\n")
    io.stderr:flush()
end

open_log()

-- ── 0. 环境诊断 ────────────────────────────────────────────────────────────
dbg("=== Environment ===")
dbg("interactive = " .. tostring(terminal_mod.interactive()))
dbg("is_tty      = " .. tostring(terminal_mod.is_tty()))
dbg("is_ci       = " .. tostring(terminal_mod.is_ci()))
local caps = terminal_mod.detect_capabilities()
for k, v in pairs(caps) do
    dbg("cap." .. k .. " = " .. tostring(v))
end

-- 启用框架内部输入调试（会记录原始字节到 input_debug.txt）
input_mod._debug_log = "diag_chat_mouse_input.txt"
io.open(input_mod._debug_log, "w"):close()

-- ── 1. 底层直接测试（复刻 diag_windows_mouse.lua 的核心逻辑）───────────
-- 先确认在这个进程里，terminal.read 确实能拿到鼠标。
local function test_raw_mouse()
    dbg("\n=== Test 1: raw terminal.read + keys.parse ===")
    local terminal = tui_core.terminal
    terminal.windows_vt_enable()
    terminal.set_raw(true)

    -- 手动发送鼠标启用序列（和 diag_windows_mouse.lua 一样）
    terminal.write("\x1b[?1006h")
    terminal.write("\x1b[?1000h")

    local got = false
    local deadline = 3000  -- 3 秒超时
    local start = tui_core.time.now()
    while not got and (tui_core.time.now() - start) < deadline do
        local data = terminal.read()
        if data and #data > 0 then
            local hex = data:gsub(".", function(c) return ("%02X "):format(c:byte()) end)
            dbg("raw bytes: " .. hex:gsub(" $", ""))
            local evs = tui_core.keys.parse(data)
            for _, ev in ipairs(evs) do
                dbg("parsed: name=" .. tostring(ev.name) ..
                    " type=" .. tostring(ev.type) ..
                    " button=" .. tostring(ev.button) ..
                    " x=" .. tostring(ev.x) ..
                    " y=" .. tostring(ev.y))
                if ev.name == "mouse" then got = true end
            end
        else
            tui_core.time.sleep(10)
        end
    end

    -- 关闭鼠标
    terminal.write("\x1b[?1000l")
    terminal.write("\x1b[?1006l")
    terminal.set_raw(false)

    if got then
        dbg("RESULT: raw mouse OK")
    else
        dbg("RESULT: raw mouse FAILED (timeout, no mouse event)")
    end
    return got
end

-- ── 2. 框架路径诊断 ────────────────────────────────────────────────────────
-- 使用 tui.render() 启动最小组件，但保留 stderr 日志输出能力。
-- 注意：tui.render 会劫持 stdout 用于渲染，所以所有诊断必须走 stderr 或文件。

local test_result = { input_events = 0, mouse_events = 0, click_count = 0 }

local function App()
    local count, setCount = tui.useState(0)
    local app = tui.useApp()

    -- mount 时输出订阅状态诊断
    tui.useEffect(function()
        local mh = input_mod._mouse_handlers()
        local mw = input_mod._middleware_list()
        dbg("App mounted: mouse_handlers=" .. #mh .. " middlewares=" .. #mw)
    end, {})

    -- 监听所有键盘/鼠标事件
    tui.useInput(function(input, key)
        test_result.input_events = test_result.input_events + 1
        dbg("useInput: #" .. test_result.input_events ..
            " name=" .. tostring(key.name) ..
            " input=" .. tostring(input) ..
            " ctrl=" .. tostring(key.ctrl) ..
            " mouse?=" .. tostring(key.name == "mouse"))
        if key.name == "char" and input == "q" and not key.ctrl and not key.meta then
            dbg("useInput: 'q' -> exit")
            app.exit()
        end
    end)

    -- 直接订阅鼠标总线（绕过 hit_test）
    tui.useMouse(function(ev)
        test_result.mouse_events = test_result.mouse_events + 1
        dbg("useMouse: #" .. test_result.mouse_events ..
            " type=" .. tostring(ev.type) ..
            " button=" .. tostring(ev.button) ..
            " x=" .. tostring(ev.x) ..
            " y=" .. tostring(ev.y))
    end)

    -- 带 onClick 的 Box，测试 hit_test 路径
    return tui.Box {
        width = 30, height = 6,
        borderStyle = "round",
        color = "green",
        onClick = function(ev)
            test_result.click_count = test_result.click_count + 1
            dbg("onClick! count=" .. test_result.click_count ..
                " x=" .. ev.col .. " y=" .. ev.row ..
                " localCol=" .. ev.localCol .. " localRow=" .. ev.localRow)
            setCount(count + 1)
        end,
        tui.Text { text = "Click inside this box!" },
        tui.Text { text = "Count: " .. count },
        tui.Text { text = "Press 'q' to quit." },
    }
end

local function test_framework_mouse()
    dbg("\n=== Test 2: framework path (tui.render) ===")

    -- 运行框架路径（tui.render 会阻塞直到退出）
    tui.render(App)

    dbg("after run:")
    dbg("  input_events  = " .. test_result.input_events)
    dbg("  mouse_events  = " .. test_result.mouse_events)
    dbg("  click_count   = " .. test_result.click_count)

    if test_result.mouse_events > 0 then
        dbg("RESULT: framework mouse events OK")
    else
        dbg("RESULT: framework mouse events FAILED (no mouse events reached useMouse)")
    end

    if test_result.click_count > 0 then
        dbg("RESULT: hit_test onClick OK")
    else
        dbg("RESULT: hit_test onClick FAILED (no clicks reached onClick handler)")
    end
end

-- ── 主流程 ─────────────────────────────────────────────────────────────────
local raw_ok = test_raw_mouse()
if raw_ok then
    test_framework_mouse()
else
    dbg("\nRaw mouse test failed — framework test skipped.")
    dbg("This means the terminal itself is not sending mouse events,")
    dbg("or tui_core.terminal.read() cannot read them.")
end

dbg("\n=== Done. See " .. log_path .. " and " .. input_mod._debug_log .. " for details. ===")
if log_f then log_f:close() end
