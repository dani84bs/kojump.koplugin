--[[--
Kojump is a plugin to provide browser-style back/forward history navigation for KOReader.
--]]--

local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Kojump = WidgetContainer:extend{
    name = "kojump",
    is_doc_only = true,
}

function Kojump:init()
    self.history = {}
    self.history_idx = 0
    self.current_page = nil
    self.is_navigating = false

    self.ui.menu:registerToMainMenu(self)
end

function Kojump:onDispatcherRegisterActions()
    Dispatcher:registerAction("kojump_back", {
        category = "none",
        event = "KojumpBack",
        title = _("Kojump: Go Back"),
        general = true,
    })
    Dispatcher:registerAction("kojump_forward", {
        category = "none",
        event = "KojumpForward",
        title = _("Kojump: Go Forward"),
        general = true,
    })
end

function Kojump:addToMainMenu(menu_items)
    menu_items.kojump_back = {
        text = _("Kojump: Go Back"),
        sorting_hint = "navi",
        callback = function()
            self:goBack()
        end,
    }
    menu_items.kojump_forward = {
        text = _("Kojump: Go Forward"),
        sorting_hint = "navi",
        callback = function()
            self:goForward()
        end,
    }
end

function Kojump:onDocSettingsLoad(doc_settings)
    self.doc_settings = doc_settings
    local data = doc_settings.data.kojump
    if data then
        self.history = data.history or {}
        self.history_idx = data.history_idx or 0
    else
        self.history = {}
        self.history_idx = 0
    end
end

function Kojump:saveHistory()
    if self.doc_settings then
        self.doc_settings.data.kojump = {
            history = self.history,
            history_idx = self.history_idx,
        }
        if self.doc_settings.save then
            self.doc_settings:save()
        end
    end
end

function Kojump:initHistory(page_num)
    if not self.history or #self.history == 0 then
        self.history = { page_num }
        self.history_idx = 1
        self:saveHistory()
    end
    self.current_page = page_num
end

function Kojump:onPageUpdate(page_num)
    if not page_num then return end

    if not self.current_page then
        self:initHistory(page_num)
        return
    end

    if page_num == self.current_page then
        return
    end

    if self.is_navigating then
        self.current_page = page_num
        self.is_navigating = false
        return
    end

    -- Check if it was a jump (absolute difference > 1)
    local diff = math.abs(page_num - self.current_page)
    if diff > 1 then
        -- Truncate any forward history
        while #self.history > self.history_idx do
            table.remove(self.history)
        end

        table.insert(self.history, page_num)
        self.history_idx = self.history_idx + 1

        -- Enforce capacity of 20 entries
        if #self.history > 20 then
            table.remove(self.history, 1)
            self.history_idx = self.history_idx - 1
        end

        self:saveHistory()
    end

    self.current_page = page_num
end

function Kojump:canGoBack()
    return self.history_idx > 1
end

function Kojump:canGoForward()
    return self.history_idx < #self.history
end

function Kojump:goBack()
    if self:canGoBack() then
        self.history_idx = self.history_idx - 1
        local target_page = self.history[self.history_idx]
        self.is_navigating = true
        self:saveHistory()
        self:jumpToPage(target_page, _("Jumped back to page %d"))
    else
        UIManager:show(InfoMessage:new{
            text = _("Cannot go back: No history available."),
            timeout = 1.5,
        })
    end
end

function Kojump:goForward()
    if self:canGoForward() then
        self.history_idx = self.history_idx + 1
        local target_page = self.history[self.history_idx]
        self.is_navigating = true
        self:saveHistory()
        self:jumpToPage(target_page, _("Jumped forward to page %d"))
    else
        UIManager:show(InfoMessage:new{
            text = _("Cannot go forward: At newest position."),
            timeout = 1.5,
        })
    end
end

function Kojump:onKojumpBack()
    self:goBack()
end

function Kojump:onKojumpForward()
    self:goForward()
end

function Kojump:jumpToPage(page_num, message_fmt)
    self.ui:handleEvent(Event:new("GotoPage", page_num))
    UIManager:show(InfoMessage:new{
        text = string.format(message_fmt, page_num),
        timeout = 1.5,
    })
end

return Kojump
