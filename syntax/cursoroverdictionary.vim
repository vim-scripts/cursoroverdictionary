" cursoroverdictionary.vim -- cursoroverdictionary出力ウインドウのハイライト
" 
" version : 0.0.1
" author : ampmmn(htmnymgw <delete>@<delete> gmail.com)
" url    : http://d.hatena.ne.jp/ampmmn

scriptencoding cp932
syn match codKeyword /^== .\{-} ==/
syn match codCategory /【.\{-}】/

highlight default link codKeyword Title
highlight default link codCategory Keyword

