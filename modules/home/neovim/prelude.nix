# Put lua config here that should be loaded first
{...}: {
  programs.neovim.extraLuaConfig =
    # lua
    ''
      vim.g.mapleader = ';'
      vim.g.maplocalleader = ' '
      vim.o.number = true
      vim.o.cursorline = true
      vim.o.list = true
      vim.opt.listchars = {
          trail = '␣',
          extends = '⇉',
          precedes = '⇇',
          nbsp = '·',
          tab = '▏┈',
          leadmultispace = '▏┈',
      }
      vim.o.sw = 4
      vim.o.shiftround = true

      vim.o.smartindent = true

      vim.o.infercase = true
      vim.o.ignorecase = true
      vim.o.smartcase = true
      vim.o.gdefault = true
      vim.o.linebreak = true

      vim.keymap.set('n', 'J', '20j')
      vim.keymap.set('n', 'j', 'gj')
      vim.keymap.set('n', 'K', '20k')
      vim.keymap.set('n', 'k', 'gk')
      vim.keymap.set('n', 'H', '<c-w>h')
      vim.keymap.set('n', 'L', '<c-w>l')
      vim.keymap.set('n', '<c-i>', '<c-]>')
      vim.keymap.set('n', '<c-h>', 'gT')
      vim.keymap.set('n', '<c-l>', 'gt')
      vim.keymap.set('n', '<CR>', '@="m`o<C-V><Esc>``"<CR>')

      vim.keymap.set('n', '<c-u>', '<cmd>nohls<cr>', { silent = true})
      vim.keymap.set('n', 'U', '<c-r>')

      vim.keymap.set('n', 'Q', 'gqap')
      vim.keymap.set('v', 'Q', 'gq')

    '';
}
