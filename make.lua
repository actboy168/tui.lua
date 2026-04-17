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
    msvc = {
        flags = { "/wd4819" },
    },
}

-- Lua DLL #1: yoga binding
lm:lua_dll "yoga" {
    sources  = "src/yoga/luayoga.c",
    deps     = "yoga_core",
    includes = "3rd/yoga",
}

-- Lua DLL #2: tui_core (Stage 1: terminal only; wcwidth/keys will be added later)
lm:lua_dll "tui_core" {
    sources = {
        "src/tui_core/tui_core.c",
        "src/tui_core/terminal.c",
    },
    windows = {
        links = { "imm32" },
    },
}

lm:default { "yoga", "tui_core" }
