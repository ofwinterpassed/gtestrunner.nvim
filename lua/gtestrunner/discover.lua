local M = {}

local gtestfuncquery = [[
(function_definition
		declarator: (function_declarator
				declarator: (identifier) @gtestfunc (#match? @gtestfunc "^TEST(_[PF])?$")
				parameters: (parameter_list
						.
						(parameter_declaration
								type: (type_identifier) @gtestsuite)
						.
						(parameter_declaration
								type: (type_identifier) @gtestname)
				)
		)
) @gtest
]]

local queries = {}

local get_query = function(lang)
	if queries[lang] == nil then
		queries[lang] = vim.treesitter.query.parse(lang, gtestfuncquery)
	end
	return queries[lang]
end

-- iter_matches returns a list of nodes per capture on newer neovim versions
local first_node = function(nodes)
	if type(nodes) == 'table' then
		return nodes[1]
	end
	return nodes
end

-- Returns the tests in the buffer ordered by line. Each test is
-- { id = 'Suite.Name', suite, name, start_row, end_row } with 0-based rows.
M.tests = function(buf)
	local ok, parser = pcall(vim.treesitter.get_parser, buf, 'cpp')
	if not ok or parser == nil then
		return {}
	end
	local root = parser:parse()[1]:root()
	local query = get_query(parser:lang())

	local tests = {}
	for _, match in query:iter_matches(root, buf, 0, -1, { all = true }) do
		local test = {}
		for id, nodes in pairs(match) do
			local capture = query.captures[id]
			local node = first_node(nodes)
			if capture == 'gtest' then
				local start_row, _, end_row = node:range()
				test.start_row = start_row
				test.end_row = end_row
			elseif capture == 'gtestsuite' then
				test.suite = vim.treesitter.get_node_text(node, buf)
			elseif capture == 'gtestname' then
				test.name = vim.treesitter.get_node_text(node, buf)
			end
		end
		if test.suite and test.name then
			test.id = test.suite .. '.' .. test.name
			table.insert(tests, test)
		end
	end
	table.sort(tests, function(a, b) return a.start_row < b.start_row end)
	return tests
end

M.test_at_row = function(tests, row)
	for _, test in ipairs(tests) do
		if test.start_row <= row and row <= test.end_row then
			return test
		end
	end
	return nil
end

-- Groups tests by suite in order of first appearance: { { name, tests }, ... }
M.suites = function(tests)
	local suites = {}
	local by_name = {}
	for _, test in ipairs(tests) do
		local suite = by_name[test.suite]
		if suite == nil then
			suite = { name = test.suite, tests = {} }
			by_name[test.suite] = suite
			table.insert(suites, suite)
		end
		table.insert(suite.tests, test)
	end
	return suites
end

return M
