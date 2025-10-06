local vim = vim

local logger = require("codex.logger")

local Json = vim.json or {}
local encode = Json.encode or vim.fn.json_encode
local decode = Json.decode or vim.fn.json_decode

local M = {}

---@class CodexClientState
---@field job_id integer|nil
---@field stdin integer|nil
---@field stdout_buffer string
---@field stderr_buffer string
---@field next_id integer
---@field pending table<integer, fun(result: table|nil, err: table|nil)>
---@field ready boolean
---@field conversation_id string|nil
---@field subscription_id string|nil
---@field shutting_down boolean
M.state = {
  job_id = nil,
  stdout_buffer = "",
  stderr_buffer = "",
  next_id = 1,
  pending = {},
  ready = false,
  conversation_id = nil,
  subscription_id = nil,
  shutting_down = false,
}

local function reset_state()
  M.state.stdout_buffer = ""
  M.state.stderr_buffer = ""
  M.state.pending = {}
  M.state.next_id = 1
  M.state.ready = false
  M.state.conversation_id = nil
  M.state.subscription_id = nil
  M.state.shutting_down = false
end

local function emit_notification(level, ...)
  local ok_notify, notify = pcall(vim.notify, table.concat(vim.tbl_map(tostring, { ... }), " "), level)
  if not ok_notify then
    logger.info("codex", ...)
  end
end

local function handle_event(event_type, params)
  if event_type == "agent_message" and params.msg and params.msg.message then
    emit_notification(vim.log.levels.INFO, params.msg.message)
    return
  end

  if event_type == "agent_message_delta" and params.msg and params.msg.delta then
    emit_notification(vim.log.levels.INFO, params.msg.delta)
    return
  end

  if event_type == "error" and params.msg and params.msg.message then
    emit_notification(vim.log.levels.ERROR, params.msg.message)
    return
  end

  if event_type == "task_complete" then
    emit_notification(vim.log.levels.INFO, "Codex task complete")
    return
  end

  logger.debug("codex", "Unhandled Codex event", event_type, vim.inspect(params))
end

local function handle_notification(method, params)
  if method == "sessionConfigured" then
    M.state.ready = true
    logger.info("codex", "Session configured")
    return
  end

  if method == "authStatusChange" then
    logger.debug("codex", "Auth status changed")
    return
  end

  if method:sub(1, 11) == "codex/event" then
    local event_type = method:sub(13)
    handle_event(event_type, params or {})
    return
  end

  logger.debug("codex", "Unhandled Codex notification", method, vim.inspect(params))
end

local function resolve_pending(id, result, err)
  local callback = M.state.pending[id]
  if not callback then
    logger.warn("codex", "No pending handler for id", id)
    return
  end
  M.state.pending[id] = nil
  local ok, msg = pcall(callback, result, err)
  if not ok then
    logger.error("codex", "Pending callback error", msg)
  end
end

local function process_message(json_str)
  if not json_str or json_str == "" then
    return
  end

  local ok, message = pcall(decode, json_str)
  if not ok then
    logger.error("codex", "Failed to decode Codex message", ok, message, json_str)
    return
  end

  if type(message) ~= "table" then
    return
  end

  if message.id ~= nil then
    if message.error then
      resolve_pending(message.id, nil, message.error)
    else
      resolve_pending(message.id, message.result, nil)
    end
    return
  end

  if message.method then
    local params = message.params
    local method = message.method
    handle_notification(method, params)
  end
end

local function extract_messages(buffer)
  local messages = {}
  local start_idx = nil
  local depth = 0
  local in_string = false
  local escape = false

  local i = 1
  while i <= #buffer do
    local c = buffer:sub(i, i)
    if not start_idx then
      if c == "{" then
        start_idx = i
        depth = 1
        in_string = false
        escape = false
      end
    else
      if in_string then
        if escape then
          escape = false
        elseif c == "\\" then
          escape = true
        elseif c == '"' then
          in_string = false
        end
      else
        if c == '"' then
          in_string = true
        elseif c == '{' then
          depth = depth + 1
        elseif c == '}' then
          depth = depth - 1
          if depth == 0 then
            local json_str = buffer:sub(start_idx, i)
            table.insert(messages, json_str)
            start_idx = nil
          end
        end
      end
    end
    i = i + 1
  end

  local remainder = ""
  if start_idx then
    remainder = buffer:sub(start_idx)
  end

  return messages, remainder
end

local function handle_stdout(_, data)
  if not data then
    return
  end

  for _, chunk in ipairs(data) do
    if type(chunk) ~= "string" or chunk == "" then
      goto continue
    end

    M.state.stdout_buffer = M.state.stdout_buffer .. chunk
    local extracted, remainder = extract_messages(M.state.stdout_buffer)
    M.state.stdout_buffer = remainder
    for _, raw in ipairs(extracted) do
      process_message(raw)
    end

    ::continue::
  end
end

local function handle_stderr(_, data)
  if not data then
    return
  end

  for _, chunk in ipairs(data) do
    if chunk ~= nil and chunk ~= "" then
      logger.warn("codex", "stderr:", chunk)
    end
  end
end

local function handle_exit(_, code)
  logger.info("codex", "Codex app-server exited", code)
  M.state.job_id = nil
  reset_state()
end

local function send_payload(payload)
  if not M.state.job_id then
    return false, "Codex app-server not running"
  end

  local ok, encoded = pcall(encode, payload)
  if not ok then
    return false, "Failed to encode payload"
  end

  encoded = encoded .. "\n"
  local ok_send, err = pcall(vim.fn.chansend, M.state.job_id, encoded)
  if not ok_send then
    logger.error("codex", "Failed to send message", err)
    return false, err
  end

  return true, nil
end

local function send_request(method, params, callback)
  local id = M.state.next_id
  M.state.next_id = M.state.next_id + 1

  M.state.pending[id] = callback

  local payload = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params,
  }

  local ok, err = send_payload(payload)
  if not ok then
    M.state.pending[id] = nil
    return false, err
  end

  return true, nil
end

local function ensure_conversation(params)
  if M.state.ready and M.state.conversation_id then
    return
  end

  send_request("initialize", {
    clientInfo = {
      name = "codex.nvim",
      title = "Codex Neovim",
      version = require("codex").version:string(),
    },
  }, function(result, err)
    if err then
      logger.error("codex", "Initialize failed", vim.inspect(err))
      return
    end

    logger.info("codex", "Initialized Codex app-server", vim.inspect(result))

    send_request("newConversation", params, function(conv_result, conv_err)
      if conv_err then
        logger.error("codex", "Failed to start conversation", vim.inspect(conv_err))
        return
      end

      M.state.conversation_id = conv_result.conversationId or conv_result.conversation_id

      if not M.state.conversation_id then
        logger.error("codex", "Conversation id missing in response")
        return
      end

      logger.info("codex", "Started conversation", M.state.conversation_id)

      send_request("addConversationListener", {
        conversationId = M.state.conversation_id,
      }, function(listener_result, listener_err)
        if listener_err then
          logger.error("codex", "Failed to add conversation listener", vim.inspect(listener_err))
          return
        end
        M.state.subscription_id = listener_result.subscriptionId or listener_result.subscription_id
        M.state.ready = true
        logger.info("codex", "Codex listener subscription", M.state.subscription_id)
        vim.schedule(function()
          local ok, main_module = pcall(require, "codex")
          if ok and type(main_module.process_mention_queue) == "function" then
            main_module.process_mention_queue(true)
          end
        end)
      end)
    end)
  end)
end

function M.is_ready()
  return M.state.ready and M.state.conversation_id ~= nil and M.state.job_id ~= nil
end

function M.start(config)
  if M.state.job_id then
    return true, M.state.job_id
  end

  reset_state()

  local cmd = config.codex_cmd or "codex"
  local args = { cmd, "app-server" }

  logger.debug("codex", "Starting app-server", table.concat(args, " "))

  local job_id = vim.fn.jobstart(args, {
    on_stdout = handle_stdout,
    on_stderr = handle_stderr,
    on_exit = handle_exit,
  })

  if job_id <= 0 then
    return false, "Failed to start codex app-server"
  end

  M.state.job_id = job_id

  local convo_params = {
    model = config.model,
    approvalPolicy = config.approval_policy,
    sandbox = config.sandbox,
  }

  ensure_conversation(convo_params)

  return true, job_id
end

function M.stop()
  M.state.shutting_down = true
  if M.state.job_id then
    pcall(vim.fn.chanclose, M.state.job_id)
    pcall(vim.fn.jobstop, M.state.job_id)
  end
  M.state.job_id = nil
  reset_state()
  return true
end

local function make_text_item(text)
  return {
    type = "text",
    data = {
      text = text,
    },
  }
end

local function send_user_message(text)
  if not M.is_ready() then
    return false, "Codex session not ready"
  end

  local items = {
    make_text_item(text),
  }

  local params = {
    conversationId = M.state.conversation_id,
    items = items,
  }

  return send_request("sendUserMessage", params, function(result, err)
    if err then
      logger.error("codex", "sendUserMessage failed", vim.inspect(err))
    end
  end)
end

local function read_file_segment(path, start_line, end_line)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end

  if start_line and end_line and start_line >= 0 and end_line >= start_line then
    local slice = {}
    for i = start_line + 1, math.min(#lines, end_line + 1) do
      table.insert(slice, lines[i])
    end
    lines = slice
  end

  return table.concat(lines, "\n")
end

function M.send_at_mention(path, start_line, end_line)
  if not path or path == "" then
    return false, "No path provided"
  end

  local content = read_file_segment(path, start_line, end_line)
  if not content then
    content = string.format("[unable to read %s]", path)
  end

  local header
  if start_line and end_line then
    header = string.format("@%s:%d-%d", path, start_line + 1, end_line + 1)
  else
    header = string.format("@%s", path)
  end

  local message = string.format("%s\n\n%s", header, content)
  local ok, err = send_user_message(message)
  if ok then
    logger.info("codex", string.format("Sent @ mention: %s", header))
  end
  return ok, err
end

function M.send_selection(text, metadata)
  if not text or text == "" then
    return false, "Selection empty"
  end

  local header
  if metadata and metadata.source then
    header = string.format("Selection from %s", metadata.source)
  else
    header = "Selection"
  end

  local message = string.format("%s:\n\n%s", header, text)
  local ok, err = send_user_message(message)
  return ok, err
end

return M
