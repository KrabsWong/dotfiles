return {
  "akinsho/toggleterm.nvim",
  version = "*",
  enabled = false,
  keys = {
    { "<C-\\>", "<cmd>ToggleTerm<cr>", desc = "Toggle terminal", mode = { "n", "t" } },
    { "<Esc>", "<cmd>ToggleTerm<cr>", desc = "Close terminal in terminal mode", mode = { "t" } },
  },
  opts = {
    open_mapping = false, -- 禁用插件自带的快捷键
    start_in_insert = true,
    direction = "float",
    shade_terminals = true,
    on_open = function()
      vim.cmd("startinsert!") -- 自动进入插入模式
    end,
  }
}
