local M = {}
local diff = require("vscode-diff.diff")
local ns_id = vim.api.nvim_create_namespace("git-mediate-conflict")

local DEBOUNCE_MS = 100
local MARKERS = {
	ours_start = "^<<<<<<<",
	base_start = "^|||||||",
	separator = "^=======",
	theirs_end = "^>>>>>>>",
}

local buf_timers = {}
local buf_diff_modes = {}

local function setup_highlights()
	vim.api.nvim_set_hl(0, "ConflictOurs", { bg = "#2d4f2d", default = true })
	vim.api.nvim_set_hl(0, "ConflictLineOurs", { bg = "#3d5f3d", default = true })
	vim.api.nvim_set_hl(0, "ConflictCharOurs", { bg = "#4d9f4d", default = true })

	vim.api.nvim_set_hl(0, "ConflictBase", { bg = "#3c3f52", default = true })
	vim.api.nvim_set_hl(0, "ConflictLineBase", { bg = "#505368", default = true })
	vim.api.nvim_set_hl(0, "ConflictCharBase", { bg = "#6f7394", default = true })

	vim.api.nvim_set_hl(0, "ConflictTheirs", { bg = "#4f2f24", default = true })
	vim.api.nvim_set_hl(0, "ConflictLineTheirs", { bg = "#7a3a2c", default = true })
	vim.api.nvim_set_hl(0, "ConflictCharTheirs", { bg = "#d04a32", default = true })

	vim.api.nvim_set_hl(0, "ConflictMarker", { fg = "#666666", default = true })
end

---@param buf number Buffer handle
---@return table[] List of conflict objects
local function parse_conflicts(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local conflicts = {}
	local i = 1

	while i <= #lines do
		local line = lines[i]

		if line:match(MARKERS.ours_start) then
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
				if line:match(MARKERS.base_start) then
					conflict.base_start_line = i - 1
					conflict.base = { start = nil, lines = {} }
					i = i + 1
					conflict.base.start = i - 1
					while i <= #lines do
						line = lines[i]
						if line:match(MARKERS.separator) then
							break
						end
						table.insert(conflict.base.lines, line)
						i = i + 1
					end
					break
				elseif line:match(MARKERS.separator) then
					break
				end
				table.insert(conflict.ours.lines, line)
				i = i + 1
			end

			if line:match(MARKERS.separator) then
				conflict.separator_line = i - 1
				i = i + 1
				conflict.theirs.start = i - 1 -- 0-indexed

				while i <= #lines do
					line = lines[i]
					if line:match(MARKERS.theirs_end) then
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

local DiffMode = {
	OURS_VS_BASE = 1,
	THEIRS_VS_BASE = 2,
}

local DiffModeNames = {
	[DiffMode.OURS_VS_BASE] = "Ours vs Base",
	[DiffMode.THEIRS_VS_BASE] = "Theirs vs Base",
}

---@param buf number Buffer handle
---@return number
local function get_diff_mode(buf)
	return buf_diff_modes[buf] or DiffMode.OURS_VS_BASE
end

---@param conflict table Parsed conflict with ours, base, theirs
---@param diff_mode number The diff mode to use
---@return table section_a First section to compare
---@return table section_b Second section to compare
---@return string LineHLGroupA
---@return string CharHLGroupA
---@return string LineHLGroupB
---@return string CharHLGroupB
local function select_mode(conflict, diff_mode)
	if not conflict.base or #conflict.base.lines == 0 then
		return conflict.ours,
			conflict.theirs,
			"ConflictLineOurs",
			"ConflictCharOurs",
			"ConflictLineTheirs",
			"ConflictCharTheirs"
	end

	local base_equals_ours = vim.deep_equal(conflict.base, conflict.ours)
	local base_equals_theirs = vim.deep_equal(conflict.base, conflict.theirs)

	-- If selected mode would diff identical sections, switch to the other mode
	if diff_mode == DiffMode.OURS_VS_BASE and base_equals_ours and not base_equals_theirs then
		diff_mode = DiffMode.THEIRS_VS_BASE
	elseif diff_mode == DiffMode.THEIRS_VS_BASE and base_equals_theirs and not base_equals_ours then
		diff_mode = DiffMode.OURS_VS_BASE
	end

	if diff_mode == DiffMode.THEIRS_VS_BASE then
		return conflict.theirs,
			conflict.base,
			"ConflictLineTheirs",
			"ConflictCharTheirs",
			"ConflictLineBase",
			"ConflictCharBase"
	else
		return conflict.ours,
			conflict.base,
			"ConflictLineOurs",
			"ConflictCharOurs",
			"ConflictLineBase",
			"ConflictCharBase"
	end
end

---@param buf number Buffer handle
---@param section table Section with start and lines
---@param hl_group string Highlight group name
local function apply_section_bg(buf, section, hl_group)
	if not section or not section.start then
		return
	end
	for i = 0, #section.lines - 1 do
		local line = section.start + i
		local line_len = #(section.lines[i + 1] or "")
		pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line, 0, {
			end_col = line_len,
			hl_group = hl_group,
			hl_eol = true,
			priority = 100,
		})
	end
end

---@param buf number Buffer handle
---@param line number 0-indexed line number
local function apply_marker_hl(buf, line)
	if line then
		pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line, 0, {
			line_hl_group = "ConflictMarker",
			priority = 100,
		})
	end
end

---@param range table|nil Range object with start_line and end_line
---@return boolean
local function is_empty_line_range(range)
	if not range then
		return true
	end
	return range.end_line <= range.start_line
end

---@param range table|nil Range object with start_line, end_line, start_col, end_col
---@return boolean
local function is_empty_char_range(range)
	if not range then
		return true
	end
	return range.start_line == range.end_line and range.start_col == range.end_col
end

---@param line string The line content
---@param utf16_col number 1-based UTF-16 column
---@return number 1-based byte column
local function utf16_col_to_byte_col(line, utf16_col)
	if not line or utf16_col <= 1 then
		return utf16_col
	end
	local ok, byte_idx = pcall(vim.str_byteindex, line, utf16_col - 1, true)
	if ok then
		return byte_idx + 1
	end
	return utf16_col
end

---@param buf number Buffer handle
---@param section table Section with start position
---@param range table Range with start_line and end_line (1-indexed from diff)
---@param hl_group string Highlight group name
---@param buf_lines table Buffer lines for bounds checking
local function apply_line_highlight(buf, section, range, hl_group, buf_lines)
	-- range.start_line/end_line are 1-indexed from diff
	-- section.start is 0-indexed buffer line of first content
	local start_line = section.start + range.start_line - 1
	local end_line = section.start + range.end_line - 1

	for line = start_line, end_line - 1 do
		if line >= 0 and line < #buf_lines then
			local line_len = #(buf_lines[line + 1] or "")
			pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line, 0, {
				end_col = line_len,
				hl_group = hl_group,
				hl_eol = true,
				priority = 150,
			})
		end
	end
end

---@param buf number Buffer handle
---@param section table Section with start position
---@param range table Range with line and column info (1-indexed from diff)
---@param hl_group string Highlight group name
---@param buf_lines table Buffer lines for bounds checking
---@param section_lines table The original lines of this section (for UTF-16 conversion)
local function apply_char_highlight(buf, section, range, hl_group, buf_lines, section_lines)
	local start_line = section.start + range.start_line - 1
	local end_line = section.start + range.end_line - 1

	if start_line < 0 or start_line >= #buf_lines or end_line < 0 or end_line >= #buf_lines then
		return
	end

	local start_col = utf16_col_to_byte_col(section_lines[range.start_line] or "", range.start_col) - 1
	local end_col = utf16_col_to_byte_col(section_lines[range.end_line] or "", range.end_col) - 1

	start_col = math.max(0, math.min(start_col, #buf_lines[start_line + 1]))
	end_col = math.max(0, math.min(end_col, #buf_lines[end_line + 1]))

	if start_line == end_line then
		pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, start_line, start_col, {
			end_col = end_col,
			hl_group = hl_group,
			priority = 200,
		})
	else
		pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, start_line, start_col, {
			end_line = start_line + 1,
			end_col = 0,
			hl_group = hl_group,
			priority = 200,
		})

		for line = start_line + 1, end_line - 1 do
			if line >= 0 and line < #buf_lines then
				pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line, 0, {
					end_line = line + 1,
					end_col = 0,
					hl_group = hl_group,
					priority = 200,
				})
			end
		end

		if end_col > 0 then
			pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, end_line, 0, {
				end_col = end_col,
				hl_group = hl_group,
				priority = 200,
			})
		end
	end
end

---@param buf number Buffer handle
---@param section_a table First section (mapped to original in diff)
---@param section_b table Second section (mapped to modified in diff)
---@param diff_result table Result from vscode-diff.diff.compute_diff
---@param buf_lines table Buffer lines for bounds checking
local function apply_diff_highlights(
	buf,
	section_a,
	section_b,
	diff_result,
	buf_lines,
	line_hl_a,
	char_hl_a,
	line_hl_b,
	char_hl_b
)
	if not diff_result or not diff_result.changes then
		return
	end

	for _, change in ipairs(diff_result.changes) do
		if not is_empty_line_range(change.original) then
			apply_line_highlight(buf, section_a, change.original, line_hl_a, buf_lines)
		end
		if not is_empty_line_range(change.modified) then
			apply_line_highlight(buf, section_b, change.modified, line_hl_b, buf_lines)
		end

		for _, inner in ipairs(change.inner_changes or {}) do
			if not is_empty_char_range(inner.original) then
				apply_char_highlight(buf, section_a, inner.original, char_hl_a, buf_lines, section_a.lines)
			end
			if not is_empty_char_range(inner.modified) then
				apply_char_highlight(buf, section_b, inner.modified, char_hl_b, buf_lines, section_b.lines)
			end
		end
	end
end

---@param buf number Buffer handle
---@param conflict table Parsed conflict object
local function highlight_conflict(buf, conflict)
	local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local diff_mode = get_diff_mode(buf)

	apply_section_bg(buf, conflict.ours, "ConflictOurs")
	if conflict.base and #conflict.base.lines > 0 then
		apply_section_bg(buf, conflict.base, "ConflictBase")
	end
	apply_section_bg(buf, conflict.theirs, "ConflictTheirs")

	apply_marker_hl(buf, conflict.start_line)
	if conflict.base_start_line then
		apply_marker_hl(buf, conflict.base_start_line)
	end
	apply_marker_hl(buf, conflict.separator_line)
	apply_marker_hl(buf, conflict.end_line)

	local section_a, section_b, line_hl_a, char_hl_a, line_hl_b, char_hl_b = select_mode(conflict, diff_mode)
	local diff_result = diff.compute_diff(section_a.lines, section_b.lines)
	apply_diff_highlights(buf, section_a, section_b, diff_result, buf_lines, line_hl_a, char_hl_a, line_hl_b, char_hl_b)
end

---@param buf number Buffer handle
local function clear_highlights(buf)
	pcall(vim.api.nvim_buf_clear_namespace, buf, ns_id, 0, -1)
end

---@param buf number Buffer handle
local function refresh_highlights(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	clear_highlights(buf)
	local conflicts = parse_conflicts(buf)
	for _, conflict in ipairs(conflicts) do
		highlight_conflict(buf, conflict)
	end
end

---@param buf number Buffer handle
local function debounced_refresh(buf)
	if buf_timers[buf] then
		vim.fn.timer_stop(buf_timers[buf])
	end
	buf_timers[buf] = vim.fn.timer_start(DEBOUNCE_MS, function()
		vim.schedule(function()
			refresh_highlights(buf)
		end)
	end)
end

local function buffer_has_conflicts(buf)
	local result = 0
	vim.api.nvim_buf_call(buf, function()
		result = vim.fn.search(MARKERS.ours_start, "nw")
	end)
	return result ~= 0
end

local function setup_autocommands()
	local augroup = vim.api.nvim_create_augroup("GitMediateHighlight", { clear = true })

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
		group = augroup,
		pattern = "*",
		callback = function(args)
			local buf = args.buf
			if buffer_has_conflicts(buf) then
				refresh_highlights(buf)
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		pattern = "*",
		callback = function(args)
			local buf = args.buf
			if buffer_has_conflicts(buf) then
				debounced_refresh(buf)
			else
				clear_highlights(buf)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = augroup,
		pattern = "*",
		callback = function(args)
			local buf = args.buf
			if buf_timers[buf] then
				vim.fn.timer_stop(buf_timers[buf])
				buf_timers[buf] = nil
			end
			buf_diff_modes[buf] = nil
		end,
	})
end

function M.setup()
	setup_highlights()
	setup_autocommands()
end

function M.refresh()
	local buf = vim.api.nvim_get_current_buf()
	refresh_highlights(buf)
end

function M.clear()
	local buf = vim.api.nvim_get_current_buf()
	clear_highlights(buf)
end

function M.cycle_diff_mode()
	local buf = vim.api.nvim_get_current_buf()
	local current = get_diff_mode(buf)
	local new_mode = current == DiffMode.OURS_VS_BASE and DiffMode.THEIRS_VS_BASE or DiffMode.OURS_VS_BASE

	buf_diff_modes[buf] = new_mode
	refresh_highlights(buf)
	vim.notify("Diff mode: " .. DiffModeNames[new_mode], vim.log.levels.INFO)
end

return M
