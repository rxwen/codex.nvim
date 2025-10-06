-- Simple config module tests that don't rely on the vim API

_G.vim = { ---@type vim_global_api
  schedule_wrap = function(fn)
    return fn
  end,
  deepcopy = function(t)
    -- Basic deepcopy implementation for testing purposes
    local copy = {}
    for k, v in pairs(t) do
      if type(v) == "table" then
        copy[k] = _G.vim.deepcopy(v)
      else
        copy[k] = v
      end
    end
    return copy
  end,
  notify = function(_, _, _) end,
  log = {
    levels = {
      NONE = 0,
      ERROR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4,
      TRACE = 5,
    },
  },
  o = { ---@type vim_options_table
    columns = 80,
    lines = 24,
  },
  bo = setmetatable({}, { -- Mock for vim.bo and vim.bo[bufnr]
    __index = function(t, k)
      if type(k) == "number" then
        if not t[k] then
          t[k] = {} ---@type vim_buffer_options_table
        end
        return t[k]
      end
      return nil
    end,
    __newindex = function(t, k, v)
      if type(k) == "number" then
        -- For mock simplicity, allows direct setting for vim.bo[bufnr].opt = val or similar assignments.
        if not t[k] then
          t[k] = {}
        end
        rawset(t[k], v) -- Assuming v is the option name if k is bufnr, this is simplified
      else
        rawset(t, k, v)
      end
    end,
  }), ---@type vim_bo_proxy
  diagnostic = { ---@type vim_diagnostic_module
    get = function()
      return {}
    end,
    -- Add other vim.diagnostic functions as needed for these tests
  },
  empty_dict = function()
    return {}
  end,

  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local tables = { ... }

    for _, tbl in ipairs(tables) do
      for k, v in pairs(tbl) do
        if type(v) == "table" and type(result[k]) == "table" then
          result[k] = _G.vim.tbl_deep_extend(behavior, result[k], v)
        else
          result[k] = v
        end
      end
    end

    return result
  end,
  cmd = function() end, ---@type fun(command: string):nil
  api = {}, ---@type table
  fn = { ---@type vim_fn_table
    mode = function()
      return "n"
    end,
    delete = function(_, _)
      return 0
    end,
    filereadable = function(_)
      return 1
    end,
    fnamemodify = function(fname, _)
      return fname
    end,
    expand = function(s, _)
      return s
    end,
    getcwd = function()
      return "/mock/cwd"
    end,
    mkdir = function(_, _, _)
      return 1
    end,
    buflisted = function(_)
      return 1
    end,
    bufname = function(_)
      return "mockbuffer"
    end,
    bufnr = function(_)
      return 1
    end,
    win_getid = function()
      return 1
    end,
    win_gotoid = function(_)
      return true
    end,
    line = function(_)
      return 1
    end,
    col = function(_)
      return 1
    end,
    virtcol = function(_)
      return 1
    end,
    getpos = function(_)
      return { 0, 1, 1, 0 }
    end,
    setpos = function(_, _)
      return true
    end,
    tempname = function()
      return "/tmp/mocktemp"
    end,
    globpath = function(_, _)
      return ""
    end,
    termopen = function(_, _)
      return 0
    end,
    stdpath = function(_)
      return "/mock/stdpath"
    end,
    json_encode = function(_)
      return "{}"
    end,
    json_decode = function(_)
      return {}
    end,
  },
  fs = { remove = function() end }, ---@type vim_fs_module
}

describe("Config module", function()
  local config

  setup(function()
    -- Reset the module to ensure a clean state for each test
    package.loaded["codex.config"] = nil

    config = require("codex.config")
  end)

  it("should have default values", function()
    assert(type(config.defaults) == "table")
    assert(type(config.defaults.port_range) == "table")
    assert(type(config.defaults.port_range.min) == "number")
    assert(type(config.defaults.port_range.max) == "number")
    assert(type(config.defaults.auto_start) == "boolean")
    assert(type(config.defaults.log_level) == "string")
    assert(type(config.defaults.track_selection) == "boolean")
  end)

  it("should apply and validate user configuration", function()
    local user_config = {
      terminal_cmd = "toggleterm",
      log_level = "debug",
      track_selection = false,
      models = {
        { name = "Codex Opus 4 (Latest)", value = "claude-opus-4-20250514" },
        { name = "Codex Sonnet 4 (Latest)", value = "claude-sonnet-4-20250514" },
      },
    }

    local success, final_config = pcall(function()
      return config.apply(user_config)
    end)

    assert(success == true)
    assert(final_config.env ~= nil) -- Should inherit default empty table
    assert(type(final_config.env) == "table")
  end)

  it("should merge user config with defaults", function()
    local user_config = {
      auto_start = true,
      log_level = "debug",
    }

    local merged_config = config.apply(user_config)

    assert(merged_config.auto_start == true)
    assert("debug" == merged_config.log_level)
    assert(config.defaults.port_range.min == merged_config.port_range.min)
    assert(config.defaults.track_selection == merged_config.track_selection)
  end)
end)
