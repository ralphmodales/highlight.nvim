local M = {}
local ns_id = vim.api.nvim_create_namespace("highlight")
local notes = {}
local highlight_count = 0

vim.api.nvim_set_hl(0, "KindleHighlight", { bg = "#ffff00", fg = "#000000" })

local function find_project_root()
	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		return vim.fn.getcwd()
	end

	local dir = vim.fn.fnamemodify(current_file, ":h")

	local root_markers = { ".git", ".hg", ".svn", "package.json", "Cargo.toml", ".project_root" }

	while dir ~= "/" and dir ~= "" do
		for _, marker in ipairs(root_markers) do
			if vim.fn.isdirectory(dir .. "/" .. marker) == 1 or vim.fn.filereadable(dir .. "/" .. marker) == 1 then
				return dir
			end
		end
		dir = vim.fn.fnamemodify(dir, ":h")
	end

	return vim.fn.getcwd()
end

local function get_storage_path()
	local project_root = find_project_root()
	return project_root .. "/.highlights"
end

local function save_data()
	local path = get_storage_path()
	if not path then
		return
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local file = io.open(path, "w")
	if file then
		local encoded = vim.json.encode(notes)
		file:write(encoded)
		file:close()
	else
		vim.api.nvim_echo({ { "Failed to open file for writing: " .. path, "ErrorMsg" } }, true, {})
	end
end

local function load_data()
	local path = get_storage_path()
	if not path then
		return
	end
	local file = io.open(path, "r")
	if file then
		local content = file:read("*all")
		file:close()
		local disk_notes = vim.json.decode(content) or {}
		for key, disk_data in pairs(disk_notes) do
			if not notes[key] then
				notes[key] = disk_data
			else
				notes[key] = vim.tbl_deep_extend("keep", notes[key], disk_data)
			end
		end
		highlight_count = 0
		local max_lines = vim.api.nvim_buf_line_count(0) - 1
		for key, data in pairs(notes) do
			local target_line = data.line
			if target_line < 0 then
				target_line = 0
			elseif target_line > max_lines then
				target_line = max_lines
			end
			local line_length = #vim.api.nvim_buf_get_lines(0, target_line, target_line + 1, false)[1]
			if data.start_col < 0 then
				data.start_col = 0
			elseif data.start_col > line_length then
				data.start_col = line_length
			end
			if data.end_col < 0 then
				data.end_col = 0
			elseif data.end_col > line_length then
				data.end_col = line_length
			end
			vim.api.nvim_buf_add_highlight(0, ns_id, "KindleHighlight", target_line, data.start_col, data.end_col)
			if data.number and data.number > highlight_count then
				highlight_count = data.number
			end
			if data.note and data.note ~= "" then
				vim.api.nvim_buf_set_extmark(0, ns_id, target_line, data.end_col, {
					virt_text = { { " " .. data.number, "Comment" } },
					virt_text_pos = "overlay",
				})
			end
			data.line = target_line
		end
	end
end

local function get_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local line = start_pos[2] - 1
	local start_col = start_pos[3] - 1
	local end_col = end_pos[3] - 1

	local line_text = vim.api.nvim_buf_get_lines(0, line, line + 1, false)[1] or ""
	if end_col > #line_text then
		end_col = #line_text
	end
	if end_col < start_col then
		end_col = start_col
	end

	local selected_text = string.sub(line_text, start_col + 1, end_col + 1)
	return {
		line = line,
		start_col = start_col,
		end_col = end_col + 1,
		text = selected_text,
	}
end

function M.add_highlight()
	local selection
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local mode = vim.fn.mode()

	if start_pos[2] > 0 and end_pos[2] > 0 and (start_pos[2] ~= end_pos[2] or start_pos[3] ~= end_pos[3]) then
		selection = get_visual_selection()
		if not selection then
			return
		end
	else
		local pos = vim.api.nvim_win_get_cursor(0)
		local line_idx = pos[1] - 1
		local col = pos[2]
		local line_content = vim.api.nvim_buf_get_lines(0, line_idx, line_idx + 1, false)[1] or ""
		local word_start = col
		local word_end = col
		while word_start > 0 and not line_content:sub(word_start + 1, word_start + 1):match("%s") do
			word_start = word_start - 1
		end
		if line_content:sub(word_start + 1, word_start + 1):match("%s") then
			word_start = word_start + 1
		end
		while word_end < #line_content and not line_content:sub(word_end + 1, word_end + 1):match("%s") do
			word_end = word_end + 1
		end
		local phrase = line_content:sub(word_start + 1, word_end)
		selection = {
			line = line_idx,
			start_col = word_start,
			end_col = word_end,
			text = phrase,
		}
	end

	if selection.start_col < 0 then
		selection.start_col = 0
	end
	local line_len = #vim.api.nvim_buf_get_lines(0, selection.line, selection.line + 1, false)[1]
	if selection.end_col > line_len then
		selection.end_col = line_len
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
end

function M.add_or_show_note()
	local pos = vim.api.nvim_win_get_cursor(0)
	local line = pos[1] - 1
	local col = pos[2]
	local key = nil

	for k, data in pairs(notes) do
		if data.line == line then
			if col >= data.start_col and col <= data.end_col then
				key = k
				break
			end
		end
	end

	if not key then
		for k, data in pairs(notes) do
			if data.line == line then
				key = k
				break
			end
		end
	end

	if not key then
		vim.api.nvim_echo({ { "No highlight found on this line", "WarningMsg" } }, true, {})
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
		local cleaned_lines = {}
		for i, line in ipairs(lines) do
			if line ~= "-- Press <Esc> to save and close --" and i ~= #lines - 1 then
				table.insert(cleaned_lines, line)
			end
		end
		local note = table.concat(cleaned_lines, "\n")

		if not notes[key] then
			vim.api.nvim_win_close(win, true)
			return
		end

		local max_lines = vim.api.nvim_buf_line_count(0) - 1

		if note ~= "" and note ~= "Enter note here..." then
			if not notes[key].number then
				highlight_count = highlight_count + 1
				notes[key].number = highlight_count
			end
			notes[key].note = note

			local target_line = notes[key].line
			if target_line < 0 then
				target_line = 0
			elseif target_line > max_lines then
				target_line = max_lines
			end
			notes[key].line = target_line

			local line_length = #vim.api.nvim_buf_get_lines(0, target_line, target_line + 1, false)[1]
			if notes[key].end_col > line_length then
				notes[key].end_col = line_length
			end
			if notes[key].start_col > line_length then
				notes[key].start_col = line_length
			end

			vim.api.nvim_buf_clear_namespace(0, ns_id, target_line, target_line + 1)
			vim.api.nvim_buf_add_highlight(
				0,
				ns_id,
				"KindleHighlight",
				target_line,
				notes[key].start_col,
				notes[key].end_col
			)
			vim.api.nvim_buf_set_extmark(0, ns_id, target_line, notes[key].end_col, {
				virt_text = { { " " .. notes[key].number, "Comment" } },
				virt_text_pos = "overlay",
			})
		elseif notes[key].note then
			notes[key].note = nil
			notes[key].number = nil

			local target_line = notes[key].line
			if target_line < 0 then
				target_line = 0
			elseif target_line > max_lines then
				target_line = max_lines
			end
			notes[key].line = target_line

			local line_length = #vim.api.nvim_buf_get_lines(0, target_line, target_line + 1, false)[1]
			if notes[key].end_col > line_length then
				notes[key].end_col = line_length
			end
			if notes[key].start_col > line_length then
				notes[key].start_col = line_length
			end

			vim.api.nvim_buf_clear_namespace(0, ns_id, target_line, target_line + 1)
			vim.api.nvim_buf_add_highlight(
				0,
				ns_id,
				"KindleHighlight",
				target_line,
				notes[key].start_col,
				notes[key].end_col
			)
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
		vim.api.nvim_echo({ { "No highlights or notes in this file", "WarningMsg" } }, true, {})
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
		if data.note and data.note ~= "" then
			if not data.number then
				highlight_count = highlight_count + 1
				data.number = highlight_count
				save_data()
			end
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
