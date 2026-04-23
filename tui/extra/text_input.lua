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
--   features    : optional feature flags table, e.g. { undoRedo = false }.
--   keymap      : optional shortcut overrides, e.g. { ["ctrl+s"] = "submit" }.
--
-- Cursor rendering: TextInput uses useCursor() to declare its
-- cursor position (Ink-compatible API). The framework converts this to
-- absolute coordinates via find_cursor() after layout. IME candidate
-- window placement follows the physical cursor position.
--
-- Cursor position is a UTF-8 character index (1..#chars+1), not a byte
-- offset. Conversions to display columns go through wcwidth.

local tui  = require "tui"
local core = require "tui.extra.editing"

local M = {}

local function text_input_impl(props)
    props = props or {}

    local value       = props.value or ""
    local onChange    = props.onChange
    local onSubmit    = props.onSubmit
    local placeholder = props.placeholder or ""
    local mask        = props.mask
    local clipboard   = tui.useClipboard()
    local features    = core.resolve_features(props)
    local keymap      = core.resolve_keymap(props, core.default_text_input_keymap())

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
    local chars = core.to_chars(value)
    local caret_state, set_caret = tui.useState(#chars)
    local selection_anchor, set_selection_anchor = tui.useState(nil)
    local undo_stack, set_undo_stack = tui.useState({})
    local redo_stack, set_redo_stack = tui.useState({})
    local history_group, set_history_group = tui.useState(nil)
    local caret_clamped = caret_state
    if caret_clamped > #chars then caret_clamped = #chars end
    local anchor_clamped = selection_anchor
    if anchor_clamped ~= nil and anchor_clamped > #chars then
        anchor_clamped = #chars
    end
    if anchor_clamped == caret_clamped then
        anchor_clamped = nil
    end
    tui.useEffect(function()
        if caret_state > #chars then set_caret(#chars) end
        if selection_anchor ~= anchor_clamped then set_selection_anchor(anchor_clamped) end
    end, { caret_state, #chars, selection_anchor, anchor_clamped })

    -- Keep a ref to latest props so the useFocus callback sees fresh value.
    local ctx_ref, _ = tui.useState({})
    ctx_ref.chars = chars
    ctx_ref.caret = caret_clamped
    ctx_ref.anchor = anchor_clamped
    ctx_ref.on_change = onChange
    ctx_ref.on_submit = onSubmit
    ctx_ref.set_caret = set_caret
    ctx_ref.set_anchor = set_selection_anchor
    ctx_ref.value = value
    ctx_ref.clipboard = clipboard
    ctx_ref.features = features
    ctx_ref.keymap = keymap
    ctx_ref.undo_stack = undo_stack
    ctx_ref.redo_stack = redo_stack
    ctx_ref.history_group = history_group

    local function snapshot_current()
        return {
            value = ctx_ref.value,
            caret = ctx_ref.caret,
            anchor = ctx_ref.anchor,
        }
    end

    local function push_undo_snapshot()
        if not ctx_ref.features.undo_redo then
            return
        end
        core.push_history_snapshot(set_undo_stack, set_redo_stack, snapshot_current())
        ctx_ref.redo_stack = {}
    end

    local function clear_history_group()
        core.clear_history_group(set_history_group, ctx_ref)
    end

    tui.useEffect(function()
        core.sync_history_feature(features.undo_redo, set_undo_stack, set_redo_stack, ctx_ref)
    end, { features.undo_redo })
    tui.useEffect(function()
        core.sync_selection_feature(features.selection, set_selection_anchor, ctx_ref)
    end, { features.selection })

    local function restore_snapshot(snapshot)
        local restore_chars = core.to_chars(snapshot.value or "")
        local restore_caret = math.min(math.max(snapshot.caret or 0, 0), #restore_chars)
        local restore_anchor = snapshot.anchor
        if restore_anchor ~= nil then
            restore_anchor = math.min(math.max(restore_anchor, 0), #restore_chars)
            if restore_anchor == restore_caret then
                restore_anchor = nil
            end
        end
        ctx_ref.set_caret(restore_caret)
        ctx_ref.set_anchor(restore_anchor)
        ctx_ref.caret = restore_caret
        ctx_ref.anchor = restore_anchor
        ctx_ref.chars = restore_chars
        ctx_ref.value = snapshot.value or ""
        if ctx_ref.on_change then
            ctx_ref.on_change(ctx_ref.value)
        end
    end

    -- Composing (pre-edit) text state for IME input.
    -- When an IME is actively composing (e.g. typing pinyin), the terminal
    -- may send composing events. Most macOS terminals (Terminal.app, iTerm2)
    -- handle pre-edit display internally and only send the final confirmed
    -- text. Terminals that support protocols like kitty may send composing
    -- sequences, which keys.parse will translate into composing events.
    local composing, set_composing = tui.useState("")
    ctx_ref.composing = composing

    local focus_handle = tui.useFocus {
        autoFocus = (not disabled) and (props.autoFocus ~= false),
        id        = props.focusId,
        isActive  = not disabled,
        on_input  = function(input, key)
            local cs = ctx_ref.chars
            local c  = ctx_ref.caret
            local anchor = ctx_ref.anchor
            local name = key.name
            local action = core.resolve_key_action(key, ctx_ref.keymap)

            local function emit(new_chars, new_caret, opts)
                local new_value = core.chars_to_string(new_chars)
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
                ctx_ref.set_caret(new_caret)
                ctx_ref.set_anchor(nil)
                if ctx_ref.on_change then
                    ctx_ref.on_change(new_value)
                end
                ctx_ref.chars = new_chars
                ctx_ref.caret = new_caret
                ctx_ref.anchor = nil
                ctx_ref.value = new_value
            end

            local function move_caret(new_caret, extend)
                extend = extend and ctx_ref.features.selection
                if extend then
                    local next_anchor = anchor
                    if next_anchor == nil then
                        next_anchor = c
                    end
                    ctx_ref.set_anchor(next_anchor == new_caret and nil or next_anchor)
                    ctx_ref.anchor = next_anchor == new_caret and nil or next_anchor
                else
                    if ctx_ref.anchor ~= nil then
                        ctx_ref.set_anchor(nil)
                        ctx_ref.anchor = nil
                    end
                end
                if new_caret ~= c then
                    ctx_ref.set_caret(new_caret)
                    ctx_ref.caret = new_caret
                end
            end

            local function delete_selection_if_any()
                local nc, new_caret = core.delete_selection(cs, anchor, c)
                if nc then
                    emit(nc, new_caret)
                    return true
                end
                return false
            end

            local function replace_selection_if_any(text)
                if not core.has_selection(anchor, c) then
                    return false
                end
                local nc, new_caret = core.replace_selection(cs, anchor, c, text)
                if nc then
                    emit(nc, new_caret)
                    return true
                end
                return false
            end

            local function clear_selection_if_any()
                if ctx_ref.anchor == nil then
                    return false
                end
                ctx_ref.set_anchor(nil)
                ctx_ref.anchor = nil
                return true
            end

            if core.handle_shared_editor_input {
                name = name,
                shortcut = action,
                input = input,
                composing = ctx_ref.composing,
                set_composing = set_composing,
                clear_selection = clear_selection_if_any,
                replace_selection = replace_selection_if_any,
                insert_text = function(text)
                    local nc, new_caret = core.insert_text(cs, c, text)
                    if nc then emit(nc, new_caret) end
                end,
                selection_text = function()
                    return core.selection_text(cs, anchor, c)
                end,
                delete_selection = delete_selection_if_any,
                clipboard = ctx_ref.clipboard,
                features = ctx_ref.features,
                undo_stack = ctx_ref.undo_stack,
                redo_stack = ctx_ref.redo_stack,
                set_undo_stack = set_undo_stack,
                set_redo_stack = set_redo_stack,
                snapshot_current = snapshot_current,
                restore_snapshot = restore_snapshot,
                clear_history_group = clear_history_group,
            } then
                return
            end

            if action == "submit" then
                clear_history_group()
                if ctx_ref.features.submit and ctx_ref.on_submit then ctx_ref.on_submit(ctx_ref.value) end
            elseif action == "select_all" then
                clear_history_group()
                local all_anchor = (#cs > 0) and 0 or nil
                ctx_ref.set_anchor(all_anchor)
                ctx_ref.anchor = all_anchor
                if c ~= #cs then
                    ctx_ref.set_caret(#cs)
                    ctx_ref.caret = #cs
                end
            elseif action == "line_start" then
                clear_history_group()
                move_caret(0, key.shift)
            elseif action == "line_end" then
                clear_history_group()
                move_caret(#cs, key.shift)
            elseif action == "move_left" then
                clear_history_group()
                if c > 0 then move_caret(c - 1, key.shift) end
            elseif action == "move_right" then
                clear_history_group()
                if c < #cs then move_caret(c + 1, key.shift) end
            elseif action == "word_left" then
                clear_history_group()
                move_caret(core.find_word_left(cs, c), key.shift)
            elseif action == "word_right" then
                clear_history_group()
                move_caret(core.find_word_right(cs, c), key.shift)
            elseif action == "kill_left" then
                if not delete_selection_if_any() then
                    local nc, new_caret = core.delete_to_start(cs, c)
                    if nc then
                        emit(nc, new_caret, {
                            history = core.make_history_edit("delete_backward", c, new_caret),
                        })
                    end
                end
            elseif action == "kill_right" then
                if not delete_selection_if_any() then
                    local nc, new_caret = core.delete_to_end(cs, c)
                    if nc then
                        emit(nc, new_caret, {
                            history = core.make_history_edit("delete_forward", c, new_caret),
                        })
                    end
                end
            elseif action == "delete_word_left" then
                if not delete_selection_if_any() then
                    local nc, new_caret = core.delete_word_backward(cs, c)
                    if nc then
                        emit(nc, new_caret, {
                            history = core.make_history_edit("delete_backward", c, new_caret),
                        })
                    end
                end
            elseif action == "delete_word_right" then
                if not delete_selection_if_any() then
                    local nc, new_caret = core.delete_word_forward(cs, c)
                    if nc then
                        emit(nc, new_caret, {
                            history = core.make_history_edit("delete_forward", c, new_caret),
                        })
                    end
                end
            elseif action == "delete_backward" then
                if not delete_selection_if_any() then
                    local nc, new_caret = core.delete_backward(cs, c)
                    if nc then
                        emit(nc, new_caret, {
                            history = core.make_history_edit("delete_backward", c, new_caret),
                        })
                    end
                end
            elseif action == "delete_forward" then
                if not delete_selection_if_any() then
                    local nc, new_caret = core.delete_forward(cs, c)
                    if nc then
                        emit(nc, new_caret, {
                            history = core.make_history_edit("delete_forward", c, new_caret),
                        })
                    end
                end
            elseif name == "char" and input and input ~= "" then
                -- Insert printable UTF-8 character(s) at caret.
                if not replace_selection_if_any(input) then
                    local nc, new_caret = core.insert_text(cs, c, input)
                    if nc then
                        emit(nc, new_caret, {
                            history = core.make_history_edit("insert", c, new_caret),
                        })
                    end
                end
            elseif name == "paste" and input and input ~= "" then
                -- Bracketed paste: strip newlines (single-line field), then
                -- insert all remaining chars at once.
                if ctx_ref.features.paste then
                    local sanitized = input:gsub("\r\n", " "):gsub("[\r\n]", " ")
                    if sanitized ~= "" then
                        if not replace_selection_if_any(sanitized) then
                            local nc, new_caret = core.insert_text(cs, c, sanitized)
                            if nc then
                                emit(nc, new_caret, {
                                    history = core.make_history_edit("paste", c, new_caret, { coalesce = false }),
                                })
                            end
                        end
                    end
                end
            end
        end,
    }
    local focus_flag = focus_handle.isFocused

        -- Clear composing state when focus is lost so that a stale pre-edit
        -- string does not linger when the input regains focus later.
    tui.useEffect(function()
        core.sync_composing_feature(features.ime_composing, {
            set_composing = set_composing,
            composing = ctx_ref.composing,
        })
        core.clear_composing_on_blur({
            set_composing = set_composing,
            composing = ctx_ref.composing,
        }, focus_flag)
        if not features.ime_composing then
            ctx_ref.composing = ""
        end
        if not focus_flag then
            ctx_ref.composing = ""
        end
    end, { focus_flag, features.ime_composing })

    -- Visible text + caret column.
    local width = props.width or props.minWidth or nil
    -- Fall back to a reasonable default when unset; parent Box typically
    -- passes a flex-grown child so we try to render the whole value.
    local show_placeholder = (#chars == 0) and not focus_flag and placeholder ~= ""
    local render_width = width or math.max(core.prefix_width(chars, #chars) + 1,
                                            tui.displayWidth(placeholder))
    if render_width < 1 then render_width = 1 end

    local text_children, caret_col
    if show_placeholder then
        text_children, caret_col = { placeholder }, 0
    else
        if composing ~= "" then
            local display_chars, display_caret = core.with_composing(chars, caret_clamped, composing)
            local visible
            visible, caret_col = core.make_window(display_chars, display_caret, render_width, mask)
            text_children = { visible }
        else
            local _visible, _caret_col, start_i, end_i = core.make_window(chars, caret_clamped, render_width, mask)
            caret_col = _caret_col
            text_children = core.selection_spans(chars, features.selection and anchor_clamped or nil, caret_clamped, {
                mask = mask,
                start = start_i,
                stop = end_i,
            })
        end
    end

    -- Build the Text child; user may apply styling via a wrapper Box.
    local text_el = tui.Text { width = render_width, wrap = "nowrap", table.unpack(text_children) }

    -- Ink-style useCursor(): declare the caret relative to this component's
    -- rendered root box.
    local cursor = tui.useCursor()
    if focus_flag and not disabled then
        cursor.setCursorPosition {
            x = caret_col,
            y = 0,
        }
    end

    -- Mouse support: wrap the Text element in a Box so the framework's
    -- hit-test can dispatch onClick events to this component.
    local onClick
    if not disabled then
        onClick = function(ev)
            -- Click to focus
            if not focus_flag then
                focus_handle.focus()
            end
            -- Click to move cursor: localCol is the 0-based column offset
            -- relative to the handler Box (provided by hit_test.dispatch_click).
            local local_col = ev.localCol
            if local_col < 0 then local_col = 0 end
            -- Convert display column to character index
            local new_caret = core.col_to_char_index(chars, local_col, mask)
            if new_caret ~= nil then
                ctx_ref.set_caret(new_caret)
                ctx_ref.set_anchor(nil)
                ctx_ref.caret = new_caret
                ctx_ref.anchor = nil
            end
        end
    end

    return tui.Box {
        width  = render_width,
        height = 1,
        onClick = onClick,
        text_el,
    }
end

-- Public factory. `key` (if any) is hoisted to the element for reconciler
-- sibling identity, matching the Box/Text factories.
function M.TextInput(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = text_input_impl, props = props, key = key }
end

return M
