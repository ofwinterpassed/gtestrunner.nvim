local results = require('gtestrunner.results')

local M = {}

local ns = vim.api.nvim_create_namespace('gtestrunner')

M.highlights = {
	unknown = 'GtestrunnerUnknown',
	running = 'GtestrunnerRunning',
	passed = 'GtestrunnerPassed',
	failed = 'GtestrunnerFailed',
	skipped = 'GtestrunnerSkipped',
}

local labels = {
	unknown = 'not run',
	running = 'running',
	passed = 'passed',
	failed = 'failed',
	skipped = 'skipped',
}

-- Short status text, e.g. "passed · 3 ms" or "failed · 2 failures · 10 ms"
M.describe = function(result)
	local status = result and result.status or 'unknown'
	local parts = { labels[status] }
	if status == 'failed' and #result.failures > 1 then
		table.insert(parts, #result.failures .. ' failures')
	end
	if result and result.time_ms and (status == 'passed' or status == 'failed') then
		table.insert(parts, result.time_ms .. ' ms')
	end
	return table.concat(parts, ' · ')
end

-- Draws a sign and a virtual line above every test in the buffer
M.render = function(buf, tests, config)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	if not config.signs and not config.virtual_lines then
		return
	end
	for _, test in ipairs(tests) do
		local result = results.get(test.id)
		local status = result and result.status or 'unknown'
		local icon = config.icons[status]
		local hl = M.highlights[status]
		local opts = {}
		if config.signs then
			opts.sign_text = icon
			opts.sign_hl_group = hl
		end
		if config.virtual_lines then
			local line = vim.api.nvim_buf_get_lines(buf, test.start_row, test.start_row + 1, false)[1] or ''
			local indent = line:match('^%s*')
			opts.virt_lines = { { { indent .. icon .. ' ' .. test.id .. ' ' .. M.describe(result), hl } } }
			opts.virt_lines_above = true
		end
		pcall(vim.api.nvim_buf_set_extmark, buf, ns, test.start_row, 0, opts)
	end
end

M.clear = function(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
end

return M
