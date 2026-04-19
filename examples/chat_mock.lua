-- examples/chat_mock.lua — simulated AI chat UI.
--
-- Demonstrates:
--   * <Static> for append-only message history (rows don't redraw once set)
--   * <TextInput> with IME-aware cursor placement
--   * useInterval to stream bot reply character-by-character
--
-- Keys: Enter to submit, Ctrl+C / Ctrl+D to quit.

local tui = require "tui"

-- Scripted bot replies in lock-step with user input count.
local replies = {
    "hi there! how can I help?",
    "好的，我明白你的意思。",
    "sure — anything else?",
    "再见 👋",
}

local function formatMsg(msg)
    -- msg = { who = "user"|"bot", text = string }
    local tag = msg.who == "user" and "you" or "bot"
    local color = msg.who == "user" and "green" or "cyan"
    return tui.Text { color = color, ("[%s] %s"):format(tag, msg.text) }
end

local function App()
    local history, setHistory   = tui.useState({})
    local input, setInput       = tui.useState("")
    local streaming, setStream  = tui.useState(nil)  -- { target=reply_str, shown=n } or nil

    -- Stream a bot reply one char at a time when one is active.
    tui.useInterval(function()
        if not streaming then return end
        local s = streaming
        if s.shown >= #s.target then
            -- Finalize: commit the full bot message to history.
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
        -- Append user message.
        setHistory(function(h)
            local nh = {}
            for i, m in ipairs(h) do nh[i] = m end
            nh[#nh + 1] = { who = "user", text = value }
            return nh
        end)
        setInput("")
        -- Queue a bot reply (cycle through scripted replies).
        local idx = ((#history) % #replies) + 1
        setStream({ target = replies[idx], shown = 0 })
    end

    -- Build the Static items list. When a bot reply is streaming, show the
    -- partial text as a dynamic row below Static (not part of history yet).
    local size = tui.useWindowSize()

    return tui.Box {
        flexDirection = "column",
        width  = size.cols,
        -- History (append-only) at the top.
        tui.Static {
            items  = history,
            render = function(m) return formatMsg(m) end,
        },
        -- Streaming partial reply (dynamic).
        streaming and tui.Text {
            color = "cyan", dim = true,
            ("[bot] %s▍"):format(streaming.target:sub(1, streaming.shown))
        } or nil,
        -- Input row.
        tui.Box {
            borderStyle = "round",
            color  = "yellow",
            paddingX = 1,
            tui.TextInput {
                value    = input,
                onChange = setInput,
                onSubmit = submit,
                placeholder = "type a message and press Enter",
            },
        },
    }
end

tui.render(App)
