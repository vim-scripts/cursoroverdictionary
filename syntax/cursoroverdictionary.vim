" cursoroverdictionary.vim -- cursoroverdictionary�o�̓E�C���h�E�̃n�C���C�g
" 
" version : 0.1
" author : ampmmn(htmnymgw <delete>@<delete> gmail.com)
" url    : http://d.hatena.ne.jp/ampmmn

scriptencoding cp932
syn match codKeyword /^== .\{-} ==/
syn match codCategory /�y.\{-}�z/
syn match codSection /^\%(\u\|\s\)\+$/
syn match codVerticalBar /|/ contained
syn match codLink /|.\{-}|/ contains=codVerticalBar

highlight default link codKeyword Title
highlight default link codCategory Keyword
highlight default link codSearchWord Title
highlight default link codSection Type
highlight default link codVerticalBar Ignore
highlight default link codLink Underlined

