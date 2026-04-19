-- examples/chat_mock.lua — simulated AI chat UI.
--
-- Demonstrates:
--   * <Static> for append-only message history (rows don't redraw once set)
--   * <Textarea> with bracketed-paste multi-line support
--   * useInterval to stream bot reply character-by-character
--
-- Keys: Ctrl+Enter to submit, Enter for newline, Ctrl+C / Ctrl+D to quit.

local tui = require "tui"

-- Scripted bot replies in lock-step with user input count.
local replies = {
    "hi there! how can I help?",
    "好的，我明白你的意思。",
    "sure — anything else?",
    "再见 👋",
}

-- Render a single chat message.  Multi-line values (pasted text) are shown
-- with the tag on the first line and subsequent lines indented to align.
local function formatMsg(msg)
    local tag   = msg.who == "user" and "you" or "bot"
    local color = msg.who == "user" and "green" or "cyan"
    local prefix  = ("[%s] "):format(tag)
    local indent  = (" "):rep(#prefix)
    local lines   = {}
    for line in (msg.text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    local children = {}
    for i, line in ipairs(lines) do
        local text = (i == 1 and prefix or indent) .. line
        children[#children + 1] = tui.Text { color = color, text }
    end
    if #children == 1 then return children[1] end
    return tui.Box { flexDirection = "column", table.unpack(children) }
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
        -- Trim trailing whitespace/newlines before sending.
        local trimmed = value:match("^(.-)%s*$")
        if trimmed == "" then return end
        setHistory(function(h)
            local nh = {}
            for i, m in ipairs(h) do nh[i] = m end
            nh[#nh + 1] = { who = "user", text = trimmed }
            return nh
        end)
        setInput("")
        local idx = ((#history) % #replies) + 1
        setStream({ target = replies[idx], shown = 0 })
    end

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
        -- Multi-line input area.
        tui.Box {
            flexDirection = "column",
            borderStyle = "round",
            color  = "yellow",
            paddingX = 1,
            tui.Textarea {
                value    = input,
                onChange = setInput,
                onSubmit = submit,
                placeholder = "type a message — Enter for newline, Ctrl+Enter to send",
                height   = 3,
            },
            tui.Text {
                dim = true, color = "yellow",
                "Ctrl+Enter to send  ·  paste multi-line text freely",
            },
        },
    }
end

tui.render(App)
