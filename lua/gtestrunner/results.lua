local M = {}

-- test id -> { status = 'running'|'passed'|'failed'|'skipped', time_ms, failures = { string } }
-- Tests without an entry have status 'unknown' (not run).
local by_id = {}

local listeners = {}

M.on_change = function(callback)
	table.insert(listeners, callback)
end

local changed = function()
	for _, callback in ipairs(listeners) do
		callback()
	end
end

M.get = function(id)
	return by_id[id]
end

M.status = function(id)
	local result = by_id[id]
	return result and result.status or 'unknown'
end

M.clear = function()
	by_id = {}
	changed()
end

M.set_status = function(ids, status)
	for _, id in ipairs(ids) do
		by_id[id] = status ~= 'unknown' and { status = status, failures = {} } or nil
	end
	changed()
end

M.set_running = function(ids)
	M.set_status(ids, 'running')
end

-- Precedence used when combining several results, e.g. the instances of a TEST_P
-- or the tests of a suite.
local precedence = { failed = 6, running = 5, building = 4, unknown = 3, passed = 2, skipped = 1 }

M.combine = function(statuses)
	local combined
	for _, status in ipairs(statuses) do
		if combined == nil or precedence[status] > precedence[combined] then
			combined = status
		end
	end
	return combined or 'unknown'
end

-- 'Name/0' or 'Name/CustomParamName' -> 'Name' for parameterized tests
local strip_param = function(name)
	return (name:gsub('/.*$', ''))
end

-- 'Instance/Suite' -> 'Suite' for parameterized tests
local strip_instance = function(name)
	return (name:gsub('^.*/', ''))
end

local parse_ms = function(time)
	local seconds = type(time) == 'string' and tonumber(time:match('[%d.]+'))
	return seconds and math.floor(seconds * 1000 + 0.5) or 0
end

local read_report = function(path)
	local file = io.open(path, 'r')
	if file == nil then
		return nil
	end
	local content = file:read('*a')
	file:close()
	local ok, report = pcall(vim.json.decode, content)
	if ok and type(report) == 'table' then
		return report
	end
	return nil
end

-- Updates results from a gtest json report (--gtest_output=json:<path>).
-- `ids` are the tests that were requested; ones missing from the report get
-- `missing.status` (default 'failed') with `missing.message`.
M.finish = function(ids, report_path, missing)
	missing = missing or {}
	local report = read_report(report_path)
	os.remove(report_path)

	local found = {}
	for _, suite in ipairs(report and report.testsuites or {}) do
		for _, case in ipairs(suite.testsuite or {}) do
			if case.status ~= 'NOTRUN' then
				local id = strip_instance(suite.name) .. '.' .. strip_param(case.name)
				local status = 'passed'
				if type(case.failures) == 'table' and #case.failures > 0 then
					status = 'failed'
				elseif case.result == 'SKIPPED' then
					status = 'skipped'
				end
				local result = found[id] or { time_ms = 0, failures = {} }
				result.status = result.status and M.combine({ result.status, status }) or status
				result.time_ms = result.time_ms + parse_ms(case.time)
				for _, failure in ipairs(type(case.failures) == 'table' and case.failures or {}) do
					table.insert(result.failures, failure.failure)
				end
				found[id] = result
			end
		end
	end

	for id, result in pairs(found) do
		by_id[id] = result
	end
	for _, id in ipairs(ids) do
		if found[id] == nil then
			if missing.status == 'unknown' then
				by_id[id] = nil
			else
				local message = missing.message
				if message == nil then
					message = report and 'Test was not found in the executable' or 'No test report was written'
				end
				by_id[id] = { status = missing.status or 'failed', failures = { message } }
			end
		end
	end
	changed()
end

return M
