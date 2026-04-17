-- test/test_chat_flow.lua — end-to-end offscreen simulation of the chat demo.
--
-- Mirrors examples/chat_mock.lua but inlined so the test doesn't require
-- examples/ to be a module. Exercises Static + TextInput + useInterval +
-- useWindowSize in one flow: type → submit → stream → resize → unmount.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "chat_flow"

-- Build a chat-mock App with a single scripted reply.
local function make_chat_app(reply_text)
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
            tui.Static { items = history, render = fmt },
            streaming and tui.Text { ("[bot] %s"):format(streaming.target:sub(1, streaming.shown)) } or nil,
            tui.Box { flexGrow = 1 },
            tui.Box {
                border = "round",
                paddingX = 1,
                tui.TextInput {
                    value    = input,
                    onChange = setInput,
                    onSubmit = submit,
                },
            },
        }
    end
end

-- Helper: flatten the laid-out tree to a list of visible Text strings.
local function collect_texts(tree)
    local out = {}
    local function walk(e)
        if not e then return end
        if e.kind == "text" then
            out[#out + 1] = e.text or ""
        end
        for _, c in ipairs(e.children or {}) do walk(c) end
    end
    walk(tree)
    return out
end

function suite:test_type_submit_stream_resize_flow()
    local App = make_chat_app("hello")

    local h = testing.render(App, { cols = 40, rows = 10 })

    -- Type "hi" and press Enter. :type walks UTF-8 boundaries and rerenders
    -- between each keystroke; :press rerenders once after.
    h:type("hi"):press("enter")

    -- After submit: history gains [you] hi; streaming starts at shown=0 so
    -- no streaming row text rendered yet.
    local texts = collect_texts(h:tree())
    local found_user = false
    for _, t in ipairs(texts) do
        if t:find("[you] hi", 1, true) then found_user = true; break end
    end
    lt.assertEquals(found_user, true, "user message should appear in history")

    -- Advance 40ms three times → streaming shown = 3 → "[bot] hel".
    h:advance(40):advance(40):advance(40)
    local partial_found = false
    for _, t in ipairs(collect_texts(h:tree())) do
        if t == "[bot] hel" then partial_found = true; break end
    end
    lt.assertEquals(partial_found, true, "streaming partial 'hel' should render")

    -- Two more ticks finalize "hello" (shown=5 triggers the finalize branch
    -- on the following tick, so advance enough to land on finalize).
    h:advance(40):advance(40):advance(40)
    local final_found = false
    for _, t in ipairs(collect_texts(h:tree())) do
        if t == "[bot] hello" then final_found = true; break end
    end
    lt.assertEquals(final_found, true, "bot reply should finalize into history")

    -- Resize to 60×20: row width expands accordingly and useWindowSize
    -- drives a re-render with the new dimensions.
    h:resize(60, 20)
    lt.assertEquals(#h:rows(), 20, "row count should match new height")
    lt.assertEquals(#h:row(1), 60, "row width should match new cols")

    h:unmount()
end
