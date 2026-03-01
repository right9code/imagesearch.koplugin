local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local CacheManager = {}

-- Helper: create directory and all parents (mkdir -p)
local function mkdirp(path)
    -- Try direct creation first (works if parent exists)
    local ok, err = lfs.mkdir(path)
    if ok or err == "File exists" then return true end
    -- Parent may be missing: recursively create it
    local parent = path:match("^(.+)/[^/]+")
    if parent and parent ~= path then
        local parent_ok = mkdirp(parent)
        if not parent_ok then return false, "failed to create " .. parent end
        ok, err = lfs.mkdir(path)
        if ok or err == "File exists" then return true end
    end
    return false, err
end

-- Get cache directory for plugin
function CacheManager.getCacheDir()
    local DataStorage = require("datastorage")
    local cache_dir = DataStorage:getDataDir() .. "/cache/imagesearch"
    local ok, err = mkdirp(cache_dir)
    if not ok then
        logger.warn("ImageSearch: Failed to create cache dir:", err)
        return nil, err
    end
    return cache_dir
end

-- Get cache size in bytes
function CacheManager.getCacheSize()
    local cache_dir = CacheManager.getCacheDir()
    if not cache_dir then
        return 0
    end
    
    local total_size = 0
    local count = 0
    for entry in lfs.dir(cache_dir) do
        if entry ~= "." and entry ~= ".." then
            local filepath = cache_dir .. "/" .. entry
            local size = lfs.attributes(filepath, "size")
            if size then
                total_size = total_size + size
                count = count + 1
            end
        end
    end
    
    return total_size, count
end

-- Save data to file
function CacheManager.saveToFile(filepath, data)
    if not data or data == "" then
        return nil, "No data to save"
    end
    
    local file, err = io.open(filepath, "wb")
    if not file then
        logger.warn("ImageSearch: Failed to open file for writing:", filepath, err)
        return nil, err
    end
    
    file:write(data)
    file:close()
    
    logger.info("ImageSearch: Saved", #data, "bytes to:", filepath)
    return true
end

-- Check if file exists
function CacheManager.fileExists(filepath)
    local mode = lfs.attributes(filepath, "mode")
    return mode == "file"
end

-- Simple string hash function (DJB2) to ensure uniqueness
local function string_hash(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

-- Get safe filename from URL
function CacheManager.getFilenameFromUrl(url)
    -- Use hash of full URL to prevent collisions and handle odd URL structures
    local ext = url:match("%.(%w+)$")
    if not ext then ext = "jpg" end
    
    -- Strip query from extension check if needed, but hash uses full URL
    -- actually, let's just force .jpg if we can't find one, simpler
    if #ext > 4 then ext = "jpg" end 
    
    local unique_name = "img_" .. string_hash(url) .. "." .. ext
    return unique_name
end

-- Download image and cache it
function CacheManager.downloadAndCache(url, api_client)
    -- Handle local files (like AI generated ones)
    if url:find("^file://") then
        local path = url:gsub("^file://", "")
        if CacheManager.fileExists(path) then
            return path
        end
    end

    local cache_dir = CacheManager.getCacheDir()
    if not cache_dir then
        return nil, "Cache directory not available"
    end
    
    local filename = CacheManager.getFilenameFromUrl(url)
    local filepath = cache_dir .. "/" .. filename
    
    -- Check cache first
    if CacheManager.fileExists(filepath) then
        logger.info("ImageSearch: Using cached image:", filepath)
        return filepath
    end
    
    -- Download image
    logger.info("ImageSearch: Downloading image from:", url)
    local image_data, err = api_client.downloadImage(url, {
        timeout = 30,
        maxtime = 45,
    })
    
    if not image_data then
        logger.warn("ImageSearch: Download failed:", err)
        return nil, err
    end
    
    -- Save to cache
    local ok, save_err = CacheManager.saveToFile(filepath, image_data)
    if not ok then
        return nil, save_err
    end
    
    return filepath
end

-- Clear cache
function CacheManager.clearCache()
    local cache_dir = CacheManager.getCacheDir()
    if not cache_dir then
        return
    end
    
    local count = 0
    for entry in lfs.dir(cache_dir) do
        if entry ~= "." and entry ~= ".." then
            local filepath = cache_dir .. "/" .. entry
            local ok = os.remove(filepath)
            if ok then
                count = count + 1
            end
        end
    end
    
    logger.info("ImageSearch: Cleared", count, "cached files")
    return count
end

return CacheManager
