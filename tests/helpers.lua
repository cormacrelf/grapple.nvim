local Util = require("grapple.util")

local H = {}

H.util = Util

H.fs_root = vim.fn.fnamemodify("./.tests/fs", ":p")

function H.path(path)
    return Util.path_join(H.fs_root, path)
end

---@param files string[]
function H.fs_create(files)
    local paths = {}
    for _, file in ipairs(files) do
        local file = H.path(file)
        local parent = vim.fs.dirname(file)
        vim.fn.mkdir(parent, "p")
        paths[#paths + 1] = file
        Util.write_file(paths[#paths], "")
    end
    return paths
end

function H.fs_rm(dir)
    vim.loop.fs_rmdir(H.path(dir))
end

function H.inline_inspect(root)
    return string.gsub(string.gsub(vim.inspect(root), "\n", " "), "%s+", " ")
end

return H
