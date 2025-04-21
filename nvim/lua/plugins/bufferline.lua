return {
  "akinsho/bufferline.nvim",
  version = "*",
  event = "VeryLazy",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    options = {
      numbers = "ordinal",
      show_tab_indicators = true,
      offsets = {
        {
          filetype = "neo-tree",
          text = "Neo Tree",
          highlight = "Directory",
          separator = true,
          text_align = "left",
        },
      },
      diagnostics_indicator = function(count, level)
        local icon = level:match("error") and " " or " "
        return " " .. icon .. count
      end,
    },
    highlights = {
      buffer_selected = {
        italic = false,
        bold = true,
      },
      numbers_selected = {
        bold = false,
        italic = false,
      },
    },
  },
}
