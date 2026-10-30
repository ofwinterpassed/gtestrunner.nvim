local results = require('gtestrunner.results')

local M = {}

local ns = vim.api.nvim_create_namespace('gtestrunner')

M.highlights = {
	unknown = 'GtestrunnerUnknown',
	building = 'GtestrunnerBuilding',
	running = 'GtestrunnerRunning',
	passed = 'GtestrunnerPassed',
	failed = 'GtestrunnerFailed',
	skipped = 'GtestrunnerSkipped',
}

local labels = {
	unknown = 'not run',
	building = 'building',
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

M.stale_text = 'older build'

-- Draws a sign and a virtual line above every test in the buffer. Tests with results from
-- another build than `build_id` are marked as run with an older build.
M.render = function(buf, tests, config, build_id)
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
		local stale = results.is_stale(test.id, build_id)
		local icon = config.icons[status]
		local hl = M.highlights[status]
		local opts = {}
		if config.signs then
			-- signs are at most two cells wide
			local stale_sign = icon .. config.icons.stale
			opts.sign_text = (stale and vim.fn.strdisplaywidth(stale_sign) <= 2) and stale_sign or icon
			opts.sign_hl_group = hl
		end
		if config.virtual_lines then
			local line = vim.api.nvim_buf_get_lines(buf, test.start_row, test.start_row + 1, false)[1] or ''
			local indent = line:match('^%s*')
			local chunks = { { indent .. icon .. ' ' .. test.id .. ' ' .. M.describe(result), hl } }
			if stale then
				table.insert(chunks, { ' · ' .. M.stale_text, 'GtestrunnerStale' })
			end
			opts.virt_lines = { chunks }
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
