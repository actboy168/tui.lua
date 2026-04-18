#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

#if defined(_WIN32)
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  include <imm.h>
#  pragma comment(lib, "imm32.lib")

/* ── 输出 ─────────────────────────────────────────────────────── */

static int
lwindows_vt_enable(lua_State *L) {
    SetConsoleOutputCP(65001);
    SetConsoleCP(65001);
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hout == INVALID_HANDLE_VALUE) { lua_pushboolean(L, 0); return 1; }
    DWORD mode = 0;
    if (!GetConsoleMode(hout, &mode)) { lua_pushboolean(L, 1); return 1; }
    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN;
    SetConsoleMode(hout, mode);
    lua_pushboolean(L, 1);
    return 1;
}

static int
lwrite(lua_State *L) {
    size_t len;
    const char *s = luaL_checklstring(L, 1, &len);
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hout == INVALID_HANDLE_VALUE || len == 0) return 0;
    DWORD written;
    WriteFile(hout, s, (DWORD)len, &written, NULL);
    return 0;
}

static int
lget_size(lua_State *L) {
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (hout == INVALID_HANDLE_VALUE || !GetConsoleScreenBufferInfo(hout, &csbi)) {
        lua_pushinteger(L, 80); lua_pushinteger(L, 24); return 2;
    }
    lua_pushinteger(L, csbi.srWindow.Right  - csbi.srWindow.Left + 1);
    lua_pushinteger(L, csbi.srWindow.Bottom - csbi.srWindow.Top  + 1);
    return 2;
}

/* ── UTF-16 → UTF-8 ───────────────────────────────────────────── */

static int
utf16_to_utf8(WCHAR high, WCHAR low, int use_surrogate, char *out) {
    DWORD cp;
    if (use_surrogate)
        cp = 0x10000 + ((DWORD)(high - 0xD800) << 10) + (low - 0xDC00);
    else
        cp = (DWORD)high;
    if (cp < 0x80)    { out[0]=(char)cp; return 1; }
    if (cp < 0x800)   { out[0]=(char)(0xC0|(cp>>6));  out[1]=(char)(0x80|(cp&0x3F)); return 2; }
    if (cp < 0x10000) { out[0]=(char)(0xE0|(cp>>12)); out[1]=(char)(0x80|((cp>>6)&0x3F));
                        out[2]=(char)(0x80|(cp&0x3F)); return 3; }
    out[0]=(char)(0xF0|(cp>>18)); out[1]=(char)(0x80|((cp>>12)&0x3F));
    out[2]=(char)(0x80|((cp>>6)&0x3F)); out[3]=(char)(0x80|(cp&0x3F)); return 4;
}

/* ── raw mode ─────────────────────────────────────────────────── */

static DWORD s_orig_in_mode  = 0;
static DWORD s_orig_out_mode = 0;
static int   s_raw_saved     = 0;
static HIMC  s_orig_imc      = NULL;

static int
lset_raw(lua_State *L) {
    int enable = lua_toboolean(L, 1);
    HANDLE hin  = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hin == INVALID_HANDLE_VALUE || hout == INVALID_HANDLE_VALUE) return 0;

    if (enable) {
        if (!s_raw_saved) {
            GetConsoleMode(hin,  &s_orig_in_mode);
            GetConsoleMode(hout, &s_orig_out_mode);
            s_raw_saved = 1;
        }
        DWORD raw_in = s_orig_in_mode
            & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT);
        raw_in |= ENABLE_WINDOW_INPUT;
        SetConsoleMode(hin, raw_in);

        HWND hwnd = GetConsoleWindow();
        if (hwnd && !s_orig_imc)
            s_orig_imc = ImmAssociateContext(hwnd, NULL);
    } else {
        if (s_raw_saved) {
            SetConsoleMode(hin,  s_orig_in_mode);
            SetConsoleMode(hout, s_orig_out_mode);
            s_raw_saved = 0;
        }
        HWND hwnd = GetConsoleWindow();
        if (hwnd && s_orig_imc) {
            ImmAssociateContext(hwnd, s_orig_imc);
            s_orig_imc = NULL;
        }
    }
    return 0;
}

/* ── lread_raw：非阻塞，ReadConsoleInputW + 正确 IME 过滤 ─────── */
/*
 * 规则（参考 Windows 文本控件行为）：
 *   1. 只处理 bKeyDown == TRUE 的事件，忽略 key-up。
 *   2. vk == VK_PROCESSKEY (0xE5)：IME 正在处理合成，直接丢弃。
 *      此时 uChar.UnicodeChar 是中间状态字符，不可信。
 *   3. uChar.UnicodeChar != 0：文本输入（含 IME 最终确认的汉字）。
 *      IME 确认后产生的字符事件，vk 通常为 0 或非 0xE5，wch 为目标字符。
 *   4. uChar.UnicodeChar == 0：功能键，通过 vk 映射到 ANSI escape。
 */
static int
lread_raw(lua_State *L) {
    HANDLE hin = GetStdHandle(STD_INPUT_HANDLE);
    if (hin == INVALID_HANDLE_VALUE) return 0;

    DWORD count = 0;
    if (!GetNumberOfConsoleInputEvents(hin, &count) || count == 0)
        return 0;

    INPUT_RECORD recs[64];
    DWORD nread = 0;
    if (!ReadConsoleInputW(hin, recs, 64, &nread) || nread == 0)
        return 0;

    char   buf[512];
    int    len = 0;
    WCHAR  pending_high = 0;

    for (DWORD i = 0; i < nread && len < (int)sizeof(buf) - 8; i++) {
        INPUT_RECORD *r = &recs[i];

        /* 只处理按键按下事件 */
        if (r->EventType != KEY_EVENT || !r->Event.KeyEvent.bKeyDown)
            continue;

        WORD  vk  = r->Event.KeyEvent.wVirtualKeyCode;
        WCHAR wch = r->Event.KeyEvent.uChar.UnicodeChar;

        /* 规则2：VK_PROCESSKEY —— IME 合成中，丢弃 */
        if (vk == VK_PROCESSKEY)
            continue;

        if (wch != 0) {
            /* 规则3：文本输入（普通字符 + IME 确认汉字） */
            if (wch >= 0xD800 && wch <= 0xDBFF) {
                pending_high = wch;
                continue;
            } else if (wch >= 0xDC00 && wch <= 0xDFFF && pending_high) {
                len += utf16_to_utf8(pending_high, wch, 1, buf + len);
                pending_high = 0;
            } else {
                pending_high = 0;
                len += utf16_to_utf8(wch, 0, 0, buf + len);
            }
        } else {
            /* 规则4：功能键，映射到 ANSI escape */
            pending_high = 0;
            switch (vk) {
            case VK_UP:     buf[len++]='\27';buf[len++]='[';buf[len++]='A'; break;
            case VK_DOWN:   buf[len++]='\27';buf[len++]='[';buf[len++]='B'; break;
            case VK_RIGHT:  buf[len++]='\27';buf[len++]='[';buf[len++]='C'; break;
            case VK_LEFT:   buf[len++]='\27';buf[len++]='[';buf[len++]='D'; break;
            case VK_HOME:   buf[len++]='\27';buf[len++]='[';buf[len++]='H'; break;
            case VK_END:    buf[len++]='\27';buf[len++]='[';buf[len++]='F'; break;
            case VK_DELETE: buf[len++]='\27';buf[len++]='[';buf[len++]='3';buf[len++]='~'; break;
            case VK_PRIOR:  buf[len++]='\27';buf[len++]='[';buf[len++]='5';buf[len++]='~'; break;
            case VK_NEXT:   buf[len++]='\27';buf[len++]='[';buf[len++]='6';buf[len++]='~'; break;
            default: break;
            }
        }
    }

    if (len == 0) return 0;
    lua_pushlstring(L, buf, len);
    return 1;
}

/* ── IME 候选框位置 ────────────────────────────────────────────── */

static int
lset_ime_pos(lua_State *L) {
    int col = (int)luaL_checkinteger(L, 1);
    int row = (int)luaL_checkinteger(L, 2);
    HWND hwnd = GetConsoleWindow();
    if (!hwnd) return 0;
    HIMC himc = ImmGetContext(hwnd);
    if (!himc) return 0;
    HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
    COORD font_size = {8, 16};
    if (hout != INVALID_HANDLE_VALUE) {
        CONSOLE_FONT_INFO cfi;
        if (GetCurrentConsoleFont(hout, FALSE, &cfi)) {
            COORD fs = GetConsoleFontSize(hout, cfi.nFont);
            if (fs.X > 0 && fs.Y > 0) font_size = fs;
        }
    }
    int scroll_left = 0, scroll_top = 0;
    if (hout != INVALID_HANDLE_VALUE) {
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (GetConsoleScreenBufferInfo(hout, &csbi)) {
            scroll_left = csbi.srWindow.Left;
            scroll_top  = csbi.srWindow.Top;
        }
    }
    int px = ((col - 1) - scroll_left) * font_size.X;
    int py = ((row - 1) - scroll_top)  * font_size.Y;
    CANDIDATEFORM cf = {0};
    cf.dwStyle        = CFS_CANDIDATEPOS;
    cf.ptCurrentPos.x = px;
    cf.ptCurrentPos.y = py + font_size.Y;
    ImmSetCandidateWindow(himc, &cf);
    COMPOSITIONFORM compf = {0};
    compf.dwStyle        = CFS_POINT;
    compf.ptCurrentPos.x = px;
    compf.ptCurrentPos.y = py;
    ImmSetCompositionWindow(himc, &compf);
    ImmReleaseContext(hwnd, himc);
    return 0;
}

#else /* POSIX */

#include <termios.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <unistd.h>
#include <string.h>

static struct termios s_orig_termios;
static int            s_raw_saved = 0;

static int lwindows_vt_enable(lua_State *L) { (void)L; return 0; }

static int
lset_raw(lua_State *L) {
    int enable = lua_toboolean(L, 1);
    if (enable) {
        struct termios raw;
        if (!s_raw_saved) {
            if (tcgetattr(STDIN_FILENO, &s_orig_termios) < 0)
                return luaL_error(L, "tcgetattr failed");
            s_raw_saved = 1;
        }
        raw = s_orig_termios;
        raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        raw.c_oflag &= ~(OPOST);
        raw.c_cflag |=  (CS8);
        raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
        raw.c_cc[VMIN]  = 0;
        raw.c_cc[VTIME] = 0;
        if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) < 0)
            return luaL_error(L, "tcsetattr failed");
    } else {
        if (s_raw_saved) {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &s_orig_termios);
            s_raw_saved = 0;
        }
    }
    return 0;
}

static int
lget_size(lua_State *L) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) < 0 || ws.ws_col == 0) {
        lua_pushinteger(L, 80); lua_pushinteger(L, 24);
    } else {
        lua_pushinteger(L, (int)ws.ws_col);
        lua_pushinteger(L, (int)ws.ws_row);
    }
    return 2;
}

static int
lread_raw(lua_State *L) {
    fd_set fds; struct timeval tv = {0, 0};
    FD_ZERO(&fds); FD_SET(STDIN_FILENO, &fds);
    if (select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv) <= 0) return 0;
    char buf[64];
    ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
    if (n <= 0) return 0;
    lua_pushlstring(L, buf, (size_t)n);
    return 1;
}

static int
lwrite(lua_State *L) {
    size_t len;
    const char *s = luaL_checklstring(L, 1, &len);
    if (len == 0) return 0;
    write(STDOUT_FILENO, s, len);
    return 0;
}

static int
lset_ime_pos(lua_State *L) {
    /* POSIX: IME positioning is handled entirely by ime.lua via
     * terminal.write() with terminal-specific escape sequences.
     * This stub exists solely to keep the module API consistent
     * across platforms; it is never called in production. */
    (void)L;
    return 0;
}

#endif /* _WIN32 */

LUAMOD_API int
luaopen_terminal(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        { "set_raw",           lset_raw           },
        { "get_size",          lget_size          },
        { "windows_vt_enable", lwindows_vt_enable },
        { "read_raw",          lread_raw          },
        { "write",             lwrite             },
        { "set_ime_pos",       lset_ime_pos       },
        { NULL, NULL },
    };
    luaL_newlib(L, l);
    return 1;
}
