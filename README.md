# gtestrunner.nvim
A simple plugin to run and debug individual google tests from nvim, with or without nvim-dap.

When a C++ file with tests (`TEST`, `TEST_F` and `TEST_P`) is opened it shows:

- a panel on the right with the status of the suites and tests in the file
- a sign in the sign column for every test
- a line above every test with its status, e.g. `✓ MySuite.MyTest passed · 3 ms`

The status is read from the json report of google test (`--gtest_output=json`), both when running with and
without the debugger.

## Install

### Lazy

```lua
{
	'ofwinterpassed/gtestrunner.nvim',
    dependencies = {
        'mfussenegger/nvim-dap', -- only needed for debugging
        'nvim-treesitter/nvim-treesitter', -- with the cpp parser installed
        'nvim-mini/mini.nvim', -- or 'folke/snacks.nvim' or 'nvim-telescope/telescope.nvim', see picker below
    },
    -- for using default values: config = true
    -- the values below matches the default
	opts = {
		picker = 'mini', -- 'mini', 'snacks' or 'telescope'
		bin_path = './build',
		default_executable = 'a.out',
		-- also used for the working directory when running without the debugger
		base_dap_config = {
			type = 'cppdbg',
			request = 'launch',
			cwd = '${workspaceFolder}',
			terminal = 'integrated',
			runInTerminal = true,
			stopAtEntry = false,
			MIMode = 'gdb',
		},
		panel = {
			auto_open = true, -- open the panel when entering a file with tests
			width = 50,
			max_failure_lines = 10, -- failure message lines shown per test
		},
		signs = true,
		virtual_lines = true,
		icons = {
			unknown = '○',
			running = '●',
			passed = '✓',
			failed = '✗',
			skipped = '⊘',
		},
	},
}
```

`panel` and `icons` are merged with the defaults, the other options replace them.

## Exposed functions

```lua
require('gtestrunner').set_debug_executable()
```

Opens a file picker for executables in `gtestrunner.bin_path` and selects it as the current executable on `<enter>`. The picker is chosen with the `picker` option:

- `'mini'` (default): uses [mini.pick](https://github.com/nvim-mini/mini.nvim), which should be set up with `require('mini.pick').setup()`
- `'snacks'`: uses [snacks.nvim](https://github.com/folke/snacks.nvim) picker
- `'telescope'`: uses [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

Only the selected picker needs to be installed. All of them use `fd` to find the executables. Changing the executable clears the test results.

### Running tests

| Function | Description |
|---|---|
| `run_test()` / `debug_test()` | Run / debug the test the cursor is in |
| `run_suite()` / `debug_suite()` | Run / debug the suite of the test the cursor is in |
| `run_file()` / `debug_file()` | Run / debug all tests in the current file |
| `cancel()` | Stop the run without the debugger |
| `show_output()` | Show the output of the latest run without the debugger |
| `clear_results()` | Reset all tests to not run |

`run_gtest_under_cursor()` and `run_gtestsuite_under_cursor()` still work and are the same as `debug_test()` and `debug_suite()`.

### Panel

| Function | Description |
|---|---|
| `open_panel()` / `close_panel()` / `toggle_panel()` | Open / close / toggle the panel |

After closing the panel it doesn't open automatically again until it is opened with `open_panel()` or `toggle_panel()`.

Keys in the panel:

| Key | Action |
|---|---|
| `<CR>` | Jump to the test or suite |
| `r` / `d` | Run / debug the test or suite under the cursor |
| `R` / `D` | Run / debug all tests in the file |
| `o` | Show output |
| `x` | Cancel run |
| `q` | Close the panel |

### Highlights

`GtestrunnerUnknown`, `GtestrunnerRunning`, `GtestrunnerPassed`, `GtestrunnerFailed`, `GtestrunnerSkipped`,
`GtestrunnerTitle`, `GtestrunnerSuite` and `GtestrunnerFailureText` can be overridden, they link to `Comment`,
`Diagnostic*` and `Title` highlights by default.
