-- examples/select_menu.lua - 选项列表示例
-- 运行: luamake lua examples/select_menu.lua
-- 按键: ↑↓ 移动, Enter 选择, Esc 退出

local tui = require "tui"

local function MenuApp()
    local items = {
        { label = "新建项目", value = "new" },
        { label = "打开文件", value = "open" },
        { label = "保存", value = "save" },
        { label = "设置", value = "settings" },
        { label = "退出", value = "quit" },
    }
    local selected, setSelected] = tui.useState(nil)
    local app = tui.useApp()

    tui.useInput(function(_, key)
        if key.name == "escape" then
            app:exit()
        end
    end)

    if selected then
        return tui.Box {
            flexDirection = "column",
            padding = 2,
            tui.Text { bold = true, "已选择" },
            tui.Newline {},
            tui.Text { ("选项: %s"):format(selected.label) },
            tui.Text { ("值: %s"):format(selected.value) },
            tui.Newline {},
            tui.Text { dim = true, "按 Esc 退出" }
        }
    end

    return tui.Box {
        flexDirection = "column",
        padding = 2,

        tui.Text { bold = true, "主菜单" },
        tui.Newline {},

        tui.Select {
            items = items,
            onSelect = function(item)
                setSelected(item)
            end
        },

        tui.Newline {},
        tui.Text { dim = true, "↑↓ 移动  Enter 选择  Esc 退出" }
    }
end

tui.render(MenuApp)
