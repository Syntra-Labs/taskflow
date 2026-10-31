# taskflow

> **Source-First Task Management, DAG Dependency Resolution, and Two-Layer Task Specification**  
> Sovereign task agenda, in-tree task anchoring, and Neovim taskflow plugin.

---

## 1. Overview

`taskflow` decouples task management, DAG dependency tracking, and contract specification from text editors into an independent, source-first systems tool.

Instead of storing project status and tasks in ephemeral chat buffers or external SaaS ticketing systems:
- **In-Tree Single Source of Truth**: All tasks are anchored directly in source code comments (`TODO (task_id): ...`, Hoare `requires: [dep1, dep2]`, `blocks: [...]`).
- **Two-Layer Task Specification**: High-level architectural intent (Layer 1) paired with concrete Hoare preconditions/postconditions and file coordinates (Layer 2).
- **Topological DAG Sorter**: Resolves task execution order using native C++20 topological graph traversal (`libtaskflow_dtl.so`).
- **Dual CLI & Neovim Workflow**:
  - `taskflow --list`: Scan and rank in-line tasks across the repository.
  - `taskflow <target>`: Execute an in-line task or target coordinate.
  - Neovim plugin: `:Tasks`, `:Tasks add`, `:Tasks form`, `:Tasks drop`, `:Tasks test`.

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
  config = function()
    require("taskflow")
  end,
}
```

---

## 4. CLI Usage

```bash
# Scan and list all in-tree tasks
taskflow --list

# Target a specific file or task ID
taskflow src/engine.cpp:42
```
