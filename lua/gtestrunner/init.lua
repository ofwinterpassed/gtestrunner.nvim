local M = {}

M.setup = function(opts)
	for key, value in pairs(opts) do
		M[key] = value
	end
	M.current_executable = M.bin_path .. '/' .. M.default_executable
end

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

M.base_dap_config = {
	type = 'cppdbg',
	request = 'launch',
	cwd = '${workspaceFolder}',
	terminal = 'integrated',
	runInTerminal = true,
	stopAtEntry = false,
	MIMode = 'gdb',
}

M.bin_path = './build'

M.default_executable = 'a.out'

M.current_executable = M.bin_path .. '/' .. M.default_executable

M.run_gtest_under_cursor = function()
	local language_tree = vim.treesitter.get_parser()
	local syntax_tree = language_tree:parse()[1]
	local lang = language_tree:lang()
	local root = syntax_tree:root()

	local query = vim.treesitter.query.parse(lang, gtestfuncquery)

	local buf = vim.api.nvim_get_current_buf()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))

	for _, captures, _, _ in query:iter_matches(root, buf, root:start(), root:end_(), {all=true}) do
		for _, tfnode in ipairs(captures[4]) do
			if vim.treesitter.is_in_node_range(tfnode, row - 1, col) then
				local param = '--gtest_filter=*'
				for _, node in ipairs(captures[2]) do
					param = param .. vim.treesitter.get_node_text(node, buf) .. '.'
				end
				for _, node in ipairs(captures[3]) do
					param = param .. vim.treesitter.get_node_text(node, buf) .. '*'
				end
				local config = M.base_dap_config
				config.name = config.type .. ' ' .. config.MIMode .. ' ' .. M.current_executable .. ' ' .. param
				config.program = M.current_executable
				config.args = { param }
				print(config.program .. ' ' .. param)
				require('dap').run(config)
				return
			end
		end
	end
	--print('Not in a test')
end

M.run_gtestsuite_under_cursor = function()
	local language_tree = vim.treesitter.get_parser()
	local syntax_tree = language_tree:parse()[1]
	local lang = language_tree:lang()
	local root = syntax_tree:root()

	local query = vim.treesitter.query.parse(lang, gtestfuncquery)

	local buf = vim.api.nvim_get_current_buf()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))

	for _, captures, _, _ in query:iter_matches(root, buf, root:start(), root:end_(), {all=true}) do
		for _, tfnode in ipairs(captures[4]) do
			if vim.treesitter.is_in_node_range(tfnode, row - 1, col) then
				local param = '--gtest_filter=*'
				for _, node in ipairs(captures[2]) do
					param = param .. vim.treesitter.get_node_text(node, buf) .. '*'
				end
				local config = M.base_dap_config
				config.name = config.type .. ' ' .. config.MIMode .. ' ' .. M.current_executable .. ' ' .. param
				config.program = M.current_executable
				config.args = { param }
				print(config.program .. ' ' .. param)
				require('dap').run(config)
				return
			end
		end
	end
	print('Not in a test')
end

M.set_debug_executable = function()
	local actions = require('telescope.actions')
	local action_state = require('telescope.actions.state')

	require('telescope.builtin').find_files {
		prompt_title = 'Set executable: ',
		cwd = M.bin_path,
		previewer = false,
		find_command = { "fd", "--type", "x" },
		attach_mappings = function(
			prompt_bufnr, _)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				print(selection[1])
				M.current_executable = M.bin_path .. '/' .. selection[1]
			end)
			return true
		end, }
end

return M
