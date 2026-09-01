# **Scan-o-tron-3000.nvim**

Run one test, one suite, one file, or your whole project — with red/green gutter marks on every `it()`/`describe()` line and a navigable per-file tree of results, no neotest required.

## Why this exists

neotest's gutter icons drift out of sync, its adapter/config setup is heavier than it needs to be, running just one test or suite is inconsistent, and its output panel is hard to navigate per-file.

**`Scan-o-tron-3000.nvim` starts over with one source of truth per file:** a treesitter-derived position tree drives the gutter signs, the run-scoping ("what's under my cursor"), and the result panel — not three independently-drifting trackers.

---

## How it works

1. Triggering a run builds a fresh position tree of every `describe`/`it` in the current file via treesitter — there's no proactive scan on buffer open, the tree is (re)built on demand each time.
2. `:ScanOTron run-nearest` runs whatever test or suite the cursor is inside; `run-file` runs the whole file; `run-project` runs everything.
3. While a run is in flight, affected lines get a running mark; on completion they flip to a green check, red X, or (if a test never reported at all) a distinct "errored" mark — so a crashed run is never confused with a pass.
4. `:ScanOTron toggle-panel` opens a per-file tree of every test run this session; failing tests auto-expand with their captured output, `<CR>` jumps to a test's source line.
5. Only one run per file (or the whole project) runs at a time — triggering another mid-run no-ops with a notification rather than queueing.

---

## Installation

> **Requirements:** Neovim >= 0.10, `npx` on your `$PATH` for the `ts-spec` adapter (Vitest, Jest, or Mocha — auto-detected from `package.json`), and the `typescript` treesitter parser (`:TSInstall typescript` via nvim-treesitter).

### lazy.nvim

```lua
{
  "johnkingkong/scan-o-tron-3000.nvim",
  keys = {
    { "<leader>tt", function() require("scan-o-tron-3000").run_nearest() end, desc = "Run nearest test" },
    { "<leader>tf", function() require("scan-o-tron-3000").run_file() end, desc = "Run file's tests" },
    { "<leader>tp", function() require("scan-o-tron-3000").run_project() end, desc = "Run project's tests" },
    { "<leader>ts", function() require("scan-o-tron-3000").toggle_panel() end, desc = "Toggle test output panel" },
  },
  config = function()
    require("scan-o-tron-3000").setup({
      -- see Configuration below
    })
  end,
}
```

### vim-plug

```vim
Plug 'johnkingkong/scan-o-tron-3000.nvim'
```

```lua
require('scan-o-tron-3000').setup()
```

### pckr.nvim

```lua
require('pckr').add({
  {
    'johnkingkong/scan-o-tron-3000.nvim',
    config = function()
      require('scan-o-tron-3000').setup()
    end
  };
})
```

### mini.deps

```lua
local MiniDeps = require('mini.deps')
MiniDeps.add({ source = 'johnkingkong/scan-o-tron-3000.nvim' })
require('scan-o-tron-3000').setup()
```

---

## Configuration

```lua
require("scan-o-tron-3000").setup({
  adapters = { require("scan-o-tron-3000.adapters.ts-spec") }, -- optional, this is the default
})
```

`setup()` is entirely optional — skip it and the plugin runs with the `ts-spec` adapter (`.spec.ts`/`.test.ts`, Vitest/Jest/Mocha auto-detected) registered by default.

Commands: `:ScanOTron run-nearest`, `:ScanOTron run-file`, `:ScanOTron run-project`, `:ScanOTron toggle-panel`.

No default keymaps are shipped — bind the ones you want, e.g. the `keys` block in the Installation example above.

---

## Architecture

The plugin is split into small, single-purpose modules:

**`lua/scan-o-tron-3000/init.lua`** — the public API: `setup()`, `run_nearest()`, `run_file()`, `run_project()`, `toggle_panel()`; resolves the adapter and cursor-scoped position for a run

**`lua/scan-o-tron-3000/config.lua`** — defaults and `setup()`/`get()` for the registered adapters list

**`lua/scan-o-tron-3000/positions.lua`** — builds the `describe`/`it` position tree from an adapter's flat treesitter query results, by range containment

**`lua/scan-o-tron-3000/results.lua`** — matches an adapter's parsed results back onto the position tree by test name, and aggregates pass/fail/running state up through `describe` nodes

**`lua/scan-o-tron-3000/runner.lua`** — spawns an adapter's run command via `vim.system`, one run per file/project at a time

**`lua/scan-o-tron-3000/signs.lua`** — gutter extmarks (pass/fail/running/errored) driven by the position tree's state

**`lua/scan-o-tron-3000/panel.lua`** — the navigable per-file tree output window

**`lua/scan-o-tron-3000/adapters/ts-spec.lua`** — the built-in adapter: `.spec.ts`/`.test.ts` detection, the `describe`/`it` treesitter query, Vitest/Jest/Mocha detection and command-building, and JSON reporter parsing for both

**`plugin/scan-o-tron-3000.lua`** — registers `:ScanOTron`

**`lua/health/scan-o-tron-3000.lua`** — powers `:checkhealth scan-o-tron-3000`

---

## Health check

Run `:checkhealth scan-o-tron-3000` to verify `npx` and the `typescript` treesitter parser are both available.

---

## Non-goals (for now)

- Only the `ts-spec` adapter (Vitest/Jest/Mocha) ships today — the adapter contract is generic, but no other language adapter is included yet.
- No DAP/debugger integration.
- No `.each`/`.skip`/templated test-name variants in the `ts-spec` treesitter query.
- No queueing of concurrent run requests — a second trigger while one is in flight no-ops with a notification rather than queueing.
- Result matching is by leaf test name only, not full describe-block ancestry — two tests with identical titles in different `describe` blocks in the same file will collide and may show each other's pass/fail status.

---

## Development

```bash
make deps   # clone plenary.nvim + nvim-treesitter test deps into .deps/, compile the typescript parser
make test   # run the plenary busted test suite
make lint   # stylua --check and luacheck
```

---

## License

MIT
