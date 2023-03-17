local tblite_tbl = require("tblite.tbl")

local H = {}

function H.schema_with_id(schema)
    return vim.tbl_extend("force", {
        id = { type = "number", primary = true },
    }, schema or {})
end

function H.parsed_with_id(parsed)
    return vim.tbl_extend("force", {
        id = { name = "id", type = "number", primary = true, required = true },
    }, parsed or {})
end

function H.table_with_rows(rows)
    local tbl = tblite_tbl.new("", {
        id = { type = "number", primary = true },
        name = { type = "text", unique = true, required = true },
        age = { type = "integer", default = 0 },
        labels = { type = "table" },
    })
    tbl:insert(rows, true)
    return tbl
end

function H.without_id(rows)
    return vim.tbl_map(function(row)
        row.id = nil
        return row
    end, rows)
end

describe("json_tbl", function()
    describe("#parse_schema", function()
        local good_test_cases = {
            {
                desc = "primary",
                schema = { id = { type = "number", primary = true } },
                parsed = H.parsed_with_id(),
            },
            {
                desc = "primary-different-name",
                schema = { guid = { type = "string", primary = true } },
                parsed = { guid = { name = "guid", type = "string", primary = true, required = true } },
            },
            {
                desc = "primary-from-true",
                schema = { id = true },
                parsed = H.parsed_with_id(),
            },
            {
                desc = "primary-overrides-unique",
                schema = { id = { type = "number", primary = true, unique = true } },
                parsed = H.parsed_with_id(),
            },
            {
                desc = "named-field",
                schema = H.schema_with_id({ deedle = { type = "integer" } }),
                parsed = H.parsed_with_id({ deedle = { name = "deedle", type = "number" } }),
            },
            {
                desc = "named-field-from-type",
                schema = H.schema_with_id({ di = "number" }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "number" } }),
            },
            {
                desc = "sql-integer",
                schema = H.schema_with_id({ di = { type = "integer" } }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "number" } }),
            },
            {
                desc = "sql-text",
                schema = H.schema_with_id({ di = { type = "text" } }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "string" } }),
            },
            {
                desc = "string",
                schema = H.schema_with_id({ di = { type = "string" } }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "string" } }),
            },
            {
                desc = "table",
                schema = H.schema_with_id({ di = { type = "table" } }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "table" } }),
            },
            {
                desc = "required",
                schema = H.schema_with_id({ di = { type = "number", required = true } }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "number", required = true } }),
            },
            {
                desc = "unique",
                schema = H.schema_with_id({ di = { type = "number", unique = true } }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "number", unique = true } }),
            },
            {
                desc = "reference",
                schema = H.schema_with_id({ di = { type = "number", reference = "other.id" } }),
                parsed = H.parsed_with_id({
                    di = { name = "di", type = "number", reference = { tbl = "other", field = "id" } },
                }),
            },
            {
                desc = "default",
                schema = H.schema_with_id({ di = { type = "number", default = 0 } }),
                parsed = H.parsed_with_id({ di = { name = "di", type = "number", default = 0 } }),
            },
        }

        for _, tc in ipairs(good_test_cases) do
            it(("parses a %s schema"):format(tc.desc), function()
                assert.are.same(tc.parsed, tblite_tbl.parse_schema(tc.schema))
            end)
        end

        local bad_test_cases = {
            {
                desc = "empty",
                schema = {},
                error = "schema must have at least one primary field",
            },
            {
                desc = "missing-primary",
                schema = { id = { type = "number" } },
                error = "schema must have at least one primary field",
            },
            {
                desc = "duplicate-primary",
                schema = {
                    id = { type = "number", primary = true },
                    di = { type = "string", primary = true },
                },
                error = "found more than one primary field in schema",
            },
            {
                desc = "missing-type-on-primary-field",
                schema = { id = { primary = true } },
                error = "missing type for field 'id'",
            },
            {
                desc = "missing-type-on-field",
                schema = H.schema_with_id({ di = { required = true } }),
                error = "missing type for field 'di'",
            },
            {
                desc = "default-primary",
                schema = { id = { type = "number", primary = true, default = 0 } },
                error = "primary field 'id' cannot have a default value",
            },
            {
                desc = "default-unique",
                schema = H.schema_with_id({ di = { type = "number", unique = true, default = 0 } }),
                error = "unique field 'di' cannot have a default value",
            },
            {
                desc = "incorrect-default-type",
                schema = H.schema_with_id({ di = { type = "number", default = "nan" } }),
                error = "incorrect default value type for field 'di'",
            },
        }

        for _, tc in ipairs(bad_test_cases) do
            it(("fails to parse a %s schema"):format(tc.desc), function()
                -- stylua: ignore
                assert.error(function() tblite_tbl.parse_schema(tc.schema) end, tc.error)
            end)
        end
    end)

    describe("#validate", function()
        local test_cases = {
            {
                desc = "valid-empty",
                schema = H.schema_with_id(),
                input = {},
                valid = true,
            },
            {
                desc = "valid-number",
                schema = H.schema_with_id({ di = { type = "integer" } }),
                input = { di = 123 },
                valid = true,
            },
            {
                desc = "valid-string",
                schema = H.schema_with_id({ di = { type = "text" } }),
                input = { di = "yarrrr" },
                valid = true,
            },
            {
                desc = "valid-list",
                schema = H.schema_with_id({ di = { type = "table" } }),
                input = { di = { 1, 2, 3 } },
                valid = true,
            },
            {
                desc = "valid-table",
                schema = H.schema_with_id({ di = { type = "table" } }),
                input = { di = { a = 1, b = 2 } },
                valid = true,
            },
            {
                desc = "valid-required",
                schema = H.schema_with_id({ di = { type = "number", required = true } }),
                input = { di = 1 },
                valid = true,
            },
            {
                desc = "valid-not-required",
                schema = H.schema_with_id({ di = { type = "number" } }),
                input = {},
                valid = true,
            },
            {
                desc = "invalid-id",
                schema = H.schema_with_id(),
                input = { id = 123 },
                valid = false,
                reason = "row cannot include primary key 'id'",
            },
            {
                desc = "invalid-incorrect-type",
                schema = H.schema_with_id({ di = { type = "number" } }),
                input = { di = "zip-a-dee-doo-dah" },
                valid = false,
                reason = "field 'di' is of type 'string', expected 'number'",
            },
            {
                desc = "invalid-missing-required",
                schema = H.schema_with_id({
                    di = { type = "number", required = true },
                    ad = { type = "string" },
                }),
                input = { ad = "ba" },
                valid = false,
                reason = "field 'di' is required",
            },
            {
                desc = "invalid-extra-field",
                schema = H.schema_with_id({ di = { type = "number" } }),
                input = { a = 1, di = 4 },
                valid = false,
                reason = "field 'a' is not part of the schema",
            },
        }

        for _, tc in ipairs(test_cases) do
            it(("checks a %s row"):format(tc.desc), function()
                local ok, reason = tblite_tbl.new("", tc.schema):valid(tc.input)
                assert.equals(tc.valid, ok)
                assert.equals(tc.reason, reason)
            end)
        end
    end)

    describe("#unique", function()
        local test_cases = {
            {
                desc = "unique-row-empty-table",
                tbl = H.table_with_rows(),
                input = { name = "bob", age = 54 },
                unique = true,
            },
            {
                desc = "unique-row-seeded-table",
                tbl = H.table_with_rows({ { name = "rob", age = 35 } }),
                input = { name = "bob", age = 54 },
                unique = true,
            },
            {
                desc = "unique-name-same-age",
                tbl = H.table_with_rows({ { name = "rob", age = 54 } }),
                input = { name = "bob", age = 54 },
                unique = true,
            },
            {
                desc = "conflicting-name-different-age",
                tbl = H.table_with_rows({ { name = "bob", age = 35 } }),
                input = { name = "bob", age = 54 },
                unique = false,
            },
            {
                desc = "duplicate-row",
                tbl = H.table_with_rows({ { name = "bob", age = 54 } }),
                input = { name = "bob", age = 54 },
                unique = false,
            },
        }

        for _, tc in ipairs(test_cases) do
            it(("checks a %s input"):format(tc.desc), function()
                assert.equals(tc.unique, tc.tbl:unique(tc.input))
            end)
        end
    end)

    describe("#insert", function()
        local good_test_cases = {
            {
                desc = "nothing-nil",
                rows = nil,
                inserted = {},
            },
            {
                desc = "nothing-empty-table",
                rows = {},
                inserted = {},
            },
            {
                desc = "single-row",
                rows = { name = "bob", age = 54 },
                inserted = { { name = "bob", age = 54 } },
            },
            {
                desc = "multiple-rows",
                rows = {
                    { name = "bob", age = 54 },
                    { name = "rob", age = 55 },
                },
                inserted = {
                    { name = "bob", age = 54 },
                    { name = "rob", age = 55 },
                },
            },
            {
                desc = "single-row-default-field",
                rows = { name = "bob" },
                inserted = { { name = "bob", age = 0 } },
            },
        }

        for _, tc in ipairs(good_test_cases) do
            it(("inserts a %s row"):format(tc.desc), function()
                local tbl = H.table_with_rows()
                assert.are.same(tc.inserted, H.without_id(tbl:insert(tc.rows)))

                -- stylua: ignore
                local count = vim.tbl_count(tc.rows or {}) == 0 and 0
                    or #tc.rows == 0 and 1 -- single row
                    or #tc.rows

                assert.are.same(count, tbl:count())
                assert.are.same(count + 1, tbl:increment_id())
            end)
        end

        it("inserts a row with an id", function()
            local tbl = H.table_with_rows()
            local inserted = { { id = 1, name = "bob", age = 0 } }
            assert.are.same(inserted, tbl:insert({ name = "bob" }))
        end)

        it("does not insert anything when there is an invalid row", function()
            local tbl = H.table_with_rows()
            assert.error(function()
                tbl:insert({ { name = "valid-rob" }, { age = 54 } })
            end, "row is not valid '{ age = 54 }': field 'name' is required")
            assert.are.same(0, tbl:count())
        end)

        it("does not insert anything when there is a non-unique row", function()
            local tbl = H.table_with_rows({ name = "bob", age = 54 })
            assert.error(function()
                tbl:insert({ { name = "valid-rob" }, { name = "bob" } })
            end, "row is not unique '{ name = \"bob\" }'")
            assert.are.same(1, tbl:count())
        end)
    end)

    describe("#select", function()
        local tbl = H.table_with_rows({
            { name = "bob" },
            { name = "rob", age = 50 },
            { name = "cob", age = 50 },
            { name = "lob", age = 20, labels = { "a", "b", "b" } },
        })

        local test_cases = {
            {
                desc = "all-by-nil-spec",
                spec = nil,
                expected = {
                    { name = "bob", age = 0 },
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                    { name = "lob", age = 20, labels = { "a", "b", "b" } },
                },
            },
            {
                desc = "all-by-empty-table-spec",
                spec = {},
                expected = {
                    { name = "bob", age = 0 },
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                    { name = "lob", age = 20, labels = { "a", "b", "b" } },
                },
            },
            {
                desc = "value-by-where-primary",
                spec = { where = { id = 1 } },
                expected = { { name = "bob", age = 0 } },
            },
            {
                desc = "value-by-where-index",
                spec = { where = { name = "bob" } },
                expected = { { name = "bob", age = 0 } },
            },
            {
                desc = "values-by-where-field",
                spec = { where = { age = 50 } },
                expected = {
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "values-by-where-primarys",
                spec = { where = { id = { 1, 2 } } },
                expected = {
                    { name = "bob", age = 0 },
                    { name = "rob", age = 50 },
                },
            },
            {
                desc = "values-by-where-indexes",
                spec = { where = { name = { "bob", "cob" } } },
                expected = {
                    { name = "bob", age = 0 },
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "values-by-where-fields",
                spec = { where = { age = { 0, 50 } } },
                expected = {
                    { name = "bob", age = 0 },
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "value-by-contains",
                spec = { contains = { labels = "a" } },
                expected = {
                    { name = "lob", age = 20, labels = { "a", "b", "b" } },
                },
            },
        }

        for _, tc in ipairs(test_cases) do
            it(("looks for %s rows"):format(tc.desc), function()
                assert.are.same(tc.expected, H.without_id(tbl:select(tc.spec)))
            end)
        end
    end)

    describe("#delete", function()
        local good_test_cases = {
            {
                desc = "all-by-nil",
                where = {},
                after = {},
            },
            {
                desc = "all-by-empty-table",
                where = {},
                after = {},
            },
            {
                desc = "value-by-primary",
                where = { id = 1 },
                after = {
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "value-by-index",
                where = { name = "bob" },
                after = {
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "value-by-field",
                where = { age = 0 },
                after = {
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "value-by-fields",
                where = { name = "rob", age = 50 },
                after = {
                    { name = "bob", age = 0 },
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "values-by-primarys",
                where = { id = { 1, 2 } },
                after = {
                    { name = "cob", age = 50 },
                },
            },
            {
                desc = "values-by-indexes",
                where = { name = { "bob", "cob" } },
                after = {
                    { name = "rob", age = 50 },
                },
            },
            {
                desc = "values-by-fields",
                where = { age = { 0, 50 } },
                after = {},
            },
        }

        for _, tc in ipairs(good_test_cases) do
            it(("deletes %s rows"):format(tc.desc), function()
                local tbl = H.table_with_rows({
                    { name = "bob" },
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                })
                assert.is_true(tbl:delete(tc.where))
                assert.are.same(tc.after, H.without_id(tbl:select()))
            end)
        end

        local bad_test_cases = {
            {
                desc = "by-bad-primary",
                where = { id = 100 },
            },
            {
                desc = "by-bad-index",
                where = { name = "blah" },
            },
            {
                desc = "by-bad-field",
                where = { age = 100 },
            },
            {
                desc = "by-bad-primarys",
                where = { id = { 10, 11 } },
            },
            {
                desc = "by-bad-indexes",
                where = { name = { "not a name", "not another name" } },
            },
            {
                desc = "by-bad-fields",
                where = { age = { -1, 100 } },
            },
            {
                desc = "by-invalid-field",
                where = { water = "bottle" },
            },
        }

        for _, tc in ipairs(bad_test_cases) do
            it(("does not delete %s rows"):format(tc.desc), function()
                local tbl = H.table_with_rows({
                    { name = "bob" },
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                })
                local rows = tbl:select()
                -- assert.is_false(tbl:delete(tc.where))
                tbl:delete(tc.where)
                assert.are.same(rows, H.without_id(tbl:select()))
            end)
        end
    end)

    describe("#update", function()
        local good_test_cases = {
            {
                desc = "all",
                specs = { set = { age = 10 } },
                after = {
                    { name = "bob", age = 10 },
                    { name = "rob", age = 10 },
                    { name = "cob", age = 10 },
                },
            },
            {
                desc = "single-row",
                specs = { where = { id = 1 }, set = { age = 10 } },
                after = {
                    { name = "bob", age = 10 },
                },
            },
            {
                desc = "multiple-rows",
                specs = { where = { age = 50 }, set = { age = 10 } },
                after = {
                    { name = "rob", age = 10 },
                    { name = "cob", age = 10 },
                },
            },
            {
                desc = "unique-field",
                specs = { where = { id = 1 }, set = { name = "bobby" } },
                after = {
                    { name = "bobby", age = 0 },
                },
            },
            {
                desc = "multiple-fields",
                specs = { where = { id = 1 }, set = { name = "bobby", age = 2 } },
                after = {
                    { name = "bobby", age = 2 },
                },
            },
        }

        for _, tc in ipairs(good_test_cases) do
            it(("updates %s rows"):format(tc.desc), function()
                local tbl = H.table_with_rows({
                    { name = "bob" },
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                })
                local where = vim.tbl_extend("force", tc.specs.where or {}, tc.specs.set)
                assert.is_true(tbl:update(tc.specs))
                assert.are.same(tc.after, H.without_id(tbl:select({ where = where })))
            end)
        end

        local bad_test_cases = {
            {
                desc = "nil-spec",
                specs = nil,
                error = "update requires 'spec.set' to be present",
            },
            {
                desc = "empty-spec",
                specs = {},
                error = "update requires 'spec.set' to be present",
            },
            {
                desc = "primary-spec",
                specs = { set = { id = 10 } },
                error = "cannot update the primary key of a row",
            },
            {
                desc = "duplicate-unique-specs",
                specs = { where = { id = 1 }, set = { name = "rob" } },
                error = "cannot update indexed field 'name' with value 'rob', uniqueness violation",
            },
        }

        for _, tc in ipairs(bad_test_cases) do
            it(("does not update %s rows"):format(tc.desc), function()
                local tbl = H.table_with_rows({
                    { name = "bob" },
                    { name = "rob", age = 50 },
                    { name = "cob", age = 50 },
                })
                local rows = tbl:select()
                -- stylua: ignore
                assert.error(function() tbl:update(tc.specs) end, tc.error)
                assert.are.same(rows, H.without_id(tbl:select()))
            end)
        end
    end)
end)
