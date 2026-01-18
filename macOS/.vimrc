" Basic, modern defaults
set nocompatible
set encoding=utf-8

" Syntax highlighting and filetype support (Python, sh, etc.)
syntax enable
filetype plugin indent on

" Mouse support in terminal Vim (click, select, scroll, etc.)
set mouse=a

" Usability
set number
set hidden
set showcmd
set wildmenu
set incsearch
set hlsearch
set ignorecase
set smartcase

" Indentation
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set autoindent
set smartindent

" Better backspace behavior in insert mode
set backspace=indent,eol,start

" Cmd+Backspace goal:
" In Insert mode, Ctrl+U deletes from cursor back to start of line.
" If Ghostty sends ^U for Cmd+Backspace, this already works with no mapping.
" Otherwise, map the key sequence you see (replace <CmdBS>).
inoremap <CmdBS> <C-u>

" Quality-of-life
set clipboard=unnamed
set ttyfast

