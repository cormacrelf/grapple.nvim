local grapple = require("grapple")
local settings = require("grapple.settings")
local g_state = require("grapple.state")
local g_scope = require("grapple.scope")
local g_tags = require("grapple.tags")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local t_utils = require("telescope.utils")
local Path = require("plenary.path")
local strings = require("plenary.strings")
local entry_display = require("telescope.pickers.entry_display")
local make_entry = require("telescope.make_entry")

local exports = {}

---@private
---@class Grapple.BufTag
---@field key Grapple.TagKey
---@field file_path Grapple.FilePath
---@field cursor Grapple.Cursor
---@field bufnr number?
--
---@private
---@class Grapple.TelescopeTagEntry
---@field value Grapple.BufTag
---@field display string|function
---@field ordinal string
---@field display_path string
---@field bufnr number?
---@field indicator string
---@field filename string
---@field lnum number

---@param scope Grapple.Scope
local function tag_entry_maker(opts, scope)
   local scope_path = g_scope.scope_path(scope)

   local disable_devicons = opts.disable_devicons

   local icon_width = 0
   if not disable_devicons then
      local icon, _ = t_utils.get_devicons("fname", disable_devicons)
      icon_width = strings.strdisplaywidth(icon)
   end

   local segments = {
      grapple_key = { width = opts.grapple_key_width + 2 }, -- for the []
      indicator = { width = 4 },
      icon = { width = icon_width },
      path = { remaining = true },
   }
   local displayer = entry_display.create({
      separator = " ",
      items = { segments.grapple_key, segments.indicator, segments.icon, segments.path },
   })

   ---@param entry Grapple.TelescopeTagEntry
   local function make_display(entry)
      local tag = entry.value
      local icon, hl_group = t_utils.get_devicons(entry.filename, disable_devicons)

      return displayer({
         { "[" .. tag.key .. "]", "TelescopeResultsNumber" },
         { entry.indicator, "TelescopeResultsComment" },
         { icon, hl_group },
         entry.display_path .. ":" .. entry.lnum,
      })
   end

   ---@param tag Grapple.BufTag
   return function(tag)
      local bufnr = tag.bufnr

      local lnum = tag.cursor and tag.cursor[1] or 1
      local indicator = "    "

      if bufnr ~= nil then
         ---@diagnostic disable-next-line: param-type-mismatch
         local bufinfo = vim.fn.getbufinfo(bufnr)[1]
         if bufinfo.listed == 1 and bufinfo.loaded == 1 then
            ---@diagnostic disable-next-line: param-type-mismatch
            local flag = tag.bufnr == vim.fn.bufnr("") and "%" or (tag.bufnr == vim.fn.bufnr("#") and "#" or " ")

            local hidden = bufinfo.hidden == 1 and "h" or "a"
            local readonly = vim.api.nvim_buf_get_option(bufnr, "readonly") and "=" or " "
            local changed = bufinfo.changed == 1 and "+" or " "
            indicator = flag .. hidden .. readonly .. changed

            local line_count = vim.api.nvim_buf_line_count(bufnr)
            -- account for potentially stale lnum as getbufinfo might not be updated or from resuming buffers picker
            lnum = bufinfo.lnum ~= 0 and math.max(math.min(bufinfo.lnum, line_count), 1) or 1
         end
      end

      local file_path = Path:new(tag.file_path)
      if vim.fn.isdirectory(scope_path) == 1 then
         file_path = file_path:make_relative(scope_path)
      end
      local display_path = tostring(file_path)

      return make_entry.set_default_entry_mt({
         value = tag,
         display = make_display,
         ordinal = tostring(tag.key) .. ":" .. display_path,

         display_path = display_path,

         bufnr = bufnr,
         indicator = indicator,
         filename = tag.file_path,
         lnum = lnum,
         col = tag.cursor and (tag.cursor[2] + 1) or 1,
      })
   end
end

---@diagnostic disable-next-line: unused-local
local function select_tag(prompt_bufnr, _map)
   actions.select_default:replace(function()
      actions.close(prompt_bufnr)
      local selection = action_state.get_selected_entry()
      grapple.select(selection.value)
   end)
   return true
end

local function filter_map(tbl, fn)
   local results = {}
   for _, tag in ipairs(tbl) do
      local x = fn(tag)
      if x ~= nil then
         table.insert(results, x)
      end
   end
   return results
end

function exports.tags(opts)
   local scope = g_state.ensure_loaded(settings.scope)
   local all_tags = g_tags.full_tags(scope)
   local tags = filter_map(all_tags, function(tag)
      ---@diagnostic disable-next-line: param-type-mismatch
      local bufnr = vim.fn.bufnr(tag.file_path)
      if opts.only_loaded_buffers and bufnr == -1 then
         return nil
      end
      tag = vim.tbl_extend("force", tag, {})
      if bufnr ~= -1 then
         if opts.only_loaded_buffers and 1 ~= vim.fn.buflisted(bufnr) then
            return nil
         end
         if opts.ignore_current_buffer and bufnr == vim.api.nvim_get_current_buf() then
            return nil
         end
         tag.bufnr = bufnr
      end
      return tag
   end)

   if not next(tags) then
      return
   end

   local all_keys = filter_map(tags, function(tag)
      return tag.key
   end)
   opts.grapple_key_width = 0
   if #all_keys > 0 then
      opts.grapple_key_width = math.max(unpack(all_keys))
   end

   return pickers
      .new(opts, {
         prompt_title = "grapple tags in scope " .. scope,
         finder = finders.new_table({ results = tags, entry_maker = tag_entry_maker(opts, scope) }),
         sorter = conf.file_sorter(opts),
         attach_mappings = select_tag,
         previewer = conf.grep_previewer(opts),
      })
      :find()
end

return require("telescope").register_extension({
   exports = exports,
})
