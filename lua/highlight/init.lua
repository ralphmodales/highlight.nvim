local M = {}
local ns_id = vim.api.nvim_create_namespace("highlight")
local notes = {}
local highlight_count = 0

vim.api.nvim_set_hl(0, "KindleHighlight", { bg = "#ffff00", fg = "#000000" })

local function get_storage_path()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		return nil
	end
	local hash = vim.fn.sha256(filepath)
	return vim.fn.stdpath("data") .. "/highlight/" .. hash .. ".json"
end

local function load_data()
	local path = get_storage_path()
	if not path then
		return
	end
	local file = io.open(path, "r")
	if file then
		local content = file:read("*all")
		notes = vim.json.decode(content) or {}
		highlight_count = 0
		for _, data in pairs(notes) do
			vim.api.nvim_buf_add_highlight(0, ns_id, "KindleHighlight", data.line, data.start_col, data.end_col)
			if data.note then
				highlight_count = math.max(highlight_count, data.number or 0)
				vim.api.nvim_buf_set_extmark(0, ns_id, data.line, data.end_col, {
					virt_text = { { " " .. data.number, "Comment" } },
					virt_text_pos = "overlay",
				})
			end
		end
		file:close()
	end
end

local function save_data()
	local path = get_storage_path()
	if not path then
		return
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local file = io.open(path, "w")
	if file then
		file:write(vim.json.encode(notes))
		file:close()
	end
end

local function get_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local line = start_pos[2] - 1
	local start_col = start_pos[3] - 1
	local end_col = end_pos[3]

	if vim.fn.mode() == #"v" then
		local line_text = vim.api.nvim_buf_get_lines(0, line, line + 1, false)[1] or ""

		if vim.fn.visualmode() == "v" then
			end_col = vim.fn.col("'>")
			if end_col > #line_text then
				end_col = #line_text
			end
		end
	end
	local line_text = vim.api.nvim_buf_get_lines(0, line, line + 1, false)[1] or ""
	local selected_text = string.sub(line_text, start_col + 1, end_col)
	print("Debug: '" .. selected_text .. "' from " .. start_col .. " to " .. end_col)
	return {
		line = line,
		start_col = start_col,
		end_col = end_col,
		text = selected_text,
	}
end

function M.add_highlight()
	local selection
	local mode = vim.fn.mode()

	if mode == "v" or mode == "V" or mode == "\22" then
		selection = get_visual_selection()
		if not selection then
			return
		end
	else
		local phrase = vim.fn.expand("<cWORD>")
		if phrase == "" then
			print("No phrase under cursor")
			return
		end

		local pos = vim.api.nvim_win_get_cursor(0)
		local line_idx = pos[1] - 1
		local line_content = vim.api.nvim_buf_get_lines(0, line_idx, line_idx + 1, false)[1] or ""

		local start_col = line_content:find(phrase, 1, true)
		if not start_col then
			print("Could not locate phrase in line")
			return
		end
		start_col = start_col - 1
		local end_col = start_col + #phrase

		if start_col < 0 or end_col > #line_content or start_col >= end_col then
			print("Failed to determine phrase boundaries")
			return
		end

		selection = {
			line = line_idx,
			start_col = start_col,
			end_col = end_col,
			text = phrase,
		}
	end

	if selection.start_col < 0 then
		selection.start_col = 0
	end
	if selection.end_col > vim.api.nvim_buf_get_lines(0, selection.line, selection.line + 1, false)[1]:len() then
		selection.end_col = vim.api.nvim_buf_get_lines(0, selection.line, selection.line + 1, false)[1]:len()
	end

	vim.api.nvim_buf_add_highlight(0, ns_id, "KindleHighlight", selection.line, selection.start_col, selection.end_col)

	local key = selection.line .. ":" .. selection.start_col
	notes[key] = notes[key]
		or {
			text = selection.text,
			line = selection.line,
			start_col = selection.start_col,
			end_col = selection.end_col,
		}
	save_data()

	print('Highlighted "' .. selection.text .. '"')
end

function M.add_or_show_note()
	local pos = vim.api.nvim_win_get_cursor(0)
	local line = pos[1] - 1
	local col = pos[2]
	local key = nil

	for k, data in pairs(notes) do
		if data.line == line and col >= data.start_col and col < data.end_col then
			key = k
			break
		end
	end

	if not key then
		print("No highlight found at this position")
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local width = 40
	local height = 5
	local opts = {
		relative = "cursor",
		width = width,
		height = height,
		col = 1,
		row = 1,
		style = "minimal",
		border = "single",
	}

	vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_option(buf, "swapfile", false)

	local win = vim.api.nvim_open_win(buf, true, opts)
	vim.api.nvim_win_set_option(win, "wrap", true)

	if notes[key].note then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(notes[key].note, "\n"))
	else
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Enter note here...", "" })
	end

	local function save_note()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local note = table.concat(lines, "\n")
		if note ~= "" and note ~= "Enter note here...\n\n-- Press <Esc> to save and close --" then
			if not notes[key].number then
				highlight_count = highlight_count + 1
				notes[key].number = highlight_count
				vim.api.nvim_buf_set_extmark(0, ns_id, notes[key].line, notes[key].end_col, {
					virt_text = { { " " .. highlight_count, "Comment" } },
					virt_text_pos = "overlay",
				})
			end
			notes[key].note = note
			print("Note saved: '" .. note .. "'")
		elseif notes[key].note then
			notes[key].note = nil
			notes[key].number = nil
			vim.api.nvim_buf_clear_namespace(0, ns_id, notes[key].line, notes[key].line + 1)
			vim.api.nvim_buf_add_highlight(
				0,
				ns_id,
				"KindleHighlight",
				notes[key].line,
				notes[key].start_col,
				notes[key].end_col
			)
			print("Note removed")
		end
		save_data()
		vim.api.nvim_buf_set_option(buf, "modified", false)
		vim.api.nvim_win_close(win, true)
	end

	vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
		buffer = buf,
		callback = save_note,
	})

	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		buffer = buf,
		callback = function()
			vim.api.nvim_win_close(win, true)
		end,
	})

	vim.keymap.set("n", "<Esc>", function()
		save_note()
	end, { buffer = buf, noremap = true, silent = true })

	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "-- Press <Esc> to save and close --" })
end

function M.list_notes()
	if next(notes) == nil then
		print("No highlights or notes in this file")
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)
	vim.api.nvim_win_set_option(win, "wrap", true)
	vim.api.nvim_win_set_option(win, "cursorline", true)

	local lines = {
		"# Highlights and Notes",
		"",
		"Press `q` to close this window",
		"Press `<Enter>` on a highlight to jump to it",
		"",
		"---",
		"",
	}

	local sorted_notes = {}
	for _, data in pairs(notes) do
		table.insert(sorted_notes, data)
	end
	table.sort(sorted_notes, function(a, b)
		return a.line < b.line or (a.line == b.line and a.start_col < b.start_col)
	end)

	for _, data in ipairs(sorted_notes) do
		local line_str = string.format('Line %d: "%s"', data.line + 1, data.text)
		if data.note then
			line_str = line_str .. string.format(" [Note %d]", data.number)
			table.insert(lines, line_str)

			for _, note_line in ipairs(vim.split(data.note, "\n")) do
				table.insert(lines, "    " .. note_line)
			end
			table.insert(lines, "")
		else
			table.insert(lines, line_str)
		end
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, noremap = true })
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, noremap = true })
	vim.keymap.set("n", "<CR>", function()
		local cursor_pos = vim.api.nvim_win_get_cursor(0)
		local line_nr = cursor_pos[1]
		local line_text = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1]

		local original_line = tonumber(line_text:match("Line (%d+):"))
		if not original_line then
			return
		end

		vim.api.nvim_win_close(win, true)

		vim.api.nvim_win_set_cursor(0, { original_line, 0 })
		vim.cmd("normal! zz")
	end, { buffer = buf, noremap = true })

	vim.api.nvim_buf_set_name(buf, "Kindle Highlights")

	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

function M.clear_all()
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
	notes = {}
	highlight_count = 0
	save_data()
	print("All highlights and notes cleared for this file")
end

function M.setup(opts)
	opts = opts or {}
	require("highlight.config").setup(opts)

	vim.api.nvim_create_autocmd("BufEnter", {
		callback = function()
			vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
			load_data()
		end,
	})

	vim.api.nvim_create_user_command("KindleHighlight", M.add_highlight, { range = true })
	vim.api.nvim_create_user_command("KindleNote", M.add_or_show_note, {})
	vim.api.nvim_create_user_command("KindleNotebook", M.list_notes, {})
	vim.api.nvim_create_user_command("KindleClear", M.clear_all, {})
end

return M
