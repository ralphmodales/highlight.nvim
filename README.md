# highlight.nvim

A Neovim plugin inspired by Kindle, allowing you to highlight words and attach notes with numbered markers.

## Features

- Highlight words with a Kindle-like yellow background
- Add notes to highlights (optional)
- Numbered markers link to notes
- View all highlights/notes in a "Notebook" style list
- Clear all annotations

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ralphmodales/highlight.nvim",
  config = function()
    require("highlight").setup()
  end
}
```

## Usage

* `:KindleHighlight` or `<leader>kh` - Highlight word and add note
* `:KindleNote` or `<leader>kn` - Show note at cursor
* `:KindleNotebook` or `<leader>kl` - List all highlights/notes
* `:KindleClear` or `<leader>kc` - Clear everything

## Configuration

```lua
require('highlight').setup({
  highlight = { bg = '#ffcc00', fg = '#000000' },
  keymaps = {
    highlight = '<leader>kh',
    show_note = '<leader>kn',
    notebook = '<leader>kl',
    clear = '<leader>kc',
  }
})
```

## Contributing

Pull request welcome!
