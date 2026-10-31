# taskflow

> **Task Management and Dependency Tracking Stored Directly in Your Code**  
> CLI tool and Neovim plugin for tracking project tasks and dependencies.

---

## 1. Overview

`taskflow` lets you track project tasks and dependencies directly inside your source code comments instead of using external ticketing tools.

- **Tasks in Your Code**: Anchor tasks right next to the code they describe (`TODO (task_id): ...`, `requires: [dep1, dep2]`, `blocks: [...]`).
- **Clear Requirements**: Connect high-level goals with specific functions, file locations, and conditions.
- **Dependency Sorting**: Automatically figures out the right order to complete tasks based on dependencies (`libtaskflow_dtl.so`).
- **CLI & Neovim Support**:
  - `taskflow --list`: Scan and show all tasks across your project.
  - `taskflow <target>`: Run or inspect a specific task.
  - In Neovim: Use `:Tasks`, `:Tasks add`, `:Tasks test`.

---

## 2. Directory Structure

```
taskflow/
├── bin/
│   ├── taskflow               # Standalone Python CLI runner
│   └── agent -> taskflow      # Compatibility symlink
├── c_src/
│   ├── dtl_engine.cpp         # C++20 topological DAG & diff tolerance sorter
│   └── anchor_engine.cpp      # C++20 fuzzy text anchoring engine
├── vendor/
│   └── router/                # Vendored Syntra-Labs/router for manifold task placement
├── lua/
│   └── taskflow/              # Neovim plugin modules
│       ├── init.lua
│       ├── tasks.lua          # Two-layer task form, DAG & cursor placement
│       ├── ui.lua             # Floating & docked task windows
│       └── ...
├── docs/
│   └── architecture/          # PlantUML task lifecycle & activity models
├── tests/                     # Taskflow test suites
├── Makefile
└── README.md
```

---

## 3. Installation & Setup

```bash
git clone https://github.com/Syntra-Labs/taskflow.git
cd taskflow
make all
make install
```

This installs `libtaskflow_dtl.so` and `libtaskflow_anchor.so` to `~/.local/lib`, and symlinks `taskflow` to `~/.local/bin/taskflow`.

### Neovim Integration
Add `taskflow` to your Neovim plugin configuration (e.g. via `lazy.nvim`):
```lua
{
  "Syntra-Labs/taskflow",
  opts = {
    keymap_history = "<leader>h", -- or false to disable
  },
}
```

Provides:
- `:Tasks` — Task manager, in-line TODO scanner, and placement engine.
- `:History` — Interactive visited files history list in recent order (with cursor jumps and time tracking).
- `<leader>h` — Quick jump to visited file history.

---

## 4. CLI Usage

```bash
# Scan and list all in-tree tasks
taskflow --list

# View recent file modification history
taskflow history

# Target a specific file or task ID
taskflow src/engine.cpp:42
```
