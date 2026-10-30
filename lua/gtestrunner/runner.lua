local results = require('gtestrunner.results')
local output = require('gtestrunner.output')

local M = {}

local job = nil
local cancelled = false

-- report path -> { ids, build_id } of the tests run by a debug session
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

-- Runs the tests without the debugger.
-- request = { executable, build_id, cwd, filter, ids }
M.run = function(request)
	if job ~= nil then
		vim.notify('gtestrunner: tests are already running', vim.log.levels.WARN)
		return
	end
	local report = report_path()
	local cmd = { request.executable, '--gtest_filter=' .. request.filter, '--gtest_output=json:' .. report }
	output.append({ '$ ' .. table.concat(cmd, ' '), '' })
	output.set_phase('running')
	cancelled = false
	results.set_running(request.ids)

	local stdout = output.writer()
	local stderr = output.writer()
	local ok, obj = pcall(vim.system, cmd, {
		cwd = request.cwd,
		stdout = function(_, data) vim.schedule(function() stdout(data) end) end,
		stderr = function(_, data) vim.schedule(function() stderr(data) end) end,
	}, function(res)
		vim.schedule(function()
			job = nil
			stdout(nil, true)
			stderr(nil, true)
			output.append({ '', cancelled and 'Cancelled' or ('Exit code ' .. res.code) })
			output.set_phase(nil)
			if cancelled then
				results.finish(request.ids, report, { status = 'unknown' })
			else
				results.finish(request.ids, report, {
					message = not report_exists(report) and ('No test report was written, exit code ' .. res.code) or nil,
				}, request.build_id)
			end
		end)
	end)
	if not ok then
		output.append({ tostring(obj) })
		output.set_phase(nil)
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
	for report, pending in pairs(pending_debug) do
		pending_debug[report] = nil
		results.finish(pending.ids, report, { status = 'unknown' })
	end
end

local finish_debug_session = function(session)
	local report = session and session.config and session.config.gtestrunner_report
	local pending = report and pending_debug[report]
	if pending == nil then
		return
	end
	pending_debug[report] = nil
	-- A session that was stopped before the tests finished leaves them as not run
	local missing = not report_exists(report) and { status = 'unknown' } or nil
	vim.schedule(function()
		results.finish(pending.ids, report, missing, pending.build_id)
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
-- request = { executable, build_id, filter, ids, dap_config }
M.debug = function(request)
	local dap = require('dap')
	if dap.adapters[request.dap_config.type] == nil then
		results.set_status(request.ids, 'unknown')
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
	pending_debug[report] = { ids = request.ids, build_id = request.build_id }
	results.set_running(request.ids)
	print(config.program .. ' ' .. table.concat(config.args, ' '))
	dap.run(config)
end

return M
