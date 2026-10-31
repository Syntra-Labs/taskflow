-- Neovim plugin entry point for Taskflow (:Tasks, :History)
if vim.g.loaded_taskflow == 1 then
    return
end
vim.g.loaded_taskflow = 1

local ok, taskflow = pcall(require, "taskflow")
if ok and taskflow then
    taskflow.setup()
end
