-- examples/todo_list.lua - 待办事项列表示例
-- 运行: luamake lua examples/todo_list.lua
-- 按键: 输入任务后按 Enter 添加, Esc 退出

local tui = require "tui"

local function TodoApp()
    local todos, setTodos = tui.useState({})
    local input, setInput = tui.useState("")
    local app = tui.useApp()

    local function addTodo()
        if #input > 0 then
            setTodos({ ...todos, { text = input, done = false } })
            setInput("")
        end
    end

    local function toggleTodo(index)
        local newTodos = {}
        for i, todo in ipairs(todos) do
            newTodos[i] = {
                text = todo.text,
                done = i == index and not todo.done or todo.done
            }
        end
        setTodos(newTodos)
    end

    tui.useInput(function(_, key)
        if key.name == "escape" then
            app:exit()
        end
    end)

    return tui.Box {
        flexDirection = "column",
        padding = 2,

        tui.Text { bold = true, "待办事项" },
        tui.Newline {},

        tui.Box {
            flexDirection = "row",
            gap = 1,
            tui.TextInput {
                value = input,
                onChange = setInput,
                onSubmit = addTodo,
                placeholder = "添加新任务...",
                flex = 1
            }
        },

        tui.Newline {},

        #todos == 0 and tui.Text { dim = true, "暂无任务" } or nil,

        tui.Static {
            items = todos,
            render = function(todo, i)
                return tui.Text {
                    todo.done and color = "green" or nil,
                    (todo.done and "[x] " or "[ ] ") .. todo.text
                }
            end
        },

        tui.Newline {},
        tui.Text { dim = true, "Enter 添加  Esc 退出" }
    }
end

tui.render(TodoApp)
