#if !defined(_WIN32) && !defined(__APPLE__)
#    ifndef _POSIX_C_SOURCE
#        define _POSIX_C_SOURCE 199309L
#    endif
#endif

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>

#if defined(_WIN32)
#    define WIN32_LEAN_AND_MEAN
#    include <Windows.h>
#elif defined(__APPLE__)
#    include <mach/mach_time.h>
#    include <errno.h>
#    include <time.h>
#else
#    include <errno.h>
#    include <time.h>
#endif

/* ---- Windows ------------------------------------------------------------- */
#if defined(_WIN32)

#    ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#        define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x2
#    endif

LONG NTAPI NtSetTimerResolution(ULONG RequestedResolution, BOOLEAN Set, PULONG ActualResolution);

static int64_t g_qpc_freq        = 0;
static int     g_support_hrtimer = 0;

static void hrtimer_start(void) {
    if (!g_support_hrtimer) {
        ULONG actual = 0;
        NtSetTimerResolution(10000, TRUE, &actual);
    }
}

static void hrtimer_end(void) {
    if (!g_support_hrtimer) {
        ULONG actual = 0;
        NtSetTimerResolution(10000, FALSE, &actual);
    }
}

static int64_t time_now_10mhz(void) {
    LARGE_INTEGER li;
    QueryPerformanceCounter(&li);
    return (int64_t)li.QuadPart / 10000LL;
}

static int64_t time_now_qpc(void) {
    LARGE_INTEGER li;
    QueryPerformanceCounter(&li);
    int64_t now   = (int64_t)li.QuadPart;
    int64_t freq  = g_qpc_freq;
    int64_t whole = (now / freq) * 1000LL;
    int64_t part  = (now % freq) * 1000LL / freq;
    return whole + part;
}

static void time_sleep(int msec) {
    if (msec < 0) return;
    HANDLE timer = CreateWaitableTimerExW(NULL, NULL,
        g_support_hrtimer ? CREATE_WAITABLE_TIMER_HIGH_RESOLUTION : 0, TIMER_ALL_ACCESS);
    if (!timer) return;
    hrtimer_start();
    LARGE_INTEGER due;
    due.QuadPart = -(msec * 10000LL);
    if (SetWaitableTimer(timer, &due, 0, NULL, NULL, 0))
        WaitForSingleObject(timer, INFINITE);
    CloseHandle(timer);
    hrtimer_end();
}

/* ---- macOS --------------------------------------------------------------- */
#elif defined(__APPLE__)

static mach_timebase_info_data_t g_timebase;
static uint64_t                  g_macos_fast_freq = 0;

static int64_t time_now_macos_fast(void) {
    return (int64_t)(mach_continuous_time() / g_macos_fast_freq);
}

static int64_t time_now_macos(void) {
    uint64_t now   = mach_continuous_time();
    uint64_t freq  = (uint64_t)1000000LL * g_timebase.denom;
    uint64_t whole = (now / freq) * g_timebase.numer;
    uint64_t part  = (now % freq) * g_timebase.numer / freq;
    return (int64_t)(whole + part);
}

static void time_sleep(int msec) {
    struct timespec ts;
    int rc;
    ts.tv_sec  = msec / 1000;
    ts.tv_nsec = (msec % 1000) * 1000000;
    do
        rc = nanosleep(&ts, &ts);
    while (rc == -1 && errno == EINTR);
}

/* ---- Linux --------------------------------------------------------------- */
#else

static int64_t time_now_posix(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static void time_sleep(int msec) {
    struct timespec ts;
    int rc;
    ts.tv_sec  = msec / 1000;
    ts.tv_nsec = (msec % 1000) * 1000000;
    do
        rc = nanosleep(&ts, &ts);
    while (rc == -1 && errno == EINTR);
}

#endif

/* ---- function pointer selected at init ----------------------------------- */

static int64_t (*g_time_now)(void) = NULL;

static void time_init(void) {
#if defined(_WIN32)
    LARGE_INTEGER li;
    QueryPerformanceFrequency(&li);
    g_qpc_freq   = (int64_t)li.QuadPart;
    g_time_now = (g_qpc_freq == 10000000LL) ? time_now_10mhz : time_now_qpc;

    HANDLE probe = CreateWaitableTimerExW(NULL, NULL,
        CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    if (probe) {
        g_support_hrtimer = 1;
        CloseHandle(probe);
    }
#elif defined(__APPLE__)
    mach_timebase_info(&g_timebase);
    if ((g_timebase.numer == 125 && g_timebase.denom == 3) ||
        (g_timebase.numer == 1   && g_timebase.denom == 1)) {
        g_macos_fast_freq = (uint64_t)1000000LL * g_timebase.denom / g_timebase.numer;
        g_time_now      = time_now_macos_fast;
    } else {
        g_time_now = time_now_macos;
    }
#else
    g_time_now = time_now_posix;
#endif
}

/* ---- Lua bindings -------------------------------------------------------- */

static int l_now(lua_State *L) {
    lua_pushinteger(L, (lua_Integer)g_time_now());
    return 1;
}

static int l_sleep(lua_State *L) {
    lua_Integer ms = luaL_checkinteger(L, 1);
    time_sleep((int)ms);
    return 0;
}

/* ---- Module opener ------------------------------------------------------- */

int tui_open_time(lua_State *L) {
    time_init();
    static const luaL_Reg lib[] = {
        { "now",   l_now   },
        { "sleep", l_sleep },
        { NULL,    NULL    },
    };
    luaL_newlibtable(L, lib);
    luaL_setfuncs(L, lib, 0);
    return 1;
}