-- tui/builtin/text_input.lua — <TextInput> component.
--
-- Props:
--   value       : current text (controlled). Required unless using defaultValue.
--   onChange    : fn(new_value) — called when the user edits the buffer.
--   onSubmit    : fn(value)     — called on Enter.
--   placeholder : string shown when value is empty and unfocused.
--   focus       : boolean (default true). When false, input is ignored and
--                 the cursor is not drawn.
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

-- Split a UTF-8 string into a list of chars (each entry = 1 grapheme for our
-- purposes — combining marks attach to the previous slot as a suffix).
local function to_chars(s)
    local chars = {}
    if not s or s == "" then return chars end
    local n, i = #s, 1
    while i <= n do
        local cw, ni = wcwidth.char_width(s, i)
        local ch = s:sub(i, ni - 1)
        if cw == 0 and #chars > 0 then
            chars[#chars] = chars[#chars] .. ch
        else
            chars[#chars + 1] = ch
        end
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
    local focus       = props.focus
    if focus == nil then focus = true end
    local mask        = props.mask

    -- Caret: persistent state. Reset if value shrank past caret externally.
    local chars = to_chars(value)
    local caret_state, setCaret = hooks.useState(#chars)
    if caret_state > #chars then
        caret_state = #chars
        setCaret(caret_state)
    end

    -- Keep a ref to latest props so the useInput callback sees fresh value.
    local ctx = { chars = chars, caret = caret_state,
                  onChange = onChange, onSubmit = onSubmit, setCaret = setCaret,
                  value = value }
    local ctxRef, _ = hooks.useState({})
    ctxRef.chars    = chars
    ctxRef.caret    = caret_state
    ctxRef.onChange = onChange
    ctxRef.onSubmit = onSubmit
    ctxRef.setCaret = setCaret
    ctxRef.value    = value

    hooks.useInput(function(input, key)
        if not focus then return end
        local cs = ctxRef.chars
        local c  = ctxRef.caret
        local name = key.name

        local function emit(new_chars, new_caret)
            ctxRef.setCaret(new_caret)
            if ctxRef.onChange then ctxRef.onChange(chars_to_string(new_chars)) end
        end

        if name == "enter" then
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
            if c > 0 then ctxRef.setCaret(c - 1) end
        elseif name == "right" then
            if c < #cs then ctxRef.setCaret(c + 1) end
        elseif name == "home" then
            ctxRef.setCaret(0)
        elseif name == "end" then
            ctxRef.setCaret(#cs)
        elseif name == "char" and input and input ~= "" then
            -- Insert printable UTF-8 character(s) at caret.
            local ins = to_chars(input)
            local nc = {}
            for i = 1, c do nc[i] = cs[i] end
            for _, ch in ipairs(ins) do nc[#nc + 1] = ch end
            for i = c + 1, #cs do nc[#nc + 1] = cs[i] end
            emit(nc, c + #ins)
        end
    end)

    -- Visible text + caret column.
    local width = props.width or props.minWidth or nil
    -- Fall back to a reasonable default when unset; parent Box typically
    -- passes a flex-grown child so we try to render the whole value.
    local show_placeholder = (#chars == 0) and not focus and placeholder ~= ""
    local render_width = width or math.max(prefix_width(chars, #chars) + 1,
                                           text_mod.display_width(placeholder))
    if render_width < 1 then render_width = 1 end

    local visible, caret_col
    if show_placeholder then
        visible, caret_col = placeholder, 0
    else
        visible, caret_col = make_window(chars, caret_state, render_width, mask)
    end

    -- Build the Text child; user may apply styling via a wrapper Box.
    local text_el = element.Text { width = render_width, wrap = "nowrap", visible }

    -- After layout, we need the absolute rect.y / rect.x to know where the
    -- caret is on screen. We use useEffect to run after commit and compute
    -- the cursor position. Since we don't have rect here pre-layout, we stash
    -- the caret_col on the element and a post-commit hook in init.lua resolves
    -- rect + cursor.set. Simpler: we set cursor.set based on a fixup helper
    -- that runs during paint; we tag the returned element with _cursor_offset
    -- so tui/init.lua's paint pipeline can resolve it.
    text_el._cursor_offset = focus and caret_col or nil

    return text_el
end

-- Public factory.
function M.TextInput(props)
    return { kind = "component", fn = TextInputImpl, props = props or {} }
end

return M
