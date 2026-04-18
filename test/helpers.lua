-- test/helpers.lua — shared test utilities

local tui = require "tui"

local M = {}

-- Build a chat-mock App with a single scripted reply.
-- Used by both test_chat_flow and test_snapshots.
function M.make_chat_app(reply_text)
    return function()
        local history, setHistory  = tui.useState({})
        local input, setInput      = tui.useState("")
        local streaming, setStream = tui.useState(nil)
        local size                 = tui.useWindowSize()

        tui.useInterval(function()
            if not streaming then return end
            local s = streaming
            if s.shown >= #s.target then
                setHistory(function(h)
                    local nh = {}
                    for i, m in ipairs(h) do nh[i] = m end
                    nh[#nh + 1] = { who = "bot", text = s.target }
                    return nh
                end)
                setStream(nil)
                return
            end
            setStream({ target = s.target, shown = s.shown + 1 })
        end, 40)

        local function submit(value)
            if value == "" then return end
            setHistory(function(h)
                local nh = {}
                for i, m in ipairs(h) do nh[i] = m end
                nh[#nh + 1] = { who = "user", text = value }
                return nh
            end)
            setInput("")
            setStream({ target = reply_text, shown = 0 })
        end

        local function fmt(m)
            local tag = m.who == "user" and "you" or "bot"
            return tui.Text { ("[%s] %s"):format(tag, m.text) }
        end

        return tui.Box {
            flexDirection = "column",
            width  = size.cols,
            height = size.rows,
            tui.Static { items = history, render = fmt, key = "history" },
            streaming and tui.Text { ("[bot] %s"):format(streaming.target:sub(1, streaming.shown)), key = "stream" } or nil,
            tui.Box { flexGrow = 1, key = "spacer" },
            tui.Box {
                borderStyle = "round",
                paddingX = 1,
                key = "prompt",
                tui.TextInput {
                    value    = input,
                    onChange = setInput,
                    onSubmit = submit,
                },
            },
        }
    end
end

return M
