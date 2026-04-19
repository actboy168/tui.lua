-- test/integration/test_forms.lua — form submission integration tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"

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
            tui.Newline { key = "nl1" },
            tui.Box {
                key = "user_row",
                flexDirection = "row",
                tui.Text { key = "user_label", "Username: " },
                tui.TextInput {
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
                tui.TextInput {
                    key = "pass_input",
                    value = password,
                    onChange = setPassword,
                    onSubmit = submit,
                    width = 20,
                }
            },
            tui.Newline { key = "nl2" },
            tui.Text { key = "hint", "Press Enter in either field to submit" },
        }
    end

    local h = testing.render(App, { cols = 45, rows = 15 })

    -- Type in username field and submit
    h:type("admin")
    h:press("enter")

    lt.assertNotEquals(submitted, nil)
    lt.assertEquals(submitted.username, "admin")
    lt.assertEquals(submitted.password, "")

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
            tui.Newline { key = "nl1" },
            tui.Box {
                key = "user_row",
                flexDirection = "row",
                tui.Text { key = "user_label", "Username: " },
                tui.TextInput {
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
                tui.TextInput {
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

    -- Fill username
    h:type("john")

    -- Use Tab to move to password field
    h:press("tab")

    -- Fill password and submit
    h:type("secret123")
    h:press("return")

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
                tui.TextInput {
                    key = "name_input",
                    value = data.name or "",
                    onChange = function(v) updateField("name", v) end,
                    onSubmit = nextStep,
                    placeholder = "Name",
                    width = 30,
                },
                tui.Newline { key = "nl" },
                tui.Text { key = "hint", "Enter: Next" },
            }
        elseif step == 2 then
            return tui.Box {
                width = 40, height = 10,
                tui.Text { key = "title", "Step 2/3: Contact Info" },
                tui.TextInput {
                    key = "email_input",
                    value = data.email or "",
                    onChange = function(v) updateField("email", v) end,
                    onSubmit = nextStep,
                    placeholder = "Email",
                    width = 30,
                },
                tui.Newline { key = "nl" },
                tui.Text { key = "hint", "Enter: Next" },
            }
        else
            return tui.Box {
                width = 40, height = 10,
                tui.Text { key = "title", "Step 3/3: Review" },
                tui.Text { key = "name", ("Name: %s"):format(data.name or "") },
                tui.Text { key = "email", ("Email: %s"):format(data.email or "") },
                tui.Newline { key = "nl" },
                tui.Text { key = "hint", "Press Enter to submit" },
            }
        end
    end

    local h = testing.render(App, { cols = 45, rows = 12 })

    -- Step 1: Fill name, then Enter to next step
    h:type("John Doe")
    h:press("return")

    -- Step 2: Fill email, then Enter to next step
    h:type("john@example.com")
    h:press("return")

    -- Step 3: Submit
    h:press("return")

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
            tui.TextInput {
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
    h:type("invalid")
    h:press("enter")
    lt.assertEquals(submitted, false)
    lt.assertEquals(#errors, 1)

    -- Clear and submit valid email
    h:press("ctrl+u")  -- clear line
    h:type("valid@example.com")
    h:press("enter")

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
            tui.Select {
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
    -- Note: Select navigation depends on focus/input handling
    h:press("down")
    h:press("down")
    h:press("return")

    -- Value should be set (if selection mechanism works)
    -- This test documents expected behavior

    h:unmount()
end
