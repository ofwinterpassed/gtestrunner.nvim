local results = require('gtestrunner.results')
local discover = require('gtestrunner.discover')
local marks = require('gtestrunner.marks')

local M = {}

local ns = vim.api.nvim_create_namespace('gtestrunner_panel')

local buf = nil
local win = nil
-- buffer whose tests are shown
local source = nil
-- panel line (1-based) -> { suite = suite } or { test = test }
local items = {}
-- set when the user closes the panel, stops it from opening automatically again
M.closed_by_user = false

local gtestrunner = function()
	return require('gtestrunner')
end

M.is_open = function()
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

M.source = function()
	return source
end

M.set_source = function(source_buf)
	source = source_buf
	M.render()
end

local item_under_cursor = function()
	if not M.is_open() then
		return nil
	end
	return items[vim.api.nvim_win_get_cursor(win)[1]]
end

M.jump = function()
	local item = item_under_cursor()
	if item == nil or source == nil or not vim.api.nvim_buf_is_valid(source) then
		return
	end
	local test = item.test or item.suite.tests[1]
	local target
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if w ~= win and vim.api.nvim_win_get_buf(w) == source then
			target = w
			break
		end
	end
	if target == nil then
		vim.cmd('wincmd p')
		target = vim.api.nvim_get_current_win()
		if target == win then
			return
		end
		vim.api.nvim_win_set_buf(target, source)
	end
	vim.api.nvim_set_current_win(target)
	-- rows can be stale until the buffer is parsed again after an edit
	local row = math.min(test.start_row + 1, vim.api.nvim_buf_line_count(source))
	vim.api.nvim_win_set_cursor(target, { row, 0 })
end

local run_item = function(debug)
	local item = item_under_cursor()
	if item == nil then
		return
	end
	if item.test then
		gtestrunner().run_tests({ item.test }, debug, source)
	else
		gtestrunner().run_suite_tests(item.suite.name, item.suite.tests, debug, source)
	end
end

local run_all = function(debug)
	if source ~= nil then
		gtestrunner().run_tests(gtestrunner().tests_for(source), debug, source)
	end
end

local create_buf = function()
	buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = 'gtestrunner'
	vim.bo[buf].modifiable = false
	pcall(vim.api.nvim_buf_set_name, buf, 'gtestrunner')

	local map = function(keys, func, desc)
		vim.keymap.set('n', keys, func, { buffer = buf, nowait = true, silent = true, desc = desc })
	end
	map('<CR>', M.jump, 'Jump to test')
	map('r', function() run_item(false) end, 'Run test or suite')
	map('d', function() run_item(true) end, 'Debug test or suite')
	map('R', function() run_all(false) end, 'Run all tests in file')
	map('D', function() run_all(true) end, 'Debug all tests in file')
	map('o', function() gtestrunner().show_output() end, 'Show output')
	map('x', function() gtestrunner().cancel() end, 'Cancel run')
	map('q', M.close, 'Close panel')
end

local add_line = function(lines, highlights, text, item, hl_ranges)
	table.insert(lines, text)
	items[#lines] = item
	for _, range in ipairs(hl_ranges or {}) do
		table.insert(highlights, { #lines - 1, range[1], range[2], range[3] })
	end
end

M.render = function()
	if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local config = gtestrunner()
	local icons = config.icons
	local lines, highlights = {}, {}
	items = {}

	local source_name = source and vim.api.nvim_buf_is_valid(source) and vim.api.nvim_buf_get_name(source) or ''
	local title = source_name ~= '' and vim.fn.fnamemodify(source_name, ':t') or '[No test file]'
	add_line(lines, highlights, title, nil, { { 0, -1, 'GtestrunnerTitle' } })
	local executable = source and config.executable_for(source) or config.current_executable
	add_line(lines, highlights, vim.fn.fnamemodify(executable or '', ':t'), nil, { { 0, -1, 'Comment' } })
	add_line(lines, highlights, 'r/d run/debug  R/D all  o output  x cancel', nil, { { 0, -1, 'Comment' } })
	add_line(lines, highlights, '')

	local tests = source and config.tests_for(source) or {}
	if #tests == 0 then
		add_line(lines, highlights, 'No tests found', nil, { { 0, -1, 'Comment' } })
	end
	for _, suite in ipairs(discover.suites(tests)) do
		local statuses, passed = {}, 0
		for _, test in ipairs(suite.tests) do
			local status = results.status(test.id)
			table.insert(statuses, status)
			if status == 'passed' then
				passed = passed + 1
			end
		end
		local status = results.combine(statuses)
		local icon = icons[status]
		add_line(lines, highlights, icon .. ' ' .. suite.name .. '  ' .. passed .. '/' .. #suite.tests,
			{ suite = suite }, {
				{ 0, #icon, marks.highlights[status] },
				{ #icon + 1, #icon + 1 + #suite.name, 'GtestrunnerSuite' },
				{ #icon + 1 + #suite.name, -1, 'Comment' },
			})

		for _, test in ipairs(suite.tests) do
			local result = results.get(test.id)
			local test_status = result and result.status or 'unknown'
			local test_icon = icons[test_status]
			local prefix = '  ' .. test_icon .. ' ' .. test.name
			local time = result and result.time_ms and (test_status == 'passed' or test_status == 'failed')
				and ('  ' .. result.time_ms .. ' ms') or ''
			add_line(lines, highlights, prefix .. time, { test = test }, {
				{ 2, 2 + #test_icon, marks.highlights[test_status] },
				{ #prefix, -1, 'Comment' },
			})
			if test_status == 'failed' then
				local shown = 0
				for _, failure in ipairs(result.failures) do
					local text = tostring(failure):gsub('\r', '')
					for _, failure_line in ipairs(vim.split(text, '\n', { trimempty = true })) do
						if shown == config.panel.max_failure_lines then
							break
						end
						add_line(lines, highlights, '      ' .. failure_line, { test = test },
							{ { 0, -1, 'GtestrunnerFailureText' } })
						shown = shown + 1
					end
				end
			end
		end
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, hl in ipairs(highlights) do
		local row, start_col, end_col, group = hl[1], hl[2], hl[3], hl[4]
		if end_col == -1 then
			end_col = #lines[row + 1]
		end
		pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, start_col, { end_col = end_col, hl_group = group })
	end
end

M.open = function()
	M.closed_by_user = false
	if M.is_open() then
		return
	end
	if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
		create_buf()
	end
	win = vim.api.nvim_open_win(buf, false, {
		split = 'right',
		win = -1,
		width = gtestrunner().panel.width,
	})
	local wo = vim.wo[win]
	wo.number = false
	wo.relativenumber = false
	wo.signcolumn = 'no'
	wo.foldcolumn = '0'
	wo.spell = false
	wo.list = false
	wo.wrap = false
	wo.cursorline = true
	wo.winfixwidth = true
	M.render()
end

M.close = function()
	M.closed_by_user = true
	if M.is_open() then
		local ok = pcall(vim.api.nvim_win_close, win, true)
		if not ok then
			vim.notify('gtestrunner: the panel is the last window, use :q to quit', vim.log.levels.WARN)
			return
		end
	end
	win = nil
end

M.toggle = function()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

M.on_win_closed = function(closed_win)
	if closed_win == win then
		win = nil
		M.closed_by_user = true
	end
end

-- Closes the panel when it would be the last window left in the tab, so :q quits as usual
M.close_if_last = function()
	if not M.is_open() then
		return
	end
	local current = vim.api.nvim_get_current_win()
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if w ~= win and w ~= current and vim.api.nvim_win_get_config(w).relative == '' then
			return
		end
	end
	if current ~= win and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
		-- cleared first so WinClosed doesn't count it as closed by the user, :q can still fail
		local panel_win = win
		win = nil
		vim.api.nvim_win_close(panel_win, true)
	end
end

return M
