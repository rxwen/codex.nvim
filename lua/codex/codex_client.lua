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
---@field session_info table|nil
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
  session_info = nil,
}

---@type table<string, fun(params: table, ctx: table)>
M._request_handlers = {}
---@type fun(event_type: string, params: table)|nil
M._event_callback = nil
---@type fun(info: table)|nil
M._session_configured_callback = nil

local send_payload

local function reset_state()
  M.state.stdout_buffer = ""
  M.state.stderr_buffer = ""
  M.state.pending = {}
  M.state.next_id = 1
  M.state.ready = false
  M.state.conversation_id = nil
  M.state.subscription_id = nil
  M.state.shutting_down = false
  M.state.session_info = nil
end

local function emit_notification(level, ...)
  local ok_notify, notify = pcall(vim.notify, table.concat(vim.tbl_map(tostring, { ... }), " "), level)
  if not ok_notify then
    logger.info("codex", ...)
  end
end

local function handle_event(event_type, params)
  local handled = false

  if event_type == "agent_message" and params.msg and params.msg.message then
    emit_notification(vim.log.levels.INFO, params.msg.message)
    handled = true
  elseif event_type == "agent_message_delta" and params.msg and params.msg.delta then
    emit_notification(vim.log.levels.INFO, params.msg.delta)
    handled = true
  elseif event_type == "error" and params.msg and params.msg.message then
    emit_notification(vim.log.levels.ERROR, params.msg.message)
    handled = true
  elseif event_type == "task_complete" then
    emit_notification(vim.log.levels.INFO, "Codex task complete")
    handled = true
  end

  if not handled then
    logger.debug("codex", "Unhandled Codex event", event_type, vim.inspect(params))
  end

  if M._event_callback then
    local ok, err = pcall(M._event_callback, event_type, params or {})
    if not ok then
      logger.warn("codex", "Event callback error", err)
    end
  end
end

local function handle_notification(method, params)
  if method == "sessionConfigured" then
    M.state.ready = true
    M.state.session_info = params or {}
    logger.info("codex", "Session configured")
    if M._session_configured_callback then
      local ok, err = pcall(M._session_configured_callback, params or {})
      if not ok then
        logger.warn("codex", "Session callback error", err)
      end
    end
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

  if message.id ~= nil and message.method ~= nil then
    handle_request(message)
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
    handle_notification(message.method, message.params)
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

send_payload = function(payload)
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

local function send_json_response(id, result)
  local payload = {
    jsonrpc = "2.0",
    id = id,
    result = result or vim.empty_dict(),
  }
  local ok, err = send_payload(payload)
  if not ok then
    logger.error("codex", "Failed to send response", err or "unknown error")
  end
end

local function send_json_error(id, error_tbl)
  local payload = {
    jsonrpc = "2.0",
    id = id,
    error = error_tbl,
  }
  local ok, err = send_payload(payload)
  if not ok then
    logger.error("codex", "Failed to send error response", err or "unknown error")
  end
end

local function handle_request(message)
  local method = message.method
  local params = message.params or {}
  local id = message.id

  local handler = M._request_handlers[method]
  if not handler then
    send_json_error(id, {
      code = -32601,
      message = "Unsupported Codex request: " .. tostring(method),
    })
    return
  end

  local responded = false
  local deferred = false

  local function respond(result)
    if responded then
      logger.debug("codex", "Duplicate response suppressed for request", method)
      return
    end
    responded = true
    send_json_response(id, result)
  end

  local function respond_error(err)
    if responded then
      logger.debug("codex", "Duplicate error suppressed for request", method)
      return
    end
    responded = true
    if type(err) ~= "table" then
      err = { code = -32603, message = "Internal error", data = tostring(err) }
    else
      err.code = err.code or -32603
      err.message = err.message or "Internal error"
    end
    send_json_error(id, err)
  end

  local ctx = {
    respond = respond,
    respond_error = respond_error,
    defer = function()
      deferred = true
    end,
    method = method,
    id = id,
  }

  local ok, ret1, ret2 = pcall(handler, params, ctx)
  if not ok then
    respond_error({ code = -32603, message = "Internal error", data = tostring(ret1) })
    return
  end

  if responded or deferred then
    return
  end

  if ret1 == false then
    respond_error(ret2)
  else
    respond(ret1 or vim.empty_dict())
  end
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

    logger.debug("codex", "Initialized Codex app-server", vim.inspect(result))

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

      logger.debug("codex", "Started conversation", M.state.conversation_id)

      send_request("addConversationListener", {
        conversationId = M.state.conversation_id,
      }, function(listener_result, listener_err)
        if listener_err then
          logger.error("codex", "Failed to add conversation listener", vim.inspect(listener_err))
          return
        end
        M.state.subscription_id = listener_result.subscriptionId or listener_result.subscription_id
        M.state.ready = true
        logger.debug("codex", "Codex listener subscription", M.state.subscription_id)
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

local function send_user_message_items(items)
  if not M.is_ready() then
    return false, "Codex session not ready"
  end

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

local function send_user_message(text)
  return send_user_message_items({
    make_text_item(text),
  })
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

  local items = {
    make_text_item(header),
    make_text_item(""),
    make_text_item(content),
  }
  local ok, err = send_user_message_items(items)
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

  local items = {
    make_text_item(header .. ":"),
    make_text_item(""),
    make_text_item(text),
  }
  local ok, err = send_user_message_items(items)
  return ok, err
end

function M.register_request_handlers(handlers)
  if type(handlers) ~= "table" then
    M._request_handlers = {}
    return
  end

  local filtered = {}
  for method, fn in pairs(handlers) do
    if type(method) == "string" and type(fn) == "function" then
      filtered[method] = fn
    end
  end
  M._request_handlers = filtered
end

function M.on_event(callback)
  if callback ~= nil and type(callback) ~= "function" then
    error("codex_client.on_event expects a function or nil")
  end
  M._event_callback = callback
end

function M.on_session_configured(callback)
  if callback ~= nil and type(callback) ~= "function" then
    error("codex_client.on_session_configured expects a function or nil")
  end
  M._session_configured_callback = callback
end

return M
