-- tui/builtin/textarea.lua — <Textarea> multi-line text editor component.
--
-- Props:
--   value       : current text (controlled, lines joined by "\n"). Required.
--   onChange    : fn(new_value) — called when the user edits the buffer.
--   onSubmit    : fn(value)     — called on Enter or Ctrl+Enter.
--   placeholder : string shown when value is empty and unfocused.
--   focus       : when explicitly set to false, the input is disabled.
--   autoFocus   : default true. Forwarded to useFocus.
--   focusId     : optional id passed to useFocus.
--   width       : optional cell width.
--   minHeight   : minimum visible row count (default 1).
--   maxHeight   : maximum visible row count (default unlimited).
--
-- Cursor:
--   Uses useDeclaredCursor() — the framework places the real terminal cursor
--   at the computed position inside the visible viewport.
--
-- Key bindings:
--   Printable chars / paste  — insert at caret
--   Enter / Ctrl+Enter       — call onSubmit (does not insert newline)
--   Shift+Enter              — insert newline
--   Backspace / Delete       — delete char; merges lines when at boundary
--   Left / Right             — move within and across lines
--   Up / Down                — move to the same visual column on prev/next line
--   Home / End               — beginning / end of current line
--   Ctrl+Home / Ctrl+End     — top / bottom of document

local tui      = require "tui"

local M = {}

-- ---------------------------------------------------------------------------
-- Helpers shared with TextInput.
-- ---------------------------------------------------------------------------

local function to_chars(s)
    local chars = {}
    if not s or s == "" then return chars end
    for ch, _ in tui.iterChars(s) do
        chars[#chars + 1] = ch
    end
    return chars
end

local function char_width(ch)
    return tui.displayWidth(ch)
end

-- Display width of chars[1..i] prefix (0-based, i chars).
local function prefix_width(chars, i)
    local w = 0
    for k = 1, i do w = w + char_width(chars[k]) end
    return w
end

-- ---------------------------------------------------------------------------
-- Parse value → array of lines (each line is a grapheme-cluster array).
-- "\n" is the separator; trailing newline produces an extra empty line.
-- ---------------------------------------------------------------------------
local function parse_lines(value)
    local lines = {}
    local cur = {}
    if not value or value == "" then
        return { {} }
    end
    for ch, _ in tui.iterChars(value) do
        if ch == "\n" then
            lines[#lines + 1] = cur
            cur = {}
        else
            cur[#cur + 1] = ch
        end
    end
    lines[#lines + 1] = cur
    return lines
end

-- Serialize array-of-lines back to a single string.
local function serialize_lines(lines)
    local parts = {}
    for li = 1, #lines do
        parts[li] = table.concat(lines[li])
    end
    return table.concat(parts, "\n")
end

-- Deep-copy lines array so edits don't alias.
local function copy_lines(lines)
    local out = {}
    for li = 1, #lines do
        local src = lines[li]
        local dst = {}
        for k = 1, #src do dst[k] = src[k] end
        out[li] = dst
    end
    return out
end

-- Given a line (grapheme array) and a target display-column x, return the
-- char index (0..#line) whose left edge is closest to x.  This gives
-- display-column-aware Up/Down navigation for CJK and other wide chars.
local function col_for_x(line, target_x)
    local x = 0
    for i = 1, #line do
        local w = char_width(line[i])
        -- Snap to whichever edge (left or right of the char) is closer.
        if x + w > target_x then
            -- Left edge (i-1) vs right edge (i): pick closer.
            return (target_x - x < x + w - target_x) and (i - 1) or i
        end
        x = x + w
    end
    return #line  -- target_x is past the end of the line
end

-- ---------------------------------------------------------------------------
-- Viewport: given height rows, compute scroll_top so that `line` is visible.
-- Returns new scroll_top.
-- ---------------------------------------------------------------------------
local function clamp_scroll(scroll_top, line, height, total_lines)
    -- line is 1-based
    if line < scroll_top + 1 then
        return line - 1
    elseif line > scroll_top + height then
        return line - height
    end
    -- Un-scroll when the viewport extends past the last content line
    -- (happens when the window grew or content shrank). Keeps as much
    -- content visible as possible while still showing the cursor.
    if total_lines and scroll_top + height > total_lines then
        return math.max(0, total_lines - height)
    end
    return scroll_top
end

-- ---------------------------------------------------------------------------
-- Component implementation.
-- ---------------------------------------------------------------------------
local function TextareaImpl(props)
    props = props or {}

    local value       = props.value or ""
    local onChange    = props.onChange
    local onSubmit    = props.onSubmit
    local placeholder = props.placeholder or ""
    local disabled    = (props.focus == false)
    local min_height  = math.max(1, math.floor(props.minHeight or 1))
    local max_height  = props.maxHeight and math.max(min_height, math.floor(props.maxHeight)) or nil

    -- Parse value → lines. Done before useState so initial caret can point
    -- to the end of the document (mirrors TextInput behaviour).
    local lines_now = parse_lines(value)
    local nlines    = #lines_now

    -- Auto-grow height: declared Yoga height = nlines (clamped to min/max).
    -- Terminal overflow is handled via useMeasure (see scroll_window below).
    local vis_height = nlines
    if vis_height < min_height then
        vis_height = min_height
    elseif max_height and vis_height > max_height then
        vis_height = max_height
    end

    -- Get the actual Yoga-allocated height for this component (may be less
    -- than vis_height when the layout clips the textarea, e.g. when a bordered
    -- parent fills the terminal). Use this as the scroll window so that
    -- clamp_scroll keeps the cursor within the visible area. Falls back to
    -- vis_height on the first frame before the measurement is available.
    local measureRef, measured_size = tui.useMeasure()
    local scroll_window = (measured_size.h > 0) and measured_size.h or vis_height

    -- Persistent state: cursor (1-based line/col), scroll top (0-based),
    -- and preferred_x for sticky Up/Down column (nil = use current position).
    local caret_line,  setCaretLine  = tui.useState(nlines)
    local caret_col,   setCaretCol   = tui.useState(#lines_now[nlines])
    local scroll_top,  setScrollTop  = tui.useState(0)
    local preferred_x, setPreferredX = tui.useState(nil)

    -- Clamp caret to valid range after external value change.
    local cl = math.min(math.max(caret_line, 1), nlines)
    local cc = math.min(math.max(caret_col, 0), #lines_now[cl])

    tui.useEffect(function()
        if caret_line ~= cl then setCaretLine(cl) end
        if caret_col  ~= cc then setCaretCol(cc)  end
    end, { caret_line, caret_col, cl, cc })

    -- Keep a ref to live values for the on_input closure.
    local ctx, _ = tui.useState({})
    ctx.lines       = lines_now
    ctx.cl          = cl
    ctx.cc          = cc
    ctx.st          = clamp_scroll(scroll_top, cl, scroll_window, nlines)
    ctx.preferred_x = preferred_x
    ctx.onChange    = onChange
    ctx.onSubmit    = onSubmit
    ctx.value       = value
    ctx.scroll_window = scroll_window

    -- Sync scroll_top if it changed.
    tui.useEffect(function()
        if scroll_top ~= ctx.st then setScrollTop(ctx.st) end
    end, { ctx.st, scroll_top })

    -- Emit helper: applies edit result and updates cursor + scroll.
    local function make_emit(ctx_ref)
        return function(new_lines, new_cl, new_cc)
            -- Use the measured scroll window (actual visible height, clipped by
            -- terminal/parent bounds). This was set by useMeasure on the previous
            -- render frame and is the correct viewport for scrolling purposes.
            local win = ctx_ref.scroll_window
            local new_st = clamp_scroll(ctx_ref.st, new_cl, win)
            setCaretLine(new_cl)
            setCaretCol(new_cc)
            setScrollTop(new_st)
            ctx_ref.cl = new_cl
            ctx_ref.cc = new_cc
            ctx_ref.st = new_st
            ctx_ref.lines = new_lines
            -- Any edit clears the sticky column.
            if ctx_ref.preferred_x ~= nil then
                setPreferredX(nil)
                ctx_ref.preferred_x = nil
            end
            if ctx_ref.onChange then
                ctx_ref.onChange(serialize_lines(new_lines))
            end
        end
    end

    -- Helper: move cursor vertically to `new_cl`, snapping to the stored
    -- preferred_x (or the current display-x if none is stored yet).
    local function move_vertical(new_cl)
        local lines = ctx.lines
        local cl    = ctx.cl
        local cc    = ctx.cc
        -- Determine the target display x (sticky column).
        local px = ctx.preferred_x
        if px == nil then
            px = prefix_width(lines[cl], cc)
            setPreferredX(px)
            ctx.preferred_x = px
        end
        local new_cc = col_for_x(lines[new_cl], px)
        setCaretLine(new_cl)
        setCaretCol(new_cc)
        ctx.cl = new_cl
        ctx.cc = new_cc
        local new_st = clamp_scroll(ctx.st, new_cl, ctx.scroll_window, #ctx.lines)
        if new_st ~= ctx.st then setScrollTop(new_st); ctx.st = new_st end
    end

    local f = tui.useFocus {
        autoFocus = (not disabled) and (props.autoFocus ~= false),
        id        = props.focusId,
        isActive  = not disabled,
        on_input  = function(input, key)
            local lines = ctx.lines
            local cl    = ctx.cl
            local cc    = ctx.cc
            local line  = lines[cl]
            local name  = key.name
            local emit  = make_emit(ctx)

            -- ---- Insert text at caret (shared by char and paste) ----------
            local function insert_text(text)
                local new_lines = copy_lines(lines)
                local nl = new_lines[cl]

                -- Split `text` into graphemes, handling embedded newlines.
                local to_insert = {}  -- list of {type="char",ch=...} or {type="nl"}
                for ch, _ in tui.iterChars(text) do
                    if ch == "\n" then
                        to_insert[#to_insert + 1] = { t = "nl" }
                    else
                        to_insert[#to_insert + 1] = { t = "ch", ch = ch }
                    end
                end
                if #to_insert == 0 then return end

                -- Collect what follows the caret on the current line.
                local tail = {}
                for i = cc + 1, #nl do tail[#tail + 1] = nl[i] end
                -- Truncate current line at caret.
                for i = #nl, cc + 1, -1 do nl[i] = nil end

                local cur_line = nl
                local ins_cl   = cl
                local ins_cc   = cc

                for _, tok in ipairs(to_insert) do
                    if tok.t == "nl" then
                        -- Push a new line after current.
                        ins_cl = ins_cl + 1
                        ins_cc = 0
                        table.insert(new_lines, ins_cl, {})
                        cur_line = new_lines[ins_cl]
                    else
                        cur_line[#cur_line + 1] = tok.ch
                        ins_cc = ins_cc + 1
                    end
                end

                -- Append tail to the last inserted line.
                for _, ch in ipairs(tail) do cur_line[#cur_line + 1] = ch end

                emit(new_lines, ins_cl, ins_cc)
            end

            -- ---------------------------------------------------------------
            if name == "char" and input and input ~= "" then
                insert_text(input)

            elseif name == "paste" and input and input ~= "" then
                insert_text(input)

            elseif name == "enter" then
                if key.shift then
                    -- Shift+Enter → insert newline.
                    insert_text("\n")
                else
                    -- Plain Enter or Ctrl+Enter → submit.
                    if ctx.onSubmit then ctx.onSubmit(ctx.value) end
                end

            elseif name == "backspace" then
                if cc > 0 then
                    -- Delete the char before the caret on the current line.
                    local new_lines = copy_lines(lines)
                    local nl = new_lines[cl]
                    table.remove(nl, cc)
                    emit(new_lines, cl, cc - 1)
                elseif cl > 1 then
                    -- Merge current line into the end of the previous line.
                    local new_lines = copy_lines(lines)
                    local prev = new_lines[cl - 1]
                    local new_cc = #prev
                    for _, ch in ipairs(new_lines[cl]) do
                        prev[#prev + 1] = ch
                    end
                    table.remove(new_lines, cl)
                    emit(new_lines, cl - 1, new_cc)
                end

            elseif name == "delete" then
                if cc < #line then
                    -- Delete the char after the caret.
                    local new_lines = copy_lines(lines)
                    table.remove(new_lines[cl], cc + 1)
                    emit(new_lines, cl, cc)
                elseif cl < #lines then
                    -- Merge next line into current line.
                    local new_lines = copy_lines(lines)
                    local cur = new_lines[cl]
                    for _, ch in ipairs(new_lines[cl + 1]) do
                        cur[#cur + 1] = ch
                    end
                    table.remove(new_lines, cl + 1)
                    emit(new_lines, cl, cc)
                end

            elseif name == "left" then
                -- Clear sticky column on horizontal/edit moves.
                if ctx.preferred_x ~= nil then setPreferredX(nil); ctx.preferred_x = nil end
                if cc > 0 then
                    setCaretCol(cc - 1)
                    ctx.cc = cc - 1
                elseif cl > 1 then
                    local new_cc = #lines[cl - 1]
                    setCaretLine(cl - 1)
                    setCaretCol(new_cc)
                    ctx.cl = cl - 1
                    ctx.cc = new_cc
                    local new_st = clamp_scroll(ctx.st, cl - 1, ctx.scroll_window, #lines)
                    if new_st ~= ctx.st then setScrollTop(new_st); ctx.st = new_st end
                end

            elseif name == "right" then
                if ctx.preferred_x ~= nil then setPreferredX(nil); ctx.preferred_x = nil end
                if cc < #line then
                    setCaretCol(cc + 1)
                    ctx.cc = cc + 1
                elseif cl < #lines then
                    setCaretLine(cl + 1)
                    setCaretCol(0)
                    ctx.cl = cl + 1
                    ctx.cc = 0
                    local new_st = clamp_scroll(ctx.st, cl + 1, ctx.scroll_window, #lines)
                    if new_st ~= ctx.st then setScrollTop(new_st); ctx.st = new_st end
                end

            elseif name == "up" then
                if cl > 1 then move_vertical(cl - 1) end

            elseif name == "down" then
                if cl < #lines then move_vertical(cl + 1) end

            elseif name == "home" then
                if ctx.preferred_x ~= nil then setPreferredX(nil); ctx.preferred_x = nil end
                setCaretCol(0)
                ctx.cc = 0

            elseif name == "end" then
                if ctx.preferred_x ~= nil then setPreferredX(nil); ctx.preferred_x = nil end
                setCaretCol(#line)
                ctx.cc = #line

            elseif name == "home" and key.ctrl then
                if ctx.preferred_x ~= nil then setPreferredX(nil); ctx.preferred_x = nil end
                setCaretLine(1); setCaretCol(0)
                ctx.cl = 1; ctx.cc = 0
                setScrollTop(0); ctx.st = 0

            elseif name == "end" and key.ctrl then
                if ctx.preferred_x ~= nil then setPreferredX(nil); ctx.preferred_x = nil end
                local last = #lines
                setCaretLine(last)
                setCaretCol(#lines[last])
                ctx.cl = last; ctx.cc = #lines[last]
                local new_st = clamp_scroll(ctx.st, last, ctx.scroll_window, #ctx.lines)
                if new_st ~= ctx.st then setScrollTop(new_st); ctx.st = new_st end
            end
        end,
    }
    local focus_flag = f.isFocused

    -- -------------------------------------------------------------------------
    -- Render: build `vis_height` Text elements, one per visible line.
    -- -------------------------------------------------------------------------
    local st     = ctx.st
    local width  = props.width
    local show_placeholder = (#value == 0) and not focus_flag and placeholder ~= ""

    -- Cursor within visible area.
    local cursor_row = cl - st - 1   -- 0-based row within viewport
    local cursor_col = prefix_width(lines_now[cl], cc)

    local row_elements = {}
    for r = 0, vis_height - 1 do
        local li = st + r + 1
        local text_str
        if show_placeholder and r == 0 then
            text_str = placeholder
        elseif li <= #lines_now then
            text_str = table.concat(lines_now[li])
        else
            text_str = ""
        end
        local row_el = tui.Text { key = tostring(r + 1), width = width, wrap = "nowrap", text_str }
        if r == cursor_row then
            local declareCursor = tui.useDeclaredCursor {
                x      = cursor_col,
                y      = 0,
                active = focus_flag and not disabled,
            }
            declareCursor(row_el)
        end
        row_elements[r + 1] = row_el
    end

    return tui.Box {
        ref = measureRef,
        flexDirection = "column",
        width = width,
        height = vis_height,
        table.unpack(row_elements),
    }
end

function M.Textarea(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = TextareaImpl, props = props, key = key }
end

return M
