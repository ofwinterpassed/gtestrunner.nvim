local results = require('gtestrunner.results')

local M = {}

-- Output of the latest run without the debugger
M.output = {}

local job = nil
local cancelled = false

-- report path -> ids of the tests run by a debug session
local pending_debug = {}

M.is_running = function()
	return job ~= nil
end

local report_path = function()
	return vim.fn.tempname() .. '.json'
end

local report_exists = function(path)
	return vim.uv.fs_stat(path) ~= nil
end

local split_lines = function(text)
	local cleaned = (text or ''):gsub('\r', '')
	local lines = vim.split(cleaned, '\n', { plain = true })
	if lines[#lines] == '' then
		table.remove(lines)
	end
	return lines
end

-- Runs the tests without the debugger.
-- request = { executable, cwd, filter, ids, on_exit }
M.run = function(request)
	if job ~= nil then
		vim.notify('gtestrunner: tests are already running', vim.log.levels.WARN)
		return
	end
	local report = report_path()
	local cmd = { request.executable, '--gtest_filter=' .. request.filter, '--gtest_output=json:' .. report }
	M.output = { '$ ' .. table.concat(cmd, ' '), '' }
	cancelled = false
	results.set_running(request.ids)

	local ok, obj = pcall(vim.system, cmd, { cwd = request.cwd, text = true }, function(res)
		vim.schedule(function()
			job = nil
			vim.list_extend(M.output, split_lines(res.stdout))
			vim.list_extend(M.output, split_lines(res.stderr))
			table.insert(M.output, '')
			table.insert(M.output, cancelled and 'Cancelled' or ('Exit code ' .. res.code))
			if cancelled then
				results.finish(request.ids, report, { status = 'unknown' })
			else
				results.finish(request.ids, report, {
					message = not report_exists(report) and ('No test report was written, exit code ' .. res.code) or nil,
				})
			end
			if request.on_exit then
				request.on_exit(res.code)
			end
		end)
	end)
	if not ok then
		table.insert(M.output, tostring(obj))
		results.finish(request.ids, report, { message = 'Failed to start ' .. request.executable })
		return
	end
	job = obj
end

-- Stops the run without the debugger. Debug sessions are stopped with nvim-dap, but
-- tests of debug runs that never started are reset to not run.
M.cancel = function()
	if job ~= nil then
		cancelled = true
		job:kill('sigterm')
	end
	for report, ids in pairs(pending_debug) do
		pending_debug[report] = nil
		results.finish(ids, report, { status = 'unknown' })
	end
end

local finish_debug_session = function(session)
	local report = session and session.config and session.config.gtestrunner_report
	local ids = report and pending_debug[report]
	if ids == nil then
		return
	end
	pending_debug[report] = nil
	-- A session that was stopped before the tests finished leaves them as not run
	local missing = not report_exists(report) and { status = 'unknown' } or nil
	vim.schedule(function()
		results.finish(ids, report, missing)
	end)
end

local listening = false

local listen_for_debug_sessions = function(dap)
	if listening then
		return
	end
	listening = true
	-- on_close is called however the session ends, also when the adapter exits or fails
	dap.listeners.on_session['gtestrunner'] = function(_, session)
		local report = session and session.config and session.config.gtestrunner_report
		if report and pending_debug[report] then
			session.on_close['gtestrunner'] = finish_debug_session
		end
	end
end

-- Runs the tests under nvim-dap.
-- request = { executable, filter, ids, dap_config }
M.debug = function(request)
	local dap = require('dap')
	if dap.adapters[request.dap_config.type] == nil then
		vim.notify('gtestrunner: no nvim-dap adapter named "' .. tostring(request.dap_config.type) .. '"',
			vim.log.levels.ERROR)
		return
	end
	listen_for_debug_sessions(dap)

	local report = report_path()
	local config = vim.deepcopy(request.dap_config)
	config.name = config.type .. ' ' .. request.executable .. ' ' .. request.filter
	config.program = request.executable
	config.args = { '--gtest_filter=' .. request.filter, '--gtest_output=json:' .. report }
	config.gtestrunner_report = report
	pending_debug[report] = request.ids
	results.set_running(request.ids)
	print(config.program .. ' ' .. table.concat(config.args, ' '))
	dap.run(config)
end

return M
