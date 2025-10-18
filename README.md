# codex.nvim

> **Project intention:** This fork keeps the polished Neovim UX delivered by the original [`codex.nvim`](https://github.com/coder/codex.nvim) while routing the integration to OpenAI Codex. You still get the mature workflow (commands, keymaps, diff tooling); the backend now speaks to the Codex CLI and its JSON-RPC surface.

[![Tests](https://github.com/coder/codex.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/coder/codex.nvim/actions/workflows/test.yml)
![Neovim version](https://img.shields.io/badge/Neovim-0.8%2B-green)
![Status](https://img.shields.io/badge/Status-beta-blue)

**Bring OpenAI Codex to Neovim** — launch the Codex CLI from inside your editor with a pure Lua implementation that now understands Codex’s approvals, streaming events, and context protocol.

> 🎯 **TL;DR:** The plugin boots `codex app-server`, keeps the familiar `Codex*` commands/keymaps, and streams your selections/files straight to Codex. Recent updates add interactive approvals, a live transcript buffer, and smarter connection handling.

<https://github.com/user-attachments/assets/9c310fb5-5a23-482b-bedc-e21ae457a82d>

## Highlights

- ✅ **Interactive approvals inside Neovim** – `applyPatchApproval` requests open native diff tabs, while `execCommandApproval` prompts through `vim.ui.select`; approve or deny without leaving the editor.
- 📝 **Streaming transcript buffer** – Codex agent/user/system messages stream into a Markdown buffer. Open it any time with `:lua require("codex.chat").open()`.
- 🔄 **Connection-aware context queue** – `@file` mentions and visual selections queue safely until the Codex session is ready, then flush in order with debounce and timeout guards.
- 🧭 **Configurable diff ergonomics** – Horizontal/vertical layouts, new-tab flow, and better focus handling let you fit Codex edits into your window workflow.

## Installation

```lua
{
  "rxwen/codex.nvim",
  dependencies = { "folke/snacks.nvim" },
  config = true,
  keys = {
    { "<leader>a", nil, desc = "AI / Codex" },
    { "<leader>ac", "<cmd>Codex<cr>", desc = "Toggle Codex terminal" },
    { "<leader>af", "<cmd>CodexFocus<cr>", desc = "Focus Codex terminal" },
    { "<leader>ar", "<cmd>Codex --resume<cr>", desc = "Resume Codex CLI" },
    { "<leader>aC", "<cmd>Codex --continue<cr>", desc = "Continue Codex CLI" },
    { "<leader>am", "<cmd>CodexSelectModel<cr>", desc = "Select Codex model" },
    { "<leader>ab", "<cmd>CodexAdd %<cr>", desc = "Add current buffer" },
    { "<leader>as", "<cmd>CodexSend<cr>", mode = "v", desc = "Send selection to Codex" },
    {
      "<leader>as",
      "<cmd>CodexTreeAdd<cr>",
      desc = "Add tree selection to Codex",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
    },
    -- Diff management
    { "<leader>aa", "<cmd>CodexDiffAccept<cr>", desc = "Accept Codex diff" },
    { "<leader>ad", "<cmd>CodexDiffDeny<cr>", desc = "Reject Codex diff" },
  },
}
```

That’s it! `require("codex").setup()` wires the server, terminal, and defaults for you.

## Requirements

- Neovim ≥ 0.8.0
- [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`, or build from source)
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) for the enhanced terminal provider (optional; native terminal fallback included)

### Customising the Codex binary

By default the plugin executes `codex app-server`. If you installed the CLI elsewhere, set `opts.codex_cmd = "/path/to/codex"` (or pass arguments directly to `require("codex").setup`). You can also override `terminal_cmd` to point at an alternate wrapper script, and populate `opts.env` to inject environment variables into the Codex terminal.

## Quick Demo

```vim
" Launch Codex in a split
:Codex

" Stream a visual selection as context
:'<,'>CodexSend

" Approve or reject proposed edits in-place
:CodexDiffAccept
```

## Usage

1. **Start the integration** – `setup()` auto-starts Codex unless you set `auto_start = false`. You can control lifecycle explicitly with `:CodexStart`, `:CodexStop`, and `:CodexStatus`.
2. **Open the terminal** – `:Codex`, `:CodexFocus`, `:CodexOpen`, and `:CodexClose` manage the Codex CLI window via your chosen terminal provider.
3. **Send context** – Use `<leader>as` in visual mode, `:CodexAdd <path> [start] [end]`, or `:CodexTreeAdd` inside supported file explorers. Selections queue until the Codex session is ready.
4. **Review output** – Watch the CLI, open the transcript buffer, or inspect diff tabs when Codex proposes edits. Approvals flow through Neovim prompts.

## Key Commands

- `:CodexStart` / `:CodexStop` / `:CodexStatus` – Control the WebSocket bridge and check connectivity.
- `:Codex`, `:CodexFocus`, `:CodexOpen`, `:CodexClose` – Manage the Codex terminal window.
- `:CodexSend` – Send the current visual selection (tree-aware).
- `:CodexAdd <file> [start] [end]` – Manually add a file or range.
- `:CodexTreeAdd` – Add selected files from NvimTree/neo-tree/oil/mini.files/netrw.
- `:CodexSelectModel` – Pick a configured model before launching Codex CLI.
- `:CodexDiffAccept` / `:CodexDiffDeny` – Accept or reject the active diff proposal.

## Working with Diffs

Codex proposals open in a dedicated diff tab with your configured layout:

- **Accept** – Write the proposed buffer (`:w`) or trigger `:CodexDiffAccept`.
- **Reject** – Close the diff window (`:q`) or call `:CodexDiffDeny`.
- **New-file behaviour** – Control whether a rejected new-file buffer stays open via `diff_opts.on_new_file_reject`.

Diff windows respect `diff_opts.layout`, `diff_opts.open_in_new_tab`, and focus-handling options so you can fit Codex edits into your existing window workflow.

## Approvals & Safety

Codex CLI now requests approval before mutating your workspace:

- **Apply patch** – `applyPatchApproval` opens each file in a blocking diff flow. Saving approves, closing rejects. Multiple files are processed sequentially with helpful log summaries.
- **Run command** – `execCommandApproval` surfaces the requested command, cwd, and reason via `vim.ui.select`. Choose “Approve” or “Deny” to respond.
- **Policy/sandbox hints** – Surface Codex defaults in the transcript and configure them with `codex_approval_policy` and `codex_sandbox_mode`.

Every approval path is asynchronous: the CLI waits for your response while Neovim remains responsive.

## Live Transcript

All Codex events are mirrored into a Markdown transcript buffer:

```vim
:lua require("codex.chat").open()
```

Use it to review agent reasoning, system notices, and your own prompts without leaving Neovim. The buffer stays hidden until you open it and survives across sessions until wiped.

## Advanced Configuration

```lua
{
  "rxwen/codex.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    -- Core behaviour
    auto_start = true,
    log_level = "info", -- "trace" | "debug" | "info" | "warn" | "error"
    track_selection = false, -- set true to stream cursor context automatically
    focus_after_send = false,
    connection_wait_delay = 600,
    connection_timeout = 10000,
    queue_timeout = 5000,
    port_range = { min = 10000, max = 65535 },

    -- Codex CLI orchestration
    codex_cmd = "codex",
    terminal_cmd = nil, -- override command executed inside terminal if needed
    env = {}, -- extra env vars for Codex CLI
    codex_approval_policy = nil, -- e.g. "untrusted", forwarded to Codex CLI
    codex_sandbox_mode = nil, -- e.g. "workspace-write"
    models = {
      { name = "GPT-5 Codex", value = "gpt-5-codex" },
      { name = "GPT-5", value = "gpt-5" },
    },
    default_model = "gpt-5-codex",

    -- Diff ergonomics
    diff_opts = {
      layout = "vertical", -- or "horizontal"
      open_in_new_tab = false,
      keep_terminal_focus = false,
      hide_terminal_in_new_tab = false,
      on_new_file_reject = "keep_empty", -- or "close_window"
    },

    -- Terminal provider configuration
    terminal = {
      split_side = "right",
      split_width_percentage = 0.30,
      provider = "auto", -- "auto" | "snacks" | "native" | "external" | "none" | custom table
      provider_opts = {
        external_terminal_cmd = nil, -- string template or function(cmd, env)
      },
      auto_close = true,
      show_native_term_exit_tip = true,
      env = {}, -- env overrides applied when spawning the terminal job
      snacks_win_opts = {}, -- forwarded to Snacks.terminal.open()
      cwd = nil,
      git_repo_cwd = false,
      cwd_provider = nil, -- function(ctx) -> cwd
    },
  },
}
```

Notable tips:

- **Selection tracking** – Enable `track_selection = true` if you want cursor movements to stream automatically; leave it off to manage context manually.
- **Environment control** – Populate `env` (top-level or terminal-specific) to forward tokens, proxies, or feature flags to the Codex CLI.
- **Model presets** – Extend `models` with additional `{ name, value }` entries to power `:CodexSelectModel`.

## Working Directory Control

Pin the Codex terminal’s working directory regardless of `autochdir` or buffer-local cwd changes. Options (highest precedence first):

- `cwd_provider(ctx)` – function receiving `{ file, file_dir, cwd }` and returning a directory string.
- `cwd` – static path.
- `git_repo_cwd = true` – use the git root derived from the active buffer (or current cwd).

Example:

```lua
require("codex").setup({
  terminal = {
    cwd_provider = function(ctx)
      return require("codex.cwd").git_root(ctx.file_dir or ctx.cwd) or ctx.file_dir or ctx.cwd
    end,
  },
})
```

## Floating Window Configuration (Snacks)

`snacks_win_opts` lets you create floating Codex terminals with custom positioning and behaviour:

```lua
local toggle_key = "<C-,>"
return {
  {
    "rxwen/codex.nvim",
    dependencies = { "folke/snacks.nvim" },
    keys = {
      { toggle_key, "<cmd>CodexFocus<cr>", desc = "Codex (Ctrl+,)", mode = { "n", "x" } },
    },
    opts = {
      terminal = {
        snacks_win_opts = {
          position = "float",
          width = 0.85,
          height = 0.85,
          border = "rounded",
          keys = {
            codex_hide = { toggle_key, function(self) self:hide() end, mode = "t", desc = "Hide" },
          },
        },
      },
    },
  },
}
```

See the [Snacks terminal docs](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md) for all available window options.

## Terminal Providers

- **`native`** – Always available fallback using Neovim’s built-in terminal.
- **`snacks`** – Integrates with Snacks.nvim if installed (auto-detected when `provider = "auto"`).
- **`external`** – Spawn Codex in another terminal application. Provide a template or function via `provider_opts.external_terminal_cmd` (remember to include `%s` placeholders for the command and optionally cwd).
- **`none`** – Skip terminal management entirely; useful when you prefer tmux/kitty but still want the server and tools.
- **Custom table** – Supply your own provider implementing `setup`, `open`, `close`, `simple_toggle`, `focus_toggle`, `get_active_bufnr`, and `is_available`.

Example external provider:

```lua
{
  "rxwen/codex.nvim",
  opts = {
    terminal = {
      provider = "external",
      provider_opts = {
        external_terminal_cmd = "alacritty --working-directory %s -e %s",
      },
    },
  },
}
```

## Auto-Save Plugins

Auto-save plugins may accept Codex diff buffers immediately. Guard against that by excluding Codex diff buffers using their buffer variables or naming convention. Example for `pocco81/auto-save.nvim`:

```lua
condition = function(buf)
  local bufname = vim.api.nvim_buf_get_name(buf)
  if bufname:match("%(proposed%)") or bufname:match("%(NEW FILE %- proposed%)") then
    return false
  end

  if vim.b[buf].codex_diff_tab_name then
    return false
  end

  return true
end,
```

## Troubleshooting

- **Codex not connecting?** Run `:CodexStatus` and confirm a lock file exists in `~/.claude/ide/` (Codex CLI still reads Claude Code lock paths for compatibility, or `$CLAUDE_CONFIG_DIR/ide/` if set).
- **Need debug logs?** Set `log_level = "debug"` (or `"trace"`) in your setup.
- **Terminal glitches?** Temporarily force `terminal.provider = "native"` to rule out Snacks or custom providers.
- **Custom Codex binary?** Ensure `codex_cmd` (and optionally `terminal_cmd`) point at the correct executable, and verify `which codex` returns the binary you expect.

## Contributing

See [DEVELOPMENT.md](./DEVELOPMENT.md) for build instructions and development guidelines. Run `make format`, `make check`, and `make test` before submitting changes.

## License

[MIT](LICENSE)

## Acknowledgements

- Built on the research and reverse-engineering from the original Coder/Claude Code integration.
- Thanks to the Codex CLI team for the JSON-RPC surface.
- Crafted with a little help from AI (how meta!).
