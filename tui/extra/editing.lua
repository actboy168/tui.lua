-- Shared editor primitives for building text input controls.
--
-- This module is used by tui.extra.text_input and tui.extra.textarea, and is
-- also available to user code that wants to build custom text editors on top
-- of the same grapheme-aware editing behaviour.

local tui = require "tui"

local M = {}

local keymap_action_names = {
    copy = "copy",
    cut = "cut",
    undo = "undo",
    redo = "redo",
    moveLeft = "move_left",
    move_left = "move_left",
    moveRight = "move_right",
    move_right = "move_right",
    moveUp = "move_up",
    move_up = "move_up",
    moveDown = "move_down",
    move_down = "move_down",
    lineStart = "line_start",
    line_start = "line_start",
    moveStart = "line_start",
    move_start = "line_start",
    lineEnd = "line_end",
    line_end = "line_end",
    selectAll = "select_all",
    select_all = "select_all",
    moveEnd = "end",
    ["end"] = "line_end",
    docStart = "doc_start",
    doc_start = "doc_start",
    docEnd = "doc_end",
    doc_end = "doc_end",
    wordLeft = "word_left",
    word_left = "word_left",
    wordRight = "word_right",
    word_right = "word_right",
    deleteBackward = "delete_backward",
    delete_backward = "delete_backward",
    deleteForward = "delete_forward",
    delete_forward = "delete_forward",
    deleteWordLeft = "delete_word_left",
    delete_word_left = "delete_word_left",
    deleteWordRight = "delete_word_right",
    delete_word_right = "delete_word_right",
    killLeft = "kill_left",
    kill_left = "kill_left",
    killRight = "kill_right",
    kill_right = "kill_right",
    submit = "submit",
    newline = "newline",
}

local default_shortcut_keymap = {
    ["left"] = "move_left",
    ["shift+left"] = "move_left",
    ["right"] = "move_right",
    ["shift+right"] = "move_right",
    ["home"] = "line_start",
    ["shift+home"] = "line_start",
    ["end"] = "line_end",
    ["shift+end"] = "line_end",
    ["backspace"] = "delete_backward",
    ["delete"] = "delete_forward",
    ["ctrl+shift+c"] = "copy",
    ["meta+c"] = "copy",
    ["ctrl+x"] = "cut",
    ["meta+x"] = "cut",
    ["ctrl+z"] = "undo",
    ["ctrl+y"] = "redo",
    ["ctrl+shift+z"] = "redo",
    ["ctrl+a"] = "select_all",
    ["ctrl+e"] = "line_end",
    ["ctrl+left"] = "word_left",
    ["ctrl+shift+left"] = "word_left",
    ["ctrl+right"] = "word_right",
    ["ctrl+shift+right"] = "word_right",
    ["ctrl+backspace"] = "delete_word_left",
    ["ctrl+shift+backspace"] = "delete_word_left",
    ["ctrl+w"] = "delete_word_left",
    ["ctrl+delete"] = "delete_word_right",
    ["ctrl+shift+delete"] = "delete_word_right",
    ["ctrl+u"] = "kill_left",
    ["ctrl+k"] = "kill_right",
}

function M.resolve_features(props)
    local features = props and props.features or nil
    return {
        undo_redo = not (features and features.undoRedo == false),
        copy_cut = not (features and features.copyCut == false),
        select_all = not (features and features.selectAll == false),
        word_ops = not (features and features.wordOps == false),
        kill_ops = not (features and features.killOps == false),
        ime_composing = not (features and features.imeComposing == false),
        paste = not (features and features.paste == false),
        submit = not (features and features.submit == false),
        selection = not (features and features.selection == false),
    }
end

local function normalize_keymap_action(action)
    return keymap_action_names[action]
end

local function copy_keymap(keymap)
    local out = {}
    for binding, action in pairs(keymap) do
        out[binding] = action
    end
    return out
end

local function canonicalize_key_binding(binding)
    if type(binding) ~= "string" or binding == "" then
        return nil
    end
    local ctrl = false
    local shift = false
    local meta = false
    local base = nil
    for part in binding:gmatch("[^+]+") do
        local token = part:lower()
        if token == "ctrl" or token == "control" then
            ctrl = true
        elseif token == "shift" then
            shift = true
        elseif token == "meta" or token == "alt" then
            meta = true
        elseif token == "return" then
            base = "enter"
        else
            base = token
        end
    end
    if not base then
        return nil
    end
    local parts = {}
    if ctrl then
        parts[#parts + 1] = "ctrl"
    end
    if shift then
        parts[#parts + 1] = "shift"
    end
    if meta then
        parts[#parts + 1] = "meta"
    end
    if base == " " then
        base = "space"
    end
    parts[#parts + 1] = base
    return table.concat(parts, "+")
end

local function key_to_binding(key)
    if not key or not key.name then
        return nil
    end
    local base
    if key.name == "char" then
        base = (key.input or ""):lower()
        if base == "" then
            return nil
        end
        if base == " " then
            base = "space"
        end
    else
        base = key.name
    end
    local parts = {}
    if key.ctrl then
        parts[#parts + 1] = "ctrl"
    end
    if key.shift then
        parts[#parts + 1] = "shift"
    end
    if key.meta then
        parts[#parts + 1] = "meta"
    end
    parts[#parts + 1] = base
    return table.concat(parts, "+")
end

function M.default_shortcut_keymap()
    return copy_keymap(default_shortcut_keymap)
end

function M.default_text_input_keymap()
    local keymap = M.default_shortcut_keymap()
    keymap["enter"] = "submit"
    return keymap
end

function M.default_textarea_keymap(enter_behavior)
    local keymap = M.default_shortcut_keymap()
    keymap["up"] = "move_up"
    keymap["shift+up"] = "move_up"
    keymap["down"] = "move_down"
    keymap["shift+down"] = "move_down"
    keymap["ctrl+home"] = "doc_start"
    keymap["ctrl+shift+home"] = "doc_start"
    keymap["ctrl+end"] = "doc_end"
    keymap["ctrl+shift+end"] = "doc_end"
    keymap["ctrl+enter"] = "submit"
    keymap["shift+enter"] = "newline"
    if enter_behavior == "newline" then
        keymap["enter"] = "newline"
    else
        keymap["enter"] = "submit"
    end
    return keymap
end

local function remove_action_bindings(keymap, action)
    for binding, current_action in pairs(keymap) do
        if current_action == action then
            keymap[binding] = nil
        end
    end
end

local function add_action_bindings(keymap, action, bindings)
    if bindings == false then
        return
    end
    if type(bindings) == "string" then
        bindings = { bindings }
    end
    if type(bindings) ~= "table" then
        return
    end
    for i = 1, #bindings do
        local binding = canonicalize_key_binding(bindings[i])
        if binding then
            keymap[binding] = action
        end
    end
end

function M.resolve_keymap(props, defaults)
    local resolved = copy_keymap(defaults or {})
    local keymap = props and props.keymap or nil
    if not keymap then
        return resolved
    end
    for binding_or_action, action_or_bindings in pairs(keymap) do
        local action = normalize_keymap_action(binding_or_action)
        if action then
            remove_action_bindings(resolved, action)
            add_action_bindings(resolved, action, action_or_bindings)
        else
            local binding = canonicalize_key_binding(binding_or_action)
            if binding then
                if action_or_bindings == false then
                    resolved[binding] = nil
                else
                    action = normalize_keymap_action(action_or_bindings)
                    if action then
                        resolved[binding] = action
                    end
                end
            end
        end
    end
    return resolved
end

function M.resolve_key_action(key, keymap)
    keymap = keymap or M.default_shortcut_keymap()
    local binding = key_to_binding(key)
    return binding and keymap[binding] or nil
end

function M.to_chars(s)
    local chars = {}
    if not s or s == "" then return chars end
    for ch, _ in tui.iterChars(s) do
        chars[#chars + 1] = ch
    end
    return chars
end

function M.chars_to_string(chars)
    return table.concat(chars)
end

function M.char_width(ch)
    return tui.displayWidth(ch)
end

function M.prefix_width(chars, i)
    local w = 0
    for k = 1, i do
        w = w + M.char_width(chars[k])
    end
    return w
end

function M.copy_chars(chars)
    local out = {}
    for i = 1, #chars do
        out[i] = chars[i]
    end
    return out
end

function M.copy_list(list)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    return out
end

function M.append_item(list, item)
    local out = M.copy_list(list)
    out[#out + 1] = item
    return out
end

function M.drop_last(list)
    local out = {}
    for i = 1, #list - 1 do
        out[i] = list[i]
    end
    return out
end

function M.mask_chars(chars, mask)
    if not mask or #mask == 0 then
        return chars
    end
    local out = {}
    for i = 1, #chars do
        out[i] = mask
    end
    return out
end

function M.make_window(chars, caret, width, mask)
    if width <= 0 then return "", 0, 1, 0 end

    local masked = M.mask_chars(chars, mask)
    local total_w = M.prefix_width(masked, #masked)
    if total_w <= width then
        return M.chars_to_string(masked), M.prefix_width(masked, caret), 1, #masked
    end

    local start = 1
    while start <= #masked do
        local caret_width = M.prefix_width(masked, caret) - M.prefix_width(masked, start - 1)
        if caret_width <= width then break end
        start = start + 1
    end

    local visible = {}
    local used = 0
    for i = start, #masked do
        local cw = M.char_width(masked[i])
        if used + cw > width then break end
        visible[#visible + 1] = masked[i]
        used = used + cw
    end

    local caret_col = M.prefix_width(masked, caret) - M.prefix_width(masked, start - 1)
    if caret_col < 0 then caret_col = 0 end
    if caret_col > width then caret_col = width end
    return table.concat(visible), caret_col, start, start + #visible - 1
end

function M.with_composing(chars, caret, composing)
    if not composing or composing == "" then
        return chars, caret
    end

    local composing_chars = M.to_chars(composing)
    local out = {}
    for i = 1, caret do out[i] = chars[i] end
    for _, ch in ipairs(composing_chars) do
        out[#out + 1] = ch
    end
    for i = caret + 1, #chars do
        out[#out + 1] = chars[i]
    end
    return out, caret + #composing_chars
end

local function is_space(ch)
    return ch ~= nil and ch:match("^%s$") ~= nil
end

function M.find_word_left(chars, caret)
    local i = caret
    while i > 0 and is_space(chars[i]) do
        i = i - 1
    end
    while i > 0 and not is_space(chars[i]) do
        i = i - 1
    end
    return i
end

function M.find_word_right(chars, caret)
    local i = caret
    while i < #chars and not is_space(chars[i + 1]) do
        i = i + 1
    end
    while i < #chars and is_space(chars[i + 1]) do
        i = i + 1
    end
    return i
end

function M.has_selection(anchor, caret)
    return anchor ~= nil and anchor ~= caret
end

function M.normalize_selection(anchor, caret)
    if anchor <= caret then
        return anchor, caret
    end
    return caret, anchor
end

function M.insert_chars(chars, caret, ins_chars)
    if not ins_chars or #ins_chars == 0 then return nil end
    local out = {}
    for i = 1, caret do out[i] = chars[i] end
    for _, ch in ipairs(ins_chars) do out[#out + 1] = ch end
    for i = caret + 1, #chars do out[#out + 1] = chars[i] end
    return out, caret + #ins_chars
end

function M.insert_text(chars, caret, text)
    if not text or text == "" then return nil end
    return M.insert_chars(chars, caret, M.to_chars(text))
end

function M.delete_backward(chars, caret)
    if caret <= 0 then return nil end
    local out = {}
    for i = 1, caret - 1 do out[i] = chars[i] end
    for i = caret + 1, #chars do out[#out + 1] = chars[i] end
    return out, caret - 1
end

function M.delete_forward(chars, caret)
    if caret >= #chars then return nil end
    local out = {}
    for i = 1, caret do out[i] = chars[i] end
    for i = caret + 2, #chars do out[#out + 1] = chars[i] end
    return out, caret
end

function M.delete_to_start(chars, caret)
    if caret <= 0 then return nil end
    local out = {}
    for i = caret + 1, #chars do
        out[#out + 1] = chars[i]
    end
    return out, 0
end

function M.delete_to_end(chars, caret)
    if caret >= #chars then return nil end
    local out = {}
    for i = 1, caret do
        out[i] = chars[i]
    end
    return out, caret
end

function M.delete_word_backward(chars, caret)
    if caret <= 0 then return nil end
    local new_caret = M.find_word_left(chars, caret)
    if new_caret == caret then return nil end
    local out = {}
    for i = 1, new_caret do out[i] = chars[i] end
    for i = caret + 1, #chars do out[#out + 1] = chars[i] end
    return out, new_caret
end

function M.delete_word_forward(chars, caret)
    if caret >= #chars then return nil end
    local new_caret = M.find_word_right(chars, caret)
    if new_caret == caret then return nil end
    local out = {}
    for i = 1, caret do out[i] = chars[i] end
    for i = new_caret + 1, #chars do out[#out + 1] = chars[i] end
    return out, caret
end

function M.delete_selection(chars, anchor, caret)
    if not M.has_selection(anchor, caret) then return nil end
    local start_pos, end_pos = M.normalize_selection(anchor, caret)
    local out = {}
    for i = 1, start_pos do out[i] = chars[i] end
    for i = end_pos + 1, #chars do out[#out + 1] = chars[i] end
    return out, start_pos
end

function M.replace_selection(chars, anchor, caret, text)
    if not M.has_selection(anchor, caret) then
        return M.insert_text(chars, caret, text)
    end
    local base, new_caret = M.delete_selection(chars, anchor, caret)
    if not text or text == "" then
        return base, new_caret
    end
    return M.insert_text(base, new_caret, text)
end

function M.selection_text(chars, anchor, caret)
    if not M.has_selection(anchor, caret) then return nil end
    local start_pos, end_pos = M.normalize_selection(anchor, caret)
    local out = {}
    for i = start_pos + 1, end_pos do
        out[#out + 1] = chars[i]
    end
    return table.concat(out)
end

local function push_span(out, selected, text)
    if text == nil or text == "" then return end
    local n = #out
    local last = out[n]
    if selected then
        if type(last) == "table" and last.inverse == true then
            last.text = last.text .. text
            return
        end
        out[n + 1] = { text = text, inverse = true }
        return
    end
    if type(last) == "string" then
        out[n] = last .. text
    else
        out[n + 1] = text
    end
end

function M.spans_for_range(chars, start_pos, end_pos, opts)
    opts = opts or {}
    local from = opts.start or 1
    local to = opts.stop or #chars
    local source = M.mask_chars(chars, opts.mask)
    if to < from then return { "" } end

    local out = {}
    local buf = {}
    local selected = nil
    for i = from, to do
        local is_selected = start_pos ~= nil and end_pos ~= nil and i > start_pos and i <= end_pos
        if selected == nil then
            selected = is_selected
        elseif selected ~= is_selected then
            push_span(out, selected, table.concat(buf))
            buf = {}
            selected = is_selected
        end
        buf[#buf + 1] = source[i]
    end
    push_span(out, selected or false, table.concat(buf))
    if #out == 0 then
        out[1] = ""
    end
    return out
end

function M.selection_spans(chars, anchor, caret, opts)
    if not M.has_selection(anchor, caret) then
        return M.spans_for_range(chars, nil, nil, opts)
    end
    local start_pos, end_pos = M.normalize_selection(anchor, caret)
    return M.spans_for_range(chars, start_pos, end_pos, opts)
end

function M.parse_lines(value)
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

function M.serialize_lines(lines)
    local parts = {}
    for li = 1, #lines do
        parts[li] = table.concat(lines[li])
    end
    return table.concat(parts, "\n")
end

function M.copy_lines(lines)
    local out = {}
    for li = 1, #lines do
        out[li] = M.copy_chars(lines[li])
    end
    return out
end

function M.compare_positions(a, b)
    if a.line < b.line then return -1 end
    if a.line > b.line then return 1 end
    if a.col < b.col then return -1 end
    if a.col > b.col then return 1 end
    return 0
end

function M.copy_position(pos)
    if not pos then return nil end
    return { line = pos.line, col = pos.col }
end

function M.same_position(a, b)
    if a == nil or b == nil then
        return a == b
    end
    return a.line == b.line and a.col == b.col
end

function M.has_selection_pos(anchor, caret)
    return anchor ~= nil and M.compare_positions(anchor, caret) ~= 0
end

function M.normalize_selection_pos(anchor, caret)
    if M.compare_positions(anchor, caret) <= 0 then
        return M.copy_position(anchor), M.copy_position(caret)
    end
    return M.copy_position(caret), M.copy_position(anchor)
end

function M.col_for_x(line, target_x)
    local x = 0
    for i = 1, #line do
        local w = M.char_width(line[i])
        if x + w > target_x then
            return (target_x - x < x + w - target_x) and (i - 1) or i
        end
        x = x + w
    end
    return #line
end

function M.clamp_scroll(scroll_top, line, height, total_lines)
    if line < scroll_top + 1 then
        return line - 1
    elseif line > scroll_top + height then
        return line - height
    end
    if total_lines and scroll_top + height > total_lines then
        return math.max(0, total_lines - height)
    end
    return scroll_top
end

function M.insert_text_lines(lines, cl, cc, text)
    if not text or text == "" then return nil end

    local new_lines = M.copy_lines(lines)
    local line = new_lines[cl]
    local tail = {}
    for i = cc + 1, #line do
        tail[#tail + 1] = line[i]
    end
    for i = #line, cc + 1, -1 do
        line[i] = nil
    end

    local cur_line = line
    local ins_cl = cl
    local ins_cc = cc
    local inserted = false

    for ch, _ in tui.iterChars(text) do
        inserted = true
        if ch == "\n" then
            ins_cl = ins_cl + 1
            ins_cc = 0
            table.insert(new_lines, ins_cl, {})
            cur_line = new_lines[ins_cl]
        else
            cur_line[#cur_line + 1] = ch
            ins_cc = ins_cc + 1
        end
    end

    if not inserted then return nil end

    for _, ch in ipairs(tail) do
        cur_line[#cur_line + 1] = ch
    end

    return new_lines, ins_cl, ins_cc
end

function M.delete_backward_lines(lines, cl, cc)
    if cc > 0 then
        local new_lines = M.copy_lines(lines)
        table.remove(new_lines[cl], cc)
        return new_lines, cl, cc - 1
    elseif cl > 1 then
        local new_lines = M.copy_lines(lines)
        local prev = new_lines[cl - 1]
        local new_cc = #prev
        for _, ch in ipairs(new_lines[cl]) do
            prev[#prev + 1] = ch
        end
        table.remove(new_lines, cl)
        return new_lines, cl - 1, new_cc
    end
    return nil
end

function M.delete_forward_lines(lines, cl, cc)
    local line = lines[cl]
    if cc < #line then
        local new_lines = M.copy_lines(lines)
        table.remove(new_lines[cl], cc + 1)
        return new_lines, cl, cc
    elseif cl < #lines then
        local new_lines = M.copy_lines(lines)
        local cur = new_lines[cl]
        for _, ch in ipairs(new_lines[cl + 1]) do
            cur[#cur + 1] = ch
        end
        table.remove(new_lines, cl + 1)
        return new_lines, cl, cc
    end
    return nil
end

function M.delete_to_line_start_lines(lines, cl, cc)
    if cc <= 0 then return nil end
    local new_lines = M.copy_lines(lines)
    local line = new_lines[cl]
    for i = cc, 1, -1 do
        table.remove(line, i)
    end
    return new_lines, cl, 0
end

function M.delete_to_line_end_lines(lines, cl, cc)
    local line = lines[cl]
    if cc >= #line then return nil end
    local new_lines = M.copy_lines(lines)
    local new_line = new_lines[cl]
    for i = #new_line, cc + 1, -1 do
        new_line[i] = nil
    end
    return new_lines, cl, cc
end

function M.delete_word_backward_lines(lines, cl, cc)
    if cc <= 0 then return nil end
    local line = lines[cl]
    local new_cc = M.find_word_left(line, cc)
    if new_cc == cc then return nil end
    local new_lines = M.copy_lines(lines)
    local new_line = new_lines[cl]
    for i = cc, new_cc + 1, -1 do
        table.remove(new_line, i)
    end
    return new_lines, cl, new_cc
end

function M.delete_word_forward_lines(lines, cl, cc)
    local line = lines[cl]
    if cc >= #line then return nil end
    local new_cc = M.find_word_right(line, cc)
    if new_cc == cc then return nil end
    local new_lines = M.copy_lines(lines)
    local new_line = new_lines[cl]
    for i = new_cc, cc + 1, -1 do
        table.remove(new_line, i)
    end
    return new_lines, cl, cc
end

function M.delete_selection_lines(lines, anchor, caret)
    if not M.has_selection_pos(anchor, caret) then return nil end
    local start_pos, end_pos = M.normalize_selection_pos(anchor, caret)
    local new_lines = M.copy_lines(lines)

    if start_pos.line == end_pos.line then
        local line = new_lines[start_pos.line]
        for i = end_pos.col, start_pos.col + 1, -1 do
            table.remove(line, i)
        end
        return new_lines, start_pos.line, start_pos.col
    end

    local first = new_lines[start_pos.line]
    local last = new_lines[end_pos.line]
    local merged = {}
    for i = 1, start_pos.col do
        merged[i] = first[i]
    end
    for i = end_pos.col + 1, #last do
        merged[#merged + 1] = last[i]
    end
    new_lines[start_pos.line] = merged
    for i = end_pos.line, start_pos.line + 1, -1 do
        table.remove(new_lines, i)
    end
    return new_lines, start_pos.line, start_pos.col
end

function M.replace_selection_lines(lines, anchor, caret, text)
    if not M.has_selection_pos(anchor, caret) then
        return nil
    end
    local base, cl, cc = M.delete_selection_lines(lines, anchor, caret)
    if not text or text == "" then
        return base, cl, cc
    end
    return M.insert_text_lines(base, cl, cc, text)
end

function M.selection_text_lines(lines, anchor, caret)
    if not M.has_selection_pos(anchor, caret) then return nil end
    local start_pos, end_pos = M.normalize_selection_pos(anchor, caret)
    if start_pos.line == end_pos.line then
        return M.selection_text(lines[start_pos.line], start_pos.col, end_pos.col)
    end

    local parts = {}
    local first = lines[start_pos.line]
    local last = lines[end_pos.line]
    local head = {}
    for i = start_pos.col + 1, #first do
        head[#head + 1] = first[i]
    end
    parts[#parts + 1] = table.concat(head)
    for li = start_pos.line + 1, end_pos.line - 1 do
        parts[#parts + 1] = table.concat(lines[li])
    end
    local tail = {}
    for i = 1, end_pos.col do
        tail[#tail + 1] = last[i]
    end
    parts[#parts + 1] = table.concat(tail)
    return table.concat(parts, "\n")
end

function M.selection_range_for_line(anchor, caret, line_no, line_len)
    if not M.has_selection_pos(anchor, caret) then return nil end
    local start_pos, end_pos = M.normalize_selection_pos(anchor, caret)
    if line_no < start_pos.line or line_no > end_pos.line then
        return nil
    end
    if start_pos.line == end_pos.line then
        return start_pos.col, end_pos.col
    end
    if line_no == start_pos.line then
        return start_pos.col, line_len
    end
    if line_no == end_pos.line then
        return 0, end_pos.col
    end
    return 0, line_len
end

function M.common_shortcut(key)
    return M.resolve_key_action(key, M.default_shortcut_keymap())
end

function M.push_history_snapshot(set_undo_stack, set_redo_stack, snapshot)
    set_undo_stack(function(stack)
        return M.append_item(stack, snapshot)
    end)
    set_redo_stack({})
end

local function copy_history_cursor(cursor)
    if type(cursor) == "table" then
        return M.copy_position(cursor)
    end
    return cursor
end

local function same_history_cursor(a, b)
    if type(a) == "table" or type(b) == "table" then
        return M.same_position(a, b)
    end
    return a == b
end

function M.make_history_edit(kind, caret_before, caret_after, opts)
    opts = opts or {}
    return {
        kind = kind,
        caret_before = copy_history_cursor(caret_before),
        caret_after = copy_history_cursor(caret_after),
        coalesce = opts.coalesce ~= false,
    }
end

function M.clear_history_group(set_history_group, state)
    if set_history_group then
        set_history_group(nil)
    end
    if state then
        state.history_group = nil
    end
end

local function same_history_group(group, edit)
    return group ~= nil
        and edit ~= nil
        and group.coalesce ~= false
        and edit.coalesce ~= false
        and group.kind == edit.kind
        and same_history_cursor(group.caret_after, edit.caret_before)
end

function M.record_history_edit(set_undo_stack, set_redo_stack, set_history_group, state, snapshot, edit)
    if not same_history_group(state and state.history_group or nil, edit) then
        M.push_history_snapshot(set_undo_stack, set_redo_stack, snapshot)
    else
        set_redo_stack({})
    end
    local group = {
        kind = edit.kind,
        caret_before = copy_history_cursor(edit.caret_before),
        caret_after = copy_history_cursor(edit.caret_after),
        coalesce = edit.coalesce ~= false,
    }
    if set_history_group then
        set_history_group(group)
    end
    if state then
        state.history_group = group
        state.redo_stack = {}
    end
end

function M.sync_history_feature(enabled, set_undo_stack, set_redo_stack, state)
    if enabled then
        return false
    end
    set_undo_stack({})
    set_redo_stack({})
    if state then
        state.undo_stack = {}
        state.redo_stack = {}
        state.history_group = nil
    end
    return true
end

function M.sync_selection_feature(enabled, set_anchor, state)
    if enabled then
        return false
    end
    set_anchor(nil)
    if state then
        state.anchor = nil
    end
    return true
end

function M.feature_enabled_for_shortcut(features, shortcut)
    if shortcut == nil then
        return true
    end
    if shortcut == "copy" or shortcut == "cut" then
        return features.copy_cut and features.selection
    end
    if shortcut == "undo" or shortcut == "redo" then
        return features.undo_redo
    end
    if shortcut == "select_all" then
        return features.select_all and features.selection
    end
    if shortcut == "word_left" or shortcut == "word_right"
        or shortcut == "delete_word_left" or shortcut == "delete_word_right" then
        return features.word_ops
    end
    if shortcut == "kill_left" or shortcut == "kill_right" then
        return features.kill_ops
    end
    return true
end

function M.restore_undo(undo_stack, set_undo_stack, set_redo_stack, snapshot_current, restore_snapshot)
    local snapshot = undo_stack[#undo_stack]
    if not snapshot then
        return false
    end
    local current = snapshot_current()
    set_undo_stack(function(stack)
        return M.drop_last(stack)
    end)
    set_redo_stack(function(stack)
        return M.append_item(stack, current)
    end)
    restore_snapshot(snapshot)
    return true
end

function M.restore_redo(redo_stack, set_undo_stack, set_redo_stack, snapshot_current, restore_snapshot)
    local snapshot = redo_stack[#redo_stack]
    if not snapshot then
        return false
    end
    local current = snapshot_current()
    set_redo_stack(function(stack)
        return M.drop_last(stack)
    end)
    set_undo_stack(function(stack)
        return M.append_item(stack, current)
    end)
    restore_snapshot(snapshot)
    return true
end

function M.set_composing(state, value)
    value = value or ""
    state.set_composing(value)
    state.composing = value
end

function M.clear_composing(state)
    if not state.composing or state.composing == "" then
        return false
    end
    M.set_composing(state, "")
    return true
end

function M.handle_shared_editor_input(state)
    state.features = state.features or M.resolve_features({})
    if not M.feature_enabled_for_shortcut(state.features, state.shortcut) then
        if state.clear_history_group then
            state.clear_history_group()
        end
        return state.shortcut ~= nil
    end
    if state.name == "composing" then
        if not state.features.ime_composing then
            return true
        end
        M.set_composing(state, state.input)
        return true
    end
    if state.name == "composing_confirm" then
        if state.input and state.input ~= "" then
            if not state.replace_selection(state.input) then
                state.insert_text(state.input)
            end
        end
        M.set_composing(state, "")
        return true
    end
    if state.name == "escape" then
        if state.clear_history_group then
            state.clear_history_group()
        end
        if M.clear_composing(state) then
            return true
        end
        return state.clear_selection()
    end
    if state.shortcut == "copy" then
        if state.clear_history_group then
            state.clear_history_group()
        end
        local text = state.selection_text()
        if text and text ~= "" then
            state.clipboard.write(text)
        end
        return true
    end
    if state.shortcut == "cut" then
        if state.clear_history_group then
            state.clear_history_group()
        end
        local text = state.selection_text()
        if text and text ~= "" then
            state.clipboard.write(text)
            state.delete_selection()
        end
        return true
    end
    if state.shortcut == "undo" then
        if state.clear_history_group then
            state.clear_history_group()
        end
        if not state.features.undo_redo then
            return true
        end
        return M.restore_undo(
            state.undo_stack,
            state.set_undo_stack,
            state.set_redo_stack,
            state.snapshot_current,
            state.restore_snapshot
        )
    end
    if state.shortcut == "redo" then
        if state.clear_history_group then
            state.clear_history_group()
        end
        if not state.features.undo_redo then
            return true
        end
        return M.restore_redo(
            state.redo_stack,
            state.set_undo_stack,
            state.set_redo_stack,
            state.snapshot_current,
            state.restore_snapshot
        )
    end
    return false
end

function M.clear_composing_on_blur(state, is_focused)
    if is_focused then
        return false
    end
    return M.clear_composing(state)
end

function M.sync_composing_feature(enabled, state)
    if enabled then
        return false
    end
    return M.clear_composing(state)
end

return M
