local map = vim.keymap.set

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
map("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Execute the current line
map("n", "<leader><leader>x", "<cmd>source %<CR>", { desc = "Execute the current line" })

-- better up/down
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
map({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
map({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

-- Move to window using the <ctrl> hjkl keys
map("n", "<C-h>", "<C-w>h", { desc = "Go to Left Window", remap = true })
map("n", "<C-j>", "<C-w>j", { desc = "Go to Lower Window", remap = true })
map("n", "<C-k>", "<C-w>k", { desc = "Go to Upper Window", remap = true })
map("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window", remap = true })

-- new file
map("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New File" })

-- windows
map("n", "<leader>-", "<C-W>s", { desc = "Split Window Below", remap = true })
map("n", "<leader>|", "<C-W>v", { desc = "Split Window Right", remap = true })
map("n", "<leader>wd", "<C-W>c", { desc = "Delete Window", remap = true })

-- Bufferline tabs
map("n", "<C-]>", ":BufferLineCycleNext<CR>", { desc = "Cycle to next buffer" })
map("n", "<C-[>", ":BufferLineCyclePrev<CR>", { desc = "Cycle to previous buffer" })
map("n", "<leader>bd", ":bd<CR>", { desc = "Close current buffer" })

-- quit all
map("n", "<leader>qq", "<cmd>qa!<cr>", { desc = "Quit All" })

-- Diagnostics
map("n", "gl", function()
  vim.diagnostic.open_float()
end, { desc = "Open Diagnostics in Float" })

map("n", "<leader>dl", function()
  vim.diagnostic.setloclist({ open = true })
end, { noremap = true, silent = true, desc = "Open diagnostics list(Location List)" })
map("n", "<leader>dc", function()
  vim.diagnostic.setloclist({ open = false })
end, { noremap = true, silent = true, desc = "Close diagnostics list(Location List)" })

-- Code format
map("n", "<leader>cf", function()
  require("conform").format({ lsp_format = "fallback" })
end, { desc = "Format current file" })
