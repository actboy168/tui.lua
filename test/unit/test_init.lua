-- test/unit/test_init.lua — unit tests for tui/init.lua core functionality

local lt  = require "ltest"
local tui = require "tui"

local suite = lt.test "init"

-- ============================================================================
-- Component factory tests
-- ============================================================================

function suite:test_component_factory_mode()
    local MyComponent = tui.component(function(props)
        return tui.Text { props.title or "Untitled" }
    end)

    local element = MyComponent { title = "Hello" }

    lt.assertEquals(element.kind, "component")
    lt.assertEquals(element.props.title, "Hello")
    lt.assertEquals(type(element.fn), "function")
end

function suite:test_component_direct_mode()
    local fn = function(props)
        return tui.Text { props.text or "" }
    end

    local element = tui.component(fn, { text = "Direct" })

    lt.assertEquals(element.kind, "component")
    lt.assertEquals(element.props.text, "Direct")
end

function suite:test_component_with_key()
    local MyComponent = tui.component(function(props)
        return tui.Text { "Test" }
    end)

    local element = MyComponent { key = "my-key", id = 123 }

    lt.assertEquals(element.key, "my-key")
    lt.assertEquals(element.props.key, nil)  -- key should be plucked out
    lt.assertEquals(element.props.id, 123)
end

-- ============================================================================
-- Host element tests
-- ============================================================================

function suite:test_box_element_structure()
    local box = tui.Box {
        width = 10, height = 5,
        borderStyle = "single",
        tui.Text { "Child" }
    }

    lt.assertEquals(box.kind, "box")
    lt.assertEquals(box.props.width, 10)
    lt.assertEquals(box.props.height, 5)
    lt.assertEquals(box.props.borderStyle, "single")
    lt.assertEquals(#box.children, 1)
    lt.assertEquals(box.children[1].kind, "text")
end

function suite:test_text_element_structure()
    local text = tui.Text {
        color = "red",
        "Hello ", "World"
    }

    lt.assertEquals(text.kind, "text")
    lt.assertEquals(text.props.color, "red")
    lt.assertEquals(text.text, "Hello World")
end

function suite:test_error_boundary_element_structure()
    local fallback = tui.Text { "Error!" }
    local boundary = tui.ErrorBoundary {
        fallback = fallback,
        tui.Text { "Content" }
    }

    lt.assertEquals(boundary.kind, "error_boundary")
    lt.assertEquals(boundary.fallback, fallback)
    lt.assertEquals(#boundary.children, 1)
end

function suite:test_error_boundary_with_function_fallback()
    local fn = function(err) return tui.Text { err } end
    local boundary = tui.ErrorBoundary {
        fallback = fn,
        tui.Text { "Content" }
    }

    lt.assertEquals(boundary.kind, "error_boundary")
    lt.assertEquals(type(boundary.fallback), "function")
end

function suite:test_error_boundary_invalid_fallback()
    lt.assertError(function()
        tui.ErrorBoundary {
            fallback = 123,  -- invalid fallback type
            tui.Text { "Content" }
        }
    end)
end

-- ============================================================================
-- Dev mode tests
-- ============================================================================

function suite:test_dev_mode_default()
    -- Dev mode should be false by default
    lt.assertEquals(tui._dev_mode, false)
end

function suite:test_dev_mode_toggle()
    local original = tui._dev_mode

    tui.setDevMode(true)
    lt.assertEquals(tui._dev_mode, true)

    tui.setDevMode(false)
    lt.assertEquals(tui._dev_mode, false)

    -- Restore original
    tui.setDevMode(original)
end

-- ============================================================================
-- Hook exports tests
-- ============================================================================

function suite:test_hooks_exported()
    -- Verify all expected hooks are exported
    lt.assertEquals(type(tui.useState), "function")
    lt.assertEquals(type(tui.useEffect), "function")
    lt.assertEquals(type(tui.useMemo), "function")
    lt.assertEquals(type(tui.useCallback), "function")
    lt.assertEquals(type(tui.useRef), "function")
    lt.assertEquals(type(tui.useLatestRef), "function")
    lt.assertEquals(type(tui.useReducer), "function")
    lt.assertEquals(type(tui.useContext), "function")
    lt.assertEquals(type(tui.createContext), "function")
    lt.assertEquals(type(tui.useInterval), "function")
    lt.assertEquals(type(tui.useTimeout), "function")
    lt.assertEquals(type(tui.useAnimation), "function")
    lt.assertEquals(type(tui.useInput), "function")
    lt.assertEquals(type(tui.useWindowSize), "function")
    lt.assertEquals(type(tui.useApp), "function")
    lt.assertEquals(type(tui.useStdout), "function")
    lt.assertEquals(type(tui.useStderr), "function")
    lt.assertEquals(type(tui.useFocus), "function")
    lt.assertEquals(type(tui.useFocusManager), "function")
    lt.assertEquals(type(tui.useDeclaredCursor), "function")
    lt.assertEquals(type(tui.useErrorBoundary), "function")
    lt.assertEquals(type(tui.log), "function")
end

-- ============================================================================
-- Scheduler passthrough tests
-- ============================================================================

function suite:test_scheduler_exports()
    lt.assertEquals(type(tui.setInterval), "function")
    lt.assertEquals(type(tui.setTimeout), "function")
    lt.assertEquals(type(tui.clearTimer), "function")
end

-- ============================================================================
-- Layout utility tests
-- ============================================================================

function suite:test_intrinsic_size_exported()
    lt.assertEquals(type(tui.intrinsicSize), "function")
end
