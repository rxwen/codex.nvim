describe("codex.terminal.external", function()
  local external_provider
  local mock_vim
  local original_vim
  local spy

  before_each(function()
    -- Store original vim global
    original_vim = vim

    -- Create spy module
    spy = require("luassert.spy")

    -- Create mock vim
    mock_vim = {
      fn = {
        jobstart = spy.new(function()
          return 123
        end), -- Return valid job id
        jobstop = spy.new(function() end),
        getcwd = spy.new(function()
          return "/cwd"
        end),
      },
      notify = spy.new(function() end),
      log = {
        levels = {
          ERROR = 3,
          WARN = 2,
          INFO = 1,
          DEBUG = 0,
        },
      },
      split = function(str, sep)
        local result = {}
        for part in string.gmatch(str, "[^" .. sep .. "]+") do
          table.insert(result, part)
        end
        return result
      end,
      schedule = function(fn)
        fn()
      end,
    }

    -- Set global vim to mock
    _G.vim = mock_vim

    -- Clear package cache and reload module
    package.loaded["codex.terminal.external"] = nil
    package.loaded["codex.logger"] = nil

    -- Mock logger
    package.loaded["codex.logger"] = {
      debug = spy.new(function() end),
      info = spy.new(function() end),
      warn = spy.new(function() end),
      error = spy.new(function() end),
    }

    external_provider = require("codex.terminal.external")
  end)

  after_each(function()
    -- Restore original vim
    _G.vim = original_vim
  end)

  describe("setup", function()
    it("should store config", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = "alacritty -e %s",
        },
      }
      external_provider.setup(config)
      -- Setup doesn't return anything, just verify it doesn't error
      assert(true)
    end)
  end)

  describe("open with string command", function()
    it("should handle string command with %s placeholder", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = "alacritty -e %s",
        },
      }
      external_provider.setup(config)

      external_provider.open("claude --help", { ENABLE_IDE_INTEGRATION = "true" })

      assert.spy(mock_vim.fn.jobstart).was_called(1)
      local call_args = mock_vim.fn.jobstart.calls[1].vals
      assert.are.same({ "alacritty", "-e", "claude", "--help" }, call_args[1])
      assert.are.same({ ENABLE_IDE_INTEGRATION = "true" }, call_args[2].env)
      assert.are.equal("/cwd", call_args[2].cwd)
    end)

    it("should error if string command missing %s placeholder", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = "alacritty -e claude",
        },
      }
      external_provider.setup(config)

      external_provider.open("claude --help", {})

      assert
        .spy(mock_vim.notify)
        .was_called_with("external_terminal_cmd must contain '%s' placeholder(s) for the command.", mock_vim.log.levels.ERROR)
      assert.spy(mock_vim.fn.jobstart).was_not_called()
    end)

    it("should error if string command is empty", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = "",
        },
      }
      external_provider.setup(config)

      external_provider.open("claude", {})

      assert.spy(mock_vim.notify).was_called()
      assert.spy(mock_vim.fn.jobstart).was_not_called()
    end)

    it("should handle string with two placeholders (cwd and command)", function()
      -- Mock vim.fn.getcwd to return a known directory
      mock_vim.fn.getcwd = spy.new(function()
        return "/test/project"
      end)

      local config = {
        provider_opts = {
          external_terminal_cmd = "alacritty --working-directory %s -e %s",
        },
      }
      external_provider.setup(config)

      external_provider.open("claude --help", { ENABLE_IDE_INTEGRATION = "true" })

      assert.spy(mock_vim.fn.jobstart).was_called(1)
      local call_args = mock_vim.fn.jobstart.calls[1].vals
      assert.are.same({ "alacritty", "--working-directory", "/test/project", "-e", "claude", "--help" }, call_args[1])
      assert.are.same({ ENABLE_IDE_INTEGRATION = "true" }, call_args[2].env)
      assert.are.equal("/test/project", call_args[2].cwd)
    end)

    it("should error if string has more than two placeholders", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = "alacritty --working-directory %s -e %s --title %s",
        },
      }
      external_provider.setup(config)

      external_provider.open("claude --help", {})

      assert.spy(mock_vim.notify).was_called_with(
        "external_terminal_cmd must use 1 '%s' (command) or 2 '%s' placeholders (cwd, command); got 3",
        mock_vim.log.levels.ERROR
      )
      assert.spy(mock_vim.fn.jobstart).was_not_called()
    end)
  end)

  describe("open with function command", function()
    it("should handle function returning string", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = function(cmd, env)
            return "kitty " .. cmd
          end,
        },
      }
      external_provider.setup(config)

      external_provider.open("claude --help", { ENABLE_IDE_INTEGRATION = "true" })

      assert.spy(mock_vim.fn.jobstart).was_called(1)
      local call_args = mock_vim.fn.jobstart.calls[1].vals
      assert.are.same({ "kitty", "claude", "--help" }, call_args[1])
      assert.are.same({ ENABLE_IDE_INTEGRATION = "true" }, call_args[2].env)
      assert.are.equal("/cwd", call_args[2].cwd)
    end)

    it("should handle function returning table", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = function(cmd, env)
            return { "osascript", "-e", 'tell app "Terminal" to do script "' .. cmd .. '"' }
          end,
        },
      }
      external_provider.setup(config)

      external_provider.open("claude", { ENABLE_IDE_INTEGRATION = "true" })

      assert.spy(mock_vim.fn.jobstart).was_called(1)
      local call_args = mock_vim.fn.jobstart.calls[1].vals
      assert.are.same({ "osascript", "-e", 'tell app "Terminal" to do script "claude"' }, call_args[1])
      assert.are.equal("/cwd", call_args[2].cwd)
    end)

    it("should pass cmd and env to function", function()
      local received_cmd, received_env
      local config = {
        provider_opts = {
          external_terminal_cmd = function(cmd, env)
            received_cmd = cmd
            received_env = env
            return "terminal " .. cmd
          end,
        },
      }
      external_provider.setup(config)

      local test_env = { ENABLE_IDE_INTEGRATION = "true", CLAUDE_CODE_SSE_PORT = "12345" }
      external_provider.open("claude --resume", test_env)

      assert.are.equal("claude --resume", received_cmd)
      assert.are.same(test_env, received_env)
    end)

    it("should error if function returns nil", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = function(cmd, env)
            return nil
          end,
        },
      }
      external_provider.setup(config)

      external_provider.open("claude", {})

      assert
        .spy(mock_vim.notify)
        .was_called_with("external_terminal_cmd function returned nil or false", mock_vim.log.levels.ERROR)
      assert.spy(mock_vim.fn.jobstart).was_not_called()
    end)

    it("should error if function returns invalid type", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = function(cmd, env)
            return 123 -- Invalid: number
          end,
        },
      }
      external_provider.setup(config)

      external_provider.open("claude", {})

      assert
        .spy(mock_vim.notify)
        .was_called_with("external_terminal_cmd function must return a string or table, got: number", mock_vim.log.levels.ERROR)
      assert.spy(mock_vim.fn.jobstart).was_not_called()
    end)
  end)

  describe("open with invalid config", function()
    it("should error if external_terminal_cmd not configured", function()
      external_provider.setup({})

      external_provider.open("claude", {})

      assert.spy(mock_vim.notify).was_called_with(
        "external_terminal_cmd not configured. Please set terminal.provider_opts.external_terminal_cmd in your config.",
        mock_vim.log.levels.ERROR
      )
      assert.spy(mock_vim.fn.jobstart).was_not_called()
    end)

    it("should error if external_terminal_cmd is invalid type", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = 123, -- Invalid: number
        },
      }
      external_provider.setup(config)

      external_provider.open("claude", {})

      assert
        .spy(mock_vim.notify)
        .was_called_with("external_terminal_cmd must be a string or function, got: number", mock_vim.log.levels.ERROR)
      assert.spy(mock_vim.fn.jobstart).was_not_called()
    end)
  end)

  describe("close", function()
    it("should stop job if valid", function()
      local config = {
        provider_opts = {
          external_terminal_cmd = "alacritty -e %s",
        },
      }
      external_provider.setup(config)

      -- Start a terminal
      external_provider.open("claude", {})

      -- Close it
      external_provider.close()

      assert.spy(mock_vim.fn.jobstop).was_called_with(123)
    end)

    it("should not error if no job running", function()
      external_provider.close()
      assert.spy(mock_vim.fn.jobstop).was_not_called()
    end)
  end)

  describe("other methods", function()
    it("get_active_bufnr should return nil for external terminals", function()
      assert.is_nil(external_provider.get_active_bufnr())
    end)

    it("is_available should return true", function()
      assert.is_true(external_provider.is_available())
    end)

    it("ensure_visible should be a no-op", function()
      -- Should not error
      external_provider.ensure_visible()
      assert(true)
    end)
  end)
end)
