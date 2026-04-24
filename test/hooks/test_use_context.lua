-- test/test_use_context.lua — createContext / Provider / useContext.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "use_context"

-- Without any Provider in scope, consumers see ctx._default.
function suite:test_no_provider_returns_default()
    local Ctx = tui.createContext("fallback")
    local captured
    local function Consumer()
        captured = tui.useContext(Ctx)
        return tui.Text { "" }
    end
    local b = testing.bare(Consumer)
    lt.assertEquals(captured, "fallback")
    b:unmount()
end

-- Provider value is visible to nested Consumer.
function suite:test_provider_value_reaches_child()
    local Ctx = tui.createContext("default")
    local captured
    local function Consumer()
        captured = tui.useContext(Ctx)
        return tui.Text { "" }
    end
    local function App()
        return Ctx.Provider { value = "hello", Consumer }
    end
    local b = testing.bare(App)
    lt.assertEquals(captured, "hello")
    b:unmount()
end

-- Nested Providers: innermost wins.
function suite:test_nested_providers_nearest_wins()
    local Ctx = tui.createContext("root")
    local captured
    local function Consumer()
        captured = tui.useContext(Ctx)
        return tui.Text { "" }
    end
    local function App()
        return Ctx.Provider {
            value = "outer",
            Ctx.Provider {
                value = "inner",
                Consumer,
            },
        }
    end
    local b = testing.bare(App)
    lt.assertEquals(captured, "inner")
    b:unmount()
end

-- Two independent contexts don't bleed into each other.
function suite:test_sibling_providers_are_independent()
    local A = tui.createContext("A_default")
    local B = tui.createContext("B_default")
    local got_a, got_b
    local function Consumer()
        got_a = tui.useContext(A)
        got_b = tui.useContext(B)
        return tui.Text { "" }
    end
    local function App()
        return A.Provider {
            value = "a1",
            B.Provider {
                value = "b1",
                Consumer,
            },
        }
    end
    local b = testing.bare(App)
    lt.assertEquals(got_a, "a1")
    lt.assertEquals(got_b, "b1")
    b:unmount()
end

-- Provider value change is observed by consumer on next render.
function suite:test_provider_value_change_triggers_consumer_observation()
    local Ctx = tui.createContext("default")
    local captured
    local function Consumer()
        captured = tui.useContext(Ctx)
        return tui.Text { "" }
    end
    local value = "v1"
    local function App()
        return Ctx.Provider { value = value, Consumer }
    end
    local b = testing.bare(App)
    lt.assertEquals(captured, "v1")
    value = "v2"
    b:rerender()
    lt.assertEquals(captured, "v2")
    b:unmount()
end

-- Missing `value` prop is an error at Provider factory time.
function suite:test_missing_value_prop_is_error()
    local Ctx = tui.createContext("default")
    local ok, err = pcall(function()
        Ctx.Provider { tui.Text { "child" } }
    end)
    lt.assertEquals(ok, false)
    lt.assertEquals(type(err) == "string" and err:find("value") ~= nil, true)
end
