-- test/integration/test_monitoring.lua — real-time monitoring dashboard tests

local lt      = require "ltest"
local testing = require "tui.testing"
local tui     = require "tui"
local extra = require "tui.extra"

local suite = lt.test "monitoring"

-- ============================================================================
-- Dashboard with live metrics
-- ============================================================================

function suite:test_metrics_dashboard()
    local App = function()
        local metrics, setMetrics = tui.useState({
            cpu = 45,
            memory = 60,
            requests = 0,
        })

        -- Simulate metric updates (deterministic for testing)
        tui.useInterval(function()
            setMetrics({
                cpu = 50,
                memory = 55,
                requests = metrics.requests + 1,
            })
        end, 100)

        return tui.Box {
            flexDirection = "column",
            width = 50, height = 15,
            tui.Box {
                key = "header",
                borderStyle = "double",
                tui.Text { "System Metrics" }
            },
            tui.Box {
                key = "metrics_row",
                flexDirection = "row",
                tui.Box {
                    key = "cpu_box",
                    borderStyle = "single",
                    width = 15, height = 5,
                    tui.Text { key = "cpu_label", "CPU" },
                    tui.Text { key = "cpu_value", ("%d%%"):format(metrics.cpu) },
                    extra.ProgressBar {
                        key = "cpu_bar",
                        value = metrics.cpu / 100,
                        width = 12,
                        color = metrics.cpu > 80 and "red" or "green"
                    }
                },
                tui.Box {
                    key = "mem_box",
                    borderStyle = "single",
                    width = 15, height = 5,
                    tui.Text { key = "mem_label", "Memory" },
                    tui.Text { key = "mem_value", ("%d%%"):format(metrics.memory) },
                    extra.ProgressBar {
                        key = "mem_bar",
                        value = metrics.memory / 100,
                        width = 12,
                        color = metrics.memory > 80 and "red" or "cyan"
                    }
                },
                tui.Box {
                    key = "req_box",
                    borderStyle = "single",
                    width = 18, height = 5,
                    tui.Text { key = "req_label", "Requests" },
                    tui.Text { key = "req_value", tostring(metrics.requests) },
                }
            },
        }
    end

    local h = testing.render(App, { cols = 55, rows = 17 })

    -- Initial state snapshot
    h:match_snapshot("metrics_initial_55x17")

    -- Advance time to trigger updates
    h:advance(100)
    h:match_snapshot("metrics_updated_55x17")

    h:advance(200)
    h:match_snapshot("metrics_after_300ms_55x17")

    h:unmount()
end

-- ============================================================================
-- Log stream viewer
-- ============================================================================

function suite:test_log_stream_viewer()
    local App = function()
        local logs, setLogs = tui.useState({})
        local isStreaming, setIsStreaming = tui.useState(true)

        tui.useInterval(function()
            if not isStreaming then return end
            local timestamp = "12:00:00"
            local level = ({"INFO", "WARN", "ERROR"})[(#logs % 3) + 1]
            local message = ("Log entry %d"):format(#logs + 1)

            setLogs(function(old)
                local new = {}
                for i, log in ipairs(old) do
                    if i > 5 then break end  -- Keep only last 5
                    new[i] = log
                end
                table.insert(new, 1, {
                    time = timestamp,
                    level = level,
                    message = message,
                })
                return new
            end)
        end, 50)

        return tui.Box {
            flexDirection = "column",
            width = 60, height = 12,
            tui.Box {
                key = "header",
                borderStyle = "single",
                tui.Text { key = "title", "Log Stream" },
                isStreaming and extra.Spinner {
                    key = "spinner",
                    type = "dots",
                    label = "Live"
                } or tui.Text { key = "paused", "Paused" }
            },
            extra.Static {
                key = "logs",
                items = logs,
                render = function(log)
                    local color = log.level == "ERROR" and "red"
                        or log.level == "WARN" and "yellow"
                        or "white"
                    return tui.Text {
                        color = color,
                        ("[%s] %s: %s"):format(log.time, log.level, log.message)
                    }
                end
            }
        }
    end

    local h = testing.render(App, { cols = 65, rows = 14 })

    -- Let some logs accumulate
    h:advance(50)
    h:advance(50)
    h:advance(50)
    h:match_snapshot("logs_3_entries_65x14")

    h:advance(100)
    h:advance(100)
    h:match_snapshot("logs_more_entries_65x14")

    h:unmount()
end

-- ============================================================================
-- Multi-panel dashboard
-- ============================================================================

function suite:test_multi_panel_dashboard()
    local App = function()
        local size = tui.useWindowSize()
        local activePanel, setActivePanel = tui.useState(1)

        local panels = {
            { title = "Overview", content = "System overview here" },
            { title = "Processes", content = "Running processes list" },
            { title = "Network", content = "Network statistics" },
        }

        tui.useInput(function(input, key)
            if key.name == "tab" then
                setActivePanel((activePanel % #panels) + 1)
            end
        end)

        return tui.Box {
            flexDirection = "row",
            width = size.cols, height = size.rows,
            -- Sidebar
            tui.Box {
                key = "sidebar",
                width = 15,
                borderStyle = "single",
                tui.Text { key = "title", "Panels" },
                extra.Newline { key = "nl" },
                extra.Static {
                    key = "panel_list",
                    items = panels,
                    render = function(p, i)
                        local marker = i == activePanel and "> " or "  "
                        return tui.Text {
                            color = i == activePanel and "cyan" or nil,
                            marker .. p.title
                        }
                    end
                }
            },
            -- Main content
            tui.Box {
                key = "main",
                flexGrow = 1,
                borderStyle = "single",
                tui.Text { key = "title", panels[activePanel].title },
                extra.Newline { key = "nl" },
                tui.Text { key = "content", panels[activePanel].content },
            }
        }
    end

    local h = testing.render(App, { cols = 60, rows = 15 })

    h:match_snapshot("dashboard_panel_1_60x15")

    -- Switch panel with Tab
    h:press("tab")
    h:match_snapshot("dashboard_panel_2_60x15")

    h:press("tab")
    h:match_snapshot("dashboard_panel_3_60x15")

    h:unmount()
end

-- ============================================================================
-- Status indicators
-- ============================================================================

function suite:test_status_indicators()
    local App = function()
        local services, setServices = tui.useState({
            { name = "Database", status = "healthy" },
            { name = "API", status = "healthy" },
            { name = "Cache", status = "degraded" },
            { name = "Queue", status = "down" },
        })

        return tui.Box {
            flexDirection = "column",
            width = 40, height = 10,
            tui.Box {
                key = "header",
                borderStyle = "double",
                tui.Text { "Service Status" }
            },
            extra.Static {
                key = "services",
                items = services,
                render = function(svc)
                    local color = svc.status == "healthy" and "green"
                        or svc.status == "degraded" and "yellow"
                        or "red"
                    local indicator = svc.status == "healthy" and "●"
                        or svc.status == "degraded" and "◐"
                        or "○"
                    return tui.Text {
                        color = color,
                        ("%s %s: %s"):format(indicator, svc.name, svc.status)
                    }
                end
            }
        }
    end

    local h = testing.render(App, { cols = 45, rows = 12 })
    h:match_snapshot("service_status_45x12")
    h:unmount()
end
