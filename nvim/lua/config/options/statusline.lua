-- 在你的 init.lua 或 statusline.lua 文件中添加以下配置

-- 定义模式显示文本和对应颜色
local mode_info = {
  ['n'] = { text = 'NORMAL', fg = '#000000', bg = '#7aa2f7' },  -- 蓝色
  ['no'] = { text = 'O-PENDING', fg = '#000000', bg = '#7aa2f7' },
  ['v'] = { text = 'VISUAL', fg = '#000000', bg = '#ff9e64' },  -- 橙色
  ['V'] = { text = 'V-LINE', fg = '#000000', bg = '#ff9e64' },
  [''] = { text = 'V-BLOCK', fg = '#000000', bg = '#ff9e64' },
  ['s'] = { text = 'SELECT', fg = '#000000', bg = '#ff9e64' },
  ['S'] = { text = 'S-LINE', fg = '#000000', bg = '#ff9e64' },
  [''] = { text = 'S-BLOCK', fg = '#000000', bg = '#ff9e64' },
  ['i'] = { text = 'INSERT', fg = '#000000', bg = '#9ece6a' },  -- 绿色
  ['ic'] = { text = 'INSERT', fg = '#000000', bg = '#9ece6a' },
  ['R'] = { text = 'REPLACE', fg = '#ffffff', bg = '#f7768e' }, -- 红色
  ['Rv'] = { text = 'V-REPLACE', fg = '#ffffff', bg = '#f7768e' },
  ['c'] = { text = 'COMMAND', fg = '#000000', bg = '#bb9af7' }, -- 紫色
  ['cv'] = { text = 'VIM EX', fg = '#000000', bg = '#bb9af7' },
  ['ce'] = { text = 'EX', fg = '#000000', bg = '#bb9af7' },
  ['r'] = { text = 'PROMPT', fg = '#000000', bg = '#e0af68' },  -- 金色
  ['rm'] = { text = 'MORE', fg = '#000000', bg = '#e0af68' },
  ['r?'] = { text = 'CONFIRM', fg = '#000000', bg = '#e0af68' },
  ['!'] = { text = 'SHELL', fg = '#000000', bg = '#7dcfff' },   -- 浅蓝
  ['t'] = { text = 'TERMINAL', fg = '#000000', bg = '#7dcfff' },
}

-- 获取当前模式的可读文本和颜色
local function get_mode()
  local current_mode = vim.api.nvim_get_mode().mode
  local info = mode_info[current_mode] or { text = string.upper(current_mode), fg = '#000000', bg = '#c0caf5' }
  
  -- 动态设置模式高亮
  vim.api.nvim_set_hl(0, 'StatusLineMode', {
    fg = info.fg,
    bg = info.bg,
    bold = true
  })
  
  return info.text
end

-- 获取文件相对路径
local function get_relative_path()
  local filepath = vim.fn.expand('%:p')
  if filepath == '' then return '' end
  
  -- 尝试获取工程根目录（使用.git作为标记）
  local project_root = vim.fn.finddir('.git', '.;')
  if project_root ~= '' then
    project_root = vim.fn.fnamemodify(project_root, ':h')
    local relative_path = vim.fn.fnamemodify(filepath, ':p'):sub(#project_root + 2)
    return relative_path
  end
  
  -- 如果没有.git目录，则返回相对于当前目录的路径
  return vim.fn.fnamemodify(filepath, ':~:.')
end

-- 将函数暴露给 v:lua
_G.statusline = {
  get_mode = get_mode,
  get_relative_path = get_relative_path
}

-- 设置statusline
local function setup_statusline()
  vim.opt.statusline = table.concat({
    -- 模式显示（颜色由get_mode函数动态设置）
    '%#StatusLineMode# %{v:lua.statusline.get_mode()} %*',
   -- 文件相对路径
    '%#StatusLinePath# %{v:lua.statusline.get_relative_path()}%*',
    -- 文件类型
    '%#StatusLineType# %y%*',
     -- 文件修改状态
    '%#StatusLineModified# %m%r%h%w %*',
    -- 右侧对齐
    '%=',
    -- 编码和行结束符
    '%#StatusLineEncoding# %{&fenc!=#""?&fenc:&enc}[%{&ff}] %*',
    -- 光标位置
    '%#StatusLinePos# %l:%c %*',
  })
  -- 定义其他高亮组
  vim.api.nvim_set_hl(0, 'StatusLineModified', { bold = true })
  vim.api.nvim_set_hl(0, 'StatusLinePath', { bold = false })
  vim.api.nvim_set_hl(0, 'StatusLineType', { bold = true })
  vim.api.nvim_set_hl(0, 'StatusLineEncoding', { bold = false })
  vim.api.nvim_set_hl(0, 'StatusLinePos', { bold = true })
end

-- 初始化
setup_statusline()

-- 自动重新加载statusline
vim.api.nvim_create_autocmd({'ModeChanged', 'BufEnter', 'FileType', 'BufModifiedSet'}, {
  callback = function()
    setup_statusline()
  end
})

