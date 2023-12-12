# gtestrunner.nvim
A simple plugin to debug individual google tests with nvim.dap

## Install

### Lazy

```lua
{
	'ofwinterpassed/gtestrunner.nvim',
    depencencies = {
        'mfussenegger/nvim-dap',
        'nvim-telescope/telescope.nvim',
        'nvim-treesitter/nvim-treesitter'
    },
    -- for using default values: config = true
    -- the values below matches the default
	opts = {
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

Opens a Telescope file finder for executables in `gtestrunner.bin_path` and selects it as the current executable on `<enter>`.

```lua
require('gtestrunner').run_gtest_under_cursor
```

Runs the gtest for the test the cursor is in with nvim-dap.

```lua
require('gtestrunner').run_gtestsuite_under_cursor
```

Runs the gtest suite for the test the cursor is in with nvim-dap.
