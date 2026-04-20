local M = {}

M.MARKERS = {
	ours_start = "^<<<<<<<",
	base_start = "^|||||||",
	separator = "^=======",
	theirs_end = "^>>>>>>>",
}

---@param buf number Buffer handle
---@return table[] List of conflict objects
function M.parse(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local conflicts = {}
	local i = 1

	while i <= #lines do
		local line = lines[i]

		if line:match(M.MARKERS.ours_start) then
			local conflict = {
				start_line = i - 1, -- 0-indexed
				ours = { start = nil, lines = {} },
				base = nil,
				theirs = { start = nil, lines = {} },
				separator_line = nil,
				base_start_line = nil,
				end_line = nil,
			}

			i = i + 1
			conflict.ours.start = i - 1 -- 0-indexed
			while i <= #lines do
				line = lines[i]
				if line:match(M.MARKERS.base_start) then
					conflict.base_start_line = i - 1
					conflict.base = { start = nil, lines = {} }
					i = i + 1
					conflict.base.start = i - 1
					while i <= #lines do
						line = lines[i]
						if line:match(M.MARKERS.separator) then
							break
						end
						table.insert(conflict.base.lines, line)
						i = i + 1
					end
					break
				elseif line:match(M.MARKERS.separator) then
					break
				end
				table.insert(conflict.ours.lines, line)
				i = i + 1
			end

			if line:match(M.MARKERS.separator) then
				conflict.separator_line = i - 1
				i = i + 1
				conflict.theirs.start = i - 1 -- 0-indexed

				while i <= #lines do
					line = lines[i]
					if line:match(M.MARKERS.theirs_end) then
						conflict.end_line = i - 1
						break
					end
					table.insert(conflict.theirs.lines, line)
					i = i + 1
				end

				table.insert(conflicts, conflict)
			end
		end

		i = i + 1
	end

	return conflicts
end

---@param buf number Buffer handle
---@return boolean
function M.buffer_has_conflicts(buf)
	local result = 0
	vim.api.nvim_buf_call(buf, function()
		result = vim.fn.search(M.MARKERS.ours_start, "nw")
	end)
	return result ~= 0
end

---@param buf number Buffer handle
---@param cursor_line number 0-indexed cursor line
---@return table|nil conflict The conflict at cursor, or nil if not in a conflict
function M.get_at_cursor(buf, cursor_line)
	local conflicts = M.parse(buf)
	for _, conflict in ipairs(conflicts) do
		if cursor_line >= conflict.start_line and cursor_line <= conflict.end_line then
			return conflict
		end
	end
	return nil
end

return M
