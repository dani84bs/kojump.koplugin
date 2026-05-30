-- spec/kojump_spec.lua
-- Busted test suite for KOReader kojump plugin.
-- Run with: busted spec/kojump_spec.lua

describe("kojump plugin", function()
    local Kojump
    local mock_dispatcher, mock_uimanager

    before_each(function()
        -- Reset package.loaded to reload cleanly
        package.loaded["dispatcher"] = nil
        package.loaded["ui/event"] = nil
        package.loaded["ui/widget/infomessage"] = nil
        package.loaded["ui/widget/menu"] = nil
        package.loaded["ui/uimanager"] = nil
        package.loaded["ui/widget/container/widgetcontainer"] = nil
        package.loaded["gettext"] = nil
        package.loaded["main"] = nil

        -- Setup mock dependencies
        mock_dispatcher = {
            registered_actions = {}
        }
        function mock_dispatcher:registerAction(name, config)
            self.registered_actions[name] = config
        end

        mock_uimanager = {
            shown = {}
        }
        function mock_uimanager:show(widget)
            table.insert(self.shown, widget)
        end

        local mock_infomessage = {
            new = function(self, tbl)
                return tbl
            end
        }

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

        -- Mock requires
        package.preload["dispatcher"] = function() return mock_dispatcher end
        package.preload["ui/event"] = function()
            return {
                new = function(self, name, page)
                    return { name = name, page = page }
                end
            }
        end
        local mock_menu = {
            new = function(self, tbl)
                return tbl
            end
        }

        package.preload["ui/widget/infomessage"] = function() return mock_infomessage end
        package.preload["ui/widget/menu"] = function() return mock_menu end
        package.preload["ui/uimanager"] = function() return mock_uimanager end
        package.preload["ui/widget/container/widgetcontainer"] = function() return mock_widgetcontainer end
        package.preload["gettext"] = function()
            return function(str) return str end
        end

        package.path = "plugins/kojump.koplugin/?.lua;./?.lua;" .. package.path
        Kojump = require("main")
    end)

    it("should initialize with empty history", function()
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

        assert.is_true(menu_registered)
        assert.are.equal(0, #plugin.history)
        assert.are.equal(0, plugin.history_idx)
    end)

    it("should initialize history on first page update", function()
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        plugin:init()

        plugin:onPageUpdate(5)
        assert.are.equal(1, #plugin.history)
        assert.are.equal(5, plugin.history[1])
        assert.are.equal(1, plugin.history_idx)
        assert.are.equal(5, plugin.current_page)
    end)

    it("should ignore normal page turns", function()
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        plugin:init()

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(6)
        plugin:onPageUpdate(7)
        plugin:onPageUpdate(6)

        assert.are.equal(1, #plugin.history)
        assert.are.equal(1, plugin.history_idx)
        assert.are.equal(6, plugin.current_page)
    end)

    it("should record jumps", function()
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        plugin:init()

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(50)

        assert.are.equal(2, #plugin.history)
        assert.are.equal(50, plugin.history[2])
        assert.are.equal(2, plugin.history_idx)

        plugin:onPageUpdate(100)
        assert.are.equal(3, #plugin.history)
        assert.are.equal(100, plugin.history[3])
        assert.are.equal(3, plugin.history_idx)
    end)

    it("should record source page of jump if manually navigated", function()
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        plugin:init()

        plugin:onPageUpdate(5)   -- Start on 5. History: {5}, idx: 1, current_page: 5
        plugin:onPageUpdate(6)   -- Turn. History: {5}, idx: 1, current_page: 6
        plugin:onPageUpdate(7)   -- Turn. History: {5}, idx: 1, current_page: 7
        plugin:onPageUpdate(8)   -- Turn. History: {5}, idx: 1, current_page: 8
        plugin:onPageUpdate(9)   -- Turn. History: {5}, idx: 1, current_page: 9

        plugin:onPageUpdate(50)  -- Jump to 50. History: {5, 9, 50}, idx: 3, current_page: 50

        assert.are.equal(3, #plugin.history)
        assert.are.equal(5, plugin.history[1])
        assert.are.equal(9, plugin.history[2])
        assert.are.equal(50, plugin.history[3])
        assert.are.equal(3, plugin.history_idx)
    end)

    it("should handle back and forward navigation", function()
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

        assert.is_true(plugin:canGoBack())
        assert.is_false(plugin:canGoForward())

        plugin:goBack()
        assert.are.equal(2, plugin.history_idx)
        assert.is_true(plugin.is_navigating)
        assert.are.equal("GotoPage", handle_event_called.name)
        assert.are.equal(50, handle_event_called.page)

        plugin:onPageUpdate(50)
        assert.is_false(plugin.is_navigating)
        assert.are.equal(50, plugin.current_page)
        assert.are.equal(3, #plugin.history)

        plugin:goBack()
        assert.are.equal(1, plugin.history_idx)
        plugin:onPageUpdate(5)
        assert.is_false(plugin:canGoBack())
        assert.is_true(plugin:canGoForward())

        plugin:goForward()
        assert.are.equal(2, plugin.history_idx)
        plugin:onPageUpdate(50)
        assert.are.equal(50, plugin.current_page)
    end)

    it("should branch and truncate forward history on new jump", function()
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end }, handleEvent = function() end } }
        plugin:init()

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(50)
        plugin:onPageUpdate(100)

        plugin:goBack()
        plugin:onPageUpdate(50)

        plugin:onPageUpdate(200)

        assert.are.equal(3, #plugin.history)
        assert.are.equal(5, plugin.history[1])
        assert.are.equal(50, plugin.history[2])
        assert.are.equal(200, plugin.history[3])
        assert.are.equal(3, plugin.history_idx)
    end)

    it("should enforce capacity limit of 20", function()
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        plugin:init()

        plugin:onPageUpdate(1)
        for i = 2, 25 do
            plugin:onPageUpdate(i * 10)
        end

        assert.are.equal(20, #plugin.history)
        assert.are.equal(20, plugin.history_idx)
        assert.are.equal(60, plugin.history[1])
        assert.are.equal(250, plugin.history[20])
    end)

    it("should load and save setting persistence", function()
        local doc_settings_saved = false
        local doc_settings = {
            data = {},
            save = function(self)
                doc_settings_saved = true
            end
        }
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        plugin:init()

        plugin:onDocSettingsLoad(doc_settings)
        assert.are.equal(0, #plugin.history)

        plugin:onPageUpdate(5)
        plugin:onPageUpdate(50)

        assert.is_true(doc_settings_saved)
        assert.are.equal(2, doc_settings.data.kojump.history_idx)
        assert.are.equal(50, doc_settings.data.kojump.history[2])

        local other_plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        other_plugin:init()
        other_plugin:onDocSettingsLoad(doc_settings)

        assert.are.equal(2, #other_plugin.history)
        assert.are.equal(2, other_plugin.history_idx)
    end)

    it("should show an info message if history is empty or contains only current page when showHistory is called", function()
        local plugin = Kojump:new{ ui = { menu = { registerToMainMenu = function() end } } }
        plugin:init()

        plugin:showHistory()

        assert.are.equal(1, #mock_uimanager.shown)
        assert.are.equal("Cannot show history: No history available.", mock_uimanager.shown[1].text)
    end)

    it("should show history menu with correctly formatted items in reverse chronological order", function()
        local handle_event_called = nil
        local mock_ui = {
            menu = { registerToMainMenu = function() end },
            handleEvent = function(self, ev)
                handle_event_called = ev
            end,
            document = {
                getPageCount = function() return 200 end
            },
            toc = {
                getTocTitleByPage = function(self, page_num)
                    if page_num == 30 then
                        return "Introduction"
                    elseif page_num == 40 then
                        return "This is an extremely long chapter title that should be truncated"
                    else
                        return nil
                    end
                end
            }
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        -- Set up some history jumps: 10 -> 20 -> 30 -> 40
        plugin:onPageUpdate(10)
        plugin:onPageUpdate(20)
        plugin:onPageUpdate(30)
        plugin:onPageUpdate(40)

        -- Now let's navigate back to page 30 (history_idx = 3)
        plugin:goBack()
        plugin:onPageUpdate(30)
        assert.are.equal(3, plugin.history_idx)
        assert.are.equal(40, plugin.history[4])

        -- Reset mock_uimanager shown list
        mock_uimanager.shown = {}

        plugin:showHistory()

        -- It should show the menu widget
        assert.are.equal(1, #mock_uimanager.shown)
        local menu = mock_uimanager.shown[1]
        assert.are.equal("Kojump History", menu.title)
        
        -- The items table should be in reverse chronological order:
        -- index 4 (forward): Page 40 (20%) - This is an extremely long chapter title ... -> label should be "→ Page 40 (20%) - This is an extremely long chapter title ..."
        -- index 3 (current): Page 30 (15%) - Introduction -> label should be "• Page 30 (15%) - Introduction (Current)"
        -- index 2 (back): Page 20 (10%) -> label should be "← Page 20 (10%)"
        -- index 1 (back): Page 10 (5%) -> label should be "← Page 10 (5%)"
        local items = menu.item_table
        assert.are.equal(4, #items)

        assert.are.equal("→ Page 40 (20%) - This is an extremely long chapter title ...", items[1].text)
        assert.are.equal("• Page 30 (15%) - Introduction (Current)", items[2].text)
        assert.are.equal("← Page 20 (10%)", items[3].text)
        assert.are.equal("← Page 10 (5%)", items[4].text)

        -- Selecting items[3] (index 2: Page 20) should trigger navigation to page 20
        items[3].callback()

        assert.are.equal(2, plugin.history_idx)
        assert.is_true(plugin.is_navigating)
        assert.are.equal("GotoPage", handle_event_called.name)
        assert.are.equal(20, handle_event_called.page)
    end)

    it("should gracefully fall back if document or TOC is missing or incomplete", function()
        local mock_ui = {
            menu = { registerToMainMenu = function() end },
            handleEvent = function(self, ev) end
        }
        local plugin = Kojump:new{ ui = mock_ui }
        plugin:init()

        plugin:onPageUpdate(10)
        plugin:onPageUpdate(20)

        mock_uimanager.shown = {}
        plugin:showHistory()

        local menu = mock_uimanager.shown[1]
        local items = menu.item_table
        assert.are.equal(2, #items)
        -- No percentage and no chapter because document and toc are missing
        assert.are.equal("• Page 20 (Current)", items[1].text)
        assert.are.equal("← Page 10", items[2].text)
    end)
end)
