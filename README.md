# gtestrunner.nvim
A simple plugin to debug individual google tests with nvim.dap

## Install

### Lazy

```lua
{
	'ofwinterpassed/gtestrunner.nvim',
    dependencies = {
        'mfussenegger/nvim-dap',
        'nvim-treesitter/nvim-treesitter',
        'nvim-mini/mini.nvim', -- or 'folke/snacks.nvim' or 'nvim-telescope/telescope.nvim', see picker below
    },
    -- for using default values: config = true
    -- the values below matches the default
	opts = {
		picker = 'mini', -- 'mini', 'snacks' or 'telescope'
		bin_path = './build',
		default_executable = 'a.out',
		base_dap_config = {
			type = 'cppdbg',
			request = 'launch',
			cwd = '${workspaceFolder}',
			terminal = 'integrated',
			runInTerminal = true,
			stopAtEntry = false,
			MIMode = 'gdb',
		}
	},
}
```

## Exposed functions

```lua
require('gtestrunner').set_debug_executable
```

Opens a file picker for executables in `gtestrunner.bin_path` and selects it as the current executable on `<enter>`. The picker is chosen with the `picker` option:

- `'mini'` (default): uses [mini.pick](https://github.com/nvim-mini/mini.nvim), which should be set up with `require('mini.pick').setup()`
- `'snacks'`: uses [snacks.nvim](https://github.com/folke/snacks.nvim) picker
- `'telescope'`: uses [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

Only the selected picker needs to be installed. All of them use `fd` to find the executables.

```lua
require('gtestrunner').run_gtest_under_cursor
```

Runs the gtest for the test the cursor is in with nvim-dap.

```lua
require('gtestrunner').run_gtestsuite_under_cursor
```

Runs the gtest suite for the test the cursor is in with nvim-dap.
