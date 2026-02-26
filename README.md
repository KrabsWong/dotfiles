# My Dotfiles

Personal configuration files for development environment.

## Structure

```
.
── brew/          # Homebrew packages
── kitty/         # Kitty terminal config
── nvim/          # Neovim (LazyVim)
── tmux/          # Tmux config
── zshrc/         # Zsh config
── codebuddy/     # CodeBuddy statusline
── utils/         # Utility scripts
```

## Components

### Kitty
Terminal emulator with themes (Dracula, Tokyo Night) and custom keymaps.

### Neovim
LazyVim-based setup with LSP, fuzzy finding, and UI enhancements.

### Tmux
Mouse support, status bar styling, and Kitty-style split shortcuts (`d`/`D`).

### Zsh
Oh My Zsh with autosuggestions, pyenv, nvs (Node), Go, and SSH status bar integration.

### Homebrew
Run `brew bundle install --file=brew/Brewfile` to install packages.

### CodeBuddy Statusline
Real-time session stats with token usage, git info, and tool counts.

## Installation

```bash
# Backup existing configs
# mv ~/.config/kitty ~/.config/kitty.bak
# mv ~/.config/nvim ~/.config/nvim.bak
# mv ~/.config/tmux ~/.config/tmux.bak
# mv ~/.zshrc ~/.zshrc.bak

# Symlink configs
ln -s ~/dotfiles/kitty ~/.config/kitty
ln -s ~/dotfiles/nvim ~/.config/nvim
ln -s ~/dotfiles/tmux/tmux.conf ~/.config/tmux/tmux.conf
ln -s ~/dotfiles/zshrc/zshrc.conf ~/.zshrc
chmod +x ~/dotfiles/codebuddy/statusline.sh
```

---

*For personal use. Feel free to take inspiration.*
