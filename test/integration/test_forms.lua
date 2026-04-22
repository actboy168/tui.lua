-- test/integration/test_forms.lua — form submission integration tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local tui_input = require "tui.input"
local tui_input = require "tui.input"
local extra = require "tui.extra"

local suite = lt.test "forms"

-- ============================================================================
-- Login form submission
-- ============================================================================

function suite:test_login_form_submit()
    local submitted = nil

    local App = function()
        local username, setUsername = tui.useState("")
        local password, setPassword = tui.useState("")

        local function submit()
            submitted = { username = username, password = password }
        end

        return tui.Box {
            flexDirection = "column",
            width = 40, height = 12,
            tui.Text { key = "title", "Login Form" },
            extra.Newline { key = "nl1" },
            tui.Box {
                key = "user_row",
                flexDirection = "row",
                tui.Text { key = "user_label", "Username: " },
                extra.TextInput {
                    key = "user_input",
                    value = username,
                    onChange = setUsername,
                    onSubmit = submit,
                    width = 20,
                }
            },
            tui.Box {
                key = "pass_row",
                flexDirection = "row",
                tui.Text { key = "pass_label", "Password: " },
                extra.TextInput {
                    key = "pass_input",
                    value = password,
                    onChange = setPassword,
                    onSubmit = submit,
                    width = 20,
                }
            },
            extra.Newline { key = "nl2" },
            tui.Text { key = "hint", "Press Enter in either field to submit" },
        }
    end

    local h = testing.render(App, { cols = 45, rows = 15 })

    -- Initial state: focus should be on username field (autoFocus default)
    h:rerender()
    lt.assertNotEquals(h:focus_id(), nil)
    local initial_focus = h:focus_id()

    -- Cursor must be visible (row 1 area, some column)
    local col0, row0 = h:cursor()
    lt.assertNotEquals(col0, nil, "cursor should be set on initial focused TextInput")

    -- Type in username field and submit
    tui_input.type("admin")
    h:rerender()

    -- Cursor advanced by 5 chars
    local col_after, _ = h:cursor()
    lt.assertEquals(col_after, col0 + 5)

    tui_input.press("enter")
    h:rerender()

    lt.assertNotEquals(submitted, nil)
    lt.assertEquals(submitted.username, "admin")
    lt.assertEquals(submitted.password, "")

    -- Focus should not have changed on submit (stays in same field)
    lt.assertEquals(h:focus_id(), initial_focus)

    h:unmount()
end

function suite:test_login_form_full_flow()
    local submitted = nil

    local App = function()
        local username, setUsername = tui.useState("")
        local password, setPassword = tui.useState("")

        local function submit()
            submitted = { username = username, password = password }
        end

        return tui.Box {
            flexDirection = "column",
            width = 40, height = 12,
            tui.Text { key = "title", "Login Form" },
            extra.Newline { key = "nl1" },
            tui.Box {
                key = "user_row",
                flexDirection = "row",
                tui.Text { key = "user_label", "Username: " },
                extra.TextInput {
                    key = "user_input",
                    value = username,
                    onChange = setUsername,
                    width = 20,
                }
            },
            tui.Box {
                key = "pass_row",
                flexDirection = "row",
                tui.Text { key = "pass_label", "Password: " },
                extra.TextInput {
                    key = "pass_input",
                    value = password,
                    onChange = setPassword,
                    onSubmit = submit,
                    width = 20,
                }
            },
        }
    end

    local h = testing.render(App, { cols = 45, rows = 15 })

    -- Focus starts on username
    h:rerender()
    local focus_before_tab = h:focus_id()
    lt.assertNotEquals(focus_before_tab, nil)

    -- Fill username
    tui_input.type("john")
    h:rerender()

    -- Use Tab to move to password field
    tui_input.press("tab")
    h:rerender()

    -- Focus must have moved to a different field
    local focus_after_tab = h:focus_id()
    lt.assertNotEquals(focus_after_tab, focus_before_tab,
        "Tab should move focus to next field")

    -- Cursor row must increase (password field is below username field)
    h:rerender()
    local _, row_pass = h:cursor()
    lt.assertNotEquals(row_pass, nil)
    lt.assertTrue(row_pass >= 1)

    -- Fill password and submit
    tui_input.type("secret123")
    h:rerender()
    tui_input.press("return")
    h:rerender()

    lt.assertNotEquals(submitted, nil)
    lt.assertEquals(submitted.username, "john")
    lt.assertEquals(submitted.password, "secret123")

    h:unmount()
end

-- ============================================================================
-- Multi-step wizard form
-- ============================================================================

function suite:test_wizard_form_navigation()
    local submissions = {}

    local App = function()
        local step, setStep = tui.useState(1)
        local data, setData = tui.useState({})

        local function nextStep()
            if step < 3 then
                setStep(step + 1)
            else
                submissions[#submissions + 1] = data
            end
        end

        local function updateField(key, value)
            local newData = {}
            for k, v in pairs(data) do newData[k] = v end
            newData[key] = value
            setData(newData)
        end

        -- Use useInput in all steps to keep hook count consistent
        tui.useInput(function(_, key)
            if step == 3 and (key.name == "return" or key.name == "enter") then
                nextStep()
            end
        end)

        if step == 1 then
            return tui.Box {
                width = 40, height = 10,
                tui.Text { key = "title", "Step 1/3: Personal Info" },
                extra.TextInput {
                    key = "name_input",
                    value = data.name or "",
                    onChange = function(v) updateField("name", v) end,
                    onSubmit = nextStep,
                    placeholder = "Name",
                    width = 30,
                },
                extra.Newline { key = "nl" },
                tui.Text { key = "hint", "Enter: Next" },
            }
        elseif step == 2 then
            return tui.Box {
                width = 40, height = 10,
                tui.Text { key = "title", "Step 2/3: Contact Info" },
                extra.TextInput {
                    key = "email_input",
                    value = data.email or "",
                    onChange = function(v) updateField("email", v) end,
                    onSubmit = nextStep,
                    placeholder = "Email",
                    width = 30,
                },
                extra.Newline { key = "nl" },
                tui.Text { key = "hint", "Enter: Next" },
            }
        else
            return tui.Box {
                width = 40, height = 10,
                tui.Text { key = "title", "Step 3/3: Review" },
                tui.Text { key = "name", ("Name: %s"):format(data.name or "") },
                tui.Text { key = "email", ("Email: %s"):format(data.email or "") },
                extra.Newline { key = "nl" },
                tui.Text { key = "hint", "Press Enter to submit" },
            }
        end
    end

    local h = testing.render(App, { cols = 45, rows = 12 })

    -- Step 1: Fill name, then Enter to next step
    tui_input.type("John Doe")
    tui_input.press("return")
    h:rerender()

    -- Step 2: Fill email, then Enter to next step
    tui_input.type("john@example.com")
    tui_input.press("return")
    h:rerender()

    -- Step 3: Submit
    tui_input.press("return")
    h:rerender()

    lt.assertEquals(#submissions, 1)
    lt.assertEquals(submissions[1].name, "John Doe")
    lt.assertEquals(submissions[1].email, "john@example.com")

    h:unmount()
end


-- ============================================================================
-- Form validation
-- ============================================================================

function suite:test_form_with_validation()
    local errors = {}
    local submitted = false

    local App = function()
        local email, setEmail = tui.useState("")
        local errorMsg, setError = tui.useState(nil)

        local function submit()
            if not email:match("@") then
                setError("Invalid email")
                errors[#errors + 1] = "Invalid email"
            else
                setError(nil)
                submitted = true
            end
        end

        return tui.Box {
            width = 40, height = 8,
            tui.Text { key = "title", "Email Form" },
            extra.TextInput {
                key = "email_input",
                value = email,
                onChange = setEmail,
                onSubmit = submit,
                width = 30,
            },
            errorMsg and tui.Text { key = "error", color = "red", errorMsg } or nil,
        }
    end

    local h = testing.render(App, { cols = 45, rows = 10 })

    -- Submit invalid email
    tui_input.type("invalid")
    h:rerender()
    tui_input.press("enter")
    h:rerender()
    lt.assertEquals(submitted, false)
    lt.assertEquals(#errors, 1)

    -- Clear and submit valid email
    tui_input.press("ctrl+u")  -- clear line
    h:rerender()
    tui_input.type("valid@example.com")
    h:rerender()
    tui_input.press("enter")
    h:rerender()

    lt.assertEquals(submitted, true)

    h:unmount()
end

-- ============================================================================
-- Form with select dropdown
-- ============================================================================

function suite:test_form_with_select()
    local selectedValue = nil

    local App = function()
        local items = {
            { label = "Option 1", value = "opt1" },
            { label = "Option 2", value = "opt2" },
            { label = "Option 3", value = "opt3" },
        }

        return tui.Box {
            width = 30, height = 10,
            tui.Text { key = "label", "Select an option:" },
            extra.Select {
                key = "select",
                items = items,
                onSelect = function(item)
                    selectedValue = item.value
                end,
            }
        }
    end

    local h = testing.render(App, { cols = 35, rows = 12 })

    -- Select an item
    tui_input.press("down")
    tui_input.press("down")
    tui_input.press("return")
    h:rerender()

    lt.assertEquals(selectedValue, "opt3")

    h:unmount()
end

-- ============================================================================
-- Snapshot — login form initial state
-- ============================================================================

function suite:test_snapshot_login_initial()
    local App = function()
        return tui.Box {
            flexDirection = "column",
            width = 40, height = 12,
            tui.Text { key = "title", "Login Form" },
            extra.Newline { key = "nl1" },
            tui.Box {
                key = "user_row",
                flexDirection = "row",
                tui.Text { key = "user_label", "Username: " },
                extra.TextInput {
                    key = "user_input",
                    value = "",
                    onChange = function() end,
                    width = 20,
                },
            },
            tui.Box {
                key = "pass_row",
                flexDirection = "row",
                tui.Text { key = "pass_label", "Password: " },
                extra.TextInput {
                    key = "pass_input",
                    value = "",
                    onChange = function() end,
                    width = 20,
                },
            },
            extra.Newline { key = "nl2" },
            tui.Text { key = "hint", "Press Enter to submit" },
        }
    end

    local h = testing.render(App, { cols = 45, rows = 15 })
    h:match_snapshot("forms_login_initial_45x15")
    h:unmount()
end
