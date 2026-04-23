local lm = require "luamake"

lm:conf {
    c = "c11",
    cxx = "c++17",
    rtti = "off",
    crt = "static",
}

-- Yoga C++ core (as source_set; linked into the yoga lua_dll)
lm:source_set "yoga_core" {
    cxx = "c++20",
    rtti = "off",
    rootdir = "3rd/yoga",
    sources = {
        "yoga/*.cpp",
        "yoga/algorithm/*.cpp",
        "yoga/config/*.cpp",
        "yoga/debug/*.cpp",
        "yoga/event/*.cpp",
        "yoga/node/*.cpp",
    },
    includes = ".",
    linux = {
        flags = { "-fPIC" },
    },
    msvc = {
        flags = { "/wd4819" },
    },
}

lm:lua_src "tui" {
    sources  = "src/tui_yoga.c",
    deps     = "yoga_core",
    includes = "3rd/yoga",
}

lm:lua_dll "tui" {
    sources = {
        "src/*.c",
        "!src/tui_yoga.c",
    },
    windows = {
        links = { "ntdll" },
        export_luaopen = "off",
        ldflags = {
            "-export:luaopen_tui_core",
        },
    },
}

lm:default { "tui" }
