-- test_kojump.lua
-- Unit tests for the KOReader kojump plugin.
-- Run with: lua tests/test_kojump.lua

package.path = "./?.lua;" .. package.path

-- 1. Mock KOReader components
local mock_dispatcher = {
    registered_actions = {}
}
function mock_dispatcher:registerAction(name, config)
    self.registered_actions[name] = config
end

local mock_infomessage = {
    new = function(self, tbl)
        return tbl
    end
}

local mock_uimanager = {
    shown = {}
}
function mock_uimanager:show(widget)
    table.insert(self.shown, widget)
end

local mock_widgetcontainer = {
    extend = function(self, tbl)
        tbl.super = self
        function tbl:new(o)
            o = o or {}
            setmetatable(o, { __index = self })
            return o
        end
        return tbl
    end
}

package.preload["dispatcher"] = function() return mock_dispatcher end
package.preload["ui/event"] = function()
    return {
        new = function(self, name, page)
            return { name = name, page = page }
        end
    }
end
package.preload["ui/widget/infomessage"] = function() return mock_infomessage end
package.preload["ui/uimanager"] = function() return mock_uimanager end
package.preload["ui/widget/container/widgetcontainer"] = function() return mock_widgetcontainer end
package.preload["gettext"] = function()
    return function(str) return str end
end

-- 2. Load the Kojump plugin class
local Kojump = require("main")

-- 3. Assertion helper
local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED:\n  Expected: %s\n  Actual:   %s\n  Context:  %s", tostring(expected), tostring(actual), tostring(msg)))
    end
end

local function print_success(test_name)
    print(string.format("[PASS] %s", test_name))
end

-- 4. Test Suite Execution
local function run_tests()
    print("Running Kojump tests...")

    -- Test 1: Initialization
    do
        local menu_registered = false
        local mock_ui = {
            menu = {
                registerToMainMenu = function(self, plugin)
                    menu_registered = true
                end
            }
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        assert_eq(menu_registered, true, "Should register to main menu")
        assert_eq(#plugin.history, 0, "History should start empty")
        assert_eq(plugin.history_idx, 0, "History index should start at 0")
        print_success("Initialization")
    end

    -- Test 2: Initial Page Update
    do
        local mock_ui = {
            menu = { registerToMainMenu = function() end }
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        plugin:onPageUpdate(5)
        assert_eq(#plugin.history, 1, "First page update should initialize history list")
        assert_eq(plugin.history[1], 5, "First page should be recorded in history")
        assert_eq(plugin.history_idx, 1, "Index should point to first element")
        assert_eq(plugin.current_page, 5, "Current page should be set to 5")
        print_success("Initial Page Update")
    end

    -- Test 3: Normal Page Turns (No Jump)
    do
        local mock_ui = {
            menu = { registerToMainMenu = function() end }
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(6)  -- page turn +1
        plugin:onPageUpdate(7)  -- page turn +1
        plugin:onPageUpdate(6)  -- page turn -1

        assert_eq(#plugin.history, 1, "Normal page turns should not create new history entries")
        assert_eq(plugin.history_idx, 1, "History index should remain 1")
        assert_eq(plugin.current_page, 6, "Current page should update to 6")
        print_success("Normal Page Turns (No Jump)")
    end

    -- Test 4: Jump Page Actions
    do
        local mock_ui = {
            menu = { registerToMainMenu = function() end }
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(50) -- Jump of 45 pages

        assert_eq(#plugin.history, 2, "A jump should append to history")
        assert_eq(plugin.history[2], 50, "New page should be recorded in history")
        assert_eq(plugin.history_idx, 2, "Index should move to 2")
        assert_eq(plugin.current_page, 50, "Current page is now 50")

        plugin:onPageUpdate(100) -- Jump of 50 pages
        assert_eq(#plugin.history, 3, "Another jump should append to history")
        assert_eq(plugin.history[3], 100, "New page should be recorded")
        assert_eq(plugin.history_idx, 3, "Index should move to 3")
        print_success("Jump Page Actions")
    end

    -- Test 5: Back and Forward Navigation
    do
        local handle_event_called = nil
        local mock_ui = {
            menu = { registerToMainMenu = function() end },
            handleEvent = function(self, ev)
                handle_event_called = ev
            end
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(50)
        plugin:onPageUpdate(100)

        assert_eq(plugin:canGoBack(), true, "Should be able to go back")
        assert_eq(plugin:canGoForward(), false, "Should not be able to go forward at end of history")

        -- Go Back
        plugin:goBack()
        assert_eq(plugin.history_idx, 2, "Index should decrement")
        assert_eq(plugin.is_navigating, true, "Should set is_navigating state to true")
        assert_eq(handle_event_called.name, "GotoPage", "Should send GotoPage event")
        assert_eq(handle_event_called.page, 50, "Should target page 50")

        -- Simulate the page update callback triggered by GotoPage
        plugin:onPageUpdate(50)
        assert_eq(plugin.is_navigating, false, "is_navigating should reset after page update")
        assert_eq(plugin.current_page, 50, "Current page should be 50")
        assert_eq(#plugin.history, 3, "History should remain intact")

        -- Go Back Again
        plugin:goBack()
        assert_eq(plugin.history_idx, 1, "Index should decrement again")
        plugin:onPageUpdate(5)
        assert_eq(plugin.current_page, 5, "Current page should be 5")
        assert_eq(plugin:canGoBack(), false, "Should not be able to go back further")
        assert_eq(plugin:canGoForward(), true, "Should now be able to go forward")

        -- Go Forward
        plugin:goForward()
        assert_eq(plugin.history_idx, 2, "Index should increment")
        plugin:onPageUpdate(50)
        assert_eq(plugin.current_page, 50, "Current page should be 50")
        print_success("Back and Forward Navigation")
    end

    -- Test 6: Branching/Truncating Forward History
    do
        local mock_ui = {
            menu = { registerToMainMenu = function() end },
            handleEvent = function() end
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(50)
        plugin:onPageUpdate(100) -- History: { 5, 50, 100 }, idx: 3

        plugin:goBack()
        plugin:onPageUpdate(50)  -- History: { 5, 50, 100 }, idx: 2

        -- Jump to new page 200 from page 50
        plugin:onPageUpdate(200)

        assert_eq(#plugin.history, 3, "History size should remain 3")
        assert_eq(plugin.history[1], 5, "Index 1 should be 5")
        assert_eq(plugin.history[2], 50, "Index 2 should be 50")
        assert_eq(plugin.history[3], 200, "Index 3 should be replaced with 200 (100 is truncated)")
        assert_eq(plugin.history_idx, 3, "Index should point to 3")
        print_success("Branching/Truncating Forward History")
    end

    -- Test 7: Capacity Limit (Max 20)
    do
        local mock_ui = {
            menu = { registerToMainMenu = function() end }
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        plugin:onPageUpdate(1)
        for i = 2, 25 do
            plugin:onPageUpdate(i * 10) -- jumps of 10 pages
        end

        assert_eq(#plugin.history, 20, "History capacity should be capped at 20")
        assert_eq(plugin.history_idx, 20, "Index should be 20")
        assert_eq(plugin.history[1], 60, "The first recorded page should be shifted (6 * 10 = 60)")
        assert_eq(plugin.history[20], 250, "The last recorded page should be 250")
        print_success("Capacity Limit (Max 20)")
    end

    -- Test 8: Settings Load & Save Persistence
    do
        local doc_settings_saved = false
        local doc_settings = {
            data = {},
            save = function(self)
                doc_settings_saved = true
            end
        }
        local mock_ui = {
            menu = { registerToMainMenu = function() end }
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        -- Trigger Load
        plugin:onDocSettingsLoad(doc_settings)
        assert_eq(#plugin.history, 0, "Initial loaded history should be empty")

        -- Perform a jump
        plugin:onPageUpdate(5)
        plugin:onPageUpdate(50)

        assert_eq(doc_settings_saved, true, "DocSettings:save() should have been called")
        assert_eq(doc_settings.data.kojump.history_idx, 2, "Saved index should be 2")
        assert_eq(doc_settings.data.kojump.history[2], 50, "Saved history[2] should be 50")

        -- Test loading existing settings
        local other_plugin = Kojump:new{ ui = mock_ui }
        other_plugin:init()
        other_plugin:onDocSettingsLoad(doc_settings)

        assert_eq(#other_plugin.history, 2, "Loaded history should contain 2 entries")
        assert_eq(other_plugin.history_idx, 2, "Loaded index should be 2")
        print_success("Settings Load & Save Persistence")
    end

    print("\nAll tests passed successfully!")
end

run_tests()
