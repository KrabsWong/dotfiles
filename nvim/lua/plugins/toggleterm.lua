return {
  "akinsho/toggleterm.nvim",
  version = "*",
  keys = {
    { "<C-\\>", "<cmd>ToggleTerm<cr>", desc = "Toggle terminal", mode = { "n", "t" } },
    { "<leader>tt", "<cmd>ToggleTerm size=10 direction=horizontal<cr>", desc = "Horizontal terminal" },
  },
  opts = {
    open_mapping = false, -- 禁用插件自带的快捷键
    start_in_insert = true,
    direction = "float",
    on_open = function(term)
      vim.cmd("startinsert!") -- 自动进入插入模式
      vim.keymap.set("t", "<ESC>", "<C-\\><C-n>", { buffer = term.bufnr })
    end,
  }
}
