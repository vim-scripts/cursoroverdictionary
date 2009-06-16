" cursoroverdictionary.vim -- カーソル位置の英単語訳を表示
" 
" version : 0.0.3
" author : ampmmn(htmnymgw <delete>@<delete> gmail.com)
" url    : http://d.hatena.ne.jp/ampmmn
"
" ----
" history
"	 0.0.3		2009-03-12	fix bug.
"	 0.0.2		2009-02-03	minor change.
"	 0.0.1		2009-01-29	initial release.
" ----

scriptencoding cp932

if exists('loaded_cursoroverdictionary') || &cp
  finish
endif
let loaded_cursoroverdictionary=1

" Check Env.
if !has('python')"{{{
	echoerr "Required Vim compiled with +python"
	finish
endif
if v:version < 700
	echoerr "cursoroverdictionary.vim requires Vim 7.0 or later."
	finish
endif"}}}

" Global Variables

" DBファイルのパス
if exists("g:CODDatabasePath")==0"{{{
	let g:CODDatabasePath='~/.cursoroverdictionary_db'
endif"}}}

" ウインドウを表示する方向
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

" Functions

" autocmdの解除
function! s:delete_augroup()"{{{
	augroup CODCursorEvent
		autocmd!
	augroup END
endfunction"}}}

" 出力バッファ & ウインドウの作成
function! s:Open(update)"{{{
	" s:open_result_buffer@quickrun.vim
	let bname = 'CursorOverDictionary'
	let cur_winnr = winnr()

	" バッファが存在しなければ、出力ウインドウとともに作成
	if bufexists(bname) == 0
		silent execute g:CODDirection g:CODWindowHeight 'new'
		setlocal bufhidden=unload
		setlocal nobuflisted
		setlocal buftype=nofile
		setlocal nomodifiable
		setlocal noswapfile
		setlocal nonumber
		setfiletype cursoroverdictionary
		silent file `=bname`
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

	execute cur_winnr 'wincmd w'

	if (a:update!=0)
		call s:UpdateWord()
	endif
endfunction"}}}

" 出力バッファ & ウインドウの破棄
function! s:Close()"{{{
	let bname = '^CursorOverDictionary$'
	silent! execute 'bwipeout!' bufnr(bname)
endfunction"}}}

" ウインドウのトグル
function! s:Toggle()"{{{
	let win_nr = winnr('$')
	call s:Open(1)
	if win_nr == winnr('$')
		call s:Close()
	endif
endfunction"}}}

python << END_OF_PYTHON_PART

# Pythonスクリプト用エラーメッセージ出力
def echoError(msg):#{{{
	msg = msg.replace("'","''")
	import vim
	vim.command("echoerr 'Error:" + msg + "'")
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

END_OF_PYTHON_PART

" 指定したpdictファイルをデータベースに登録
function! s:RegistDict(add, ...)"{{{
	if a:0 == 0
		return 
	endif
python << END_OF_PYTHON_PART
import vim

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

	add = vim.eval('a:add')
	for line in fIn:
		line = line.decode(fencode,'ignore')

		# ここでファイルを一行ずつ読み込み、単語と説明文に分割する
		keyword, description = line.split(" /// ")
		description = description.strip("\r\n")
		# 取得したデータをデータベースに流し込む
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
function! s:get_output_winnr()"{{{
	let bname = 'CursorOverDictionary'
	if bufexists(bname) == 0
		return -1
	endif
	return bufwinnr(bufnr('^'.bname.'$'))
endfunction"}}}

" カーソル位置の単語の説明文を出力ウインドウに表示
function! s:UpdateWord()"{{{
	" ビジュアルモードの時は何もしない
	if mode() =~# "[vV\<C-v>]"
		return
	endif

	" 出力バッファがない、またはウインドウに表示されていない場合は何もしない
	let [orgnr, outputnr] = [winnr(), s:get_output_winnr()]
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

	" 現在位置の単語の説明文を取得
	let [word, description] = s:getDesctiption(cursor_word)
	call s:set_current_word(word)
	call s:update_window(word, description)
endfunction"}}}

" 指定した単語を「現在の単語」として記憶
function! s:set_current_word(word)"{{{
	let [output_winnr, cur_winnr] = [s:get_output_winnr(), winnr()]
	if output_winnr == -1
		return
	endif
	execute output_winnr 'wincmd w'
	let b:last_word = a:word
	execute cur_winnr 'wincmd w'
endfunction"}}}

" 出力ウインドウの内容を更新
function! s:update_window(word, description)"{{{
	let [output_winnr, cur_winnr] = [s:get_output_winnr(), winnr()]
	if output_winnr == -1
		return
	endif
	execute output_winnr 'wincmd w'
	if len(a:description) == 0
		execute cur_winnr 'wincmd w'
		return
	endif

	setlocal modifiable

	"既存の内容を全削除し、新しい内容に置き換える
	let org_ul = &undolevels
	try
		" 一時的にundo/redo機能を無効化し変更内容がundoツリーに残らないようにする
		" (一時的とはいえグローバルな値を変えることによる副作用がありそう・・)
		let &undolevels = -1
		silent! execute 1 'delete _' line('$')
		silent! call append(0, '== ' . a:word . ' ==')
		silent! call append(1, a:description)
	finally
		let &undolevels = org_ul
	endtry
	normal! 1G

	setlocal nomodifiable

	execute cur_winnr 'wincmd w'
endfunction"}}}

python << END_OF_PYTHON_PART

# 単語に対応する説明文を取得
def getDesctiption(conn, word):#{{{
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
		cur.execute(u"select * from words where keyword=" + param, (word,))
			# なんか、ここでmemory-leakのような挙動.使い方間違ってるのだろうか?

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

" 指定された単語の説明文をデータベースから取得
function! s:getDesctiption(word)"{{{
python << END_OF_PYTHON_PART
import vim
import re
vim.command("let result_key=''")
vim.command("let result = "+ str([]))

try:
	_sqlite, isSQLite3 = importSQLite()
	dbFile = vim.eval("expand(g:CODDatabasePath)")
	conn = _sqlite.connect(dbFile)

	keyword = ''
	desc = []
	word = vim.eval("a:word")
	# 行末の改行を除去
	word = word.rstrip("\r\n")
	# 前後の空白を削除
	word = word.strip(" \t")
	
	keyword, desc = getDesctiption(conn, word)
	# 対応する説明文が見つからなかった場合は、単語を変形して再試行
	if len(desc)==0:
		stemmedWords = stemWord(word)
		for _ in stemmedWords:
			if _ == word: continue
			keyword, desc = getDesctiption(conn, _)
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
		item = item.replace('"','\\"')
		data = 'silent! let result += ["' + escape(item) + '"]'
		vim.command(data)

except _sqlite.OperationalError: pass
except ImportError: pass
END_OF_PYTHON_PART
	return [result_key, result]
endfunction"}}}

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

" 選択されたテキストを調べる
function! s:Selected()"{{{
	let word = s:selected_text()
	if len(word) == 0
		return
	endif

	let [ keyword, description ] = s:getDesctiption(word)
	if len(description) == 0
		echoerr "単語は見つかりませんでした: " . word
		return
	endif

	call s:Open(0)

	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)

"	normal! gv
endfunction"}}}

" パラメータで指定されたキーワードを調べる
" 指定されなかった場合はプロンプト入力
function! s:SearchKeyword(...)"{{{
	let word = ''
	if a:0 == 0
		let word = input("単語を入力:")
		if len(word) == ''
			return 
		endif
	else
		let word = join(a:000, ' ')
	endif

	let [ keyword, description ] = s:getDesctiption(word)
	if len(description) == 0
		echoerr "単語は見つかりませんでした: " . word
		return
	endif

	call s:Open(0)

	" ここで現在のカーソル位置の単語をb:last_word変数に登録しておく
	" (そうしないと、CursorMovedイベントが発生してウインドウの内容が上書きされてしまう)
	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)
endfunction"}}}

" Commands

" ウインドウを表示
command! CODOpen call <SID>Open(1)
" ウインドウを破棄
command! CODClose call <SID>Close()
" ウインドウのトグル表示
command! CODToggle call <SID>Toggle()

" pdictファイルのインポート
command! -bang -nargs=+ CODRegistDict call <SID>RegistDict(len("<bang>")!=0, <f-args>)

" 選択した単語・語句の説明文を表示
command! CODSelected call <SID>Selected()

" キーワードをコマンドラインパラメータで指定(指定なしの場合は対話モード)
command! -nargs=* CODSearch call <SID>SearchKeyword(<f-args>)

" vim:foldmethod=marker

