-- tui/builtin/text_input.lua — <TextInput> component.
--
-- Props:
--   value       : current text (controlled). Required unless using defaultValue.
--   onChange    : fn(new_value) — called when the user edits the buffer.
--   onSubmit    : fn(value)     — called on Enter.
--   placeholder : string shown when value is empty and unfocused.
--   focus       : when explicitly set to false, the input is disabled —
--                 it still registers a focus entry (stable hook order)
--                 but with isActive=false, so Tab navigation skips it
--                 and autoFocus is ignored. Omit it (or any other value)
--                 to use the focus chain normally.
--   autoFocus   : default true. Forwarded to useFocus.
--   focusId     : optional id passed to useFocus.
--   mask        : string (default nil). If set, each visible char is replaced
--                 by this single-char mask (e.g. "*" for passwords).
--   width       : optional cell width; defaults to container-allocated width.
--
-- Cursor rendering: the component writes a row of text into a Text element
-- and, post-commit, calls cursor.set(col, row) so tui/init.lua positions
-- the terminal's real cursor at the correct column. On Windows, this also
-- drives IME candidate window placement via terminal.set_ime_pos.
--
-- Cursor position is a UTF-8 character index (1..#chars+1), not a byte
-- offset. Conversions to display columns go through wcwidth.

local element  = require "tui.element"
local tui_core = require "tui_core"
local cursor   = require "tui.builtin.cursor"
local text_mod = require "tui.text"

local wcwidth = tui_core.wcwidth

local M = {}

-- Split a UTF-8 string into a list of chars (each entry = 1 grapheme
-- cluster). Combining marks, ZWJ sequences, VS16 promotion, RI flag pairs,
-- and Hangul L/V/T conjoining all fuse into a single slot so arrow keys /
-- backspace operate on visible characters rather than code points.
local function to_chars(s)
    local chars = {}
    if not s or s == "" then return chars end
    local n, i = #s, 1
    while i <= n do
        local ch, _, ni = wcwidth.grapheme_next(s, i)
        if ch == "" then break end
        chars[#chars + 1] = ch
        i = ni
    end
    return chars
end

local function chars_to_string(chars)
    return table.concat(chars)
end

-- Display width of chars[1..i] prefix.
local function prefix_width(chars, i)
    local w = 0
    for k = 1, i do w = w + (text_mod.display_width(chars[k])) end
    return w
end

-- Given chars + caret index (0..#chars) and a visible width budget `width`,
-- compute (visible_string, caret_col_within_visible) that keeps the caret
-- inside the window by scrolling horizontally when necessary.
local function make_window(chars, caret, width, mask)
    if width <= 0 then return "", 0 end
    -- Work on masked chars if requested.
    local masked = chars
    if mask and #mask > 0 then
        masked = {}
        for i = 1, #chars do masked[i] = mask end
    end

    -- Simple scroll: show starting at `start` such that caret fits.
    -- Prefer showing from index 1 if the whole string fits; otherwise shift.
    local total_w = prefix_width(masked, #masked)
    if total_w <= width then
        return chars_to_string(masked), prefix_width(masked, caret)
    end

    -- Find start index such that caret_col_within = width_of(start..caret) <= width.
    local start = 1
    while start <= #masked do
        local w_start_caret = prefix_width(masked, caret) - prefix_width(masked, start - 1)
        if w_start_caret <= width then break end
        start = start + 1
    end

    -- Build visible substring from `start` while staying within width.
    local visible = {}
    local used = 0
    for i = start, #masked do
        local cw = text_mod.display_width(masked[i])
        if used + cw > width then break end
        visible[#visible + 1] = masked[i]
        used = used + cw
    end
    local caret_col = prefix_width(masked, caret) - prefix_width(masked, start - 1)
    if caret_col < 0 then caret_col = 0 end
    if caret_col > width then caret_col = width end
    return table.concat(visible), caret_col
end

local function TextInputImpl(props)
    props = props or {}
    local hooks = require "tui.hooks"

    local value       = props.value or ""
    local onChange    = props.onChange
    local onSubmit    = props.onSubmit
    local placeholder = props.placeholder or ""
    local mask        = props.mask

    -- props.focus == false opts out of focus acquisition: the entry still
    -- registers in the Tab chain but with isActive=false, so navigation
    -- skips it and autoFocus has no effect. Any other value (nil, true)
    -- routes through the focus system normally. Merging this into the
    -- one useFocus path keeps the hook call order stable across props.
    local disabled = (props.focus == false)

    -- Caret: persistent state. If the external `value` prop shrank so the
    -- caret is now past the end, we clamp locally for this render and
    -- schedule the persisted clamp via useEffect (moving the setCaret out
    -- of render-time satisfies the dev-mode render-phase setState guard).
    local chars = to_chars(value)
    local caret_state, setCaret = hooks.useState(#chars)
    local caret_clamped = caret_state
    if caret_clamped > #chars then caret_clamped = #chars end
    hooks.useEffect(function()
        if caret_state > #chars then setCaret(#chars) end
    end, { caret_state, #chars })

    -- Keep a ref to latest props so the useFocus callback sees fresh value.
    local ctxRef, _ = hooks.useState({})
    ctxRef.chars    = chars
    ctxRef.caret    = caret_clamped
    ctxRef.onChange = onChange
    ctxRef.onSubmit = onSubmit
    ctxRef.setCaret = setCaret
    ctxRef.value    = value

    -- Composing (pre-edit) text state for IME input.
    -- When an IME is actively composing (e.g. typing pinyin), the terminal
    -- may send composing events. Most macOS terminals (Terminal.app, iTerm2)
    -- handle pre-edit display internally and only send the final confirmed
    -- text. Terminals that support protocols like kitty may send composing
    -- sequences, which keys.parse will translate into composing events.
    local composing, setComposing = hooks.useState("")

    local f = hooks.useFocus {
        autoFocus = (not disabled) and (props.autoFocus ~= false),
        id        = props.focusId,
        isActive  = not disabled,
        on_input  = function(input, key)
            local cs = ctxRef.chars
            local c  = ctxRef.caret
            local name = key.name

            local function emit(new_chars, new_caret)
                ctxRef.setCaret(new_caret)
                if ctxRef.onChange then
                    ctxRef.onChange(chars_to_string(new_chars))
                end
                ctxRef.chars = new_chars
                ctxRef.caret = new_caret
            end

            if name == "composing" then
                -- IME pre-edit text update: store for display at caret.
                -- The text is not yet committed; it replaces any previous
                -- composing text for this composition session.
                setComposing(input)
            elseif name == "composing_confirm" then
                -- IME confirmed the composition: insert the confirmed text
                -- and clear the composing state.
                if input and input ~= "" then
                    local ins = to_chars(input)
                    local nc = {}
                    for i = 1, c do nc[i] = cs[i] end
                    for _, ch in ipairs(ins) do nc[#nc + 1] = ch end
                    for i = c + 1, #cs do nc[#nc + 1] = cs[i] end
                    emit(nc, c + #ins)
                end
                setComposing("")
            elseif name == "escape" then
                -- Escape cancels any active composition.
                if composing ~= "" then
                    setComposing("")
                end
            elseif name == "enter" then
                if ctxRef.onSubmit then ctxRef.onSubmit(ctxRef.value) end
            elseif name == "backspace" then
                if c > 0 then
                    local nc = {}
                    for i = 1, c - 1 do nc[i] = cs[i] end
                    for i = c + 1, #cs do nc[#nc + 1] = cs[i] end
                    emit(nc, c - 1)
                end
            elseif name == "delete" then
                if c < #cs then
                    local nc = {}
                    for i = 1, c do nc[i] = cs[i] end
                    for i = c + 2, #cs do nc[#nc + 1] = cs[i] end
                    emit(nc, c)
                end
            elseif name == "left" then
                if c > 0 then
                    ctxRef.setCaret(c - 1)
                    ctxRef.caret = c - 1
                end
            elseif name == "right" then
                if c < #cs then
                    ctxRef.setCaret(c + 1)
                    ctxRef.caret = c + 1
                end
            elseif name == "home" then
                ctxRef.setCaret(0)
                ctxRef.caret = 0
            elseif name == "end" then
                ctxRef.setCaret(#cs)
                ctxRef.caret = #cs
            elseif name == "char" and input and input ~= "" then
                -- Insert printable UTF-8 character(s) at caret.
                local ins = to_chars(input)
                local nc = {}
                for i = 1, c do nc[i] = cs[i] end
                for _, ch in ipairs(ins) do nc[#nc + 1] = ch end
                for i = c + 1, #cs do nc[#nc + 1] = cs[i] end
                emit(nc, c + #ins)
            end
        end,
    }
    local focus_flag = f.isFocused

    -- Clear composing state when focus is lost so that a stale pre-edit
    -- string does not linger when the input regains focus later.
    hooks.useEffect(function()
        if not focus_flag and composing ~= "" then
            setComposing("")
        end
    end, { focus_flag })

    -- Visible text + caret column.
    local width = props.width or props.minWidth or nil
    -- Fall back to a reasonable default when unset; parent Box typically
    -- passes a flex-grown child so we try to render the whole value.
    local show_placeholder = (#chars == 0) and not focus_flag and placeholder ~= ""
    local render_width = width or math.max(prefix_width(chars, #chars) + 1,
                                           text_mod.display_width(placeholder))
    if render_width < 1 then render_width = 1 end

    local visible, caret_col
    if show_placeholder then
        visible, caret_col = placeholder, 0
    else
        -- Append composing text after the caret position for display.
        -- The composing text is shown in-place but is not part of the
        -- actual value until confirmed.
        local display_chars = {}
        for i = 1, caret_clamped do display_chars[i] = chars[i] end
        local composing_chars = to_chars(composing)
        for _, ch in ipairs(composing_chars) do
            display_chars[#display_chars + 1] = ch
        end
        for i = caret_clamped + 1, #chars do
            display_chars[#display_chars + 1] = chars[i]
        end
        local display_caret = caret_clamped + #composing_chars
        visible, caret_col = make_window(display_chars, display_caret, render_width, mask)
    end

    -- Build the Text child; user may apply styling via a wrapper Box.
    local text_el = element.Text { width = render_width, wrap = "nowrap", visible }

    -- Tag the Text element with the caret column when this input is focused;
    -- tui/init.lua's paint pipeline translates that into an absolute cursor
    -- move. Disabled and unfocused inputs leave _cursor_offset = nil.
    text_el._cursor_offset = focus_flag and caret_col or nil

    return text_el
end

-- Public factory. `key` (if any) is hoisted to the element for reconciler
-- sibling identity, matching the Box/Text factories.
function M.TextInput(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = TextInputImpl, props = props, key = key }
end

return M
