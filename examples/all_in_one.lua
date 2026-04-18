-- examples/all_in_one.lua — mock AI chat CLI.
--
-- This is the motivating downstream use case for tui.lua (see
-- docs/roadmap.md / memory project_goal): a Claude-Code-style interactive
-- chat REPL. The example stays self-contained (no real model call) but
-- exercises most of the framework in a realistic shape:
--
--   Layout & styling     : Box (flex / border / padding / color), Text
--   Builtin components   : Static, TextInput, Spinner, Select, ProgressBar
--   Hooks                : useState, useEffect, useInterval, useAnimation,
--                          useContext, useFocus, useFocusManager, useInput,
--                          useWindowSize, useApp, useRef
--   Error handling       : ErrorBoundary with function fallback
--   Theming              : createContext / Provider
--
-- Commands / keys:
--   Enter                 send message
--   /model                open model picker (↑/↓ + Enter)
--   /theme                toggle dark / light theme
--   /clear                clear chat history
--   /crash                raise a demo error (caught by ErrorBoundary)
--   /reset                reset the ErrorBoundary
--   ? or F1               toggle help overlay
--   q / Esc / Ctrl+C/D    quit

local tui = require "tui"

-- Wrap a plain "render function" into a component element so its hooks
-- (useContext, useAnimation, etc.) live on their own instance rather than
-- leaking into whichever parent render happens to call us. Without this,
-- conditionally rendering something like HelpBox() would change the
-- parent's hook count between renders and trigger the Stage-17 hook-order
-- fatal. Analogous to `React.createElement(Fn, props)` vs `Fn(props)`.
local function component(fn)
    return function(props)
        props = props or {}
        local key = props.key
        props.key = nil
        return { kind = "component", fn = fn, props = props, key = key }
    end
end

-- -----------------------------------------------------------------------------
-- Theme context. Two palettes; flipped via `t` or `/theme`.

local DARK = {
    fg        = "white",
    accent    = "cyan",
    muted     = "gray",
    user      = "green",
    bot       = "cyan",
    danger    = "red",
    border_fg = "yellow",
}
local LIGHT = {
    fg        = "black",
    accent    = "blue",
    muted     = "gray",
    user      = "green",
    bot       = "magenta",
    danger    = "red",
    border_fg = "blue",
}

local ThemeCtx = tui.createContext(DARK)

-- -----------------------------------------------------------------------------
-- Scripted bot replies. Rotated each turn so the demo reads naturally.

local REPLIES = {
    "Sure! What would you like to explore?",
    "好的，我来帮你。请稍等一下…",
    "I would approach that by breaking it into three steps.",
    "这是一个有趣的问题。让我想一想。",
    "Happy to help — could you share a bit more context?",
    "完成了 👍  还有其它需要吗？",
}

-- -----------------------------------------------------------------------------
-- Header: title + current model + uptime (useAnimation-driven) + hints.

local Header = component(function(props)
    local theme = tui.useContext(ThemeCtx)
    local anim  = tui.useAnimation { interval = 1000 }
    local secs  = math.floor((anim.time or 0) / 1000)

    return tui.Box {
        flexDirection = "row",
        borderStyle = "round",
        color = theme.border_fg,
        paddingX = 1,
        tui.Text { key = "title", color = theme.accent, bold = true, "chat demo" },
        tui.Box  { key = "gap1",  width = 2 },
        tui.Text { key = "mlabel", color = theme.muted, "model:" },
        tui.Box  { key = "gap2",  width = 1 },
        tui.Text { key = "mval",  color = theme.fg, props.model },
        tui.Box  { key = "grow",  flexGrow = 1 },
        tui.Text { key = "up",    color = theme.muted, ("uptime %ds"):format(secs) },
        tui.Box  { key = "gap3",  width = 2 },
        tui.Text { key = "hint",  color = theme.muted, "?:help  q:quit" },
    }
end)

-- -----------------------------------------------------------------------------
-- Chat history: append-only Static log. Each message is a {who, text} pair.

local History = component(function(props)
    local theme = tui.useContext(ThemeCtx)
    return tui.Static {
        items  = props.messages,
        render = function(m)
            local color = m.who == "user" and theme.user or theme.bot
            local tag   = m.who == "user" and "you" or "bot"
            return tui.Text { color = color, ("[%s] %s"):format(tag, m.text) }
        end,
    }
end)

-- -----------------------------------------------------------------------------
-- A component that throws on demand. Used to demo ErrorBoundary; armed via
-- the `/crash` slash-command or the `e` hotkey.

local Bomb = component(function(props)
    if props.armed then
        error("demo explosion (type /reset or press r to recover)", 0)
    end
    return nil  -- no visual output when unarmed
end)

-- -----------------------------------------------------------------------------
-- "Generating..." row. Visible while a reply is streaming. Shows Spinner +
-- ProgressBar + percent. `progress` is 0..1, where 1 means fully streamed.

local StreamingBanner = component(function(props)
    local theme = tui.useContext(ThemeCtx)
    return tui.Box {
        flexDirection = "row",
        tui.Box  { key = "spin", tui.Spinner { type = "dots", color = theme.accent } },
        tui.Box  { key = "gap1", width = 1 },
        tui.Text { key = "gen",  color = theme.muted, "generating" },
        tui.Box  { key = "gap2", width = 2 },
        tui.ProgressBar {
            key = "bar",
            value = props.progress, width = 20, color = theme.accent,
        },
        tui.Box  { key = "gap3", width = 1 },
        tui.Text {
            key = "pct",
            color = theme.accent,
            ("%3d%%"):format(math.floor(props.progress * 100 + 0.5)),
        },
    }
end)

-- -----------------------------------------------------------------------------
-- Help overlay. Rendered inline above the input when toggled.

local HelpBox = component(function()
    local theme = tui.useContext(ThemeCtx)
    return tui.Box {
        flexDirection = "column",
        borderStyle = "double",
        color = theme.accent,
        paddingX = 1,
        tui.Text { key = "h0", bold = true, color = theme.accent, "commands" },
        tui.Text { key = "h1", "  Enter     send message" },
        tui.Text { key = "h2", "  /model    choose model (↑/↓ + Enter)" },
        tui.Text { key = "h3", "  /theme    toggle dark / light" },
        tui.Text { key = "h4", "  /clear    clear chat history" },
        tui.Text { key = "h5", "  /crash    throw demo error" },
        tui.Text { key = "h6", "  /reset    reset ErrorBoundary" },
        tui.Text { key = "h7", "  ? / F1    toggle this help" },
        tui.Text { key = "h8", "  q / Esc   quit" },
    }
end)

-- -----------------------------------------------------------------------------
-- Root app.

local MODELS = {
    { label = "claude-opus-4",  value = "claude-opus-4"  },
    { label = "claude-sonnet",  value = "claude-sonnet"  },
    { label = "gpt-4o",         value = "gpt-4o"         },
    { label = "local/llama3",   value = "local/llama3"   },
}

-- Shape of a streaming state: { target = reply_str, shown = int }.
-- shown advances once per interval tick; when shown==#target we finalize
-- the message into history and go idle.

local function App()
    local app   = tui.useApp()
    local size  = tui.useWindowSize()

    local messages,  setMessages  = tui.useState({})
    local input,     setInput     = tui.useState("")
    local model,     setModel     = tui.useState(MODELS[1].value)
    local isDark,    setIsDark    = tui.useState(true)
    local showHelp,  setShowHelp  = tui.useState(false)
    local showModel, setShowModel = tui.useState(false)
    local streaming, setStreaming = tui.useState(nil)   -- { target, shown } or nil
    local armed,     setArmed     = tui.useState(false)

    -- Minimum size the full UI needs (header + input + footer).
    local minCols <const>, minRows <const> = 40, 8
    if size.cols < minCols or size.rows < minRows then
        return tui.Box {
            flexDirection = "column",
            alignItems = "center",
            justifyContent = "center",
            width = size.cols, height = size.rows,
            tui.Text { color = "red", bold = true, "terminal too small" },
            tui.Text { color = "gray", ("need %dx%d, got %dx%d"):format(minCols, minRows, size.cols, size.rows) },
        }
    end

    -- Stable ref so hotkeys outside the boundary can call its reset().
    local boundaryRef = tui.useRef { reset = function() end }

    -- Stream tick. When `streaming` is non-nil, reveal one more character
    -- per 40ms; at completion, append a finalized bot message.
    --
    -- IMPORTANT: under `h:advance(N)` the scheduler fires the interval many
    -- times between paints (self-catch-up). The callback therefore MUST
    -- read the latest streaming state via functional setState rather than
    -- the captured `streaming` local (which is frozen at render time).
    tui.useInterval(function()
        setStreaming(function(cur)
            if not cur then return cur end
            if cur.shown >= #cur.target then
                -- Finalize: append to history. Defer via setMessages's
                -- functional form so we don't read stale messages either.
                setMessages(function(prev)
                    local out = {}
                    for i, m in ipairs(prev) do out[i] = m end
                    out[#out + 1] = { who = "bot", text = cur.target }
                    return out
                end)
                return nil
            end
            return { target = cur.target, shown = cur.shown + 1 }
        end)
    end, 40)

    local function append_user(text)
        setMessages(function(prev)
            local out = {}
            for i, m in ipairs(prev) do out[i] = m end
            out[#out + 1] = { who = "user", text = text }
            return out
        end)
    end

    local function start_reply(for_text)
        local idx = (#messages % #REPLIES) + 1
        local body = REPLIES[idx]
        if for_text and #for_text > 0 then
            body = body .. "  (re: " .. for_text:sub(1, 40) .. ")"
        end
        setStreaming({ target = body, shown = 0 })
    end

    -- Slash-command dispatcher. Returns true if the text was a command
    -- (and should NOT be appended to history / replied to).
    local function try_slash(text)
        if text == "/theme" then
            setIsDark(function(v) return not v end); return true
        elseif text == "/crash" then
            setArmed(true); return true
        elseif text == "/reset" then
            setArmed(false); boundaryRef.current.reset(); return true
        elseif text == "/clear" then
            setMessages({}); return true
        elseif text == "/model" then
            setShowModel(true); return true
        elseif text == "/quit" or text == "/exit" then
            app.exit(); return true
        end
        return false
    end

    local function on_submit(text)
        if text == "" then return end
        setInput("")
        if try_slash(text) then return end
        append_user(text)
        start_reply(text)
    end

    tui.useInput(function(inp, key)
        if key.name == "escape" or inp == "q" then
            app.exit()
        elseif key.name == "f1" or inp == "?" then
            setShowHelp(function(v) return not v end)
        end
    end)

    local theme_value = isDark and DARK or LIGHT

    -- The model overlay (Select) is rendered inline above the input. When
    -- open it grabs autoFocus; on Enter it closes. The input Box becomes
    -- inactive while the overlay is open (isDisabled) so keys flow to Select.
    local function on_pick_model(item)
        setModel(item.value)
        setShowModel(false)
    end

    return ThemeCtx.Provider {
        value = theme_value,
        tui.Box {
            flexDirection = "column",
            width  = size.cols,
            height = size.rows,

            tui.Box { key = "header", Header { model = model } },

            -- Messages area — grows to fill available space.
            tui.Box {
                key = "msgs",
                flexDirection = "column",
                flexGrow = 1,
                paddingX = 1,
                tui.ErrorBoundary {
                    fallback = function(err, reset)
                        boundaryRef.current.reset = reset
                        return tui.Box {
                            flexDirection = "column",
                            borderStyle = "round",
                            color = "red",
                            paddingX = 1,
                            tui.Text { key = "e1", color = "red", bold = true, "caught error" },
                            tui.Text { key = "e2", color = "red", tostring(err) },
                            tui.Text { key = "e3", color = "gray", dim = true,
                                "type /reset to recover" },
                        }
                    end,
                    tui.Box { key = "history", History { messages = messages } },
                    tui.Box { key = "bomb",    Bomb    { armed    = armed    } },
                    streaming and tui.Text {
                        key = "streambuf",
                        color = theme_value.bot, dim = true,
                        ("[bot] %s\u{258F}"):format(streaming.target:sub(1, streaming.shown)),
                    } or nil,
                },
            },

            streaming and tui.Box { key = "banner", StreamingBanner { progress = streaming.shown / #streaming.target } } or nil,

            showHelp and tui.Box { key = "help", HelpBox() } or nil,

            -- Model overlay.
            showModel and tui.Box {
                key = "model-overlay",
                flexDirection = "column",
                borderStyle = "double",
                color = theme_value.accent,
                paddingX = 1,
                tui.Text { key = "title", color = theme_value.accent, bold = true, "choose model" },
                tui.Select {
                    key            = "picker",
                    focusId        = "model-overlay",
                    autoFocus      = true,
                    items          = MODELS,
                    initialIndex   = 1,
                    onSelect       = on_pick_model,
                    highlightColor = theme_value.accent,
                },
            } or nil,

            -- Input row.
            tui.Box {
                key = "input",
                flexDirection = "row",
                borderStyle = "round",
                color = theme_value.border_fg,
                paddingX = 1,
                tui.TextInput {
                    focusId     = "prompt",
                    autoFocus   = not showModel,
                    focus       = not showModel,
                    value       = input,
                    onChange    = setInput,
                    onSubmit    = on_submit,
                    placeholder = "type a message and press Enter (? for help)",
                },
            },

            tui.Text {
                key = "footer",
                color = theme_value.muted, dim = true,
                "Enter: send · /model · /theme · /clear · /crash · /reset · ?: help · q: quit",
            },
        },
    }
end

-- Script entry point. When loaded directly (`luamake lua examples/all_in_one.lua`),
-- start the real render loop. When loaded via `require`, return the App factory
-- so tests (test/test_example_all_in_one.lua) can mount it offscreen.
if ... == nil then
    tui.render(App)
end

return App
