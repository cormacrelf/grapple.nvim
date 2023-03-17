local Util = require("grapple.util")

---@class tblite.Table
---@field name string
---@field schema tblite.Schema
---@field last_id integer
---@field index table<tblite.FieldName, string[]>
---@field primary string
---@field entries table
local Table = {}
Table.__index = Table

---@param tbl_name string
---@param schema tblite.Schema
---@return tblite.Table
function Table.new(tbl_name, schema)
    local tbl = {
        name = tbl_name,
        schema = Table.parse_schema(schema),
        last_id = 0,
        index = {},
        primary = nil,
        entries = {},
    }

    setmetatable(tbl, Table)
    tbl:setup_primary()
    tbl:clear()

    return tbl
end

---@alias tblite.FieldName string

---@enum tblite.FieldType
local FIELD_TYPES = {
    number = "number",
    integer = "number",
    string = "string",
    text = "string",
    table = "table",
}

---@class tblite.FieldAttributes
---@field name tblite.FieldName
---@field type tblite.FieldType
---@field primary boolean mutually exclusive with 'unique'
---@field unique boolean mutually exclusive with 'primary'
---@field required boolean
---@field default? any
---@field reference? { tbl: string, field: tblite.FieldName }

---@alias tblite.Schema table<tblite.FieldName, tblite.FieldAttributes>

---@param input_schema table<tblite.FieldName, tblite.FieldAttributes | tblite.FieldType | boolean>
---@return tblite.Schema parsed_schema
function Table.parse_schema(input_schema)
    local parsed_schema = {}
    local primary_field = nil

    local function parse_reference(reference)
        local parts = vim.split(reference, ".", { plain = true })
        return { tbl = parts[1], field = parts[2] }
    end

    local function parse_field(name, attributes)
        -- TODO: allow attributes of the form:
        -- attributes = true (for primary key)
        -- attributes = "number" (for basic types)
        if attributes == true then
            attributes = { type = "number", primary = true, required = true }
        elseif type(attributes) ~= "table" then
            attributes = { type = attributes }
        end

        return {
            name = name,
            type = FIELD_TYPES[attributes.type],
            primary = attributes.primary,
            unique = not attributes.primary and attributes.unique or nil,
            required = attributes.required or attributes.primary or nil,
            default = attributes.default or nil,
            reference = attributes.reference and parse_reference(attributes.reference) or nil,
        }
    end

    ---@param attributes tblite.FieldAttributes
    local function validate_field(attributes)
        if not attributes.name then
            error("field name must be a string")
        end
        if not attributes.type then
            error(("missing type for field '%s'"):format(attributes.name))
        end
        if attributes.default and type(attributes.default) ~= attributes.type then
            error(("incorrect default value type for field '%s'"):format(attributes.name))
        end
        if attributes.primary and primary_field then
            error("found more than one primary field in schema")
        end
        if attributes.primary and attributes.default then
            error(("primary field '%s' cannot have a default value"):format(attributes.name))
        end
        if attributes.unique and attributes.default then
            error(("unique field '%s' cannot have a default value"):format(attributes.name))
        end
    end

    for name, attributes in pairs(input_schema) do
        local parsed = parse_field(name, attributes)
        validate_field(parsed)
        primary_field = parsed.primary and parsed.name or primary_field
        parsed_schema[parsed.name] = parsed
    end

    if not primary_field then
        error("schema must have at least one primary field")
    end

    return parsed_schema
end

function Table:clear()
    self.entries = {}
    self:reset_indices()
    return true
end

function Table:reset_indices()
    for _, field in pairs(self.schema) do
        if field.unique then
            self.index[field.name] = {}
        end
    end
end

function Table:setup_primary()
    for _, field in pairs(self.schema) do
        if field.primary then
            self.primary = field.name
        end
    end
end

---@return integer
function Table:increment_id()
    self.last_id = self.last_id + 1
    return self.last_id
end

-- function Table:schema(schema) end

function Table:count()
    return vim.tbl_count(self.entries)
end

---@param row any
---@return boolean valid
---@return string | nil reason
function Table:valid(row)
    if row[self.primary] then
        return false, ("row cannot include primary key '%s'"):format(self.primary)
    end

    for _, field in pairs(self.schema) do
        if row[field.name] then
            if type(row[field.name]) ~= field.type then
                return false,
                    ("field '%s' is of type '%s', expected '%s'"):format(field.name, type(row[field.name]), field.type)
            end
        else
            if field.required and not field.primary then
                return false, ("field '%s' is required"):format(field.name)
            end
        end
    end

    for name, _ in pairs(row) do
        if not self.schema[name] then
            return false, ("field '%s' is not part of the schema"):format(name)
        end
    end

    return true
end

---@param row any
---@return boolean unique
function Table:unique(row)
    for field_name, value in pairs(row) do
        if self.index[field_name] and self.index[field_name][value] then
            return false
        end
    end
    return true
end

---@param rows any[]
---@return any[] inserted_rows
function Table:insert(rows)
    if vim.tbl_isempty(rows or {}) then
        return {}
    end
    if #rows == 0 then
        rows = { rows }
    end

    local new_rows = {}

    for _, row in ipairs(vim.deepcopy(rows)) do
        local valid, reason = self:valid(row)
        if not valid then
            error(("row is not valid '%s': %s"):format(Util.inline_inspect(row), reason))
        end
        if not self:unique(row) then
            error(("row is not unique '%s'"):format(Util.inline_inspect(row)))
        end

        row[self.primary] = self:increment_id()

        for _, field in pairs(self.schema) do
            if self.schema[field.name].default and not row[field.name] then
                row[field.name] = self.schema[field.name].default
            end
            if self.schema[field.name].unique and row[field.name] then
                self.index[field.name][row[field.name]] = row[self.primary]
            end
        end

        table.insert(new_rows, row)
    end

    for _, new_row in ipairs(new_rows) do
        self.entries[new_row[self.primary]] = new_row
    end

    return new_rows
end

---@param spec { where?: table, contains?: table }
---@return any[]
function Table:select(spec)
    if vim.tbl_isempty(spec or {}) then
        return vim.tbl_values(self.entries)
    end

    -- Select by primary key
    if spec.where and spec.where[self.primary] then
        local ids = spec.where[self.primary]
        if type(ids) == "table" then
            return vim.tbl_map(function(id)
                return self.entries[id] ~= nil and self.entries[id] or nil
            end, ids)
        else
            return { self.entries[ids] }
        end
    end

    -- Select by unique value index
    for field, value in pairs(spec.where or {}) do
        if self.index[field] then
            if type(value) == "table" then
                return vim.tbl_map(function(v)
                    local id = self.index[field][v]
                    return self.entries[id]
                end, value)
            else
                local id = self.index[field][value]
                return { self.entries[id] }
            end
        end
    end

    -- Select by brute force lookup
    return vim.tbl_filter(function(row)
        for field, value in pairs(spec.where or {}) do
            if type(value) == "table" then
                return vim.tbl_contains(value, row[field])
            elseif row[field] and row[field] == value then
                return true
            end
        end

        for field, value in pairs(spec.contains or {}) do
            if row[field] and self.schema[field].type == "table" then
                return vim.tbl_contains(row[field], value)
            end
        end

        return false
    end, vim.tbl_values(self.entries))
end

---Compatibility: alias of 'tblite.Table.select'
---@param spec { where?: table, contains?: table }
---@return any[]
function Table:get(spec)
    return self:select(spec)
end

---@param where table?
---@return boolean
function Table:delete(where)
    if vim.tbl_isempty(where or {}) then
        return self:clear()
    end

    local function delete_row(row)
        for field, value in pairs(row) do
            if self.index[field] then
                self.index[field][value] = nil
            end
        end
        self.entries[row[self.primary]] = nil
    end

    local rows = self:select({ where = where })
    for _, row in ipairs(rows) do
        delete_row(row)
    end

    return not vim.tbl_isempty(rows)
end

---Compatibility: alias of 'tblite.Table.delete'
---@param where table?
---@return boolean
function Table:remove(where)
    return self:delete(where)
end

---@param specs { where?: table, set: table }
---@return boolean
function Table:update(specs)
    if not specs or not specs.set then
        error("update requires 'spec.set' to be present")
    end
    if specs.set[self.primary] then
        error("cannot update the primary key of a row")
    end

    local function update_row(row, set)
        for field, value in pairs(set) do
            -- stylua: ignore
            if self.index[field]
                and self.index[field][value]
                and self.index[field][value] ~= row[self.primary]
            then
                error(("cannot update indexed field '%s' with value '%s', uniqueness violation"):format(field, value))
            end
        end
        self.entries[row[self.primary]] = vim.tbl_extend("force", row, set)
    end

    local rows = self:select({ where = specs.where })
    for _, row in ipairs(rows) do
        update_row(row, specs.set)
    end

    return not vim.tbl_isempty(rows)
end

function Table:drop()
    return self:clear()
end

function Table:empty()
    return vim.tbl_isempty(self.entries)
end

-- luacheck: ignore
function Table:exists()
    return true
end

-- function Table:replace(rows) end
-- function Table:set_db(db) end
-- function Table:each(func, query) end
-- function Table:map(func, query) end
-- function Table:sort(query, transform, comp) end

return Table
