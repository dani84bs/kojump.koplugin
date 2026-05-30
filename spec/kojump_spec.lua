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
        package.preload["ui/widget/infomessage"] = function() return mock_infomessage end
        package.preload["ui/uimanager"] = function() return mock_uimanager end
        package.preload["ui/widget/container/widgetcontainer"] = function() return mock_widgetcontainer end
        package.preload["gettext"] = function()
            return function(str) return str end
        end

        package.path = "./?.lua;" .. package.path
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
end)
