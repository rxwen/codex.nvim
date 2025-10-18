---@brief [[
--- Codex approval handlers.
--- Provides interactive flows for patch and command approvals requested by the Codex app-server.
---@brief ]]

---@module 'codex.approvals'
local M = {}

local logger = require("codex.logger")

local diff_module

local function get_field(tbl, ...)
  if type(tbl) ~= "table" then
    return nil
  end
  local keys = { ... }
  for _, key in ipairs(keys) do
    if tbl[key] ~= nil then
      return tbl[key]
    end
    local camel = key:gsub("_(%l)", function(c)
      return c:upper()
    end)
    if tbl[camel] ~= nil then
      return tbl[camel]
    end
  end
  return nil
end

local function read_file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}, false
  end
  return lines, true
end

local function append_original(result, lines, start_idx, stop_idx)
  for i = start_idx, stop_idx - 1 do
    if lines[i] ~= nil then
      table.insert(result, lines[i])
    end
  end
end

local function apply_unified_diff(original_lines, diff_text)
  if diff_text == nil then
    return nil, "missing unified diff"
  end

  local diff_lines = vim.split(diff_text, "\n", { plain = true })
  local result = {}
  local original_index = 1
  local append_newline = true
  local i = 1

  while i <= #diff_lines do
    local line = diff_lines[i]
    local start_old, len_old, start_new = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
    if start_old then
      start_old = tonumber(start_old)
      len_old = tonumber(len_old ~= "" and len_old or "1")

      append_original(result, original_lines, original_index, start_old)
      original_index = start_old

      i = i + 1
      while i <= #diff_lines do
        local hunk_line = diff_lines[i]
        local prefix = hunk_line:sub(1, 1)
        if prefix == "@" then
          break
        elseif prefix == " " then
          table.insert(result, original_lines[original_index] or "")
          original_index = original_index + 1
        elseif prefix == "-" then
          original_index = original_index + 1
        elseif prefix == "+" then
          table.insert(result, hunk_line:sub(2))
        elseif prefix == "\\" then
          if hunk_line:match("No newline at end of file") then
            append_newline = false
          end
        end
        i = i + 1
      end
    else
      if line:match("^\\ No newline at end of file") then
        append_newline = false
      end
      i = i + 1
    end
  end

  append_original(result, original_lines, original_index, #original_lines + 1)

  return result, append_newline
end

local function join_lines(lines, append_newline)
  local text = table.concat(lines, "\n")
  if append_newline and (#lines > 0 or text == "") then
    text = text .. "\n"
  end
  return text
end

local function ensure_diff_module()
  if diff_module then
    return diff_module
  end
  local ok, module = pcall(require, "codex.diff")
  if not ok then
    error("codex.diff module unavailable: " .. tostring(module))
  end
  diff_module = module
  return diff_module
end

local function summarise_change(kind, path)
  if kind == "add" then
    return string.format("Add %s", path)
  elseif kind == "delete" then
    return string.format("Delete %s", path)
  elseif kind == "update" then
    return string.format("Update %s", path)
  end
  return string.format("Modify %s", path)
end

local function determine_kind(path, change)
  if type(change) ~= "table" then
    return nil
  end

  local kind = get_field(change, "kind", "type")
  if type(kind) == "string" then
    return kind
  end

  if change.unified_diff or change.unifiedDiff then
    return "update"
  end

  if change.content then
    local exists = vim.loop.fs_stat(path) ~= nil
    return exists and "update" or "add"
  end

  return nil
end

local function build_new_content(path, change)
  local kind = determine_kind(path, change)
  if not kind then
    return nil, nil, string.format("Unknown change format for %s", path)
  end

  local target_path = get_field(change, "move_path", "movePath") or path

  if kind == "add" then
    local content = get_field(change, "content") or ""
    return path, target_path, content
  elseif kind == "delete" then
    return path, target_path, ""
  elseif kind == "update" then
    local original_lines = select(1, read_file_lines(path))
    local new_lines, append_newline = apply_unified_diff(original_lines, get_field(change, "unified_diff", "unifiedDiff"))
    if not new_lines then
      return nil, nil, append_newline -- append_newline contains error message in this branch
    end
    return path, target_path, join_lines(new_lines, append_newline ~= false)
  end

  return nil, nil, string.format("Unsupported change kind: %s", tostring(kind))
end

local function open_diff_for_change(path, change)
  local original_path, target_path, new_content_or_err = build_new_content(path, change)
  if not original_path then
    return false, new_content_or_err
  end

  local new_content = new_content_or_err
  local diff = ensure_diff_module()
  local tab_name = string.format("Codex patch: %s", target_path)

  vim.notify(string.format("Review Codex patch for %s (write to accept, close to reject)", target_path), vim.log.levels.INFO)

  local ok, result_or_err = pcall(diff.open_diff_blocking, original_path, target_path, new_content, tab_name)
  if not ok then
    return false, result_or_err
  end

  local outcome = result_or_err and result_or_err.content and result_or_err.content[1]
  if outcome and outcome.text == "FILE_SAVED" then
    diff.close_diff_by_tab_name(tab_name)
    return true
  end

  diff.close_diff_by_tab_name(tab_name)
  return false, "User rejected diff"
end

local function gather_file_paths(file_changes)
  local paths = {}
  for path, _ in pairs(file_changes) do
    paths[#paths + 1] = path
  end
  table.sort(paths)
  return paths
end

local function handle_patch_changes(file_changes, ctx)
  local paths = gather_file_paths(file_changes)
  if #paths == 0 then
    ctx.respond({ decision = "approved" })
    return
  end

  ctx.defer()

  local co = coroutine.create(function()
    for _, path in ipairs(paths) do
      local ok, err = open_diff_for_change(path, file_changes[path])
      if not ok then
        logger.info("approvals", "Patch rejected for %s: %s", path, err or "unknown error")
        ctx.respond({ decision = "denied" })
        return
      end
    end

    ctx.respond({ decision = "approved" })
  end)

  vim.schedule(function()
    local ok, err = coroutine.resume(co)
    if not ok then
      logger.error("approvals", "Failed to resume patch approval coroutine", err)
      ctx.respond({ decision = "denied" })
    end
  end)
end

---Handle applyPatchApproval requests (server → client).
---@param params table
---@param ctx table
function M.handle_patch_approval(params, ctx)
  local file_changes = {}
  if type(params) == "table" then
    file_changes = params.file_changes or params.fileChanges or {}
  end

  local summary_parts = {}
  for path, change in pairs(file_changes) do
    local kind = determine_kind(path, change) or "update"
    summary_parts[#summary_parts + 1] = summarise_change(kind, path)
  end
  if #summary_parts > 0 then
    logger.info("approvals", table.concat(summary_parts, "; "))
  end

  handle_patch_changes(file_changes, ctx)
end

local function formatted_command_prompt(params)
  local parts = {}
  if params.command then
    parts[#parts + 1] = string.format("Command: %s", table.concat(params.command, " "))
  end
  if params.cwd then
    parts[#parts + 1] = string.format("CWD: %s", params.cwd)
  end
  if params.reason and params.reason ~= "" then
    parts[#parts + 1] = string.format("Reason: %s", params.reason)
  end
  if #parts == 0 then
    parts[1] = "Approve Codex command?"
  end
  return table.concat(parts, "\n")
end

---Handle execCommandApproval requests.
---@param params table
---@param ctx table
function M.handle_exec_command_approval(params, ctx)
  local prompt = formatted_command_prompt(params or {})

  ctx.defer()
  vim.schedule(function()
    local items = { "Approve", "Deny" }
    vim.ui.select(items, { prompt = prompt }, function(choice)
      if choice == "Approve" then
        ctx.respond({ decision = "approved" })
      else
        ctx.respond({ decision = "denied" })
      end
    end)
  end)
end

return M
