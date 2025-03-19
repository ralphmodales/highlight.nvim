local M = {}

local defaults = {
	highlight = { bg = "#ffff00", fg = "#000000" },
	keymaps = {
		highlight = "<leader>hh",
		show_note = "<leader>hn",
		notebook = "<leader>hl",
		clear = "<leader>hc",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
	vim.api.nvim_set_hl(0, "KindleHighlight", M.options.highlight)
	local maps = M.options.keymaps
	vim.keymap.set("n", maps.highlight, ":KindleHighlight<CR>", { desc = "Add highlight" })
	vim.keymap.set("v", maps.highlight, ":KindleHighlight<CR>", { desc = "Add highlight" })
	vim.keymap.set("n", maps.show_note, ":KindleNote<CR>", { desc = "Add/show note" })
	vim.keymap.set("n", maps.notebook, ":KindleNotebook<CR>", { desc = "List highlights/notes" })
	vim.keymap.set("n", maps.clear, ":KindleClear<CR>", { desc = "Clear all" })
end

return M
