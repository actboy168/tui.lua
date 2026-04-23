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
--   features    : optional feature flags table, e.g. { undoRedo = false }.
--   keymap      : optional shortcut overrides, e.g. { ["ctrl+s"] = "submit" }.
--
-- Cursor:
--   Uses useCursor() — the framework places the real terminal cursor
--   at the computed position inside the visible viewport.
--
-- Key bindings:
--   Printable chars / paste  — insert at caret
--   Enter / Ctrl+Enter       — call onSubmit (does not insert newline)
--   Shift+Enter              — insert newline (requires Kitty Keyboard Protocol; no-op on other terminals)
--   Backspace / Delete       — delete char; merges lines when at boundary
--   Left / Right             — move within and across lines
--   Up / Down                — move to the same visual column on prev/next line
--   Home / End               — beginning / end of current line
--   Ctrl+Home / Ctrl+End     — top / bottom of document

local tui  = require "tui"
local core = require "tui.extra.editing"

local M = {}

-- ---------------------------------------------------------------------------
-- Component implementation.
-- ---------------------------------------------------------------------------
local function textarea_impl(props)
    props = props or {}

    local value       = props.value or ""
    local onChange    = props.onChange
    local onSubmit    = props.onSubmit
    local placeholder = props.placeholder or ""
    local disabled    = (props.focus == false)
    local enter_behavior = (props.enterBehavior == "newline") and "newline" or "submit"
    local min_height  = math.max(1, math.floor(props.minHeight or 1))
    local max_height  = props.maxHeight and math.max(min_height, math.floor(props.maxHeight)) or nil
    local clipboard   = tui.useClipboard()
    local features    = core.resolve_features(props)
    local keymap      = core.resolve_keymap(props, core.default_textarea_keymap(enter_behavior))

    -- Parse value → lines. Done before useState so initial caret can point
    -- to the end of the document (mirrors TextInput behaviour).
    local lines_now = core.parse_lines(value)
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
    local caret_line, set_caret_line = tui.useState(nlines)
    local caret_col, set_caret_col = tui.useState(#lines_now[nlines])
    local selection_anchor, set_selection_anchor = tui.useState(nil)
    local scroll_top, set_scroll_top = tui.useState(0)
    local preferred_x, set_preferred_x = tui.useState(nil)
    local undo_stack, set_undo_stack = tui.useState({})
    local redo_stack, set_redo_stack = tui.useState({})
    local history_group, set_history_group = tui.useState(nil)

    -- Clamp caret to valid range after external value change.
    local cl = math.min(math.max(caret_line, 1), nlines)
    local cc = math.min(math.max(caret_col, 0), #lines_now[cl])
    local anchor_clamped = selection_anchor and {
        line = math.min(math.max(selection_anchor.line, 1), nlines),
        col = 0,
    } or nil
    if anchor_clamped then
        anchor_clamped.col = math.min(math.max(selection_anchor.col, 0), #lines_now[anchor_clamped.line])
        if anchor_clamped.line == cl and anchor_clamped.col == cc then
            anchor_clamped = nil
        end
    end

    tui.useEffect(function()
        if caret_line ~= cl then set_caret_line(cl) end
        if caret_col  ~= cc then set_caret_col(cc)  end
        if not core.same_position(selection_anchor, anchor_clamped) then set_selection_anchor(anchor_clamped) end
    end, { caret_line, caret_col, cl, cc, selection_anchor, anchor_clamped })

    -- Keep a ref to live values for the on_input closure.
    local ctx, _ = tui.useState({})
    ctx.lines       = lines_now
    ctx.cl          = cl
    ctx.cc          = cc
    ctx.anchor      = anchor_clamped
    ctx.st          = core.clamp_scroll(scroll_top, cl, scroll_window, nlines)
    ctx.preferred_x = preferred_x
    ctx.onChange    = onChange
    ctx.onSubmit    = onSubmit
    ctx.value       = value
    ctx.scroll_window = scroll_window
    ctx.set_anchor = set_selection_anchor
    ctx.set_caret_line = set_caret_line
    ctx.set_caret_col = set_caret_col
    ctx.set_scroll_top = set_scroll_top
    ctx.clipboard   = clipboard
    ctx.features = features
    ctx.keymap = keymap
    ctx.undo_stack = undo_stack
    ctx.redo_stack = redo_stack
    ctx.history_group = history_group

    local composing, set_composing = tui.useState("")
    ctx.composing = composing

    -- Sync scroll_top if it changed.
    tui.useEffect(function()
        if scroll_top ~= ctx.st then set_scroll_top(ctx.st) end
    end, { ctx.st, scroll_top })

    local function snapshot_current()
        return {
            value = ctx.value,
            cl = ctx.cl,
            cc = ctx.cc,
            anchor = core.copy_position(ctx.anchor),
        }
    end

    local function push_undo_snapshot()
        if not ctx.features.undo_redo then
            return
        end
        core.push_history_snapshot(set_undo_stack, set_redo_stack, snapshot_current())
        ctx.redo_stack = {}
    end

    local function clear_history_group()
        core.clear_history_group(set_history_group, ctx)
    end

    tui.useEffect(function()
        core.sync_history_feature(features.undo_redo, set_undo_stack, set_redo_stack, ctx)
    end, { features.undo_redo })
    tui.useEffect(function()
        core.sync_selection_feature(features.selection, set_selection_anchor, ctx)
    end, { features.selection })

    local function restore_snapshot(snapshot)
        local new_value = snapshot.value or ""
        local new_lines = core.parse_lines(new_value)
        local new_cl = math.min(math.max(snapshot.cl or 1, 1), #new_lines)
        local new_cc = math.min(math.max(snapshot.cc or 0, 0), #new_lines[new_cl])
        local new_anchor = core.copy_position(snapshot.anchor)
        if new_anchor then
            new_anchor.line = math.min(math.max(new_anchor.line, 1), #new_lines)
            new_anchor.col = math.min(math.max(new_anchor.col, 0), #new_lines[new_anchor.line])
            if new_anchor.line == new_cl and new_anchor.col == new_cc then
                new_anchor = nil
            end
        end
        local new_st = core.clamp_scroll(ctx.st, new_cl, ctx.scroll_window, #new_lines)
        set_caret_line(new_cl)
        set_caret_col(new_cc)
        set_selection_anchor(new_anchor)
        set_scroll_top(new_st)
        if ctx.preferred_x ~= nil then
            set_preferred_x(nil)
            ctx.preferred_x = nil
        end
        ctx.lines = new_lines
        ctx.cl = new_cl
        ctx.cc = new_cc
        ctx.anchor = new_anchor
        ctx.st = new_st
        ctx.value = new_value
        if ctx.onChange then
            ctx.onChange(new_value)
        end
    end

    -- Emit helper: applies edit result and updates cursor + scroll.
    local function make_emit(ctx_ref)
        return function(new_lines, new_cl, new_cc, opts)
            -- Use the measured scroll window (actual visible height, clipped by
            -- terminal/parent bounds). This was set by useMeasure on the previous
            -- render frame and is the correct viewport for scrolling purposes.
            local new_value = core.serialize_lines(new_lines)
            if ctx_ref.features.undo_redo
                and (not opts or opts.record_history ~= false)
                and new_value ~= ctx_ref.value then
                if opts and opts.history then
                    core.record_history_edit(
                        set_undo_stack,
                        set_redo_stack,
                        set_history_group,
                        ctx_ref,
                        snapshot_current(),
                        opts.history
                    )
                else
                    push_undo_snapshot()
                    clear_history_group()
                end
            elseif new_value ~= ctx_ref.value then
                clear_history_group()
            end
            local win = ctx_ref.scroll_window
            local new_st = core.clamp_scroll(ctx_ref.st, new_cl, win)
            set_caret_line(new_cl)
            set_caret_col(new_cc)
            ctx_ref.set_anchor(nil)
            set_scroll_top(new_st)
            ctx_ref.cl = new_cl
            ctx_ref.cc = new_cc
            ctx_ref.anchor = nil
            ctx_ref.st = new_st
            ctx_ref.lines = new_lines
            -- Any edit clears the sticky column.
            if ctx_ref.preferred_x ~= nil then
                set_preferred_x(nil)
                ctx_ref.preferred_x = nil
            end
            if ctx_ref.onChange then
                ctx_ref.onChange(new_value)
            end
            ctx_ref.value = new_value
        end
    end

    -- Helper: move cursor vertically to `new_cl`, snapping to the stored
    -- preferred_x (or the current display-x if none is stored yet).
    local function move_vertical(new_cl, extend)
        extend = extend and ctx.features.selection
        local lines = ctx.lines
        local cl    = ctx.cl
        local cc    = ctx.cc
        -- Determine the target display x (sticky column).
        local px = ctx.preferred_x
        if px == nil then
            px = core.prefix_width(lines[cl], cc)
            set_preferred_x(px)
            ctx.preferred_x = px
        end
        local new_cc = core.col_for_x(lines[new_cl], px)
        if extend then
            local next_anchor = ctx.anchor or { line = cl, col = cc }
            set_selection_anchor(core.compare_positions(next_anchor, { line = new_cl, col = new_cc }) == 0 and nil or next_anchor)
            ctx.anchor = core.compare_positions(next_anchor, { line = new_cl, col = new_cc }) == 0 and nil or next_anchor
        elseif ctx.anchor ~= nil then
            set_selection_anchor(nil)
            ctx.anchor = nil
        end
        set_caret_line(new_cl)
        set_caret_col(new_cc)
        ctx.cl = new_cl
        ctx.cc = new_cc
        local new_st = core.clamp_scroll(ctx.st, new_cl, ctx.scroll_window, #ctx.lines)
        if new_st ~= ctx.st then set_scroll_top(new_st); ctx.st = new_st end
    end

    local focus_handle = tui.useFocus {
        autoFocus = (not disabled) and (props.autoFocus ~= false),
        id        = props.focusId,
        isActive  = not disabled,
        on_input  = function(input, key)
            local lines = ctx.lines
            local cl    = ctx.cl
            local cc    = ctx.cc
            local anchor = ctx.anchor
            local line  = lines[cl]
            local name  = key.name
            local emit  = make_emit(ctx)
            local action = core.resolve_key_action(key, ctx.keymap)

            local function clear_preferred_x()
                    if ctx.preferred_x ~= nil then
                        set_preferred_x(nil)
                        ctx.preferred_x = nil
                    end
                end

                local function reset_navigation_group()
                    clear_history_group()
                    clear_preferred_x()
                end

                local function set_selection(new_anchor, new_cl, new_cc)
                    if new_anchor then
                        set_selection_anchor(new_anchor)
                        ctx.anchor = new_anchor
                    elseif ctx.anchor ~= nil then
                        set_selection_anchor(nil)
                        ctx.anchor = nil
                    end
                    set_caret_line(new_cl)
                    set_caret_col(new_cc)
                    ctx.cl = new_cl
                    ctx.cc = new_cc
                    local new_st = core.clamp_scroll(ctx.st, new_cl, ctx.scroll_window, #lines)
                    if new_st ~= ctx.st then set_scroll_top(new_st); ctx.st = new_st end
                end

            local function move_to(new_cl, new_cc, extend)
                extend = extend and ctx.features.selection
                if extend then
                    local next_anchor = anchor or { line = cl, col = cc }
                    if core.compare_positions(next_anchor, { line = new_cl, col = new_cc }) == 0 then
                        set_selection(nil, new_cl, new_cc)
                    else
                        set_selection(next_anchor, new_cl, new_cc)
                    end
                else
                    set_selection(nil, new_cl, new_cc)
                end
            end

            local function delete_selection_if_any()
                local new_lines, new_cl, new_cc = core.delete_selection_lines(lines, anchor, { line = cl, col = cc })
                if new_lines then
                    emit(new_lines, new_cl, new_cc)
                    return true
                end
                return false
            end

            local function replace_selection_if_any(text)
                if not core.has_selection_pos(anchor, { line = cl, col = cc }) then
                    return false
                end
                local new_lines, new_cl, new_cc = core.replace_selection_lines(lines, anchor, { line = cl, col = cc }, text)
                if new_lines then
                    emit(new_lines, new_cl, new_cc)
                    return true
                end
                return false
            end

            local function clear_selection_if_any()
                if ctx.anchor == nil then
                    return false
                end
                set_selection_anchor(nil)
                ctx.anchor = nil
                return true
            end

            -- ---- Insert text at caret (shared by char and paste) ----------
            local function insert_text(text)
                local new_lines, new_cl, new_cc = core.insert_text_lines(lines, cl, cc, text)
                if new_lines then emit(new_lines, new_cl, new_cc) end
            end

            -- ---------------------------------------------------------------
            if core.handle_shared_editor_input {
                name = name,
                shortcut = action,
                input = input,
                composing = ctx.composing,
                set_composing = set_composing,
                clear_selection = clear_selection_if_any,
                replace_selection = replace_selection_if_any,
                insert_text = insert_text,
                selection_text = function()
                    return core.selection_text_lines(lines, anchor, { line = cl, col = cc })
                end,
                delete_selection = delete_selection_if_any,
                clipboard = ctx.clipboard,
                features = ctx.features,
                undo_stack = ctx.undo_stack,
                redo_stack = ctx.redo_stack,
                set_undo_stack = set_undo_stack,
                set_redo_stack = set_redo_stack,
                snapshot_current = snapshot_current,
                restore_snapshot = restore_snapshot,
                clear_history_group = clear_history_group,
            } then
                return
            end

            if action == "doc_start" then
                reset_navigation_group()
                set_selection_anchor(nil)
                ctx.anchor = nil
                set_caret_line(1)
                set_caret_col(0)
                ctx.cl = 1
                ctx.cc = 0
                set_scroll_top(0)
                ctx.st = 0

            elseif action == "doc_end" then
                reset_navigation_group()
                set_selection_anchor(nil)
                ctx.anchor = nil
                local last = #lines
                set_caret_line(last)
                set_caret_col(#lines[last])
                ctx.cl = last
                ctx.cc = #lines[last]
                local new_st = core.clamp_scroll(ctx.st, last, ctx.scroll_window, #ctx.lines)
                if new_st ~= ctx.st then set_scroll_top(new_st); ctx.st = new_st end

            elseif action == "select_all" then
                reset_navigation_group()
                local last = #lines
                if last == 1 and #lines[1] == 0 then
                    set_selection(nil, 1, 0)
                else
                    set_selection({ line = 1, col = 0 }, last, #lines[last])
                end

            elseif action == "line_start" then
                reset_navigation_group()
                move_to(cl, 0, key.shift)

            elseif action == "line_end" then
                reset_navigation_group()
                move_to(cl, #line, key.shift)

            elseif action == "word_left" then
                reset_navigation_group()
                if cc > 0 then
                    local new_cc = core.find_word_left(line, cc)
                    move_to(cl, new_cc, key.shift)
                elseif cl > 1 then
                    local prev = lines[cl - 1]
                    local new_cc = core.find_word_left(prev, #prev)
                    move_to(cl - 1, new_cc, key.shift)
                end

            elseif action == "word_right" then
                reset_navigation_group()
                if cc < #line then
                    local new_cc = core.find_word_right(line, cc)
                    move_to(cl, new_cc, key.shift)
                elseif cl < #lines then
                    local next = lines[cl + 1]
                    local new_cc = core.find_word_right(next, 0)
                    move_to(cl + 1, new_cc, key.shift)
                end

            elseif action == "move_left" then
                reset_navigation_group()
                if cc > 0 then
                    move_to(cl, cc - 1, key.shift)
                elseif cl > 1 then
                    local new_cc = #lines[cl - 1]
                    move_to(cl - 1, new_cc, key.shift)
                end

            elseif action == "move_right" then
                reset_navigation_group()
                if cc < #line then
                    move_to(cl, cc + 1, key.shift)
                elseif cl < #lines then
                    move_to(cl + 1, 0, key.shift)
                end

            elseif action == "move_up" then
                clear_history_group()
                if cl > 1 then move_vertical(cl - 1, key.shift) end

            elseif action == "move_down" then
                clear_history_group()
                if cl < #lines then move_vertical(cl + 1, key.shift) end

            elseif action == "kill_left" then
                if not delete_selection_if_any() then
                    local new_lines, new_cl, new_cc = core.delete_to_line_start_lines(lines, cl, cc)
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "delete_backward",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc }
                            ),
                        })
                    end
                end

            elseif action == "kill_right" then
                if not delete_selection_if_any() then
                    local new_lines, new_cl, new_cc = core.delete_to_line_end_lines(lines, cl, cc)
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "delete_forward",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc }
                            ),
                        })
                    end
                end

            elseif action == "delete_word_left" then
                if not delete_selection_if_any() then
                    local new_lines, new_cl, new_cc = core.delete_word_backward_lines(lines, cl, cc)
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "delete_backward",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc }
                            ),
                        })
                    end
                end

            elseif action == "delete_word_right" then
                if not delete_selection_if_any() then
                    local new_lines, new_cl, new_cc = core.delete_word_forward_lines(lines, cl, cc)
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "delete_forward",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc }
                            ),
                        })
                    end
                end

            elseif action == "newline" then
                if not replace_selection_if_any("\n") then
                    local new_lines, new_cl, new_cc = core.insert_text_lines(lines, cl, cc, "\n")
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "newline",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc },
                                { coalesce = false }
                            ),
                        })
                    end
                end

            elseif action == "submit" then
                clear_history_group()
                if ctx.features.submit and ctx.onSubmit then ctx.onSubmit(ctx.value) end

            elseif action == "delete_backward" then
                if not delete_selection_if_any() then
                    local new_lines, new_cl, new_cc = core.delete_backward_lines(lines, cl, cc)
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "delete_backward",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc }
                            ),
                        })
                    end
                end

            elseif action == "delete_forward" then
                if not delete_selection_if_any() then
                    local new_lines, new_cl, new_cc = core.delete_forward_lines(lines, cl, cc)
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "delete_forward",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc }
                            ),
                        })
                    end
                end

            elseif name == "char" and input and input ~= "" then
                if not replace_selection_if_any(input) then
                    local new_lines, new_cl, new_cc = core.insert_text_lines(lines, cl, cc, input)
                    if new_lines then
                        emit(new_lines, new_cl, new_cc, {
                            history = core.make_history_edit(
                                "insert",
                                { line = cl, col = cc },
                                { line = new_cl, col = new_cc }
                            ),
                        })
                    end
                end

            elseif name == "paste" and input and input ~= "" then
                if ctx.features.paste then
                    if not replace_selection_if_any(input) then
                        local new_lines, new_cl, new_cc = core.insert_text_lines(lines, cl, cc, input)
                        if new_lines then
                            emit(new_lines, new_cl, new_cc, {
                                history = core.make_history_edit(
                                    "paste",
                                    { line = cl, col = cc },
                                    { line = new_cl, col = new_cc },
                                    { coalesce = false }
                                ),
                            })
                        end
                    end
                end

            end
        end,
    }
    local focus_flag = focus_handle.isFocused

    tui.useEffect(function()
        core.sync_composing_feature(features.ime_composing, {
            set_composing = set_composing,
            composing = ctx.composing,
        })
        core.clear_composing_on_blur({
            set_composing = set_composing,
            composing = ctx.composing,
        }, focus_flag)
        if not features.ime_composing then
            ctx.composing = ""
        end
        if not focus_flag then
            ctx.composing = ""
        end
    end, { focus_flag, features.ime_composing })

    -- -------------------------------------------------------------------------
    -- Render: build `vis_height` Text elements, one per visible line.
    -- -------------------------------------------------------------------------
    local st     = ctx.st
    local width  = props.width
    local show_placeholder = (#value == 0) and not focus_flag and placeholder ~= ""

    -- Cursor within visible area.
    local cursor_row = cl - st - 1   -- 0-based row within viewport
    local cursor_line, cursor_line_caret = core.with_composing(lines_now[cl], cc, composing)
    local cursor_col = core.prefix_width(cursor_line, cursor_line_caret)
    local cursor = tui.useCursor()

    local row_elements = {}
    for r = 0, vis_height - 1 do
        local li = st + r + 1
        local row_children
        if show_placeholder and r == 0 then
            row_children = { placeholder }
        elseif li <= #lines_now then
            if li == cl and composing ~= "" then
                local display_line = cursor_line
                row_children = { core.chars_to_string(display_line) }
            else
                local line_chars = lines_now[li]
                local sel_start, sel_end = core.selection_range_for_line(
                    features.selection and anchor_clamped or nil,
                    { line = cl, col = cc },
                    li,
                    #line_chars
                )
                row_children = core.spans_for_range(line_chars, sel_start, sel_end)
            end
        else
            row_children = { "" }
        end
        local row_el = tui.Text { key = tostring(r + 1), width = width, wrap = "nowrap", table.unpack(row_children) }
        if r == cursor_row and focus_flag and not disabled then
            cursor.setCursorPosition {
                x = cursor_col,
                y = cursor_row,
            }
        end
        row_elements[r + 1] = row_el
    end

    -- Mouse support: add onClick and onScroll to the outer Box.
    -- localCol/localRow are 0-based offsets relative to the handler Box,
    -- provided by hit_test.dispatch_click / dispatch_scroll.
    local onClick
    if not disabled then
        onClick = function(ev)
            -- Click to focus
            if not focus_flag then
                focus_handle.focus()
            end
            -- Click to move cursor
            local local_row = ev.localRow
            local local_col = ev.localCol
            if local_row < 0 then local_row = 0 end
            if local_col < 0 then local_col = 0 end
            -- Convert local row to line index (1-based)
            local target_line = st + local_row + 1
            if target_line > #lines_now then target_line = #lines_now end
            if target_line < 1 then target_line = 1 end
            -- Convert display column to char index for that line
            local line_chars = lines_now[target_line]
            local target_col = core.col_to_char_index(line_chars, local_col, nil)
            ctx.set_caret_line(target_line)
            ctx.set_caret_col(target_col)
            ctx.set_anchor(nil)
            ctx.cl = target_line
            ctx.cc = target_col
            ctx.anchor = nil
        end
    end

    local onScroll
    if not disabled then
        onScroll = function(ev)
            if not focus_flag then
                focus_handle.focus()
            end
            -- Scroll: direction 1 = scroll_up (wheel up, viewport moves up, st decreases)
            --         direction -1 = scroll_down (wheel down, viewport moves down, st increases)
            local new_st = st - ev.direction
            new_st = math.max(0, math.min(new_st, nlines - scroll_window))
            if new_st ~= st then
                set_scroll_top(new_st)
                ctx.st = new_st
            end
        end
    end

    return tui.Box {
        ref = measureRef,
        flexDirection = "column",
        width = width,
        height = vis_height,
        onClick = onClick,
        onScroll = onScroll,
        table.unpack(row_elements),
    }
end

function M.Textarea(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = textarea_impl, props = props, key = key }
end

return M
