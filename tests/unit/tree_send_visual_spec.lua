require("tests.busted_setup")
require("tests.mocks.vim")

describe("CodexSend visual selection in tree buffers", function()
  local original_require
  local codex
  local command_callback

  local mock_server
  local mock_logger
  local mock_visual_commands
  local mock_integrations

  before_each(function()
    -- Reset package cache
    package.loaded["codex"] = nil
    package.loaded["codex.visual_commands"] = nil
    package.loaded["codex.integrations"] = nil
    package.loaded["codex.server.init"] = nil
    package.loaded["codex.lockfile"] = nil
    package.loaded["codex.config"] = nil
    package.loaded["codex.logger"] = nil
    package.loaded["codex.diff"] = nil

    -- Mocks
    mock_server = {
      broadcast = spy.new(function()
        return true
      end),
      start = function()
        return true, 12345
      end,
      stop = function()
        return true
      end,
    }

    mock_logger = {
      setup = function() end,
      debug = function() end,
      error = function() end,
      warn = function() end,
    }

    local visual_data = {
      tree_state = {},
      tree_type = "neo-tree",
      start_pos = 10,
      end_pos = 12,
    }

    mock_visual_commands = {
      -- Force the command to take the visual path by immediately invoking the visual handler
      create_visual_command_wrapper = function(_normal_handler, visual_handler)
        return function()
          return visual_handler(visual_data)
        end
      end,
      get_files_from_visual_selection = spy.new(function(data)
        assert.is_truthy(data)
        return {
          "/proj/a.lua",
          "/proj/b.lua",
          "/proj/dir",
        }, nil
      end),
    }

    mock_integrations = {
      get_selected_files_from_tree = spy.new(function()
        -- Should not be called when visual selection produces files
        return {}, "should_not_be_called"
      end),
      _get_mini_files_selection_with_range = function()
        return {}, "unused"
      end,
    }

    -- Mock vim API and environment
    _G.vim.api.nvim_create_user_command = spy.new(function(name, callback, opts)
      if name == "CodexSend" then
        command_callback = callback
      end
    end)
    _G.vim.api.nvim_create_augroup = spy.new(function()
      return 1
    end)
    _G.vim.api.nvim_create_autocmd = spy.new(function()
      return 1
    end)
    _G.vim.api.nvim_replace_termcodes = function(s)
      return s
    end
    _G.vim.api.nvim_feedkeys = function() end

    _G.vim.fn.mode = function()
      return "v"
    end
    _G.vim.fn.line = function(_)
      return 10
    end
    _G.vim.bo = { filetype = "neo-tree" }

    -- Mock require
    original_require = _G.require
    _G.require = function(module)
      if module == "codex.logger" then
        return mock_logger
      elseif module == "codex.visual_commands" then
        return mock_visual_commands
      elseif module == "codex.integrations" then
        return mock_integrations
      elseif module == "codex.server.init" then
        return {
          get_status = function()
            return { running = true, client_count = 1 }
          end,
        }
      elseif module == "codex.lockfile" then
        return {
          create = function()
            return true, "/tmp/mock.lock", "auth"
          end,
          remove = function()
            return true
          end,
          generate_auth_token = function()
            return "auth"
          end,
        }
      elseif module == "codex.config" then
        return {
          apply = function(opts)
            return opts or { log_level = "info" }
          end,
        }
      elseif module == "codex.diff" then
        return { setup = function() end }
      elseif module == "codex.terminal" then
        return {
          setup = function() end,
          open = function() end,
          ensure_visible = function() end,
        }
      else
        return original_require(module)
      end
    end

    -- Load plugin and setup
    codex = require("codex")
    codex.setup({ auto_start = false })
    codex.state.server = mock_server
    codex.state.port = 12345
    -- Ensure immediate broadcast path in tests
    codex.state.config.disable_broadcast_debouncing = true

    -- Spy on send_at_mention to count file sends without relying on broadcast internals
    codex.send_at_mention = spy.new(function()
      return true
    end)
  end)

  after_each(function()
    _G.require = original_require
  end)

  it("uses visual selection path and broadcasts all files", function()
    assert.is_function(command_callback)

    -- Invoke the command (our wrapper will dispatch to visual handler)
    command_callback({})

    -- Should use visual selection, not fallback integrations
    assert.spy(mock_visual_commands.get_files_from_visual_selection).was_called()
    assert.spy(mock_integrations.get_selected_files_from_tree).was_not_called()

    -- 3 files should be sent via send_at_mention
    assert.spy(codex.send_at_mention).was_called()
    local call_count = #codex.send_at_mention.calls
    assert.is_true(call_count == 3, "Expected 3 sends, got " .. tostring(call_count))
  end)
end)
