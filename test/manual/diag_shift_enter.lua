-- test/manual/diag_shift_enter.lua
-- 诊断 VS Code Terminal 中 Shift+Enter 的按键事件路径。
--
-- 运行方式（在 VS Code Terminal 中）：
--   luamake lua test/manual/diag_shift_enter.lua
--
-- 按 'q' 退出，按 Shift+Enter / Enter / Ctrl+Enter 观察输出。

local tui          = require "tui"
local tui_core     = require "tui.core"
local keys         = tui_core.keys
local terminal_mod = require "tui.internal.terminal"

local log_path = "diag_shift_enter_log.txt"
local log_f = io.open(log_path, "w")

local function file_log(...)
    if log_f then
        log_f:write(table.concat({...}, " ") .. "\n")
        log_f:flush()
    end
end

local function App()
    local app = tui.useApp()
    local caps = terminal_mod.detect_capabilities()

    -- 环境信息只打一次到文件
    file_log("=== Environment ===")
    for k, v in pairs(caps) do
        file_log("cap." .. k .. " = " .. tostring(v))
    end
    file_log("KKP enabled: " .. tostring(caps.kitty_keyboard))

    tui.useInput(function(input, key)
        -- 原始字节 hex dump
        local raw = key.raw or ""
        local hex = raw:gsub(".", function(c) return ("%02X "):format(c:byte()) end)
        hex = hex:gsub(" $", "")

        -- 组装解析信息
        local info = key.name
        if key.input and #key.input > 0 then
            info = info .. " input=" .. key.input:gsub("\r", "\\r"):gsub("\n", "\\n")
        end
        if key.ctrl  then info = info .. " ctrl" end
        if key.shift then info = info .. " shift" end
        if key.meta  then info = info .. " meta" end
        if key.event_type then info = info .. " " .. key.event_type end

        -- 文件记录完整信息
        file_log("RAW: " .. hex)
        file_log("  -> " .. info)

        -- tui.log 只显示摘要（底部 log bar，只保留最新一条）
        tui.log(info .. " | " .. hex)

        if key.name == "char" and input == "q" and not key.ctrl and not key.meta then
            app:exit()
        end
    end)

    return tui.Box {
        width = 60,
        height = 6,
        flexDirection = "column",
        tui.Text { text = "Diag: Shift+Enter in VS Code Terminal" },
        tui.Text { text = "KKP: " .. tostring(caps.kitty_keyboard) .. " (type: " .. caps.terminal_type .. ")" },
        tui.Newline(),
        tui.Text { text = "Press Enter, Shift+Enter, Ctrl+Enter" },
        tui.Text { text = "Watch bottom log bar. Press 'q' to quit." },
    }
end

-- tui.render 会自动处理 raw mode、KKP push/pop、bracketed-paste 等
tui.render(App)

file_log("Done.")
if log_f then log_f:close() end
