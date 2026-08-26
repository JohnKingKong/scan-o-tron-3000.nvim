DEPS_DIR := .deps
PLENARY := $(DEPS_DIR)/plenary.nvim
TREESITTER := $(DEPS_DIR)/nvim-treesitter

.PHONY: deps test lint

deps:
	@mkdir -p $(DEPS_DIR)
	@test -d $(PLENARY) || git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY)
	@test -d $(TREESITTER) || git clone --depth 1 https://github.com/nvim-treesitter/nvim-treesitter $(TREESITTER)
	@nvim --headless --noplugin -u tests/minimal_init.lua -c "TSInstallSync! typescript" -c "qa"

test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

lint:
	stylua --check lua/ tests/ plugin/
	luacheck lua/ tests/ plugin/
