--[[--
Kojump is a plugin to provide browser-style back/forward history navigation for KOReader.
--]]--

local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local function truncate_utf8(str, max_chars)
    if not str then return nil end
    local char_count = 0
    local byte_idx = 0
    for i = 1, #str do
        local byte = string.byte(str, i)
        -- Byte is not a continuation byte (i.e. not in the range [128, 191])
        if byte < 128 or byte >= 192 then
            char_count = char_count + 1
            if char_count > max_chars then
                byte_idx = i - 1
                break
            end
        end
    end

    if char_count > max_chars then
        return string.sub(str, 1, byte_idx) .. "..."
    end
    return str
end

local Kojump = WidgetContainer:extend{
    name = "kojump",
    is_doc_only = true,
}

function Kojump:init()
    self.history = {}
    self.history_idx = 0
    self.current_page = nil
    self.is_navigating = false
    self.max_jumps = G_reader_settings and G_reader_settings:readSetting("kojump_max_jumps", 20) or 20

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
    Dispatcher:registerAction("kojump_show_history", {
        category = "none",
        event = "KojumpShowHistory",
        title = _("Kojump: Show History"),
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
    menu_items.kojump_show_history = {
        text = _("Kojump: Show History"),
        sorting_hint = "navi",
        callback = function()
            self:showHistory()
        end,
    }
    menu_items.kojump = {
        text = _("Kojump"),
        sorting_hint = "more_tools",
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function Kojump:getSubMenuItems()
    return {
        {
            text = _("Max Jumps"),
            callback = function(menu)
                self:showMaxJumpsDialog(menu)
            end,
        }
    }
end

function Kojump:showMaxJumpsDialog(menu)
    local SpinWidget = require("ui/widget/spinwidget")
    local max_jumps_spin = SpinWidget:new {
        value = self.max_jumps,
        value_min = 5,
        value_max = 100,
        value_step = 1,
        value_hold_step = 5,
        ok_text = _("Save"),
        title_text = _("Kojump Max Jumps"),
        callback = function(spin)
            self.max_jumps = spin.value
            if G_reader_settings then
                G_reader_settings:saveSetting("kojump_max_jumps", self.max_jumps)
            end
            self:pruneHistory()
            self:saveHistory()
            if menu then
                menu:updateItems()
            end
        end,
    }
    UIManager:show(max_jumps_spin)
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

        -- If our current page (source of jump) is not already the last recorded page in history,
        -- record the source page first so the user can jump back to where they manually navigated.
        if self.history[self.history_idx] ~= self.current_page then
            table.insert(self.history, self.current_page)
            self.history_idx = self.history_idx + 1
        end

        table.insert(self.history, page_num)
        self.history_idx = self.history_idx + 1

        -- Enforce capacity
        self:pruneHistory()

        self:saveHistory()
    end

    self.current_page = page_num
end

function Kojump:pruneHistory()
    while #self.history > self.max_jumps do
        table.remove(self.history, 1)
        self.history_idx = self.history_idx - 1
    end
    if #self.history == 0 then
        self.history_idx = 0
    elseif self.history_idx < 1 then
        self.history_idx = 1
    end
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

function Kojump:onKojumpShowHistory()
    self:showHistory()
end

function Kojump:showHistory()
    if not self:canGoBack() and not self:canGoForward() then
        UIManager:show(InfoMessage:new{
            text = _("Cannot show history: No history available."),
            timeout = 1.5,
        })
        return
    end

    local items = {}
    local total_pages = self.ui.document and self.ui.document:getPageCount()

    for i = #self.history, 1, -1 do
        local page_num = self.history[i]

        local percentage_str = ""
        if total_pages and total_pages > 0 then
            local percent = math.floor(page_num / total_pages * 100)
            percentage_str = string.format(" (%d%%)", percent)
        end

        local chapter_str = ""
        local chapter_title = self.ui.toc and self.ui.toc:getTocTitleByPage(page_num)
        if chapter_title and type(chapter_title) == "string" then
            chapter_title = chapter_title:match("^%s*(.-)%s*$")
            if chapter_title ~= "" then
                local truncated_title = truncate_utf8(chapter_title, 40)
                chapter_str = " - " .. truncated_title
            end
        end

        local label
        if i == self.history_idx then
            label = string.format(_("• Page %d%s%s (Current)"), page_num, percentage_str, chapter_str)
        elseif i > self.history_idx then
            label = string.format(_("→ Page %d%s%s"), page_num, percentage_str, chapter_str)
        else
            label = string.format(_("← Page %d%s%s"), page_num, percentage_str, chapter_str)
        end

        table.insert(items, {
            text = label,
            callback = function()
                self.history_idx = i
                local target_page = self.history[i]
                self.is_navigating = true
                self:saveHistory()
                self:jumpToPage(target_page, _("Jumped to page %d"))
            end
        })
    end

    local menu = Menu:new{
        title = _("Kojump History"),
        item_table = items,
    }
    UIManager:show(menu)
end

function Kojump:jumpToPage(page_num, message_fmt)
    self.ui:handleEvent(Event:new("GotoPage", page_num))
    UIManager:show(InfoMessage:new{
        text = string.format(message_fmt, page_num),
        timeout = 1.5,
    })
end

return Kojump
