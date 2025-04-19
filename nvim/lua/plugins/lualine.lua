return {
  "nvim-lualine/lualine.nvim",
  enabled = true,
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  opts = {
    theme = "palenight",
    sections = {
      lualine_c = {
        {
          "filename",
          file_status = true,
          newfile_status = false,
          path = 1,
          shorting_target = 40,
       },
      },
    },
  },
}
