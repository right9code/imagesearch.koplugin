local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local Device = require("device")
local ThumbnailDialog = require("thumbnail_dialog")
local WikiCommonsApi = require("api_client")
local CacheManager = require("image_cache_manager")
local Event = require("ui/event")

local ImageSearch = WidgetContainer:extend{
    name = "imagesearch",
    is_doc_only = false,
}

function ImageSearch:getDeviceRoot()
    -- Check common device storage roots
    local lfs = require("libs/libkoreader-lfs")
    local candidates = {
        "/mnt/onboard", -- Kobo
        "/mnt/us",      -- Kindle
        "/mnt/ext1",    -- PocketBook
        "/sdcard",      -- Android
    }
    for _, path in ipairs(candidates) do
        local mode = lfs.attributes(path, "mode")
        if mode == "directory" then
            return path
        end
    end
    -- Fallback to data dir if no standard root found
    local DataStorage = require("datastorage")
    return DataStorage:getDataDir()
end

function ImageSearch:init()
    logger.info("ImageSearch: Initializing plugin (doc_only=true)")
    if self.ui.highlight then
        logger.info("ImageSearch: Highlight module available")
    else
        logger.warn("ImageSearch: Highlight module MISSING")
    end
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    
    -- Set default configuration provided it's not already set
    if not G_reader_settings:has("imagesearch_grid_rows") then
        G_reader_settings:saveSetting("imagesearch_grid_rows", 2)
    end
    if not G_reader_settings:has("imagesearch_grid_cols") then
        G_reader_settings:saveSetting("imagesearch_grid_cols", 3)
    end
    
    -- Auto-detect and set default download directory if not set
    if not G_reader_settings:has("imagesearch_download_dir") then
        local root = self:getDeviceRoot()
        G_reader_settings:saveSetting("imagesearch_download_dir", root)
    end

    -- Register to selection menu (ReaderHighlight)
    if self.ui.highlight then
        self.ui.highlight:addToHighlightDialog("image_search", function(_reader_highlight_instance)
            return {
                text = _("Image Search"),
                callback = function()
                    if _reader_highlight_instance.selected_text and _reader_highlight_instance.selected_text.text then
                        local text = _reader_highlight_instance.selected_text.text
                        if text ~= "" then
                            -- Close the highlight menu first
                            if _reader_highlight_instance.onClose then
                                _reader_highlight_instance:onClose()
                            end
                            
                            -- Show input dialog to edit search query
                            local input_dialog
                            input_dialog = InputDialog:new{
                                title = _("Image Search"),
                                input = text,
                                buttons = {
                                    {
                                        {
                                            text = _("Cancel"),
                                            id = "close",
                                            callback = function()
                                                UIManager:close(input_dialog)
                                            end,
                                        },
                                        {
                                            text = _("Search"),
                                            is_enter_default = true,
                                            callback = function()
                                                local query = input_dialog:getInputText()
                                                UIManager:close(input_dialog)
                                                if query and query ~= "" then
                                                    self:performSearch(query)
                                                end
                                            end,
                                        },
                                    }
                                },
                            }
                            UIManager:show(input_dialog)
                            input_dialog:onShowKeyboard()
                        end
                    end
                end,
            }
        end)
        
        self.ui.highlight:addToHighlightDialog("image_generate", function(_reader_highlight_instance)
            return {
                text = _("Generate Image (AI)"),
                callback = function()
                    if _reader_highlight_instance.selected_text and _reader_highlight_instance.selected_text.text then
                        local text = _reader_highlight_instance.selected_text.text
                        if text ~= "" then
                            if _reader_highlight_instance.onClose then
                                _reader_highlight_instance:onClose()
                            end
                            
                            local InputDialog = require("ui/widget/inputdialog")
                            local input_dialog
                            input_dialog = InputDialog:new{
                                title = _("Generate Image"),
                                input = text,
                                buttons = {
                                    {
                                        {
                                            text = _("Cancel"),
                                            callback = function() UIManager:close(input_dialog) end,
                                        },
                                        {
                                            text = _("Generate"),
                                            callback = function()
                                                local query = input_dialog:getInputText()
                                                UIManager:close(input_dialog)
                                                if query and query ~= "" then
                                                    self:performGeneration(query)
                                                end
                                            end,
                                        },
                                    },
                                },
                            }
                            UIManager:show(input_dialog)
                            input_dialog:onShowKeyboard()
                        end
                    end
                end,
            }
        end)
    end
end

function ImageSearch:onImageSearchSelection(text)
    if not text or text == "" then
        return
    end
    
    logger.info("ImageSearch: Searching from selection:", text)
    self:performSearch(text)
end

function ImageSearch:onDispatcherRegisterActions()
    Dispatcher:registerAction("image_search_query", {
        category = "none",
        event = "ImageSearchQuery",
        title = _("Image Search: Search Images"),
        general = true,
    })
    Dispatcher:registerAction("image_search_selection", {
        category = "none",
        event = "ImageSearchSelection",
        title = _("Image Search for Selection"),
        selection = true,
    })
end

function ImageSearch:addToMainMenu(menu_items)
    menu_items.image_search = {
        text = _("Image Search"),
        sorting_hint = "search",
        sub_item_table_func = function()
            -- Dynamically generate menu to show current cache size
            local util = require("util")
            local size, count = CacheManager.getCacheSize()
            local cache_text = count == 0 and _("(empty)") or util.getFriendlySize(size)
            
            return {
                {
                    text = _("Search Images..."),
                    callback = function()
                        self:onImageSearchQuery()
                    end,
                },
                {
                    text = _("Generate Image (AI)..."),
                    callback = function()
                         self:onGenerateImageQuery()
                    end,
                },
                {
                    text = _("Search Source: ") .. (function()
                        local p = G_reader_settings:readSetting("imagesearch_provider")
                        if p == "openverse" then return "Openverse" end
                        if p == "duckduckgo" then return "DuckDuckGo" end
                        return "Wikimedia"
                    end)(),
                    keep_menu_open = false,
                    callback = function()
                         self:onSetSearchSource()
                    end,
                },
                {
                    text = _("Set Download Directory"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetDownloadDirectory()
                    end,
                },
                {
                    text_func = function()
                        local provider = G_reader_settings:readSetting("ai_provider") or "pollinations"
                        if provider == "pollinations" then
                            return _("AI Provider: Pollinations")
                        else
                            return _("AI Provider: Gemini")
                        end
                    end,
                    sub_item_table = {
                        {
                            text = _("Pollinations.ai (Requires Key)"),
                            checked_func = function()
                                return (G_reader_settings:readSetting("ai_provider") or "pollinations") == "pollinations"
                            end,
                            callback = function()
                                G_reader_settings:saveSetting("ai_provider", "pollinations")
                            end,
                        },
                        {
                            text = _("Google Gemini (Requires Key)"),
                            checked_func = function()
                                return G_reader_settings:readSetting("ai_provider") == "gemini"
                            end,
                            callback = function()
                                G_reader_settings:saveSetting("ai_provider", "gemini")
                            end,
                        },
                    },
                },
                {
                    text = _("Set Pollinations API Key"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetPollinationsKey()
                    end,
                },
                {
                    text = _("Set Pollinations Model"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetPollinationsModel()
                    end,
                },
                {
                    text = _("Set Gemini API Key"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetGeminiKey()
                    end,
                },
                {
                    text = _("Set Gemini Model"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetGeminiModel()
                    end,
                },
                {
                    text = _("Set Grid Rows"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetRows()
                    end,
                },
                {
                    text = _("Set Grid Columns"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetCols()
                    end,
                },
                {
                    text = _("Set Max Results"),
                    keep_menu_open = true,
                    callback = function()
                         self:onSetMaxResults()
                    end,
                },
                {
                    text = string.format(_("Clear Cache (%s)"), cache_text),
                    callback = function()
                         self:onClearCache()
                    end,
                },
                {
                    text = _("About"),
                    callback = function()
                        UIManager:show(InfoMessage:new{
                            text = _("Image Search Plugin\n\nSearch for images on the internet and view them on your device.\n\nFeatures:\n• Search images from selection\n• Manual image search\n• View thumbnails\n• Save images"),
                            timeout = 5,
                        })
                    end,
                },
            }
        end,
    }
end

function ImageSearch:onSetSearchSource()
    local UIManager = require("ui/uimanager")
    local Menu = require("ui/widget/menu")
    local ConfirmBox = require("ui/widget/confirmbox")
    local Event = require("ui/event")
    
    local current = G_reader_settings:readSetting("imagesearch_provider") or "duckduckgo"
    local menu -- Forward declaration to capture in closure
    
    menu = Menu:new{
        title = _("Select Search Source"),
        item_table = {
            {
                text = _("DuckDuckGo (Accurate)"),
                checked = current == "duckduckgo",
                callback = function()
                    local confirm = ConfirmBox:new{
                        text = _("Switch search source to DuckDuckGo?\n(Accurate web search, no keys required)"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("imagesearch_provider", "duckduckgo")
                            UIManager:close(menu)
                            UIManager:broadcastEvent(Event:new("UpdateMenu"))
                            UIManager:show(InfoMessage:new{
                                text = _("Source switched to DuckDuckGo"),
                                timeout = 2
                            })
                        end,
                    }
                    UIManager:show(confirm)
                end,
            },
            {
                text = _("Wikimedia Commons (Free/History)"),
                checked = current == "wikicommons",
                callback = function()
                    local confirm = ConfirmBox:new{
                        text = _("Switch search source to Wikimedia Commons?"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("imagesearch_provider", "wikicommons")
                            UIManager:close(menu)
                            UIManager:broadcastEvent(Event:new("UpdateMenu"))
                             UIManager:show(InfoMessage:new{
                                text = _("Source switched to Wikimedia"),
                                timeout = 2
                            })
                        end,
                    }
                    UIManager:show(confirm)
                end,
            },
            {
                text = _("Openverse (WordPress)"),
                checked = current == "openverse",
                callback = function()
                    local confirm = ConfirmBox:new{
                        text = _("Switch search source to Openverse?\n(Access mostly freely licensed images)"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("imagesearch_provider", "openverse")
                            UIManager:close(menu)
                            UIManager:broadcastEvent(Event:new("UpdateMenu"))
                            UIManager:show(InfoMessage:new{
                                text = _("Source switched to Openverse"),
                                timeout = 2
                            })
                        end,
                    }
                    UIManager:show(confirm)
                end,
            },
        },
    }
    UIManager:show(menu)
end

function ImageSearch:onSetDownloadDirectory()
    local DownloadMgr = require("ui/downloadmgr")
    local current_dir = G_reader_settings:readSetting("imagesearch_download_dir") or "/"
    
    DownloadMgr:new{
        title = _("Select Image Download Directory"),
        onConfirm = function(path)
            if path then
                G_reader_settings:saveSetting("imagesearch_download_dir", path)
                UIManager:show(InfoMessage:new{
                    text = _("Download directory set to:\n") .. path,
                    timeout = 3
                })
            end
        end,
    }:chooseDir(current_dir)
end

function ImageSearch:onSetRows()
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    local current = G_reader_settings:readSetting("imagesearch_rows") or 2
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set Grid Rows"),
        input = tostring(current),
        input_type = "number",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(input_dialog) end },
            { text = _("Set"), callback = function()
                local val = tonumber(input_dialog:getInputText())
                UIManager:close(input_dialog)
                if val and val > 0 and val <= 5 then
                    G_reader_settings:saveSetting("imagesearch_rows", val)
                    UIManager:show(InfoMessage:new{ text = _("Rows set to ") .. val, timeout = 2 })
                else
                    UIManager:show(InfoMessage:new{ text = _("Invalid (1-5)"), timeout = 2 })
                end
            end }
        }}
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ImageSearch:onSetCols()
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    local current = G_reader_settings:readSetting("imagesearch_cols") or 2
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set Grid Columns"),
        input = tostring(current),
        input_type = "number",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(input_dialog) end },
            { text = _("Set"), callback = function()
                local val = tonumber(input_dialog:getInputText())
                UIManager:close(input_dialog)
                if val and val > 0 and val <= 5 then
                    G_reader_settings:saveSetting("imagesearch_cols", val)
                    UIManager:show(InfoMessage:new{ text = _("Columns set to ") .. val, timeout = 2 })
                else
                    UIManager:show(InfoMessage:new{ text = _("Invalid (1-5)"), timeout = 2 })
                end
            end }
        }}
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ImageSearch:onSetMaxResults()
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    local current = G_reader_settings:readSetting("imagesearch_max_results") or 20
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set Max Search Results"),
        input = tostring(current),
        input_type = "number",
        description = _("Number of images to fetch per search (1-50)"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(input_dialog) end },
            { text = _("Set"), callback = function()
                local val = tonumber(input_dialog:getInputText())
                UIManager:close(input_dialog)
                if val and val > 0 and val <= 50 then
                    G_reader_settings:saveSetting("imagesearch_max_results", val)
                    UIManager:show(InfoMessage:new{ text = _("Max results set to ") .. val, timeout = 2 })
                else
                    UIManager:show(InfoMessage:new{ text = _("Invalid (1-50)"), timeout = 2 })
                end
            end }
        }}
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ImageSearch:onClearCache()
    local util = require("util")
    local ConfirmBox = require("ui/widget/confirmbox")
    
    -- Get current cache size
    local size, count = CacheManager.getCacheSize()
    local size_str = util.getFriendlySize(size)
    
    local confirm_box = ConfirmBox:new{
        text = string.format(_("Clear image cache?\n\nCurrent size: %s (%d files)"), size_str, count),
        ok_text = _("Clear"),
        ok_callback = function()
            local cleared = CacheManager.clearCache()
            UIManager:show(InfoMessage:new{
                text = string.format(_("Cache cleared!\n\n%d files removed"), cleared),
                timeout = 3,
            })
            -- Trigger menu refresh to update cache size display
            UIManager:broadcastEvent(Event:new("UpdateMenu"))
        end,
    }
    UIManager:show(confirm_box)
end

function ImageSearch:onImageSearchQuery()
    logger.info("ImageSearch: Opening search dialog")
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Search Images"),
        input = "",
        input_hint = _("Enter search query"),
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if query and query ~= "" then
                            self:performSearch(query)
                        end
                    end,
                },
            },
        },
    }
    
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
    return true
end

function ImageSearch:performSearch(query)
    logger.info("ImageSearch: Searching for:", query)
    
    local InfoMessage = require("ui/widget/infomessage")
    local loading_dialog = InfoMessage:new{
        text = string.format("\u{23f3}  %s", _("Searching for: ") .. query),
        dismissable = false,
        show_icon = false,
        force_one_line = true,
    }
    UIManager:show(loading_dialog)

    -- Use nextTick to ensure the dialog renders before we block the thread
    UIManager:nextTick(function()
        UIManager:scheduleIn(0.1, function()
            -- Import API client
            local api_ok, WikiCommonsApi = pcall(function()
                return require("api_client")
            end)
            
            if not api_ok then
                UIManager:close(loading_dialog)
                logger.err("ImageSearch: Failed to load API client:", WikiCommonsApi)
                UIManager:show(InfoMessage:new{
                    text = _("Error loading API client.\nPlease check the logs."),
                    timeout = 3,
                })
                return
            end
            
            -- Perform search
            local max_results = G_reader_settings:readSetting("imagesearch_max_results") or 20
            local results, err = WikiCommonsApi.searchImages(query, {
                max_results = max_results,
                timeout = 15,
                maxtime = 30,
            })
            
            UIManager:close(loading_dialog)

            if not results then
                logger.warn("ImageSearch: Search failed:", err)
                UIManager:show(InfoMessage:new{
                    text = _("Search failed:\n") .. (err or "Unknown error"),
                    timeout = 3,
                })
                return
            end
            
            if #results == 0 then
                logger.info("ImageSearch: No results found")
                UIManager:show(InfoMessage:new{
                    text = _("No images found for: ") .. query,
                    timeout = 3,
                })
                return
            end
            
            -- Log results for debug
            logger.info("ImageSearch: Found", #results, "results")
            
            self.thumbnail_dialog = ThumbnailDialog:new{
                query = query,
                results = results,
                cache_manager = self.cache_manager,
                api_client = self.api_client,
                callback_search = function() self:onImageSearchQuery() end,
            }
            UIManager:show(self.thumbnail_dialog)
        end)
    end)
end





function ImageSearch:onSetPollinationsKey()
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    
    local saved = G_reader_settings:readSetting("pollinations_api_key") or ""
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set Pollinations API Key"),
        input = saved,
        hint = _("Enter your Pollinations.ai API Key (sk_... or pk_...) from enter.pollinations.ai"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local key = input_dialog:getInputText()
                        G_reader_settings:saveSetting("pollinations_api_key", key)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Pollinations API Key saved"),
                            timeout = 2
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ImageSearch:onSetPollinationsModel()
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    local PollinationsClient = require("pollinations_client")
    local current_model = G_reader_settings:readSetting("pollinations_model") or PollinationsClient.DEFAULT_MODEL

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set Pollinations Model"),
        input = current_model,
        hint = _("Model: flux, turbo, gptimage, kontext, seedream, nanobanana"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local model = input_dialog:getInputText()
                        if model == "" then model = nil end
                        G_reader_settings:saveSetting("pollinations_model", model)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Pollinations model set to: ") .. (model or PollinationsClient.DEFAULT_MODEL),
                            timeout = 2
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ImageSearch:onSetGeminiKey()
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    
    -- Check for hardcoded key first
    local GeminiClient = require("gemini_client")
    local hardcoded = GeminiClient.getApiKey()
    local saved = G_reader_settings:readSetting("gemini_api_key") or ""
    
    local current_key = hardcoded or saved
    local hint_text = _("Enter your Google AI Studio API Key")
    if hardcoded then
        hint_text = _("Using Hardcoded Key from gemini_client.lua")
    end
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set Gemini API Key"),
        input = current_key,
        hint = hint_text,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local key = input_dialog:getInputText()
                        G_reader_settings:saveSetting("gemini_api_key", key)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Gemini API Key saved"),
                            timeout = 2
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    -- Don't show keyboard immediately if we have a hardcoded key, user likely just wants to verify
    if not hardcoded then
        input_dialog:onShowKeyboard()
    end
end

function ImageSearch:onSetGeminiModel()
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    local GeminiClient = require("gemini_client")
    local current_model = G_reader_settings:readSetting("gemini_model") or GeminiClient.DEFAULT_MODEL
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Set Gemini Model"),
        input = current_model,
        hint = _("Model name (e.g. gemini-2.0-flash-exp)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local model = input_dialog:getInputText()
                        -- Allow clearing it to reset to default
                        if model == "" then model = nil end
                        
                        G_reader_settings:saveSetting("gemini_model", model)
                        UIManager:close(input_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Model set to: ") .. (model or "Default"),
                            timeout = 2
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end


function ImageSearch:onGenerateImageQuery()
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Generate Image (AI)"),
        input = "",
        hint = _("Describe the image (e.g., 'Cyberpunk city')"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Generate"),
                    callback = function()
                        local query = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if query and query ~= "" then
                            self:performGeneration(query)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ImageSearch:performGeneration(prompt)
    local InfoMessage = require("ui/widget/infomessage")
    
    -- Check which provider is selected (default to pollinations)
    local provider = G_reader_settings:readSetting("ai_provider") or "pollinations"
    
    logger.info("ImageSearch: Showing loading dialog for generation")
    local loading_dialog = InfoMessage:new{
        text = string.format("\u{23f3}  %s", _("Generating image...")),
        dismissable = false,
        show_icon = false,
        force_one_line = true,
    }
    UIManager:show(loading_dialog)

    -- Use nextTick to ensure the dialog renders before we block the thread
    UIManager:nextTick(function()
        -- Add another small delay just to be safe for E-ink/slow devices
        UIManager:scheduleIn(0.2, function()
            logger.info("ImageSearch: Starting generation with provider:", provider)
            local results, err
            
            if provider == "gemini" then
                -- Use Gemini (requires API key)
                local GeminiClient = require("gemini_client")
                local api_key = G_reader_settings:readSetting("gemini_api_key")
                
                if not api_key or api_key == "" then
                    UIManager:close(loading_dialog)
                    UIManager:show(InfoMessage:new{
                        text = _("Please set your Gemini API Key in settings first."),
                        timeout = 3
                    })
                    return
                end
                results, err = GeminiClient.generateImage(prompt, api_key)
            else
                -- Use Pollinations
                local PollinationsClient = require("pollinations_client")
                local api_key = G_reader_settings:readSetting("pollinations_api_key")
                
                if not api_key or api_key == "" then
                    UIManager:close(loading_dialog)
                    UIManager:show(InfoMessage:new{
                        text = _("Please set your Pollinations API Key in settings first."),
                        timeout = 3
                    })
                    return
                end
                local pollinations_model = G_reader_settings:readSetting("pollinations_model")
                results, err = PollinationsClient.generateImage(prompt, api_key, { model = pollinations_model })
            end

            logger.info("ImageSearch: Generation finished, closing loading dialog")
            UIManager:close(loading_dialog)

            if not results then
                UIManager:show(InfoMessage:new{
                    text = _("Generation failed: ") .. (err or "Unknown error"),
                    timeout = 3
                })
                return
            end

            -- Display results in thumbnail dialog
            self.thumbnail_dialog = ThumbnailDialog:new{
                query = prompt,
                results = results,
                cache_manager = self.cache_manager,
                api_client = self.api_client,
                callback_search = function() self:onImageSearchQuery() end,
            }
            UIManager:show(self.thumbnail_dialog)
        end)
    end)
end

return ImageSearch
