---@brief [[
--- Lightweight chat transcript management for Codex.
--- Maintains a dedicated Markdown buffer and helpers to stream agent output.
---@brief ]]

---@module 'codex.chat'
local M = {}

local chat_bufnr
local active_stream
local default_open_fn = function(bufnr)
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("wrap", true, { win = win })
end

---@type fun(bufnr: integer)|nil
M._open_window = nil

local function ensure_buffer()
  if chat_bufnr and vim.api.nvim_buf_is_valid(chat_bufnr) then
    return chat_bufnr
  end

  chat_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[chat_bufnr].filetype = "markdown"
  vim.bo[chat_bufnr].buftype = "nofile"
  vim.bo[chat_bufnr].swapfile = false
  vim.bo[chat_bufnr].bufhidden = "hide"
  vim.bo[chat_bufnr].modifiable = true
  vim.bo[chat_bufnr].readonly = false

  return chat_bufnr
end

local function append_raw_lines(lines)
  local bufnr = ensure_buffer()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
  return bufnr, line_count + #lines
end

local function append_block(prefix, text)
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  lines[1] = prefix .. lines[1]
  for i = 2, #lines do
    lines[i] = "  " .. lines[i]
  end

  local bufnr = ensure_buffer()
  local start = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, start, start, false, lines)
  vim.api.nvim_buf_set_lines(bufnr, start + #lines, start + #lines, false, { "" })

  return bufnr, start + #lines - 1
end

function M.append_agent_message(message)
  local bufnr, last_line = append_block("**Agent:** ", message)
  active_stream = { bufnr = bufnr, line = last_line }
end

function M.append_agent_delta(delta)
  if not delta or delta == "" then
    return
  end

  if not active_stream or not active_stream.bufnr or not vim.api.nvim_buf_is_valid(active_stream.bufnr) then
    M.append_agent_message(delta)
    return
  end

  local bufnr = active_stream.bufnr
  local line = active_stream.line
  local existing = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { existing .. delta })
end

function M.append_user_message(message)
  append_block("**You:** ", message)
  active_stream = nil
end

function M.append_system_message(message)
  append_raw_lines({ string.format("*[Codex] %s*", message), "" })
  active_stream = nil
end

function M.open(opts)
  local bufnr = ensure_buffer()
  local current_win = vim.fn.bufwinid(bufnr)
  if current_win ~= -1 then
    vim.api.nvim_set_current_win(current_win)
    return
  end

  local open_fn = opts and opts.open_window or M._open_window or default_open_fn
  open_fn(bufnr)
end

function M._set_open_window(fn)
  if fn ~= nil and type(fn) ~= "function" then
    error("codex.chat._set_open_window expects a function or nil")
  end
  M._open_window = fn
end

return M
