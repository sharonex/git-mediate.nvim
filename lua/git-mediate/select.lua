local M = {}
local conflicts = require("git-mediate.conflicts")

---@param section table Section with start and lines
---@param cursor_line number 0-indexed cursor line
---@return boolean
local function cursor_in_section(section, cursor_line)
	if not section or not section.start then
		return false
	end
	local section_end = section.start + #section.lines - 1
	return cursor_line >= section.start and cursor_line <= section_end
end

function M.version()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1] - 1 -- Convert to 0-indexed

	local conflict = conflicts.get_at_cursor(buf, cursor_line)
	if not conflict then
		vim.notify("Cursor is not in a conflict", vim.log.levels.WARN)
		return
	end

	local chosen_lines
	if cursor_in_section(conflict.ours, cursor_line) then
		chosen_lines = conflict.ours.lines
	elseif cursor_in_section(conflict.theirs, cursor_line) then
		chosen_lines = conflict.theirs.lines
	else
		vim.notify("Cursor is not in ours or theirs section", vim.log.levels.WARN)
		return
	end

	-- Replace the entire conflict (start_line to end_line inclusive) with chosen lines
	vim.api.nvim_buf_set_lines(buf, conflict.start_line, conflict.end_line + 1, false, chosen_lines)
end

return M
