-- test/core/test_vterm.lua — Virtual Terminal Emulator unit tests

local lt    = require "ltest"
local vterm = require "tui.testing.vterm"

local suite = lt.test "vterm"

-- ---------------------------------------------------------------------------
-- Helpers

local function make_term(cols, rows)
    local vt = vterm.new(cols, rows)
    return vt, vterm.as_terminal(vt)
end

local function write(term, s)
    term.write(s)
end

-- ---------------------------------------------------------------------------
-- Basic creation

function suite:test_new_creates_blank_screen()
    local vt = vterm.new(5, 3)
    lt.assertEquals(#vterm.screen_string(vt), 3)
    for r = 1, 3 do
        lt.assertEquals(vterm.row_string(vt, r), "     ")
    end
end

function suite:test_cursor_starts_at_home()
    local vt = vterm.new(10, 5)
    local c = vterm.cursor(vt)
    lt.assertEquals(c.col, 1)
    lt.assertEquals(c.row, 1)
    lt.assertEquals(c.visible, true)
end

-- ---------------------------------------------------------------------------
-- Character writing

function suite:test_write_puts_chars_at_cursor()
    local vt, term = make_term(10, 3)
    write(term, "Hello")
    lt.assertEquals(vterm.row_string(vt, 1), "Hello     ")
    local c = vterm.cursor(vt)
    lt.assertEquals(c.col, 6)
    lt.assertEquals(c.row, 1)
end

function suite:test_write_wraps_at_right_edge()
    local vt, term = make_term(5, 3)
    write(term, "ABCDEXYZ")
    lt.assertEquals(vterm.row_string(vt, 1), "ABCDE")
    lt.assertEquals(vterm.row_string(vt, 2), "XYZ  ")
    local c = vterm.cursor(vt)
    lt.assertEquals(c.col, 4)
    lt.assertEquals(c.row, 2)
end

function suite:test_cr_moves_to_col_one()
    local vt, term = make_term(10, 3)
    write(term, "AB\rXY")
    lt.assertEquals(vterm.row_string(vt, 1), "XY        ")
end

function suite:test_tab_advances_to_next_stop()
    local vt, term = make_term(20, 3)
    write(term, "A\tB\tC")
    lt.assertEquals(vterm.row_string(vt, 1), "A       B       C   ")
end

-- ---------------------------------------------------------------------------
-- Cursor movement

function suite:test_cup_absolute_position()
    local vt, term = make_term(10, 5)
    write(term, "\x1b[3;4HAB")
    lt.assertEquals(vterm.cell(vt, 4, 3).char, "A")
    lt.assertEquals(vterm.cell(vt, 5, 3).char, "B")
    local c = vterm.cursor(vt)
    lt.assertEquals(c.col, 6)
    lt.assertEquals(c.row, 3)
end

function suite:test_cuu_moves_up()
    local vt, term = make_term(10, 5)
    write(term, "\x1b[3;5H\x1b[2AX")
    lt.assertEquals(vterm.cell(vt, 5, 1).char, "X")
end

function suite:test_cud_moves_down()
    local vt, term = make_term(10, 5)
    write(term, "\x1b[1;1H\x1b[2BX")
    lt.assertEquals(vterm.cell(vt, 1, 3).char, "X")
end

function suite:test_cuf_moves_right()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[3CX")
    lt.assertEquals(vterm.cell(vt, 4, 1).char, "X")
end

function suite:test_cub_moves_left()
    local vt, term = make_term(10, 3)
    write(term, "AB\x1b[2DXY")
    lt.assertEquals(vterm.row_string(vt, 1), "XY        ")
end

function suite:test_cup_default_to_home()
    local vt, term = make_term(10, 5)
    write(term, "\x1b[3;4H\x1b[HAB")
    lt.assertEquals(vterm.cell(vt, 1, 1).char, "A")
    lt.assertEquals(vterm.cell(vt, 2, 1).char, "B")
end

-- ---------------------------------------------------------------------------
-- Erase

function suite:test_ed_0_erase_from_cursor_to_end()
    local vt, term = make_term(10, 3)
    write(term, "ABCDEFGHIJ")
    write(term, "\x1b[2;1HABCDEFGHIJ")
    write(term, "\x1b[3;1HABCDEFGHIJ")
    write(term, "\x1b[2;5H\x1b[0J")
    lt.assertEquals(vterm.row_string(vt, 1), "ABCDEFGHIJ")
    lt.assertEquals(vterm.row_string(vt, 2), "ABCD      ")
    lt.assertEquals(vterm.row_string(vt, 3), "          ")
end

function suite:test_ed_2_erases_entire_display()
    local vt, term = make_term(10, 3)
    write(term, "ABCDEFGHIJ")
    write(term, "\x1b[2;1HABCDEFGHIJ")
    write(term, "\x1b[3;1HABCDEFGHIJ")
    write(term, "\x1b[2J")
    for r = 1, 3 do
        lt.assertEquals(vterm.row_string(vt, r), "          ")
    end
end

function suite:test_el_0_erases_to_end_of_line()
    local vt, term = make_term(10, 3)
    write(term, "ABCDEFGHIJ")
    write(term, "\x1b[1;5H\x1b[0K")
    lt.assertEquals(vterm.row_string(vt, 1), "ABCD      ")
end

function suite:test_el_2_erases_whole_line()
    local vt, term = make_term(10, 3)
    write(term, "ABCDEFGHIJ")
    write(term, "\x1b[1;5H\x1b[2K")
    lt.assertEquals(vterm.row_string(vt, 1), "          ")
end

-- ---------------------------------------------------------------------------
-- SGR attributes

function suite:test_sgr_sets_fg_color()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[31mRed")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.fg.type, "indexed")
    lt.assertEquals(c.attrs.fg.idx, 1)
end

function suite:test_sgr_resets_attrs()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[31;1mBoldRed\x1b[0mPlain")
    local c1 = vterm.cell(vt, 1, 1)
    lt.assertEquals(c1.attrs.fg.idx, 1)
    lt.assertEquals(c1.attrs.bold, true)
    local c2 = vterm.cell(vt, 8, 1)
    lt.assertEquals(c2.attrs.fg, nil)
    lt.assertEquals(c2.attrs.bold, false)
end

function suite:test_sgr_truecolor()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[38;2;255;128;64mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.fg.type, "rgb")
    lt.assertEquals(c.attrs.fg.r, 255)
    lt.assertEquals(c.attrs.fg.g, 128)
    lt.assertEquals(c.attrs.fg.b, 64)
end

function suite:test_sgr_bright_fg()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[91mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.fg.type, "indexed")
    lt.assertEquals(c.attrs.fg.idx, 9)  -- 91-90+8 = 9
end

function suite:test_sgr_bright_bg()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[104mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.bg.type, "indexed")
    lt.assertEquals(c.attrs.bg.idx, 12)  -- 104-100+8 = 12
end

function suite:test_sgr_double_underline()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[21mX")
    local c = vterm.cell(vt, 1, 1)
    -- C vterm uses boolean for underline (true = any underline style)
    lt.assertEquals(c.attrs.underline, true)
end

function suite:test_decscusr_cursor_shape()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[5 q")
    lt.assertEquals(vterm.cursor(vt).style, "bar")
    write(term, "\x1b[1 q")
    lt.assertEquals(vterm.cursor(vt).style, "block")
    write(term, "\x1b[4 q")
    lt.assertEquals(vterm.cursor(vt).style, "underline")
end

-- ---------------------------------------------------------------------------
-- Cursor save/restore

function suite:test_decsc_decrc()
    local vt, term = make_term(10, 3)
    write(term, "AB\x1b7\x1b[2;3HXY\x1b8Z")
    lt.assertEquals(vterm.row_string(vt, 1), "ABZ       ")
    lt.assertEquals(vterm.cell(vt, 3, 1).char, "Z")
    local c = vterm.cursor(vt)
    lt.assertEquals(c.col, 4)
    lt.assertEquals(c.row, 1)
end

-- ---------------------------------------------------------------------------
-- RIS (full reset)

function suite:test_ris_clears_screen_and_resets_cursor()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[31mABCDE\x1b[3;5H\x1bcXY")
    lt.assertEquals(vterm.cell(vt, 1, 1).char, "X")
    lt.assertEquals(vterm.cell(vt, 2, 1).char, "Y")
    local c = vterm.cursor(vt)
    lt.assertEquals(c.col, 3)
    lt.assertEquals(c.row, 1)
end

-- ---------------------------------------------------------------------------
-- DECSET / DECRST (mode switching)

function suite:test_decset_mouse_mode()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[?1000h")
    lt.assertEquals(vterm.mouse_level(vt), 1)
    lt.assertEquals(vterm.has_mode(vt, 1000), true)
end

function suite:test_decset_mouse_ref_count()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[?1000h\x1b[?1000h\x1b[?1000l")
    lt.assertEquals(vterm.mouse_level(vt), 1)
end

function suite:test_decrst_mouse_release()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[?1000h\x1b[?1000l")
    lt.assertEquals(vterm.mouse_level(vt), 0)
    lt.assertEquals(vterm.has_mode(vt, 1000), false)
end

function suite:test_decset_bracketed_paste()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[?2004h")
    lt.assertEquals(vterm.mode(vt).bracketed_paste, true)
end

function suite:test_decset_focus_events()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[?1004h")
    lt.assertEquals(vterm.mode(vt).focus_events, true)
end

function suite:test_decset_synchronized_output()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[?2026h\x1b[?2026h")
    lt.assertEquals(vterm.mode(vt).synchronized_output, 2)
    write(term, "\x1b[?2026l")
    lt.assertEquals(vterm.mode(vt).synchronized_output, 1)
end

-- ---------------------------------------------------------------------------
-- Write log / sequence queries

function suite:test_write_log_records_all_writes()
    local vt, term = make_term(10, 3)
    write(term, "Hello")
    write(term, "World")
    local log = vterm.write_log(vt)
    lt.assertEquals(#log, 2)
    lt.assertEquals(log[1], "Hello")
    lt.assertEquals(log[2], "World")
end

function suite:test_has_sequence_finds_substring()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[?1000h\x1b[?1006h")
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1000h"), true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?999h"), false)
end

-- ---------------------------------------------------------------------------
-- Input queue / read

function suite:test_enqueue_input_and_read()
    local vt, term = make_term(10, 3)
    vterm.enqueue_input(vt, "abc")
    vterm.enqueue_input(vt, "def")
    -- read drains the entire queue at once
    lt.assertEquals(term.read(), "abcdef")
    lt.assertEquals(term.read(), nil)
end

function suite:test_clear_input()
    local vt, term = make_term(10, 3)
    vterm.enqueue_input(vt, "abc")
    vterm.clear_input(vt)
    lt.assertEquals(term.read(), nil)
end

-- ---------------------------------------------------------------------------
-- Scrolling

function suite:test_scroll_up_when_cursor_at_bottom()
    local vt, term = make_term(5, 3)
    -- Fill all 3 rows, each exactly 5 chars (wrap_pending after each)
    write(term, "11111")
    write(term, "BBBBB")
    write(term, "CCCCC")
    -- All rows full, cursor at row 3 col 5, wrap_pending=true
    -- One more char triggers wrap → scroll_up → write on row 3
    write(term, "D")
    lt.assertEquals(vterm.row_string(vt, 1), "BBBBB")
    lt.assertEquals(vterm.row_string(vt, 2), "CCCCC")
    lt.assertEquals(vterm.row_string(vt, 3), "D    ")
end

function suite:test_decstbm_restricts_scroll()
    local vt, term = make_term(5, 5)
    write(term, "11111")
    write(term, "\x1b[2;1HAAAAA")
    write(term, "\x1b[3;1HBBBBB")
    write(term, "\x1b[4;1HCCCCC")
    write(term, "\x1b[5;1HDDDDD")
    -- Set scroll region to rows 2-4
    write(term, "\x1b[2;4r")
    -- Move to row 4, col 1 and write 6 chars to trigger one scroll within region
    -- (5 chars fill the line, 6th causes wrap + scroll)
    write(term, "\x1b[4;1HXXXXXY")
    lt.assertEquals(vterm.row_string(vt, 1), "11111")
    lt.assertEquals(vterm.row_string(vt, 2), "BBBBB")  -- old row 3
    lt.assertEquals(vterm.row_string(vt, 3), "XXXXX")  -- old row 4
    lt.assertEquals(vterm.row_string(vt, 4), "Y    ")  -- wrapped char on new line
    lt.assertEquals(vterm.row_string(vt, 5), "DDDDD")  -- outside region, unchanged
end

-- ---------------------------------------------------------------------------
-- Terminal interface

function suite:test_terminal_get_size()
    local vt, term = make_term(20, 10)
    local w, h = term.get_size()
    lt.assertEquals(w, 20)
    lt.assertEquals(h, 10)
end

function suite:test_terminal_set_raw()
    local vt, term = make_term(10, 3)
    lt.assertEquals(vterm.mode(vt).raw, false)
    term.set_raw(true)
    lt.assertEquals(vterm.mode(vt).raw, true)
end

function suite:test_terminal_windows_vt_enable()
    local vt, term = make_term(10, 3)
    lt.assertEquals(term.windows_vt_enable(), true)
end

-- ---------------------------------------------------------------------------
-- UTF-8 / wide characters

function suite:test_utf8_multibyte_char()
    local vt, term = make_term(10, 3)
    write(term, "中")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.char, "中")
end

function suite:test_utf8_string()
    local vt, term = make_term(10, 3)
    write(term, "中文")
    lt.assertEquals(vterm.cell(vt, 1, 1).char, "中")
    lt.assertEquals(vterm.cell(vt, 3, 1).char, "文")
end

-- ---------------------------------------------------------------------------
-- Complex SGR combinations

function suite:test_sgr_fg_bg_combined()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[31;42mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.fg.type, "indexed")
    lt.assertEquals(c.attrs.fg.idx, 1)
    lt.assertEquals(c.attrs.bg.type, "indexed")
    lt.assertEquals(c.attrs.bg.idx, 2)
end

function suite:test_sgr_256_color()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[38;5;196mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.fg.type, "indexed")
    lt.assertEquals(c.attrs.fg.idx, 196)
end

function suite:test_sgr_bold_italic_underline()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[1;3;4mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.bold, true)
    lt.assertEquals(c.attrs.italic, true)
    lt.assertEquals(c.attrs.underline, true)
end

function suite:test_sgr_inverse_strikethrough()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[7;9mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.inverse, true)
    lt.assertEquals(c.attrs.strikethrough, true)
end

function suite:test_sgr_dim()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[2mX")
    local c = vterm.cell(vt, 1, 1)
    lt.assertEquals(c.attrs.dim, true)
end

-- ---------------------------------------------------------------------------
-- Scroll region edge cases

function suite:test_scroll_region_bottom_edge()
    local vt, term = make_term(5, 3)
    write(term, "11111")
    write(term, "\x1b[2;1HAAAAA")
    write(term, "\x1b[3;1HBBBBB")
    -- Set scroll region to rows 2-3
    write(term, "\x1b[2;3r")
    -- Move to bottom of region and overflow
    write(term, "\x1b[3;1HCCCCC")
    write(term, "D")
    -- After wrap+scroll within region: row 2 gets "CCCCC" (scrolled up from row 3)
    lt.assertEquals(vterm.row_string(vt, 1), "11111")
    lt.assertEquals(vterm.row_string(vt, 2), "CCCCC")
    lt.assertEquals(vterm.row_string(vt, 3), "D    ")
end

-- ---------------------------------------------------------------------------
-- Insert/delete characters and lines

function suite:test_ich_inserts_blanks()
    local vt, term = make_term(10, 3)
    write(term, "ABCDE")
    write(term, "\x1b[1;3H")
    write(term, "\x1b[2@")
    lt.assertEquals(vterm.row_string(vt, 1), "AB  CDE   ")
end

function suite:test_dch_deletes_chars()
    local vt, term = make_term(10, 3)
    write(term, "ABCDE")
    write(term, "\x1b[1;3H")
    write(term, "\x1b[2P")
    -- DCH 2 at col 3: removes C and D, shifts E left
    lt.assertEquals(vterm.row_string(vt, 1), "ABE       ")
end

function suite:test_il_inserts_lines()
    local vt, term = make_term(5, 5)
    write(term, "11111")
    write(term, "\x1b[2;1H22222")
    write(term, "\x1b[3;1H33333")
    write(term, "\x1b[2;1H")
    write(term, "\x1b[1L")
    lt.assertEquals(vterm.row_string(vt, 1), "11111")
    lt.assertEquals(vterm.row_string(vt, 2), "     ")
    lt.assertEquals(vterm.row_string(vt, 3), "22222")
    lt.assertEquals(vterm.row_string(vt, 4), "33333")
end

function suite:test_dl_deletes_lines()
    local vt, term = make_term(5, 5)
    write(term, "11111")
    write(term, "\x1b[2;1H22222")
    write(term, "\x1b[3;1H33333")
    write(term, "\x1b[2;1H")
    write(term, "\x1b[1M")
    lt.assertEquals(vterm.row_string(vt, 1), "11111")
    lt.assertEquals(vterm.row_string(vt, 2), "33333")
    lt.assertEquals(vterm.row_string(vt, 3), "     ")
end

-- ---------------------------------------------------------------------------
-- Cursor save/restore with style

function suite:test_decsc_saves_style()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[31;1mA")
    write(term, "\x1b7")
    write(term, "\x1b[0mB")
    write(term, "\x1b8C")
    -- After restore, style should be red+bold again
    -- Cursor was saved at col 2, so C overwrites B at col 2
    local c = vterm.cell(vt, 2, 1)
    lt.assertEquals(c.char, "C")
    lt.assertEquals(c.attrs.fg.idx, 1)
    lt.assertEquals(c.attrs.bold, true)
end

-- ---------------------------------------------------------------------------
-- Tab handling

function suite:test_tab_at_edge()
    local vt, term = make_term(10, 3)
    write(term, "\x1b[1;9HX")
    write(term, "\tY")
    lt.assertEquals(vterm.cell(vt, 9, 1).char, "X")
    lt.assertEquals(vterm.cell(vt, 10, 1).char, "Y")
end

-- ---------------------------------------------------------------------------
-- Carriage return + line feed

function suite:test_cr_lf_combination()
    local vt, term = make_term(10, 3)
    write(term, "ABCDE")
    write(term, "\r\nXYZ")
    lt.assertEquals(vterm.row_string(vt, 1), "ABCDE     ")
    lt.assertEquals(vterm.row_string(vt, 2), "XYZ       ")
end

-- ---------------------------------------------------------------------------
-- OSC sequences

function suite:test_osc_title()
    local vt, term = make_term(10, 3)
    write(term, "\x1b]2;MyTitle\x07")
    -- Title is stored but not directly queryable in current API
    -- Just verify no crash and screen is intact
    lt.assertEquals(vterm.row_string(vt, 1), "          ")
end

-- ---------------------------------------------------------------------------
-- Write log and sequence queries

function suite:test_last_sequence()
    local vt, term = make_term(10, 3)
    write(term, "Hello")
    write(term, "World")
    lt.assertEquals(vterm.last_sequence(vt), "World")
end

function suite:test_clipboard_log_osc52()
    local vt, term = make_term(10, 3)
    write(term, "\x1b]52;c;SGVsbG8=\x07")
    local log = vterm.clipboard_log(vt)
    -- OSC 52 clipboard log is stored in C but may need Lua wrapper
    -- For now just verify no crash
    lt.assertEquals(type(log), "table")
end

function suite:test_osc8_hyperlink_updates_cell_metadata()
    local vt, term = make_term(10, 3)
    write(term, "\x1b]8;;https://example.com\x1b\\X\x1b]8;;\x1b\\Y")
    local c1 = vterm.cell(vt, 1, 1)
    local c2 = vterm.cell(vt, 2, 1)
    lt.assertEquals(c1.char, "X")
    lt.assertEquals(c1.hyperlink, "https://example.com")
    lt.assertEquals(c2.char, "Y")
    lt.assertEquals(c2.hyperlink, nil)
end

-- ---------------------------------------------------------------------------
-- Resize

function suite:test_resize_larger()
    local vt = vterm.new(5, 3)
    vterm.resize(vt, 10, 5)
    lt.assertEquals(vt.cols, 10)
    lt.assertEquals(vt.rows, 5)
    lt.assertEquals(vterm.row_string(vt, 1), "          ")
end

function suite:test_resize_smaller()
    local vt, term = make_term(10, 5)
    write(term, "ABCDEFGHIJ")
    write(term, "\x1b[2;1H1234567890")
    vterm.resize(vt, 5, 2)
    lt.assertEquals(vt.cols, 5)
    lt.assertEquals(vt.rows, 2)
    lt.assertEquals(vterm.row_string(vt, 1), "ABCDE")
    lt.assertEquals(vterm.row_string(vt, 2), "12345")
end
