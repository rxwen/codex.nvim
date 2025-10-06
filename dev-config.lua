-- Development configuration for codex.nvim
-- This is Thomas's personal config for developing codex.nvim
-- Symlink this to your personal Neovim config:
-- ln -s ~/projects/codex.nvim/dev-config.lua ~/.config/nvim/lua/plugins/dev-codex.lua

return {
  "coder/codex.nvim",
  dev = true, -- Use local development version
  keys = {
    -- AI/Codex Code prefix
    { "<leader>a", nil, desc = "AI/Codex Code" },

    -- Core Codex commands
    { "<leader>ac", "<cmd>CodexCode<cr>", desc = "Toggle Codex" },
    { "<leader>af", "<cmd>CodexCodeFocus<cr>", desc = "Focus Codex" },
    { "<leader>ar", "<cmd>CodexCode --resume<cr>", desc = "Resume Codex" },
    { "<leader>aC", "<cmd>CodexCode --continue<cr>", desc = "Continue Codex" },
    { "<leader>am", "<cmd>CodexCodeSelectModel<cr>", desc = "Select Codex model" },

    -- Context sending
    { "<leader>as", "<cmd>CodexCodeAdd %<cr>", mode = "n", desc = "Add current buffer" },
    { "<leader>as", "<cmd>CodexCodeSend<cr>", mode = "v", desc = "Send to Codex" },
    {
      "<leader>as",
      "<cmd>CodexCodeTreeAdd<cr>",
      desc = "Add file from tree",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
    },

    -- Development helpers
    { "<leader>ao", "<cmd>CodexCodeOpen<cr>", desc = "Open Codex" },
    { "<leader>aq", "<cmd>CodexCodeClose<cr>", desc = "Close Codex" },
    { "<leader>ai", "<cmd>CodexCodeStatus<cr>", desc = "Codex Status" },
    { "<leader>aS", "<cmd>CodexCodeStart<cr>", desc = "Start Codex Server" },
    { "<leader>aQ", "<cmd>CodexCodeStop<cr>", desc = "Stop Codex Server" },

    -- Diff management (buffer-local, only active in diff buffers)
    { "<leader>aa", "<cmd>CodexCodeDiffAccept<cr>", desc = "Accept diff" },
    { "<leader>ad", "<cmd>CodexCodeDiffDeny<cr>", desc = "Deny diff" },
  },

  -- Development configuration - all options shown with defaults commented out
  ---@type PartialCodexCodeConfig
  opts = {
    -- Server Configuration
    -- port_range = { min = 10000, max = 65535 }, -- WebSocket server port range
    -- auto_start = true, -- Auto-start server on Neovim startup
    -- log_level = "info", -- "trace", "debug", "info", "warn", "error"
    -- terminal_cmd = nil, -- Custom terminal command (default: "claude")

    -- Send/Focus Behavior
    focus_after_send = true, -- Focus Codex terminal after successful send while connected

    -- Selection Tracking
    -- track_selection = true, -- Enable real-time selection tracking
    -- visual_demotion_delay_ms = 50, -- Delay before demoting visual selection (ms)

    -- Connection Management
    -- connection_wait_delay = 200, -- Wait time after connection before sending queued @ mentions (ms)
    -- connection_timeout = 10000, -- Max time to wait for Codex Code connection (ms)
    -- queue_timeout = 5000, -- Max time to keep @ mentions in queue (ms)

    -- Diff Integration
    -- diff_opts = {
    --   layout = "horizontal", -- "vertical" or "horizontal" diff layout
    --   open_in_new_tab = true, -- Open diff in a new tab (false = use current tab)
    --   keep_terminal_focus = true, -- Keep focus in terminal after opening diff
    --   hide_terminal_in_new_tab = true, -- Hide Codex terminal in the new diff tab for more review space
    -- },

    -- Terminal Configuration
    -- terminal = {
    --   split_side = "right",                     -- "left" or "right"
    --   split_width_percentage = 0.30,            -- Width as percentage (0.0 to 1.0)
    --   provider = "auto",                        -- "auto", "snacks", or "native"
    --   show_native_term_exit_tip = true,         -- Show exit tip for native terminal
    --   auto_close = true,                        -- Auto-close terminal after command completion
    --   snacks_win_opts = {},                     -- Opts to pass to `Snacks.terminal.open()`
    -- },

    -- Development overrides (uncomment as needed)
    -- log_level = "debug",
    -- terminal = {
    --   provider = "native",
    --   auto_close = false, -- Keep terminals open to see output
    -- },
  },
}
