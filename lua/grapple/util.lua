local uv = vim.loop

local M = {}

function M.inline_inspect(root)
    return (string.gsub(string.gsub(vim.inspect(root), "\n", " "), "%s+", " "))
end

---@diagnostic disable-next-line undefined-field
local sep = uv.os_uname().version:match("Windows") and "\\" or "/"

function M.path_join(...)
    return table.concat(vim.tbl_flatten({ ... }), sep)
end

function M.path_norm(path)
    return vim.fs.normalize(path)
end

function M.path_abs(path)
    ---@diagnostic disable-next-line undefined-field
    local real_path, _ = uv.fs_realpath(path)
    return real_path
end

function M.path_from_buffer(buffer)
    local excluded_ft = { "grapple" }

    -- stylua: ignore
    if not vim.api.nvim_buf_is_valid(buffer)
        or vim.tbl_contains(excluded_ft, vim.api.nvim_buf_get_option(buffer, "filetype"))
        or vim.api.nvim_buf_get_option(buffer, "buftype") ~= ""
        or vim.api.nvim_buf_get_name(buffer) == ""
    then
        return
    end

    return vim.api.nvim_buf_get_name(buffer)
end

function M.buffer_from_path(path)
    return vim.fn.bufnr(path)
end

function M.cursor_from_buffer(buffer)
    -- stylua: ignore
    return vim.api.nvim_buf_is_valid(buffer)
        and vim.api.nvim_buf_get_mark(buffer, '"')
        or { 0, 0 }
end

function M.create_dir(path)
    vim.fn.mkdir(path, "p")
end

function M.read_file(path)
    ---@diagnostic disable undefined-field
    local fd = uv.fs_open(path, "r", 438)
    if fd then
        local stat = assert(uv.fs_fstat(fd))
        local data = assert(uv.fs_read(fd, stat.size, 0))
        assert(uv.fs_close(fd))
        return data
    end
    ---@diagnostic enable undefined-field
end

function M.write_file(path, content)
    ---@diagnostic disable undefined-field
    local fd = assert(uv.fs_open(path, "w", 438))
    assert(uv.fs_write(fd, content))
    assert(uv.fs_close(fd))
    ---@diagnostic enable undefined-field
end

function M.timestamp()
    ---@diagnostic disable-next-line
    return os.time(os.date("!*t"))
end

---Encode string as urlencoded
---@param str string
---@return string
function M.encode(str)
    return (
        string.gsub(str, "([^%w])", function(match)
            return string.upper(string.format("%%%02x", string.byte(match)))
        end)
    )
end

---Decode urlencoded string
---@param str string
---@return string
function M.decode(str)
    return (string.gsub(str, "%%(%x%x)", function(match)
        return string.char(tonumber(match, 16))
    end))
end

---@param tbl table
---@return string | nil
function M.serialize(tbl)
    local ok, result = pcall(vim.json.encode, tbl)
    if not ok then
        return
    end
    return result
end

---@param json string
---@return table | nil
function M.deserialize(json)
    local ok, result = pcall(vim.json.decode, json)
    if not ok then
        return
    end
    return result
end

math.randomseed(os.clock())

---@alias Grapple.UUID string

--- Simple UUID generation
--- @return Grapple.UUID
function M.uuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (
        string.gsub(template, "[xy]", function(c)
            local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format("%x", v)
        end)
    )
end

return M
