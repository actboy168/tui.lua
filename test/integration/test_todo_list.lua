-- test/integration/test_todo_list.lua — todo list flow integration tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local tui_input = require "tui.input"
local tui_input = require "tui.input"
local extra   = require "tui.extra"

local suite = lt.test "todo_list"

-- ============================================================================
-- Self-contained todo app (no examples/ file dependency)
-- ============================================================================

local function TodoApp()
    local todos, setTodos = tui.useState({})
    local input, setInput = tui.useState("")

    local function addTodo()
        if #input > 0 then
            local new = {}
            for i, t in ipairs(todos) do new[i] = t end
            new[#new + 1] = { text = input, done = false }
            setTodos(new)
            setInput("")
        end
    end

    return tui.Box {
        flexDirection = "column",
        width = 40, height = 15,
        tui.Text { key = "title", bold = true, "Todos" },
        extra.Newline { key = "nl1" },
        extra.TextInput {
            key = "inp",
            value = input,
            onChange = setInput,
            onSubmit = addTodo,
            placeholder = "Add task...",
            width = 30,
        },
        extra.Newline { key = "nl2" },
        #todos == 0
            and tui.Text { key = "empty", dim = true, "No tasks" }
            or nil,
        extra.Static {
            key = "list",
            items = todos,
            render = function(todo, i)
                return tui.Text {
                    key = tostring(i),
                    (todo.done and "[x] " or "[ ] ") .. todo.text
                }
            end
        },
    }
end

-- ============================================================================
-- Initial state
-- ============================================================================

function suite:test_initial_empty_state()
    local h = testing.render(TodoApp, { cols = 45, rows = 17 })

    -- "No tasks" placeholder visible
    lt.assertNotEquals(h:frame():find("No tasks"), nil)
    -- Placeholder text in input field
    lt.assertNotEquals(h:frame():find("Add task%.%.%."), nil)

    h:unmount()
end

-- ============================================================================
-- Add a single task
-- ============================================================================

function suite:test_add_single_task()
    local h = testing.render(TodoApp, { cols = 45, rows = 17 })

    tui_input.type("Buy milk")
    h:rerender()
    tui_input.press("enter")
    h:rerender()

    local frame = h:frame()
    lt.assertNotEquals(frame:find("Buy milk"), nil)
    lt.assertNotEquals(frame:find("%[ %]"), nil)    -- unchecked marker

    -- "No tasks" should be gone
    lt.assertEquals(frame:find("No tasks"), nil)

    h:unmount()
end

-- ============================================================================
-- Add multiple tasks and verify order
-- ============================================================================

function suite:test_add_multiple_tasks()
    local h = testing.render(TodoApp, { cols = 45, rows = 17 })

    tui_input.type("Task one")
    h:rerender()
    tui_input.press("enter")
    h:rerender()

    tui_input.type("Task two")
    h:rerender()
    tui_input.press("enter")
    h:rerender()

    tui_input.type("Task three")
    h:rerender()
    tui_input.press("enter")
    h:rerender()

    -- All three tasks appear in the tree
    local text = table.concat(testing.text_content(h:tree()), "\n")
    lt.assertNotEquals(text:find("Task one"), nil)
    lt.assertNotEquals(text:find("Task two"), nil)
    lt.assertNotEquals(text:find("Task three"), nil)

    h:unmount()
end

-- ============================================================================
-- Input clears after submit
-- ============================================================================

function suite:test_input_clears_after_submit()
    local h = testing.render(TodoApp, { cols = 45, rows = 17 })

    tui_input.type("Do something")
    h:rerender()
    tui_input.press("enter")
    h:rerender()

    -- The task was added to the list
    lt.assertNotEquals(h:frame():find("Do something"), nil)

    -- The input row (row 3: title=1, newline=2, input=3) must be cleared.
    -- It should not still contain the submitted text.
    local input_row = h:row(3)
    lt.assertEquals(input_row:find("Do something"), nil,
        "input row should be cleared after submit")

    h:unmount()
end

-- ============================================================================
-- Empty input does not add task
-- ============================================================================

function suite:test_empty_submit_noop()
    local h = testing.render(TodoApp, { cols = 45, rows = 17 })

    tui_input.press("enter")  -- submit with empty input

    lt.assertNotEquals(h:frame():find("No tasks"), nil)

    h:unmount()
end

-- ============================================================================
-- Snapshot
-- ============================================================================

function suite:test_snapshot_with_tasks()
    local h = testing.render(TodoApp, { cols = 45, rows = 17 })

    tui_input.type("First task")
    h:rerender()
    tui_input.press("enter")
    h:rerender()
    tui_input.type("Second task")
    h:rerender()
    tui_input.press("enter")
    h:rerender()

    h:match_snapshot("todo_two_tasks_45x17")
    h:unmount()
end
