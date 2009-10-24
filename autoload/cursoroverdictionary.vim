" cursoroverdictionary.vim -- カーソル位置の英単語訳を表示
" 
" version : 0.1
" author : ampmmn(htmnymgw <delete>@<delete> gmail.com)
" url    : http://d.hatena.ne.jp/ampmmn
"

" Global Variables

scriptencoding utf-8

" DBファイルのパス
if exists("g:CODDatabasePath")==0"{{{
	let g:CODDatabasePath='~/.cursoroverdictionary_db'
endif"}}}

" ウインドウを表示する方向
" 上に水平分割表示: ''
" 下に水平分割表示: 'rightbelow'
" 左に垂直分割表示: 'vertical'
" 右に垂直分割表示: 'vertical rightbelow'
if exists("g:CODDirection")==0"{{{
	let g:CODDirection='rightbelow'
endif"}}}

" ウインドウ初期表示時の幅・高さ
if exists("g:CODWindowHeight")==0"{{{
	let g:CODWindowHeight='10'
endif"}}}

" stemming処理時の置換パターンリスト
if exists("g:CODAdditionalStemmingPatterns")== 0"{{{
	let g:CODAdditionalStemmingPatterns=[]
endif "}}}

" カーソル移動時の内容更新を無効化
" (外部検索機能のみを利用する際に使用します)
if exists("g:CODDisableCursorMoveUpdate")== 0"{{{
	let g:CODDisableCursorMoveUpdate=0
endif "}}}

" 外部検索結果のキャッシュファイル指定
" (指定しない場合は、Vim終了時にキャッシュファイルを破棄します)
" let g:CODPermanentCachePath = '~/.cod_external_cache.db'

" autocmdの解除
function! s:delete_augroup()"{{{
	augroup CODCursorEvent
		autocmd!
	augroup END
endfunction"}}}

" 出力バッファ & ウインドウの作成
function! cursoroverdictionary#open(update, engine_name)"{{{

	let context = s:get_external_engine(a:engine_name)

	let bname = get(context, 'bufname', 'CursorOverDictionary')
	let cur_winnr = winnr()

	if exists("s:regist_operator_last") == 0 && exists('*operator#user#define')
		call operator#user#define('cod-last', 'cursoroverdictionary#operator_last')
		let s:regist_operator_last = 1
	endif


	" バッファが存在しなければ、出力ウインドウとともに作成
	if bufexists(bname) == 0
		let height = get(context, 'windowheight', g:CODWindowHeight)
		if height == 0
			let height = ''
		endif

		silent execute get(context, 'direction', g:CODDirection) height 'new'
		setlocal bufhidden=unload
		setlocal nobuflisted
		setlocal buftype=nofile
		setlocal nomodifiable
		setlocal noswapfile
		setlocal nonumber
		setlocal foldmethod=marker
		setfiletype cursoroverdictionary
		silent file `=bname`
		noremap <buffer><silent> q :bwipeout<cr>
		noremap <buffer><silent> H :call cursoroverdictionary#previous_page()<cr>
		noremap <buffer><silent> L :call cursoroverdictionary#next_page()<cr>
		noremap <buffer><silent> <cr> :call <SID>jump_marker()<cr>
		noremap <buffer><silent> K :if expand("<cword>") != ''\|call cursoroverdictionary#search_keyword_ex(<SID>get_recent_engine(), expand("<cword>"))\|endif<CR>
		vnoremap <buffer><silent> K :call cursoroverdictionary#selected_ex(<SID>get_recent_engine())<cr>
		if exists('*operator#user#define')
			map <buffer><silent> c <Plug>(operator-cod-last)
		endif
	else
		" バッファはウインドウ上に表示されているか? なければウインドウだけ作成
		let bufnr = bufnr('^'.bname.'$')
		let winnr = bufwinnr(bufnr)
		if winnr != -1
			return
		endif

		execute g:CODDirection g:CODWindowHeight 'split'
		silent execute bufnr 'buffer'
	endif

	augroup CODCursorEvent
		autocmd!
		autocmd CursorMoved * call <SID>UpdateWord()
		execute "autocmd BufWipeout" bname "call s:delete_augroup()"
	augroup END

	let windowfocus = get(s:get_external_engine(a:engine_name), 'windowfocus', 0) != 0

	if windowfocus == 0
		execute cur_winnr 'wincmd w'
	endif

	if (a:update!=0)
		call s:UpdateWord()
	endif
endfunction"}}}

" 出力バッファ & ウインドウの破棄
function! cursoroverdictionary#close(name)"{{{

	let engine_name = len(a:name)==0 ? s:get_recent_engine(): a:name
	let context = s:get_external_engine(engine_name)
	let bname = '^'. get(context, 'bufname', 'CursorOverDictionary') .'$'
	silent! execute 'bwipeout!' bufnr(bname)
endfunction"}}}

" ウインドウのトグル
function! cursoroverdictionary#toggle(name)"{{{
	let engine_name = len(a:name)==0 ? s:get_recent_engine(): a:name
	let win_nr = winnr('$')
	call cursoroverdictionary#open(1, engine_name)
	if win_nr == winnr('$')
		call cursoroverdictionary#close(engine_name)
	endif
endfunction"}}}


" エラーメッセージの出力
function! s:echoerr(msg) "{{{
	echohl ErrorMsg
	echo a:msg
	echohl
endfunction "}}}

if has('python')

python << END_OF_PYTHON_PART

# Pythonスクリプト用エラーメッセージ出力
def echoError(msg):#{{{
	msg = msg.replace("'","''")
	import vim
	vim.command("call s:echoerr('Error:" + msg + "')")
#}}}

# sqliteライブラリのインポート
def importSQLite():#{{{
	try:
		import sqlite3
		return sqlite3, True
	except ImportError:
		import sqlite
		return sqlite, False
#}}}

# 単語を登録
def insert_keyword(cur, keyword, description, add, _sqlite, isSQLite3): #{{{
	param = u"(?,?)"
	if isSQLite3 == False:
		  param = u"(%s,%s)"
	try:
		cur.execute(u"insert into words values" + param, (keyword, description))
	except _sqlite.IntegrityError:
		if int(add) == 0: raise
		del_param = u"?"
		if isSQLite3 == False:
			del_param = u"%s"
		# 既存のキーを削除した上で再登録を試みる
		cur.execute(u"delete from words where keyword=" + del_param, (keyword,))
		cur.execute(u"insert into words values" + param, (keyword, description))
#}}}

END_OF_PYTHON_PART

endif " has('python')

" 指定したpdictファイルをデータベースに登録
" @param add 0:上書きしない 1:強制的に登録
function! cursoroverdictionary#register_dictionary(add, ...)"{{{
	if !has('python')
		echoerr "cursoroverdictionary#register_dictionary requires +python option"
		return
	endif

	if a:0 == 0
		return 
	endif
python << END_OF_PYTHON_PART
import vim

# 辞書ファイルのフォーマット種類を返す
def get_dict_format(fIn):
	# 一行分だけデータを読んでその内容だけで判定する(手抜き)
	line = fIn.readline()
	# ファイル位置を先頭に戻す
	fIn.seek(0)
	# PDICテキスト形式の場合は1,一行テキスト形式の場合は0を返す
	return " /// " not in line

try:
	_sqlite, isSQLite3 = importSQLite()
	pdict_path = vim.eval("expand(a:1)")

	# pdic辞書ファイルの文字コード
	enc = vim.eval('&enc')
	fencode=enc
	# fencodeが有効かどうかのテスト
	"test".decode(fencode)

	fIn = open(pdict_path)

	dbFile = vim.eval("expand(g:CODDatabasePath)")
	conn = _sqlite.connect(dbFile)

	cur = conn.cursor()

	if isSQLite3 == False:
		try: cur.con.encoding = (enc,)
		except: pass

	# DBの作成
	# sqliteではif not existsが使えないのでエラーをつぶしている(sqlite3では使用可能)
	try:
		cur.execute(u"create table words (keyword TEXT PRIMARY KEY, description TEXT);")
	except: pass

	keyword, description = '', ''

	dict_fmt = get_dict_format(fIn)
	for line in fIn:
		line = line.decode(fencode,'ignore')

		# ここでファイルを一行ずつ読み込み、単語と説明文に分割する
		if dict_fmt == 0:
			keyword, description = line.split(" /// ")
			description = description.strip("\r\n")
		else:
			if keyword == '':
				keyword = line.strip()
				continue
			else:
				description = line.strip()

		if "/" in keyword:
			keyword = ''
			continue

		# 取得したデータをデータベースに流し込む
		insert_keyword(cur, keyword, description, vim.eval('a:add'), _sqlite, isSQLite3)
		keyword, description = '', ''

	conn.commit()
	conn.close()
except UnicodeDecodeError:
	echoError('データベース登録時に文字コードを変換できませんでした。('+fencode +'->utf-8)')
except ImportError:
	echoError('sqliteのimportに失敗しました(pythonのバージョンが古い?)')
except _sqlite.IntegrityError:
	echoError('キーワード「%s」は既に登録済みです'%(keyword.encode(enc),))
except _sqlite.OperationalError:
	echoError('DBの操作中にエラーが発生しました(Diskfullか、さもなくばBug)')
except IOError:
	echoError("指定されたファイルは存在しません : " + pdict_path)
except LookupError:
	echoError('不明な文字コード形式です : ' + fencode)
END_OF_PYTHON_PART
endfunction"}}}

" 出力ウインドウ番号を取得
function! s:get_output_winnr(bname)"{{{
	if bufexists(a:bname) == 0
		return -1
	endif
	return bufwinnr(bufnr('^'. a:bname .'$'))
endfunction"}}}

" 状態の更新
function! s:update(name, new_item) "{{{

	let context = s:get_external_engine(a:name)

	if s:is_empty_searchresult(a:new_item)
		return 0
	endif


	let prev_item = s:get_recent_history(0)
	let prev_context = s:get_external_engine(get(prev_item, "engine_name", ''))
	let bname = get(prev_context, 'bufname', 'CursorOverDictionary')
	let [output_winnr, cur_winnr] = [s:get_output_winnr(bname), winnr()]
	silent! let LeaveFunc_ = function(get(prev_context, "leave_function", ''))
	if type(LeaveFunc_) == type(function("tr"))
		execute output_winnr 'wincmd w'
		call LeaveFunc_()
		execute cur_winnr 'wincmd w'
	endif

	call s:set_current_word(context, expand("<cword>"))
	call s:update_window(context, a:new_item.keyword, a:new_item.description)

	let a:new_item.engine_name = a:name
	call s:add_search_history(a:new_item)

	"
	silent! let EnterFunc_ = function(get(context, "enter_function", ''))
	if type(EnterFunc_) == type(function("tr"))
		let bname = get(context, 'bufname', 'CursorOverDictionary')
		let [output_winnr, cur_winnr] = [s:get_output_winnr(bname), winnr()]
		execute output_winnr 'wincmd w'
		call EnterFunc_()
		execute cur_winnr 'wincmd w'
	endif

	return 1
endfunction "}}}

" カーソル位置の単語の説明文を出力ウインドウに表示
function! s:UpdateWord()"{{{

	if g:CODDisableCursorMoveUpdate != 0
		return
	endif

	" ビジュアルモードの時は何もしない
	if mode() =~# "[vV\<C-v>]"
		return
	endif

	" 出力バッファがない、またはウインドウに表示されていない場合は何もしない
	let [orgnr, outputnr] = [winnr(), s:get_output_winnr('CursorOverDictionary')]
	if outputnr == -1
		return
	endif

	" 現在のウインドウが出力ウインドウの場合は何もしない
	if outputnr == orgnr
		return
	endif

	" 現在位置の単語がない場合は何もしない
	let cursor_word = expand("<cword>")
	if len(cursor_word) == 0
		return
	endif

	" 単語が前回と同じだったら何もしない
	execute outputnr 'wincmd w'
	let last_word = ''
	if exists("b:last_word")
		let last_word = b:last_word
	endif
	execute orgnr 'wincmd w'
	if last_word ==# cursor_word
		return
	endif

	let name = 'internal'

	let his = s:get_recent_history(0)
	let l:pos = s:get_current_position(name)

	" 現在位置の単語の説明文を取得
	let item = s:getDescription(cursor_word, g:CODDatabasePath)
	if s:is_empty_searchresult(item) && s:has_default_engine()
		" 見つからなかった場合はデフォルトの検索エンジンのキャッシュから探してみる
		let item = s:getDescriptionFromCache(s:get_default_engine(), cursor_word)
	endif
	call s:update(name, item)

	let his.pos = l:pos
endfunction"}}}

" 指定した単語を「現在の単語」として記憶
function! s:set_current_word(context, word)"{{{
	let bname = get(a:context, 'bufname', 'CursorOverDictionary')
	let [output_winnr, cur_winnr] = [s:get_output_winnr(bname), winnr()]
	if output_winnr == -1
		return
	endif
	execute output_winnr 'wincmd w'
	let b:last_word = a:word
	execute cur_winnr 'wincmd w'
endfunction"}}}

" 出力ウインドウの内容を更新
function! s:update_window(context, word, description)"{{{
	let bname = get(a:context, 'bufname', 'CursorOverDictionary')
	let [output_winnr, cur_winnr] = [s:get_output_winnr(bname), winnr()]
	if output_winnr == -1
		return
	endif
	execute output_winnr 'wincmd w'
	if len(a:description) == 0
		execute cur_winnr 'wincmd w'
		return
	endif

	setlocal modifiable

	" 指定したキーワードを強調するsyntaxを設定(highlight指定はsyntaxファイル側)
	silent! syntax clear codSearchWord
	if len(a:word) > 0
		execute 'syntax match codSearchWord /\c'.escape(a:word, ' /').'/'
	endif

	"既存の内容を全削除し、新しい内容に置き換える
	let org_ul = &undolevels
	try
		" 一時的にundo/redo機能を無効化し変更内容がundoツリーに残らないようにする
		" (一時的とはいえグローバルな値を変えることによる副作用がありそう・・)
		let l:word = substitute(a:word,"\n\\|\t",'','g')
		let &undolevels = -1

		silent! execute 1 'delete _' line('$')
		let l:fmr = len(l:word) > &columns-10 && match(&fmr, ',') != -1 ? split(&fmr, ','): ['','']

		silent! call append(0, l:fmr[0] . '== ' . l:word . ' ==' . l:fmr[1])
		silent! call append(1, a:description)
	finally
		let &undolevels = org_ul
	endtry
	normal! 1G

	setlocal nomodifiable

	execute cur_winnr 'wincmd w'
endfunction"}}}

if has('python')

python << END_OF_PYTHON_PART

# 単語に対応する説明文を取得
def getDescriptionFromDB(conn, word):#{{{
	enc = vim.eval('&enc')
	_sqlite, isSQLite3 = importSQLite()
	cur = conn.cursor()

	if isSQLite3 == False:
		try: cur.con.encoding = (enc,'ignore')
		except: pass

	def conv(_, enc):
		if type(_) == type(u''): return _.encode(enc)
		else: return _

	try:
		param = u"?"
		if isSQLite3 == False:
			param = u"%s"
		if type(word) != type(u''): word = word.decode(enc)
		try:
		  cur.execute(u"select * from words where keyword=" + param, (word,))
			  # なんか、ここでmemory-leakのような挙動.使い方間違ってるのだろうか?
		except _sqlite.DatabaseError:
			return '', []

		keyword = ''
		desc = []
		for item in cur.fetchall():
			keyword = conv(item[0], enc)
			desc = conv(item[1], enc).split(" \\ ")
			break
		return keyword, desc
	finally:
		cur.close()
#}}}

# 'VC'の繰り返し数を取得
def get_VC_count(word):#{{{
	return len(re.findall("[aiueo][bcdfghjklmnpqrstvwxz]y?", word))
#}}}

internal_patlist = [
	# studies -> study
	['ies$', 'y'],
	# released -> release
	['ed$', 'e'],
	# 比較
	['er$', ''],
	# 最上級
	['est', ''],
]

# 指定した英単語のステミングを行う。
# Porter Stemming Algorithm : http://tartarus.org/~martin/PorterStemmer/
def stemWord(word):#{{{
	import re
	
	word = word.lower()
	
	result = [ word ]
	
	# Porterアルゴリズムで拾えない単語用の変換(ユーザ側で定義)
	patlist = vim.eval("g:CODAdditionalStemmingPatterns")
	for item in patlist + internal_patlist:
		if type(item) != type([]): continue
		if len(item) < 2 or type(item[0]) != type("") or type(item[1]) != type(""):
			continue
		try: sub_result = re.subn(item[0], item[1], word)
		except: continue
		if sub_result[1] == 0: continue
		result.append(sub_result[0])

	def evalWords(word, *arrays):
		n = 0
		for i,_ in enumerate(arrays):
			if callable(_[0]):
				if len(_) == 1 or _[1](word):
					word, n = _[0](word)
			else:
				pat, rep = _[0], _[1]
				m = re.search('(.*)'+pat, word)
				if m == None or len(m.groups())<1: continue
				w = m.groups()[0]
				if len(_) == 2 or _[2](w):
					word, n = re.subn(pat,rep,word)
			if n != 0: return word, i
		return word, -1

	# 単語は母音を含むか?
	def hasVowel(word): return re.search('[aiueo]', word) != None
	# 文字は子音か?
	def isConstant(chr): return re.match('[bcdfghjklmnpqrstvwxz]', chr) != None
	# m > nを評価する関数を返す
	def mGT(n):
		def greaterThan(_): return get_VC_count(_) > n
		return greaterThan
	# m == nを評価する関数を返す
	def mEQ(n):
		def equal(_): return get_VC_count(_)  == n
		return equal
	# 単語がCVCで終端されているかを判定
	def cvcEnds(_):
		if len(_) < 3 or isConstant(_[-3]) == False or \
		   hasVowel(_[-2]) == False or isConstant(_[-1]) == False:
			return False
		return _[-1] not in 'wxy'
	# SS$ -> S$
	def DtoSLtr(_):
		return _[:-1], 1
	# 単語の末尾二文字がSSのように連続するか?
	def isDblLtr(_):
		return len(_) >= 2 and _[-2] == _[-1]
	
	def step1(word):
		# Step 1a
		word, i = evalWords(word, 
			('sses$',"ss"), ('ies$','i'), ('ss$','ss'), ('s$', ''))
		# Step 1b
		word, i = evalWords(word, ('eed$', 'ee', mGT(0)), ('ed$', '', hasVowel), ('ing$', '', hasVowel))
		if i in (1,2):
			word, i = evalWords(word, 
				('at$', 'ate'), ('bl$', 'ble'), ('iz$', 'ize'), 
				(DtoSLtr, lambda _: isDblLtr(_) and _[-1] not in 'lsz'),
				('(.*)$', r'\1e', lambda _: mEQ(1)(_) and cvcEnds(_)))
		# Step 1c
		word, i = evalWords(word, ('y$', 'i', hasVowel))
		return word
	def step2(word):
		f = mGT(0)
		word, i = evalWords(word, 
			('ational$', 'ate', f), ('tional$', 'tion', f),
			('enci$', 'ence', f), ('anci$', 'ance', f),
			('izer$', 'ize', f), ('abli$', 'able', f),
			('alli$', 'al', f), ('entli$', 'ent', f),
			('eli$', 'e', f), ('ousli$', 'ous', f),
			('ization$', 'ize', f), ('ation$', 'ate', f),
			('ator$', 'ate', f), ('alism$', 'al', f),
			('iveness$', 'ive', f), ('fulness$', 'ful', f),
			('ousness$', 'ous', f), ('aliti$', 'al', f),
			('iviti$', 'ive', f), ('biliti$', 'ble', f))
		return word
	def step3(word):
		f = mGT(0)
		word, i = evalWords(word, 
			('icate$', 'ic', f), ('ative$', '', f), ('alize$' 'al', f),
			('iciti$', 'ic', f), ('ical$',  'ic', f), ('ful$', '', f),
			('ness$', '', f))
		return word
	def step4(word):
		f = mGT(1)
		word, i = evalWords(word, 
			('al$', '', f), ('ance$', '', f), ('ence$', '', f), ('er$', '', f),
			('ic$', '', f), ('able$', '', f), ('ible$', '', f), ('ant$', '', f),
			('ement$', '', f), ('ment$', '', f), ('ent$', '', f),
			('ion$', '', lambda word: f(word) and re.search('[st]$',word) != None),
			('ou$', '', f), ('ism$', '', f), ('ate$', '', f), ('iti$', '', f),
			('ous$', '', f), ('ive$', '', f), ('ize$', '', f))
		return word
	def step5(word):
		# Step 5a
		word, i = evalWords(word, 
			('e$', '', mGT(1)),
			('e$', '', lambda word: mEQ(1)(word) and cvcEnds(word) == False))
		# Step 5b
		word, i = evalWords(word, 
			(DtoSLtr, lambda word: mGT(1)(word) and isDblLtr(word) and re.search('l$', word) != None))
		return word
	
	for _ in [ step1, step2, step3, step4, step5]:
		tmp = _(word)
		if tmp != word:
			word = tmp
			result.append(tmp)
	
	return result
#}}}

END_OF_PYTHON_PART

endif " has('python')

" 説明文が空かどうかを判定
function! s:is_empty_description(description) "{{{
	for _ in a:description
		let l:word = substitute(_, '^\s*\(.*\)','\1', '')
		if len(l:word)!=0
			return 0
		endif
	endfor
	return 1
endfunction
"}}}

" 検索結果データ関連の処理 "{{{

" 結果データが空かどうかを判定
function! s:is_empty_searchresult(item) "{{{
	return len(get(a:item, "description", {})) == 0
endfunction "}}}

" 新規結果データインスタンスを生成
function! s:create_searchresult(...) "{{{
	let item = {}

	let item.keyword = ''
	if len(a:000) >= 1
		let item.keyword = a:000[0]
	endif
	let item.description = []
	if len(a:000) >= 2
		let item.description = a:000[1]
	endif

	return item
endfunction "}}}

" 文字参照のデコード
function! s:decode_character_reference(text) "{{{
	let body = substitute(a:text, '&gt;', '>', 'g')
	let body = substitute(body, '&lt;', '<', 'g')
	let body = substitute(body, '&quot;', '"', 'g')
	let body = substitute(body, '&apos;', "'", 'g')
	let body = substitute(body, '&;', '', 'g')
	let body = substitute(body, '&nbsp;', ' ', 'g')
	let body = substitute(body, '&yen;', '&#65509;', 'g')
	let body = substitute(body, '&#x\(\x\+\);', '\=s:Uni_nr2enc_char(submatch(1))', 'g')
	let body = substitute(body, '&#\(\d\+\);', '\=s:Uni_nr2enc_char(submatch(1))', 'g')
	let body = substitute(body, '&amp;', '\&', 'g')
	return body
endfunction"}}}

" タグを削除し、テキストのみを抽出
function! s:strip_searchresult(item, context) "{{{

	let body = s:substr(a:item.description, a:context.start_pattern, a:context.end_pattern)

	" scriptタグ内のデータはすべて不要
	let body = substitute(body, '\c<script.\{-}</script>', '', 'g')
"	" コメントはすべて削除
	let body = substitute(body, '<--.\{-}-->', '', 'g')
"	" リスト形式の項目は改行を入れる
	let body = substitute(body, '\c<li>\(\_.\{-}\)</li>', '\1\n', 'g')
	let body = substitute(body, '\c</td>', '\t', 'g')
"
	let marker_link = {}
	let body = substitute(body, '\c<a[^>]\{-}title\s\{-}="\(.\{-}\)"[^>]\{-}>\(.\{-}\)</a>', '\=s:register_link(marker_link, submatch(1), submatch(2))', 'g')
"	" 残りのタグはすべて消す
	let body = substitute(body, '<.\{-}>', '', 'g')
"	" 改行コードは\nに
	let body = substitute(body, '\r\n', '\n', 'g')
"	" 2行以上の空白は1行空白にまとめる
	let body = substitute(body, '\s\?\n\s\?\n\%(\s\?\n\)\+', '\n\n', 'g')
"
	" 文字参照のデコード
	let body = s:decode_character_reference(body)

	let a:item.description = split(body, "\n")
	if s:is_empty_description(a:item.description)
		let a:item.description = []
	endif
	let a:item.marker_link = marker_link
endfunction
"}}}

"}}}



" 指定された単語の説明文をデータベースから取得
function! s:getDescription(word, db_path)"{{{

	" 以降のコードはpythonコードなので、-python環境では実行しない
	if has('python') == 0
		return s:create_searchresult()
	endif

python << END_OF_PYTHON_PART
import vim
import re
vim.command("let result_key=''")
vim.command("let result = "+ str([]))

try:
	_sqlite, isSQLite3 = importSQLite()
	dbFile = vim.eval("expand(a:db_path)")
	conn = _sqlite.connect(dbFile)

	keyword = ''
	desc = []
	word = vim.eval("a:word")
	# 行末の改行を除去
	word = word.rstrip("\r\n")
	# 前後の空白を削除
	word = word.strip(" \t")
	
	keyword, desc = getDescriptionFromDB(conn, word)
	# 対応する説明文が見つからなかった場合は、単語を変形して再試行
	if len(desc)==0:
		stemmedWords = stemWord(word)
		for _ in stemmedWords:
			if _ == word: continue
			keyword, desc = getDescriptionFromDB(conn, _)
			if len(desc) > 0: break
	
	conn.close()

	def escape(string):
		result = ''
		if type(string) == type(u''):
			for _ in string: result += "\\u%04x"%(ord(_),)
		else:
			for _ in string: result += "\\x%02x"%(ord(_),)
			return result

	keyword = keyword.replace('"','\\"')
	vim.command('silent! let result_key = "' + escape(keyword) + '"')
	vim.command('silent! let result = []')
	for item in desc:
		data = 'silent! let result += ["' + escape(item) + '"]'
		vim.command(data)

except _sqlite.OperationalError: pass
except ImportError: pass
except UnicodeDecodeError: pass
END_OF_PYTHON_PART
	return s:create_searchresult(result_key, result)
endfunction"}}}

" function! s:AL_urlencoder_ch2hex(ch)
function! s:ch2hex(ch)"{{{
  let result = ''
  let i = 0
  let chlen = len(a:ch)
  while i < chlen
    let result .= printf("%%%02x", char2nr(a:ch[i]))
    let i += 1
  endwhile
  return result
endfunction"}}}

" URLエンコードを行います
function! s:encode_for_url(context, word)"{{{
	if get(a:context, 'url_encode', '') ==  ''
		return a:word
	endif
	return iconv(a:word, &enc, a:context.url_encode)
endfunction"}}}

" カーソル位置のマーカーリンク内文字列を取得
function! s:get_marker_string(lmkr, rmkr)"{{{
	" Note: 同一行に複数のマーカーがあり、
	" マーカー文字上にカーソカーソルを置いた状態でジャンプを実行した時の挙動が微妙
	let line = getline(".")
	let chr = line[getpos(".")[2]-1]
	" 前方の区切り文字を検索
	let s = searchpos('\V'.a:lmkr.'\|'. a:rmkr, chr == a:rmkr? 'nbW': 'nbcW')
	if s == [0,0] || s[0] != line(".") || line[s[1]-1] != a:rmkr
		return ''
	endif
	" 後方の区切り文字を検索
	let e = searchpos('\V'. a:lmkr.'\|'. a:rmkr, chr == a:lmkr? 'nW': 'ncW')
	if e == [0,0] || e[0] != line(".") || line[e[1]-1] != a:rmkr
		return ''
	endif
	return line[s[1]:e[1]-2]
endfunction"}}}

" 指定した履歴情報に関連づけられたウインドウ(バッファ)の現在位置を取得
function! s:get_current_position(name)"{{{
	let context = s:get_external_engine(a:name)
	let bname = get(context, 'bufname', 'CursorOverDictionary')
	if bufexists(bname) == 0
		return []
	endif
	let cur_winnr = bufwinnr("%")
	let winnr = s:get_output_winnr(bname)
	if winnr == -1
		return []
	endif

	execute winnr 'wincmd w'
	let pos = getpos(".")
	execute cur_winnr 'wincmd w'

	return pos
endfunction"}}}

" カーソル位置がマーカー内だった場合、マーカーを検索
function! s:jump_marker() "{{{
	let link = s:get_marker_string('|','|')
	if link == ''
		return
	endif

	let his = s:get_recent_history(0)
	if s:is_empty_searchresult(his)
		return
	endif

	let l:pos = getpos(".")

	let name = s:get_recent_engine()

	let item = {}
	if has_key(his, "marker_link") && has_key(his.marker_link, link)
		let item = s:search(name, his.marker_link[link])
	endif
	if s:is_empty_searchresult(item)
		let item = s:search(name, link)
	endif

	call s:update(name, item)

	let his.pos = l:pos

endfunction "}}}

" 外部から訳を取得するためのURLを生成
function! s:makeUrl(context, word) "{{{
	let l:word = s:encode_for_url(a:context, a:word)
  let l:word = substitute(l:word, '\c[^- *.0-9a-z]', '\=s:ch2hex(submatch(0))', 'g')
  let l:escaped_word = substitute(l:word, ' ', '+', 'g')
	let l:url = substitute(a:context.url, '{word}', l:escaped_word, 'g')

	let l:url = substitute(l:url, '|', '%7c', 'g')

	return l:url
endfunction
"}}}

" ファイル読み込み
function! s:readfile(filepath) "{{{
	if filereadable(a:filepath) == 0
		return ''
	endif
	return join(readfile(a:filepath, 'b'), "\n")
endfunction
"}}}

" cURLを実行して、データを読み込む
function! s:do_curl(req)"{{{

	let retry_count = 2
	let redirect = " -L --max-redirs " . retry_count . " "

	let l:opt = '--fail -s -w "%{http_code}"' . redirect

	let tmp_data = tempname()

	let l:proxy = len(a:req.proxy) ? ' -x ' . a:req.proxy : ' '
	let l:useragent = len(a:req.user_agent) ? ' -A "' . a:req.user_agent . '" ' : ''


	let cmd = "curl " . l:opt . l:proxy . l:useragent . ' -o ' . tmp_data . ' "' . a:req.url. '"'
	let response = system(s:escape_for_win32(cmd))

	let res_data = { "statuscode":200 }
	if response =~ '^\d\+$'
		let res_data.statuscode = 0+response
	endif

	let res_data.data = s:readfile(tmp_data)
	" 失敗したら、気休めに標準出力の結果をうけとる
	if res_data.data == ''
		let res_data.data = response
	endif

	silent call delete(tmp_data)
	return res_data
endfunction"}}}

" cURLを使ってURLからデータを取得
function! s:get_from_url(context, word) "{{{

	" curlが実行できない場合はエラー
	if executable('curl') == 0
		call s:echoerr('curlがみつかりません')
		return ''
	endif

	let req = {}

	" URL文字列の生成
	let req.url = s:makeUrl(a:context, a:word)
	if req.url == ''
		return ''
	endif

	let req.proxy = ''
	if $http_proxy != '' || $HTTP_PROXY != ''
		let l:http_proxy = $http_proxy != '' ? $http_proxy : $HTTP_PROXY
		let req.proxy= substitute(l:http_proxy, '\%(https\?://\)\(.\{-}\)', '\1', '')
	endif
	let req.proxy = get(a:context, "proxy", req.proxy)
	let req.user_agent = get(a:context, "user_agent", '')

	let res = s:do_curl(req)
	" 200でなければエラー
	if res.statuscode != 200
		return ''
	endif

	return res.data
endfunction
"}}}

" 外部コマンドからデータを取得
function! s:get_from_system(context, word) "{{{
  let l:word = s:encode_for_url(a:context, a:word)
	let l:url = substitute(a:context.url, '{word}', l:word, 'g')
	return system(s:escape_for_win32(l:url))
endfunction
"}}}

" Win32環境固有のエスケープ処理
function! s:escape_for_win32(data) "{{{
	let data = a:data
	" Windowsで、%...%という文字列がパスに含まれていた場合、
	" 環境変数として展開されてしまうことがあるため、これをエスケープする
	if has('win32') == 0
		return data
	endif
	let data = substitute(data, '%', '^\%', 'g')
	let data = substitute(data, '&', '^&', 'g')
	let data = substitute(data, '"', '""', 'g')
	return '"'.data.'"'
endfunction
"}}}

" (start,end)間の部分文字列を得る
function! s:substr(data, start, end)"{{{
	" NOTE:正規表現の後方参照を使うと大きいデータで極端に遅くなるための代替処理
	let s = len(a:start)>0 ? match(a:data, a:start . '\zs'): 0
	let e = len(a:end)>0 ? match(a:data, a:end, s) : len(a:end)

	if s == -1 && e == -1
		return a:data
	endif

	return a:data[s : e-1]
endfunction"}}}

" title属性とリンク内テキストの関連づけを保持
function! s:register_link(marker_link, link, text)"{{{
	
	let l:text = s:decode_character_reference(a:text)
	let a:marker_link[l:text] = s:decode_character_reference(a:link)

	return '|'. a:text . '|'
endfunction"}}}

" キャッシュファイルのパスを取得
function! s:getCacheFilePath() "{{{
  " 永続的なキャッシュファイルが指定されていた場合は、それを使用
  if exists('g:CODPermanentCachePath') && g:CODPermanentCachePath != ''
    return g:CODPermanentCachePath
  endif
  " そうでなければ、一時的なパスを生成し、キャッシュファイルとする
  if exists('s:tempCachePath') == 0
    let s:tempCachePath = tempname()
  endif
  return s:tempCachePath
endfunction "}}}

" 外部からの取得結果をキャッシュに登録
function! s:register_cache(engine_name, item) "{{{
  if has('python') == 0
    return 0
  endif

  let l:keyword = a:engine_name . "@@" . a:item.keyword
	let l:description = a:item.description

	" marker_link属性を文字列化
	let l:marker_link = ''
	if has_key(a:item, 'marker_link') && len(a:item.marker_link)
		let l:marker_link = string(a:item.marker_link)
	endif

python << END_OF_PYTHON_PART
import vim
try:
	_sqlite, isSQLite3 = importSQLite()

	enc = vim.eval('&enc')
	fencode=enc

	dbFile = vim.eval("expand(s:getCacheFilePath())")
	conn = _sqlite.connect(dbFile)

	cur = conn.cursor()

	if isSQLite3 == False:
		try: cur.con.encoding = (enc,)
		except: pass

	# DBの作成
	# sqliteではif not existsが使えないのでエラーをつぶしている(sqlite3では使用可能)
	try:
		cur.execute(u"create table words (keyword TEXT PRIMARY KEY, description TEXT);")
	except: pass

	keyword, descList = vim.eval('l:keyword'), vim.eval('l:description')
	marker_link = vim.eval('l:marker_link')
	# 行末の改行を除去
	keyword = keyword.rstrip("\r\n")
	# 前後の空白を削除
	keyword = keyword.strip(" \t")

	if type(keyword) != type(u''): keyword = keyword.decode(enc)

	description = ' \\ '.join(descList)
	# 「\\\\ 」を区切りとしてmarker_link情報を埋め込む
	# (s:getDescriptionFromCache側で復元します)
	if len(marker_link) > 0:
		description += ' \\ \\\\\\\\ '
		description += marker_link
	description = description.decode(enc)

	if "/" not in keyword:
	  # 取得したデータをデータベースに流し込む
	  insert_keyword(cur, keyword, description, True, _sqlite, isSQLite3)

	conn.commit()
	conn.close()
except UnicodeDecodeError:
	echoError('データベース登録時に文字コードを変換できませんでした。('+fencode +'->utf-8)')
except ImportError:
	echoError('sqliteのimportに失敗しました(pythonのバージョンが古い?)')
except _sqlite.IntegrityError:
	echoError('キーワード「%s」は既に登録済みです'%(keyword.encode(enc),))
except _sqlite.OperationalError:
	echoError('DBの操作中にエラーが発生しました(Diskfullか、さもなくばBug)')
except IOError:
	echoError("指定されたファイルは存在しません : " + pdict_path)
except LookupError:
	echoError('不明な文字コード形式です : ' + fencode)
END_OF_PYTHON_PART
	return 1
endfunction
"}}}

" キャッシュから単語の説明文を取得
function! s:getDescriptionFromCache(context, word) "{{{
  let searchWord = a:context.name . '@@' . a:word
  let item = s:getDescription(searchWord, s:getCacheFilePath())

	let item.keyword = a:word
	" Note: ここでのs:getDescriptionの戻り値は
	" <a:context.name> . '@@' . keyword という形式になっているので
	" ここでキーワードを書き換える

	" marker_link属性の復元
	for _ in range(len(item.description))
		let l:line = item.description[_]
		if l:line !~ '^\\\\\\\\ '
			continue
		endif
		exe "let item.marker_link =" substitute(l:line, '^\\\\\\\\ \(.*\)', '\1', '')
		call remove(item.description, _)
		break
	endfor

  return item
endfunction "}}}

" ユーザ定義関数から取得
function! s:get_from_function(context, word) "{{{
	" [1:]としているのは先頭の*を取り除くため
	let Func = function(a:context.url[1:])
	return type(Func) != type(0) ? Func(a:word) : ''
endfunction "}}}

" 外部から単語の説明文を取得
function! s:getDescriptionFromExternal(context, word) "{{{
	" 前後の空白を除去
	let l:word = matchstr(a:word, '^\s*\zs.\{-}\ze\%(\s\|\n\)*$')
	" 必要に応じてキャッシュを利用する
	let item = s:getDescriptionFromCache(a:context, l:word)
	" ToDo: getDescriptionFromCacheでitemの状態を完全に復元できるようにする
	if s:is_empty_searchresult(item) == 0
		return item
	endif

	" URLへのアクセスを行い、結果を取得
	if a:context.url =~# 'https\?://'
		let _ = s:get_from_url(a:context, l:word)
	elseif a:context.url[0] == '*'
		let _ = s:get_from_function(a:context, l:word)
	else
		let _ = s:get_from_system(a:context, l:word)
	endif
	if _ == ''
		return s:create_searchresult()
	endif
	if has_key(a:context, 'error_pattern') && _ =~# a:context.error_pattern
		return s:create_searchresult()
	endif

	" サイト側のエンコード形式 -> &encへのデコード
	let item.description = iconv(_, a:context.site_encode, &enc)

	" 得られたデータから、必要な部分のテキストのみを抽出
	call s:strip_searchresult(item, a:context)
	" 必要に応じてキャッシュ登録
	call s:register_cache(a:context.name, item)
	return item
endfunction
"}}}

" get select text.
" http://vim.g.hatena.ne.jp/keyword/%e9%81%b8%e6%8a%9e%e3%81%95%e3%82%8c%e3%81%9f%e3%83%86%e3%82%ad%e3%82%b9%e3%83%88%e3%81%ae%e5%8f%96%e5%be%97
function! s:selected_text(...)"{{{
  let [visual_p, pos] = [mode() =~# "[vV\<C-v>]", getpos('.')]
  let [r_, r_t] = [@@, getregtype('"')]
  let [r0, r0t] = [@0, getregtype('0')]
  if &cb == "unnamed"
	  let [rast, rastt] = [@*, getregtype('*')]
  endif


  if visual_p
    execute "normal! \<Esc>"
  endif
  silent normal! gvy
  let [_, _t] = [@@, getregtype('"')]

  call setreg('"', r_, r_t)
  call setreg('0', r0, r0t)
  " set cb=unnamedな環境だと、yank,pasteに"*レジスタが使われるのでこれも復元できるように
  if &cb == "unnamed"
	  call setreg('*', rast, rastt)
  endif
  if visual_p
    normal! gv
  else
    call setpos('.', pos)
  endif
  return a:0 && a:1 ? [_, _t] : _
endfunction"}}}

function! s:search(name, word)"{{{
	if len(a:word) == 0
		return {}
	endif
	if a:name == 'internal'
		" 内部検索
		let item = s:getDescription(a:word, g:CODDatabasePath)
		if s:is_empty_searchresult(item) && s:has_default_engine()
			" 見つからなかった場合はデフォルトの検索エンジンを使って外部から取得してみる
			let item = s:getDescriptionFromExternal(s:get_default_engine(), a:word)
		endif
	elseif s:has_external_engine(a:name)
		" 外部検索
		let item = s:getDescriptionFromExternal(s:get_external_engine(a:name), a:word)
	else
		return {}
	endif
	if s:is_empty_searchresult(item)
		call s:echoerr("単語は見つかりませんでした: " . a:word)
	endif
	return item
endfunction"}}}

" パラメータで指定されたキーワードを調べる
" 指定されなかった場合はプロンプト入力
function! s:search_word(name, ...)"{{{
	let word = len(a:000) == 0 ? input("単語を入力:") : join(a:000, ' ')
	let item = s:search(a:name, word)
	if s:is_empty_searchresult(item)
		return 1
	endif
	call cursoroverdictionary#open(0, a:name)
	call s:update(a:name, item)
	return 0
endfunction"}}}
" 選択されたテキストを調べる
function! cursoroverdictionary#selected()"{{{
	call cursoroverdictionary#selected_ex('internal')
endfunction"}}}

" 外部検索エンジンで選択されたテキストを調べる
function! cursoroverdictionary#selected_ex(name)"{{{
	let text = s:selected_text()
	if len(text) == 0 | return | endif
	return cursoroverdictionary#search_keyword_ex(a:name, text)
endfunction"}}}

" パラメータで指定されたキーワードを調べる
" 指定されなかった場合はプロンプト入力
function! cursoroverdictionary#search_keyword(...)"{{{
	return call('cursoroverdictionary#search_keyword_ex', ['internal']+a:000)
endfunction"}}}

" パラメータで指定されたキーワードを調べる
" 指定されなかった場合はプロンプト入力
function! cursoroverdictionary#search_keyword_ex(name, ...)"{{{
	let his = s:get_recent_history(0)
	let l:pos = s:get_current_position(a:name)

	let item = call('s:search_word', [ a:name ] + a:000)

	let his.pos = l:pos
	return item
endfunction"}}}

"	位置情報があったらカーソル位置を復元
function! s:restore_cursor_position(item)"{{{
	let pos = get(a:item, "pos", [])
	if len(pos) == 4
		call setpos(".", pos)
	endif
endfunction"}}}

function s:move_history(offset)"{{{
	let next_index= s:search_history_index + a:offset
	if next_index < 0 || len(s:search_history_list) <= next_index
		return 1
	endif

	" 履歴をたどる前に現在の履歴における位置を記憶
	let cur_item = s:get_recent_history(0)
	let cur_item.pos = getpos(".")

	let s:search_history_index = next_index
	let his = s:get_recent_history(0)
	call s:search_word(his.engine_name, his.keyword)
	call s:restore_cursor_position(his)
endfunction"}}}

" 「前に戻る」
function! cursoroverdictionary#previous_page()"{{{
	return s:move_history(-1)
endfunction"}}}

" 「次に進む」
function! cursoroverdictionary#next_page()"{{{
	return s:move_history(1)
endfunction"}}}

" 外部検索エンジンの設定
let s:external_engines = {}
" デフォルト
let s:default_engine = ''


" 履歴保持件数
let s:history_max_count = 100
" 検索結果データをを要素とするリスト
let s:search_history_list = []
" s:search_history_listの現在位置を示すインデックス値
let s:search_history_index = -1

" 検索履歴を追加
function! s:add_search_history(item) "{{{

	" 検索文字列が空だったら何もしない
	if len(a:item.keyword) == 0
		return
	endif

	" 履歴の重複チェック
	if s:search_history_index >= 0 && a:item.keyword == s:search_history_list[s:search_history_index].keyword
		return
	endif

	let s:search_history_list = s:search_history_list[ : s:search_history_index]

	call insert(s:search_history_list, a:item, s:search_history_index + 1)

	if len(s:search_history_list) > s:history_max_count
		let s:search_history_list = s:search_history_list[ len(s:search_history_list)-s:history_max_count : ]
	else
		let s:search_history_index += 1
	endif
endfunction "}}}

" 検索履歴データを取得
function! s:get_recent_history(offset)"{{{
	let index = s:search_history_index + a:offset
	if index < 0 || len(s:search_history_list) < index
		return s:create_searchresult()
	endif

	return s:search_history_list[index]
endfunction"}}}

" 直近で使用した外部検索エンジン名を取得
function! s:get_recent_engine()"{{{
	if len(s:search_history_list) == 0
		return ''
	endif
	let item = s:get_recent_history(0)
	return item.engine_name
endfunction"}}}

" 指定された外部検索エンジンがないか調べ、なければエラーメッセージ表示
function! s:has_external_engine(name) "{{{
	if has_key(s:external_engines, a:name) == 0
		call s:echoerr(a:name . "は登録されていません")
		return 0
	endif
	return 1
endfunction
"}}}

function! s:get_external_engine(name)"{{{
	return get(s:external_engines, a:name, {})
endfunction"}}}

" 検索エンジンデータに属性を設定
function! s:set_engine_attribute(engine_name, attr_name, data, ...) "{{{
	if s:has_external_engine(a:engine_name) == 0
		return 0
	endif
	let context = s:external_engines[a:engine_name]

	" 4番目の引数で0が指定された場合は、属性の上書きは行わない
	if has_key(context, a:attr_name) && len(a:000) > 0 && a:1 == 0
		return 1
	endif

	let context[a:attr_name] = a:data
	return 1
endfunction "}}}

" 外部検索エンジンの登録
function! cursoroverdictionary#add(name, url, urlenc, siteenc) "{{{
	if has_key(s:external_engines, a:name) == 0
		let s:external_engines[a:name] = {}
	endif

	let context = s:external_engines[a:name]
	let context.name = a:name
	let context.url = a:url
	let context.url_encode = a:urlenc
	let context.site_encode = a:siteenc
	let context.start_pattern = ''
	let context.end_pattern = ''

	call s:add_operator_user(a:name)
endfunction
"}}}

" 取得したデータの切り出しパターンを設定
function! cursoroverdictionary#set_trim_pattern(name, start, end) "{{{
	if s:has_external_engine(a:name) == 0
		return 0
	endif
	let context = s:external_engines[a:name]
	call extend(context, {"start_pattern":a:start, "end_pattern":a:end})
	return 1
endfunction
"}}}

" プロキシを使う設定
function! cursoroverdictionary#enable_proxy(name, proxy, ...) "{{{
	return s:set_engine_attribute(a:name, "proxy", a:proxy, s:ow(a:000))
endfunction
"}}}

function! s:ow(arg)"{{{
	return len(a:arg) ? a:arg[0] : 1
endfunction"}}}

" 外部URLへリクエストを送る際のUSER-AGENTを設定
" (設定しない場合はcURLのデフォルトを使用)
function! cursoroverdictionary#set_user_agent(name, agent, ...) "{{{
	return s:set_engine_attribute(a:name, "user_agent", a:agent, s:ow(a:000))
endfunction
"}}}

" デフォルトの外部検索エンジンを指定します
function! cursoroverdictionary#set_default_engine(name) "{{{
	if s:has_external_engine(a:name) == 0
		return 0
	endif
	let s:default_engine = a:name
	return 1
endfunction
"}}}

" 結果表示ウインドウ新規表示時にフォーカスを移動するかどうかを設定します
function! cursoroverdictionary#set_windowfocus(name, on, ...) "{{{
	return s:set_engine_attribute(a:name, "windowfocus", a:on, s:ow(a:000))
endfunction "}}}

" ウインドウの高さを設定
function! cursoroverdictionary#set_windowheight(name, height, ...)"{{{
	return s:set_engine_attribute(a:name, "windowheight", a:height, s:ow(a:000))
endfunction"}}}

" ウインドウ表示方向を指定
function! cursoroverdictionary#set_windowdirection(name, dir, ...)"{{{
	return s:set_engine_attribute(a:name, "direction", a:dir, s:ow(a:000))
endfunction"}}}

" 結果表示バッファ名を指定
function! cursoroverdictionary#set_buffername(name, bufname, ...)"{{{
	return s:set_engine_attribute(a:name, 'bufname', a:bufname, s:ow(a:000))
endfunction"}}}

" エラーとするパターンを設定
function! cursoroverdictionary#set_errorpattern(name, pattern, ...)"{{{
	return s:set_engine_attribute(a:name, 'error_pattern', a:pattern, s:ow(a:000))
endfunction"}}}

" バッファ更新時に実行する処理を設定
function! cursoroverdictionary#set_updateevent(name, enterfunc, leavefunc, ...) "{{{
	call s:set_engine_attribute(a:name, 'enter_function', a:enterfunc, s:ow(a:000))
	call s:set_engine_attribute(a:name, 'leave_function', a:leavefunc, s:ow(a:000))
endfunction "}}}

" デフォルトの外部検索エンジンを取得します
function! s:get_default_engine() "{{{
	if has_key(s:external_engines, s:default_engine) == 0
		return 0
	endif
	return s:external_engines[s:default_engine]
endfunction
"}}}

" デフォルトの外部検索エンジンの有無を確認します
function! s:has_default_engine() "{{{
	return type(s:get_default_engine()) != type(0)
endfunction
"}}}

" operator実行の際に使う外部検索エンジン
let s:operator_user_engine = ''

" operatorで実行する直前に、使用する外部検索エンジンを設定します
function! cursoroverdictionary#set_engine_in_operator_user(name) "{{{
	let s:operator_user_engine = a:name
endfunction
"}}}

" operator-userから呼び出せるようにします
function! cursoroverdictionary#operator_default(motion_wise) "{{{

	let v = operator#user#visual_command_from_wise_name(a:motion_wise)

	let [original_U_content, original_U_type] = [@", getregtype('"')]
	if &cb == "unnamed"
		let [rast, rastt] = [@*, getregtype('*')]
	endif
	silent execute 'normal!' '`['.v.'`]y'
	let word = @"
	call setreg('"', original_U_content, original_U_type)
	if &cb == "unnamed"
		call setreg('*', rast, rastt)
	endif
	return cursoroverdictionary#search_keyword_ex(s:operator_user_engine, word)
endfunction
"}}}

function! cursoroverdictionary#operator_last(motion_wise) "{{{
	call cursoroverdictionary#set_engine_in_operator_user(s:get_recent_engine())
	return cursoroverdictionary#operator_default(a:motion_wise)
endfunction "}}}

" 任意の検索エンジンによる検索処理をoperator-userから呼び出せるようにします
function! s:add_operator_user(name) "{{{

	if s:has_external_engine(a:name) == 0
		return 0
	endif

	silent! call operator#user#define('cod-' . a:name, 'cursoroverdictionary#operator_default', "call cursoroverdictionary#set_engine_in_operator_user('" . a:name . "')")

	return 1
endfunction
"}}}

" 以下、alice.vimからのコード(一部改変)
function! s:Utf_nr2byte(nr)"{{{
  if a:nr < 0x80
    return nr2char(a:nr)
  elseif a:nr < 0x800
    return nr2char(a:nr/64+192).nr2char(a:nr%64+128)
  else
    return nr2char(a:nr/4096%16+224).nr2char(a:nr/64%64+128).nr2char(a:nr%64+128)
  endif
endfunction"}}}

function! s:Uni_nr2enc_char(charcode)"{{{
  let char = s:Utf_nr2byte(a:charcode)
  if has('iconv') && strlen(char) > 1
    let char = strtrans(iconv(char, 'utf-8', &encoding))
  endif
  return char
endfunction"}}}

" vim:foldmethod=marker


