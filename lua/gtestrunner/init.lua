local discover = require('gtestrunner.discover')
local results = require('gtestrunner.results')
local runner = require('gtestrunner.runner')
local marks = require('gtestrunner.marks')
local panel = require('gtestrunner.panel')
local output = require('gtestrunner.output')

local M = {}

M.base_dap_config = {
	type = 'cppdbg',
	request = 'launch',
	cwd = '${workspaceFolder}',
	terminal = 'integrated',
	runInTerminal = true,
	stopAtEntry = false,
	MIMode = 'gdb',
}

M.picker = 'mini'

M.bin_path = './build'

M.default_executable = 'a.out'

M.current_executable = M.bin_path .. '/' .. M.default_executable

M.panel = {
	-- open the panel when entering a file with tests
	auto_open = true,
	width = 50,
	max_failure_lines = 10,
	-- show the build output in the lower half of the panel while building
	show_build_output = true,
}

M.signs = true

M.virtual_lines = true

-- function(buf) returning the test executable for the tests in a buffer, or nil to use
-- current_executable
M.resolve_executable = nil

-- function(request, done) that builds the test executable before the tests are run, with
-- request = { executable, buf, output = function(lines) }. It must call done(ok) when finished
-- and can return a function that cancels the build.
M.build = nil

-- write modified buffers before building
M.save_before_build = true

M.icons = {
	unknown = '○',
	building = '◌',
	running = '●',
	passed = '✓',
	failed = '✗',
	skipped = '⊘',
	-- added to the icon of tests that were run with an older build of the executable
	stale = '*',
}

-- options that are merged with the defaults instead of replacing them
local nested_options = { panel = true, icons = true }

-- attached buffer -> { tests }
local buffers = {}
local refresh_ticks = {}

-- executable picked with set_debug_executable, used instead of resolve_executable
local executable_override = nil

-- build in progress: { ids, cancel = function or nil }
local build_state = nil

M.executable_for = function(buf)
	if executable_override then
		return executable_override
	end
	if M.resolve_executable and buf and vim.api.nvim_buf_is_valid(buf) then
		local executable = M.resolve_executable(buf)
		if executable then
			return executable
		end
	end
	return M.current_executable
end

M.tests_for = function(buf)
	local state = buffers[buf]
	return state and state.tests or {}
end

local render_marks = function(buf)
	local state = buffers[buf]
	if state ~= nil then
		marks.render(buf, state.tests, M, results.build_id(M.executable_for(buf)))
	end
end

local render_all = function()
	for buf in pairs(buffers) do
		render_marks(buf)
	end
	panel.render()
end

results.on_change(render_all)
-- progress and elapsed time in the panel
output.on_change(panel.render)

local on_enter = function(buf)
	if #M.tests_for(buf) == 0 then
		return
	end
	-- the executable can have been rebuilt outside of nvim
	render_marks(buf)
	if panel.source() ~= buf then
		panel.set_source(buf)
	else
		panel.render()
	end
	if M.panel.auto_open and not panel.is_open() and not panel.closed_by_user then
		panel.open()
	end
end

local refresh = function(buf)
	local state = buffers[buf]
	if state == nil or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	state.tests = discover.tests(buf)
	render_marks(buf)
	if panel.source() == buf then
		panel.render()
	end
end

local schedule_refresh = function(buf)
	local tick = (refresh_ticks[buf] or 0) + 1
	refresh_ticks[buf] = tick
	vim.defer_fn(function()
		if refresh_ticks[buf] == tick then
			refresh(buf)
		end
	end, 200)
end

local attach = function(buf, group)
	if buffers[buf] ~= nil then
		-- reloaded, e.g. :e after :bd which drops the marks
		refresh(buf)
		return
	end
	buffers[buf] = { tests = {} }
	vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave', 'BufWritePost' }, {
		group = group,
		buffer = buf,
		callback = function() schedule_refresh(buf) end,
	})
	vim.api.nvim_create_autocmd('BufWipeout', {
		group = group,
		buffer = buf,
		callback = function()
			buffers[buf] = nil
			refresh_ticks[buf] = nil
		end,
	})
	refresh(buf)
	if buf == vim.api.nvim_get_current_buf() then
		on_enter(buf)
	end
end

local define_highlights = function()
	local links = {
		GtestrunnerUnknown = 'Comment',
		GtestrunnerBuilding = 'DiagnosticHint',
		GtestrunnerRunning = 'DiagnosticWarn',
		GtestrunnerPassed = 'DiagnosticOk',
		GtestrunnerFailed = 'DiagnosticError',
		GtestrunnerSkipped = 'DiagnosticInfo',
		GtestrunnerTitle = 'Title',
		GtestrunnerSuite = 'Identifier',
		GtestrunnerFailureText = 'DiagnosticVirtualTextError',
		GtestrunnerStale = 'Comment',
	}
	for group, link in pairs(links) do
		vim.api.nvim_set_hl(0, group, { link = link, default = true })
	end
end

M.setup = function(opts)
	for key, value in pairs(opts or {}) do
		if nested_options[key] and type(value) == 'table' then
			M[key] = vim.tbl_deep_extend('force', M[key], value)
		else
			M[key] = value
		end
	end
	M.current_executable = M.bin_path .. '/' .. M.default_executable

	define_highlights()

	local group = vim.api.nvim_create_augroup('gtestrunner', { clear = true })
	buffers = {}
	vim.api.nvim_create_autocmd('FileType', {
		group = group,
		pattern = 'cpp',
		callback = function(args) attach(args.buf, group) end,
	})
	vim.api.nvim_create_autocmd('BufEnter', {
		group = group,
		callback = function(args) on_enter(args.buf) end,
	})
	vim.api.nvim_create_autocmd('WinClosed', {
		group = group,
		callback = function(args) panel.on_win_closed(tonumber(args.match)) end,
	})
	vim.api.nvim_create_autocmd('QuitPre', {
		group = group,
		callback = function() panel.close_if_last() end,
	})
	vim.api.nvim_create_autocmd('ColorScheme', {
		group = group,
		callback = define_highlights,
	})

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'cpp' then
			attach(buf, group)
		end
	end
end

-- Matches the test and its parameterized instances, e.g. Instance/Suite.Name/0
local test_filter = function(test)
	local id = test.id
	return table.concat({ id, id .. '/*', '*/' .. id, '*/' .. id .. '/*' }, ':')
end

local suite_filter = function(suite)
	return suite .. '.*:*/' .. suite .. '.*'
end

local resolve_cwd = function()
	local cwd = M.base_dap_config.cwd or '${workspaceFolder}'
	return (cwd:gsub('%${workspaceFolder}', function() return vim.fn.getcwd() end))
end

local launch = function(executable, filter, ids, debug)
	if vim.uv.fs_stat(executable) == nil then
		results.set_status(ids, 'unknown')
		vim.notify('gtestrunner: test executable not found: ' .. executable ..
			'\nPick one with set_debug_executable()', vim.log.levels.ERROR)
		return
	end
	local request = {
		-- absolute, the tests may run in another directory than the current one
		executable = vim.fn.fnamemodify(executable, ':p'),
		build_id = results.build_id(executable),
		filter = filter,
		ids = ids,
	}
	if debug then
		request.dap_config = M.base_dap_config
		runner.debug(request)
	else
		request.cwd = resolve_cwd()
		runner.run(request)
	end
end

local start = function(filter, ids, debug, buf)
	if runner.is_running() or build_state ~= nil then
		vim.notify('gtestrunner: tests are already running', vim.log.levels.WARN)
		return
	end
	local executable = M.executable_for(buf)
	output.clear()
	if M.build == nil then
		launch(executable, filter, ids, debug)
		return
	end

	if M.save_before_build then
		vim.cmd('silent! wall')
	end
	results.set_status(ids, 'building')
	output.set_phase('building')
	if M.panel.show_build_output then
		panel.show_output()
	end
	local state = { ids = ids }
	build_state = state
	local request = {
		executable = executable,
		buf = buf,
		output = output.append,
	}
	local cancel = M.build(request, function(ok)
		vim.schedule(function()
			-- cancelled, or replaced by a newer build
			if build_state ~= state then
				return
			end
			build_state = nil
			output.set_phase(nil)
			if ok then
				panel.hide_output()
				-- resolved again, the build can create or move the executable
				launch(M.executable_for(buf), filter, ids, debug)
			else
				-- the output stays in the panel to show what failed
				results.set_status(ids, 'unknown')
				vim.notify('gtestrunner: building the tests failed, see show_output()', vim.log.levels.ERROR)
			end
		end)
	end)
	if type(cancel) == 'function' then
		state.cancel = cancel
	end
end

M.run_tests = function(tests, debug, buf)
	if #tests == 0 then
		vim.notify('gtestrunner: no tests to run', vim.log.levels.WARN)
		return
	end
	local filters, ids = {}, {}
	for _, test in ipairs(tests) do
		table.insert(filters, test_filter(test))
		table.insert(ids, test.id)
	end
	start(table.concat(filters, ':'), ids, debug, buf or vim.api.nvim_get_current_buf())
end

-- Runs the whole suite, `tests` are the tests of the suite that are shown as running
M.run_suite_tests = function(suite, tests, debug, buf)
	local ids = {}
	for _, test in ipairs(tests) do
		table.insert(ids, test.id)
	end
	start(suite_filter(suite), ids, debug, buf or vim.api.nvim_get_current_buf())
end

local test_under_cursor = function()
	local buf = vim.api.nvim_get_current_buf()
	local tests = M.tests_for(buf)
	local test = discover.test_at_row(tests, vim.api.nvim_win_get_cursor(0)[1] - 1)
	if test == nil then
		vim.notify('gtestrunner: the cursor is not in a test', vim.log.levels.WARN)
	end
	return test, tests
end

local run_test_under_cursor = function(debug)
	local test = test_under_cursor()
	if test then
		M.run_tests({ test }, debug)
	end
end

local run_suite_under_cursor = function(debug)
	local test, tests = test_under_cursor()
	if test then
		local suite_tests = vim.tbl_filter(function(t) return t.suite == test.suite end, tests)
		M.run_suite_tests(test.suite, suite_tests, debug)
	end
end

M.run_test = function() run_test_under_cursor(false) end
M.debug_test = function() run_test_under_cursor(true) end
M.run_suite = function() run_suite_under_cursor(false) end
M.debug_suite = function() run_suite_under_cursor(true) end
M.run_file = function() M.run_tests(M.tests_for(vim.api.nvim_get_current_buf()), false) end
M.debug_file = function() M.run_tests(M.tests_for(vim.api.nvim_get_current_buf()), true) end

-- Previous names of debug_test and debug_suite
M.run_gtest_under_cursor = M.debug_test
M.run_gtestsuite_under_cursor = M.debug_suite

-- Cancels the build or the run without the debugger
M.cancel = function()
	local state = build_state
	if state ~= nil then
		build_state = nil
		if state.cancel then
			state.cancel()
		end
		output.append({ '', 'Build cancelled' })
		output.set_phase(nil)
		results.set_status(state.ids, 'unknown')
	end
	runner.cancel()
end

M.clear_results = results.clear
M.open_panel = panel.open
M.close_panel = panel.close
M.toggle_panel = panel.toggle

-- Shows the live output of the latest build and run without the debugger in a split
M.show_output = output.show

local set_executable = function(path)
	print(path)
	M.current_executable = M.bin_path .. '/' .. path
	-- a picked executable is used for all tests, also when resolve_executable is set
	executable_override = M.current_executable
	-- results belong to the previous executable
	results.clear()
end

-- Stops using the executable picked with set_debug_executable
M.reset_executable = function()
	executable_override = nil
	results.clear()
end

local pickers = {}

pickers.mini = function()
	require('mini.pick').builtin.cli({ command = { 'fd', '--type', 'x' } }, {
		source = {
			name = 'Set executable',
			cwd = M.bin_path,
			choose = function(item)
				set_executable(item)
			end,
		},
	})
end

pickers.snacks = function()
	require('snacks').picker.files({
		title = 'Set executable',
		cwd = M.bin_path,
		cmd = 'fd',
		args = { '--type', 'x' },
		confirm = function(picker, item)
			picker:close()
			if item then
				set_executable(item.file)
			end
		end,
	})
end

pickers.telescope = function()
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
				set_executable(selection[1])
			end)
			return true
		end, }
end

M.set_debug_executable = function()
	local picker = pickers[M.picker]
	if picker == nil then
		vim.notify('gtestrunner: unknown picker "' .. tostring(M.picker) .. '", expected mini, snacks or telescope',
			vim.log.levels.ERROR)
		return
	end
	picker()
end

return M
