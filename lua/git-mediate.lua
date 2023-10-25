local M = {}

local diff = require("vscode-diff.diff")

local qf_ns = vim.api.nvim_create_namespace("git-mediate-qf")

local function setup_qf_highlights()
	vim.api.nvim_set_hl(0, "GitMediateQfAdd", { fg = "#98c379", default = true })
	vim.api.nvim_set_hl(0, "GitMediateQfDel", { fg = "#e06c75", default = true })
	vim.api.nvim_set_hl(0, "GitMediateQfAddChar", { bg = "#4d9f4d", default = true })
	vim.api.nvim_set_hl(0, "GitMediateQfDelChar", { bg = "#9f4d4d", default = true })
end

local function apply_char_diff(qf_bufnr, diffA, diffB)
	if #diffA == 0 or #diffB == 0 then
		return
	end

	local a_texts = vim.tbl_map(function(x) return x.text end, diffA)
	local b_texts = vim.tbl_map(function(x) return x.text end, diffB)
	local result = diff.compute_diff(a_texts, b_texts)

	if not result or not result.changes then
		return
	end

	local prefix = #"|| +"
	for _, change in ipairs(result.changes) do
		for _, inner in ipairs(change.inner_changes or {}) do
			local orig_idx = inner.original and inner.original.start_line
			if orig_idx and orig_idx >= 1 and orig_idx <= #diffA then
				local entry = diffA[orig_idx]
				pcall(vim.api.nvim_buf_set_extmark, qf_bufnr, qf_ns, entry.lnum, prefix + inner.original.start_col - 1, {
					end_col = prefix + inner.original.end_col - 1,
					hl_group = "GitMediateQfDelChar",
					priority = 200,
				})
			end
			local mod_idx = inner.modified and inner.modified.start_line
			if mod_idx and mod_idx >= 1 and mod_idx <= #diffB then
				local entry = diffB[mod_idx]
				pcall(vim.api.nvim_buf_set_extmark, qf_bufnr, qf_ns, entry.lnum, prefix + inner.modified.start_col - 1, {
					end_col = prefix + inner.modified.end_col - 1,
					hl_group = "GitMediateQfAddChar",
					priority = 200,
				})
			end
		end
	end
end

local function highlight_qf_buffer()
	local qf_bufnr = vim.fn.getqflist({ qfbufnr = 0 }).qfbufnr
	if qf_bufnr == 0 then
		return
	end

	vim.api.nvim_buf_clear_namespace(qf_bufnr, qf_ns, 0, -1)
	local lines = vim.api.nvim_buf_get_lines(qf_bufnr, 0, -1, false)

	local current_section = nil
	local diffA, diffB = {}, {}

	for i, line in ipairs(lines) do
		local lnum = i - 1

		if line:match("DiffA:") then
			current_section = "A"
		elseif line:match("DiffB:") then
			current_section = "B"
		elseif line:match("### Conflict") then
			apply_char_diff(qf_bufnr, diffA, diffB)
			diffA, diffB = {}, {}
			current_section = nil
		end

		if line:match("^|| %+") then
			vim.api.nvim_buf_set_extmark(qf_bufnr, qf_ns, lnum, 0, { end_col = #line, hl_group = "GitMediateQfAdd", priority = 100 })
			if current_section == "A" then
				table.insert(diffA, { lnum = lnum, text = line:sub(5) })
			elseif current_section == "B" then
				table.insert(diffB, { lnum = lnum, text = line:sub(5) })
			end
		elseif line:match("^|| %-") then
			vim.api.nvim_buf_set_extmark(qf_bufnr, qf_ns, lnum, 0, { end_col = #line, hl_group = "GitMediateQfDel", priority = 100 })
		end
	end

	apply_char_diff(qf_bufnr, diffA, diffB)
end

function M.setup()
	highlight.setup()
	setup_qf_highlights()

	vim.api.nvim_create_user_command("GitMediate", function()
		if vim.bo.modified then
			vim.cmd("write")
		end

		local saved_efm = vim.o.errorformat
		vim.o.errorformat = "%f:%l:%m"
		vim.cmd('cexpr system("git mediate -d")')
		vim.o.errorformat = saved_efm
		vim.cmd("copen")
		vim.cmd("wincmd L")

		vim.keymap.set("n", "<CR>", ":.cc<CR>zz", { buffer = true, desc = "Jump to entry" })

		highlight_qf_buffer()
		vim.cmd("checktime")
	end, {})

	vim.api.nvim_create_user_command("GitMediateToggle", highlight.cycle_diff_mode, {})

	vim.keymap.set("n", "<leader>g[", ":GitMediate<CR>", { noremap = true, silent = true })
end

return M
