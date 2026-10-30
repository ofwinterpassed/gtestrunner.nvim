-- Output of the latest build and run without the debugger, kept in a scratch buffer that is
-- shown by show_output() and in the panel while building.
local M = {}

local buf = nil
-- lines not written to the buffer yet, flushed at most every 100 ms
local pending = {}
local flush_scheduled = false
local listeners = {}
local timer = nil

-- 'building', 'running' or nil
M.phase = nil
-- vim.uv.hrtime() when the phase started
M.started = nil
-- { done, total } from ninja style "[12/345]" progress lines
M.progress = nil

M.on_change = function(callback)
	table.insert(listeners, callback)
end

local changed = function()
	for _, callback in ipairs(listeners) do
		callback()
	end
end

M.buf = function()
	if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		pcall(vim.api.nvim_buf_set_name, buf, 'gtestrunner output')
		vim.bo[buf].modifiable = false
		vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, nowait = true, silent = true })
	end
	return buf
end

-- Windows showing the output with the cursor on the last line, they follow new output
local windows_at_end = function(b)
	local line_count = vim.api.nvim_buf_line_count(b)
	local wins = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == b and vim.api.nvim_win_get_cursor(win)[1] >= line_count then
			table.insert(wins, win)
		end
	end
	return wins
end

local flush = function()
	flush_scheduled = false
	if #pending == 0 then
		return
	end
	local lines = pending
	pending = {}
	local b = M.buf()
	local following = windows_at_end(b)
	local empty = vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ''
	vim.bo[b].modifiable = true
	vim.api.nvim_buf_set_lines(b, empty and 0 or -1, -1, false, lines)
	vim.bo[b].modifiable = false
	local line_count = vim.api.nvim_buf_line_count(b)
	for _, win in ipairs(following) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_cursor(win, { line_count, 0 })
		end
	end
	changed()
end

M.append = function(lines)
	for _, line in ipairs(lines) do
		table.insert(pending, line)
		if M.phase == 'building' then
			local done, total = line:match('%[(%d+)/(%d+)%]')
			if done then
				M.progress = { tonumber(done), tonumber(total) }
			end
		end
	end
	if not flush_scheduled then
		flush_scheduled = true
		vim.defer_fn(flush, 100)
	end
end

M.clear = function()
	pending = {}
	M.progress = nil
	local b = M.buf()
	vim.bo[b].modifiable = true
	vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
	vim.bo[b].modifiable = false
	changed()
end

-- All output lines, including the ones not flushed yet
M.lines = function()
	local lines = vim.api.nvim_buf_get_lines(M.buf(), 0, -1, false)
	if #lines == 1 and lines[1] == '' then
		lines = {}
	end
	return vim.list_extend(lines, pending)
end

M.set_phase = function(phase)
	M.phase = phase
	M.started = phase and vim.uv.hrtime() or nil
	if phase == 'building' then
		M.progress = nil
	end
	-- update the elapsed time every second
	if phase and timer == nil then
		timer = vim.uv.new_timer()
		timer:start(1000, 1000, vim.schedule_wrap(changed))
	elseif phase == nil and timer ~= nil then
		timer:stop()
		timer:close()
		timer = nil
	end
	changed()
end

local format_elapsed = function(ns)
	local seconds = math.floor(ns / 1e9)
	if seconds < 60 then
		return seconds .. 's'
	end
	return math.floor(seconds / 60) .. 'm ' .. (seconds % 60) .. 's'
end

-- e.g. "Building · 27% [123/456] · 1m 23s", nil when nothing is building or running
M.status_text = function()
	if M.phase == nil then
		return nil
	end
	local parts = { M.phase == 'building' and 'Building' or 'Running' }
	if M.phase == 'building' and M.progress and M.progress[2] > 0 then
		local done, total = M.progress[1], M.progress[2]
		table.insert(parts, math.floor(done * 100 / total) .. '% [' .. done .. '/' .. total .. ']')
	end
	table.insert(parts, format_elapsed(vim.uv.hrtime() - M.started))
	return table.concat(parts, ' · ')
end

-- Returns function(data, flush) that splits process output into lines and appends them,
-- keeping a partial last line until more output arrives
M.writer = function()
	local partial = ''
	return function(data, flush_partial)
		local text = (partial .. (data or '')):gsub('\r', '')
		local lines = vim.split(text, '\n', { plain = true })
		partial = table.remove(lines)
		if flush_partial and partial ~= '' then
			table.insert(lines, partial)
			partial = ''
		end
		if #lines > 0 then
			M.append(lines)
		end
	end
end

-- Shows the output in a split at the bottom
M.show = function()
	flush()
	local b = M.buf()
	local win = vim.fn.bufwinid(b)
	if win == -1 then
		vim.cmd('botright split')
		win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win, b)
		vim.api.nvim_win_set_height(win, 15)
	end
	vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(b), 0 })
end

return M
