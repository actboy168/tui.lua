local lt = require "ltest"
local editing = require "tui.extra.editing"
local extra = require "tui.extra"

local suite = lt.test "editing"

local function key_event(name, input, ctrl, shift, meta)
    return {
        name = name,
        input = input or "",
        raw = input or "",
        ctrl = ctrl or false,
        shift = shift or false,
        meta = meta or false,
    }
end

function suite:test_extra_exports_editing_module()
    lt.assertEquals(extra.editing, editing)
end

function suite:test_find_word_boundaries()
    local chars = editing.to_chars("hello brave world")
    lt.assertEquals(editing.find_word_left(chars, #chars), 12)
    lt.assertEquals(editing.find_word_right(chars, 0), 6)
    lt.assertEquals(editing.find_word_right(chars, 6), 12)
end

function suite:test_delete_word_backward_and_forward()
    local chars = editing.to_chars("hello brave world")
    local left_chars, left_caret = editing.delete_word_backward(chars, #chars)
    lt.assertEquals(editing.chars_to_string(left_chars), "hello brave ")
    lt.assertEquals(left_caret, 12)

    local right_chars, right_caret = editing.delete_word_forward(chars, 6)
    lt.assertEquals(editing.chars_to_string(right_chars), "hello world")
    lt.assertEquals(right_caret, 6)
end

function suite:test_insert_text_lines_preserves_tail()
    local lines = editing.parse_lines("ab\ncd")
    local new_lines, cl, cc = editing.insert_text_lines(lines, 1, 1, "X\nY")
    lt.assertEquals(editing.serialize_lines(new_lines), "aX\nYb\ncd")
    lt.assertEquals(cl, 2)
    lt.assertEquals(cc, 1)
end

function suite:test_delete_word_forward_lines()
    local lines = editing.parse_lines("hello brave world")
    local new_lines, cl, cc = editing.delete_word_forward_lines(lines, 1, 6)
    lt.assertEquals(editing.serialize_lines(new_lines), "hello world")
    lt.assertEquals(cl, 1)
    lt.assertEquals(cc, 6)
end

function suite:test_replace_selection_single_line()
    local chars = editing.to_chars("abcd")
    local new_chars, new_caret = editing.replace_selection(chars, 1, 3, "X")
    lt.assertEquals(editing.chars_to_string(new_chars), "aXd")
    lt.assertEquals(new_caret, 2)
end

function suite:test_delete_selection_lines_across_rows()
    local lines = editing.parse_lines("ab\ncd\nef")
    local new_lines, cl, cc = editing.delete_selection_lines(
        lines,
        { line = 1, col = 1 },
        { line = 3, col = 1 }
    )
    lt.assertEquals(editing.serialize_lines(new_lines), "af")
    lt.assertEquals(cl, 1)
    lt.assertEquals(cc, 1)
end

function suite:test_selection_text_helpers()
    local chars = editing.to_chars("abcd")
    lt.assertEquals(editing.selection_text(chars, 1, 3), "bc")

    local lines = editing.parse_lines("ab\ncd\nef")
    lt.assertEquals(
        editing.selection_text_lines(lines, { line = 1, col = 1 }, { line = 3, col = 1 }),
        "b\ncd\ne"
    )
end

function suite:test_selection_spans_and_ranges()
    local chars = editing.to_chars("abcd")
    local spans = editing.selection_spans(chars, 1, 3)
    lt.assertEquals(spans[1], "a")
    lt.assertEquals(spans[2].text, "bc")
    lt.assertEquals(spans[2].inverse, true)
    lt.assertEquals(spans[3], "d")

    local start_col, end_col = editing.selection_range_for_line(
        { line = 1, col = 1 },
        { line = 3, col = 1 },
        2,
        2
    )
    lt.assertEquals(start_col, 0)
    lt.assertEquals(end_col, 2)
end

function suite:test_list_and_position_helpers()
    local list = { "a", "b" }
    local appended = editing.append_item(list, "c")
    local dropped = editing.drop_last(appended)

    lt.assertEquals(#list, 2)
    lt.assertEquals(#appended, 3)
    lt.assertEquals(appended[3], "c")
    lt.assertEquals(#dropped, 2)
    lt.assertEquals(dropped[2], "b")

    lt.assertTrue(editing.same_position({ line = 1, col = 2 }, { line = 1, col = 2 }))
    lt.assertFalse(editing.same_position({ line = 1, col = 2 }, { line = 1, col = 3 }))
    lt.assertTrue(editing.same_position(nil, nil))
end

function suite:test_history_helpers_move_snapshots_between_stacks()
    local undo_stack = {}
    local redo_stack = {}
    local restored = nil

    local function set_undo_stack(update)
        undo_stack = type(update) == "function" and update(undo_stack) or update
    end

    local function set_redo_stack(update)
        redo_stack = type(update) == "function" and update(redo_stack) or update
    end

    editing.push_history_snapshot(set_undo_stack, set_redo_stack, { value = "one" })
    lt.assertEquals(#undo_stack, 1)
    lt.assertEquals(undo_stack[1].value, "one")
    lt.assertEquals(#redo_stack, 0)

    local snapshot_current = function()
        return { value = "current" }
    end
    local restore_snapshot = function(snapshot)
        restored = snapshot.value
    end

    lt.assertTrue(editing.restore_undo(undo_stack, set_undo_stack, set_redo_stack, snapshot_current, restore_snapshot))
    lt.assertEquals(restored, "one")
    lt.assertEquals(#undo_stack, 0)
    lt.assertEquals(#redo_stack, 1)
    lt.assertEquals(redo_stack[1].value, "current")

    lt.assertTrue(editing.restore_redo(redo_stack, set_undo_stack, set_redo_stack, snapshot_current, restore_snapshot))
    lt.assertEquals(restored, "current")
    lt.assertEquals(#undo_stack, 1)
    lt.assertEquals(undo_stack[1].value, "current")
    lt.assertEquals(#redo_stack, 0)
end

function suite:test_history_coalescing_helpers()
    local undo_stack = {}
    local redo_stack = { "stale" }
    local history_group = nil
    local state = { redo_stack = redo_stack, history_group = history_group }

    local function set_undo_stack(update)
        undo_stack = type(update) == "function" and update(undo_stack) or update
    end

    local function set_redo_stack(update)
        redo_stack = type(update) == "function" and update(redo_stack) or update
        state.redo_stack = redo_stack
    end

    local function set_history_group(value)
        history_group = value
        state.history_group = value
    end

    editing.record_history_edit(
        set_undo_stack,
        set_redo_stack,
        set_history_group,
        state,
        { value = "" },
        editing.make_history_edit("insert", 0, 1)
    )
    lt.assertEquals(#undo_stack, 1)
    lt.assertEquals(#redo_stack, 0)
    lt.assertEquals(history_group.kind, "insert")

    editing.record_history_edit(
        set_undo_stack,
        set_redo_stack,
        set_history_group,
        state,
        { value = "a" },
        editing.make_history_edit("insert", 1, 2)
    )
    lt.assertEquals(#undo_stack, 1)

    editing.record_history_edit(
        set_undo_stack,
        set_redo_stack,
        set_history_group,
        state,
        { value = "ab" },
        editing.make_history_edit("delete_backward", 2, 1)
    )
    lt.assertEquals(#undo_stack, 2)

    editing.clear_history_group(set_history_group, state)
    lt.assertNil(history_group)
    lt.assertNil(state.history_group)
end

function suite:test_shared_editor_input_handles_composing_and_clipboard_shortcuts()
    local composing = ""
    local copied = nil
    local inserted = nil
    local replaced = nil
    local deleted = false
    local cleared = false

    local state = {
        name = "composing",
        shortcut = nil,
        input = "ni",
        composing = composing,
        set_composing = function(value) composing = value end,
        clear_selection = function() cleared = true; return true end,
        replace_selection = function(text) replaced = text; return false end,
        insert_text = function(text) inserted = text end,
        selection_text = function() return "abc" end,
        delete_selection = function() deleted = true end,
        clipboard = { write = function(text) copied = text end },
        undo_stack = {},
        redo_stack = {},
        set_undo_stack = function() end,
        set_redo_stack = function() end,
        snapshot_current = function() return {} end,
        restore_snapshot = function() end,
    }

    lt.assertTrue(editing.handle_shared_editor_input(state))
    lt.assertEquals(composing, "ni")

    state.name = "composing_confirm"
    state.input = "你"
    lt.assertTrue(editing.handle_shared_editor_input(state))
    lt.assertEquals(replaced, "你")
    lt.assertEquals(inserted, "你")
    lt.assertEquals(composing, "")

    state.name = nil
    state.shortcut = "copy"
    lt.assertTrue(editing.handle_shared_editor_input(state))
    lt.assertEquals(copied, "abc")

    state.shortcut = "cut"
    lt.assertTrue(editing.handle_shared_editor_input(state))
    lt.assertEquals(copied, "abc")
    lt.assertTrue(deleted)

    state.shortcut = nil
    state.name = "escape"
    lt.assertTrue(editing.handle_shared_editor_input(state))
    lt.assertTrue(cleared)
end

function suite:test_clear_composing_on_blur()
    local composing = "abc"
    local set_calls = 0
    local state = {
        composing = composing,
        set_composing = function(value)
            composing = value
            set_calls = set_calls + 1
        end,
    }

    lt.assertFalse(editing.clear_composing_on_blur(state, true))
    lt.assertEquals(composing, "abc")
    lt.assertEquals(set_calls, 0)

    lt.assertTrue(editing.clear_composing_on_blur(state, false))
    lt.assertEquals(composing, "")
    lt.assertEquals(set_calls, 1)
end

function suite:test_feature_resolution_and_history_sync()
    local features = editing.resolve_features({})
    lt.assertTrue(features.undo_redo)
    lt.assertTrue(features.copy_cut)
    lt.assertTrue(features.select_all)
    lt.assertTrue(features.word_ops)
    lt.assertTrue(features.kill_ops)
    lt.assertTrue(features.ime_composing)
    lt.assertTrue(features.paste)
    lt.assertTrue(features.submit)
    lt.assertTrue(features.selection)

    features = editing.resolve_features({ features = { undoRedo = false } })
    lt.assertFalse(features.undo_redo)

    features = editing.resolve_features({
        features = {
            copyCut = false,
            selectAll = false,
            wordOps = false,
            killOps = false,
            imeComposing = false,
            paste = false,
            submit = false,
            selection = false,
        },
    })
    lt.assertFalse(features.copy_cut)
    lt.assertFalse(features.select_all)
    lt.assertFalse(features.word_ops)
    lt.assertFalse(features.kill_ops)
    lt.assertFalse(features.ime_composing)
    lt.assertFalse(features.paste)
    lt.assertFalse(features.submit)
    lt.assertFalse(features.selection)

    local undo_stack = { 1 }
    local redo_stack = { 2 }
    local state = { undo_stack = undo_stack, redo_stack = redo_stack }
    local function set_undo_stack(update)
        undo_stack = type(update) == "function" and update(undo_stack) or update
    end
    local function set_redo_stack(update)
        redo_stack = type(update) == "function" and update(redo_stack) or update
    end

    lt.assertTrue(editing.sync_history_feature(false, set_undo_stack, set_redo_stack, state))
    lt.assertEquals(#undo_stack, 0)
    lt.assertEquals(#redo_stack, 0)
    lt.assertEquals(#state.undo_stack, 0)
    lt.assertEquals(#state.redo_stack, 0)
end

function suite:test_keymap_resolution_and_action_lookup()
    local keymap = editing.resolve_keymap({
        keymap = {
            ["ctrl+s"] = "submit",
            ["enter"] = false,
            redo = { "ctrl+r" },
            ["ctrl+b"] = "moveLeft",
        },
    }, editing.default_text_input_keymap())

    lt.assertEquals(editing.resolve_key_action(key_event("char", "s", true), keymap), "submit")
    lt.assertNil(editing.resolve_key_action(key_event("enter", "\r"), keymap))
    lt.assertEquals(editing.resolve_key_action(key_event("char", "r", true), keymap), "redo")
    lt.assertNil(editing.resolve_key_action(key_event("char", "y", true), keymap))
    lt.assertEquals(editing.resolve_key_action(key_event("char", "b", true), keymap), "move_left")
    lt.assertEquals(editing.resolve_key_action(key_event("left"), editing.default_text_input_keymap()), "move_left")
    lt.assertEquals(editing.resolve_key_action(key_event("home", "", true), editing.default_textarea_keymap("submit")), "doc_start")
    lt.assertEquals(editing.common_shortcut(key_event("char", "z", true)), "undo")
    lt.assertEquals(editing.common_shortcut(key_event("char", "c", true, true)), "copy")
end
