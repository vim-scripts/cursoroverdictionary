" cursoroverdictionary.vim -- カーソル位置の英単語訳を表示
" 
" version : 0.0.8
" author : ampmmn(htmnymgw <delete>@<delete> gmail.com)
" url    : http://d.hatena.ne.jp/ampmmn
"
" ----
" history
"	 0.0.8		2009-10-05	bug fix for garbled message.
"	 0.0.7		2009-10-03	bug fix
"	 0.0.6		2009-10-02	minor change.
"	 0.0.5		2009-10-02	Several features added.
"	 0.0.4		2009-09-29	Add support for PDIC Text Format
"	 0.0.3		2009-03-12	bug fix.
"	 0.0.2		2009-02-03	minor change.
"	 0.0.1		2009-01-29	initial release.
" ----

scriptencoding utf-8

if exists('loaded_cursoroverdictionary') || &cp
  finish
endif

" Check Env.
if v:version < 700
	echoerr "cursoroverdictionary.vim requires Vim 7.0 or later."
	finish
endif"}}}

"
"" Commands
"
"" ウインドウを表示
command! CODOpen call cursoroverdictionary#open(1)
"" ウインドウを破棄
command! CODClose call cursoroverdictionary#close()
"" ウインドウのトグル表示
command! CODToggle call cursoroverdictionary#toggle()

" pdictファイルのインポート
command! -bang -nargs=+ CODRegistDict call cursoroverdictionary#register_dictionary(len("<bang>")!=0, <f-args>)

" 選択した単語・語句の説明文を表示
command! CODSelected call cursoroverdictionary#selected()
command! -nargs=1 CODSelectedEx call cursoroverdictionary#selected_ex(<f-args>)

" キーワードをコマンドラインパラメータで指定(指定なしの場合は対話モード)
command! -nargs=* CODSearch call cursoroverdictionary#search_keyword(<f-args>)
command! -nargs=+ CODSearchEx call cursoroverdictionary#search_keyword_ex(<f-args>)

let loaded_cursoroverdictionary=1

" vim:foldmethod=marker

