" cursoroverdictionary.vim -- カーソル位置の英単語訳を表示
" 
" version : 0.0.7
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


" autocmdの解除
function! s:delete_augroup()"{{{
	augroup CODCursorEvent
		autocmd!
	augroup END
endfunction"}}}

" 出力バッファ & ウインドウの作成
function! cursoroverdictionary#open(update)"{{{
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
		noremap <buffer><silent> q :bwipeout<cr>
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
function! cursoroverdictionary#close()"{{{
	let bname = '^CursorOverDictionary$'
	silent! execute 'bwipeout!' bufnr(bname)
endfunction"}}}

" ウインドウのトグル
function! cursoroverdictionary#toggle()"{{{
	let win_nr = winnr('$')
	call cursoroverdictionary#open(1)
	if win_nr == winnr('$')
		call cursoroverdictionary#close()
	endif
endfunction"}}}


" エラーメッセージの出力
function! s:echoerr(msg)
	let msg = iconv(a:msg, 'utf-8', &enc)

		echohl ErrorMsg
		echo msg
		echohl
endfunction

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


	add = vim.eval('a:add')
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
function! s:get_output_winnr()"{{{
	let bname = 'CursorOverDictionary'
	if bufexists(bname) == 0
		return -1
	endif
	return bufwinnr(bufnr('^'.bname.'$'))
endfunction"}}}

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
		let l:word = substitute(a:word,"\n\\|\t",'','g')
		let &undolevels = -1
		silent! execute 1 'delete _' line('$')
		silent! call append(0, '== ' . l:word . ' ==')
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

endif " has('python')

" 指定された単語の説明文をデータベースから取得
function! s:getDesctiption(word)"{{{

	" 以降のコードはpythonコードなので、-python環境では実行しない
	if has('python') == 0
		return ['', '']
	endif

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
except UnicodeDecodeError: pass
END_OF_PYTHON_PART
	return [result_key, result]
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

" 外部から訳を取得するためのURLを生成
function! s:makeUrl(context, word) "{{{
  let l:word = iconv(a:word, &enc, a:context.url_encode)
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

" 外部コマンド実行のためのコマンドライン文字列を生成
function! s:get_from_url(context, url) "{{{
	let tmp_data = tempname()

	let l:proxy = ''
	if has_key(a:context, "proxy") && a:context.proxy != ""
		let l:proxy = ' -x ' . a:context.proxy
	endif

	let l:useragent = ''
	if has_key(a:context, "user_agent")
		let l:useragent = ' -A "' . a:context.user_agent . '" '
	endif

	let cmd = "curl --fail -s -w \"%{http_code}\"". l:proxy . l:useragent . ' -o ' . tmp_data . ' "' . a:url. '"'

	let response = system(s:escape_for_win32(cmd))
	let result = iconv(s:readfile(tmp_data), a:context.site_encode, &enc)

	" 失敗したら、気休めに標準出力の結果をうけとる
	if result == ''
		let result = response
	endif

	silent call delete(tmp_data)

	return result
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
	let s = match(a:data, a:start . '\zs')
	let e = match(a:data, a:end, s)
	return a:data[s : e-1]
endfunction"}}}

" タグを削除し、テキストのみを抽出
function! s:stripTag(context, contents) "{{{
	let body = s:substr(a:contents, a:context.start_pattern, a:context.end_pattern)

	" scriptタグ内のデータはすべて不要
	let body = substitute(body, '<script.\{-}</script>', '', 'g')
	" リスト形式の項目は改行を入れる
	let body = substitute(body, '<li>\(\_.\{-}\)</li>', '\1\n', 'g')
	" 残りのタグはすべて消す
	let body = substitute(body, '<.\{-}>', '', 'g')
	" 改行コードは\nに
	let body = substitute(body, '\r\n', '\n', 'g')
	" 2行以上の空白は1行空白にまとめる
	let body = substitute(body, '\n\n\n\+', '\n\n', 'g')

	return split(body, "\n")
endfunction
"}}}

" 外部から単語の説明文を取得
function! s:getDesctiptionFromExternal(context, word) "{{{
	let [keyword, description] = [ '', [] ]

	" 前後の空白/改行を削除
	let l:word = substitute(a:word, '^\s*\(.*\)','\1', '')
	while len(l:word) && (l:word[len(l:word)-1]=="\n" || l:word[len(l:word)-1]==' ')
		let l:word = l:word[: len(l:word)-2]
	endwhile

	" URL文字列の生成
	let l:url = s:makeUrl(a:context, l:word)
	if l:url == ''
		return ['',[]]
	endif


	" URLへのアクセスを行い、結果を取得
	let l:result = s:get_from_url(a:context, l:url)
	if l:result == ''
		return ['', []]
	endif

	" 得られたデータから、必要な部分のテキストのみを抽出
	return [a:word, s:stripTag(a:context, l:result)]
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

" 選択されたテキストを調べる
function! cursoroverdictionary#selected()"{{{
	let word = s:selected_text()
	if len(word) == 0
		return
	endif

	let [ keyword, description ] = s:getDesctiption(word)
	if len(description) == 0 && s:has_default_engine()
		" 見つからなかった場合はデフォルトの検索エンジンを使って外部から取得してみる
		let [ keyword, description ] = s:getDesctiptionFromExternal(s:get_default_engine(), word)
	endif
	if len(description) == 0
		call s:echoerr("単語は見つかりませんでした: " . word)
		return
	endif

	call cursoroverdictionary#open(0)

	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)

"	normal! gv
endfunction"}}}

" 外部検索エンジンで選択されたテキストを調べる
function! cursoroverdictionary#selected_ex(name)"{{{
	let word = s:selected_text()
	if len(word) == 0
		return
	endif

	" 見つからなかった場合は外部から取得してみる
	if s:has_external_engine(a:name) == 0
		return
	endif

	let [ keyword, description ] = s:getDesctiptionFromExternal(s:external_engines[a:name], word)
	if len(description) == 0
		call s:echoerr("単語は見つかりませんでした: " . word)
		return
	endif

	call cursoroverdictionary#open(0)

	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)

"	normal! gv
endfunction"}}}

" パラメータで指定されたキーワードを調べる
" 指定されなかった場合はプロンプト入力
function! cursoroverdictionary#search_keyword(...)"{{{
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
	if len(description) == 0 && s:has_default_engine()
		" 見つからなかった場合は外部から取得してみる
		let [ keyword, description ] = s:getDesctiptionFromExternal(s:get_default_engine(), word)
	endif
	if len(description) == 0
		call s:echoerr("単語は見つかりませんでした: " . word)
		return
	endif

	call cursoroverdictionary#open(0)

	" ここで現在のカーソル位置の単語をb:last_word変数に登録しておく
	" (そうしないと、CursorMovedイベントが発生してウインドウの内容が上書きされてしまう)
	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)
endfunction"}}}

" パラメータで指定されたキーワードを調べる
" 指定されなかった場合はプロンプト入力
function! cursoroverdictionary#search_keyword_ex(name, ...)"{{{
	let word = ''
	if a:0 == 0
		let word = input("単語を入力:")
		if len(word) == ''
			return 
		endif
	else
		let word = join(a:000, ' ')
	endif

	if s:has_external_engine(a:name) == 0
		return
	endif

	let [ keyword, description ] = s:getDesctiptionFromExternal(s:external_engines[a:name], word)
	if len(description) == 0
		call s:echoerr("単語は見つかりませんでした: " . word)
		return
	endif

	call cursoroverdictionary#open(0)

	" ここで現在のカーソル位置の単語をb:last_word変数に登録しておく
	" (そうしないと、CursorMovedイベントが発生してウインドウの内容が上書きされてしまう)
	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)
endfunction"}}}

" 外部検索エンジンの設定
let s:external_engines = {}
" デフォルト
let s:default_engine = ''

" 指定された外部検索エンジンがないか調べ、なければエラーメッセージ表示
function! s:has_external_engine(name) "{{{
	if has_key(s:external_engines, a:name) == 0
		call s:echoerr(a:name . "は登録されていません")
		return 0
	endif
	return 1
endfunction
"}}}

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

	call s:add_operator_user(a:name)
endfunction
"}}}

" 取得したデータの切り出しパターンを設定
function! cursoroverdictionary#set_trim_pattern(name, start, end) "{{{
	if s:has_external_engine(a:name) == 0
		return 0
	endif

	let context = s:external_engines[a:name]
	let context.start_pattern = a:start
	let context.end_pattern = a:end

	return 1
endfunction
"}}}

" プロキシを使う設定
function! cursoroverdictionary#enable_proxy(name, proxy) "{{{
	if s:has_external_engine(a:name) == 0
		return 0
	endif
	let context = s:external_engines[a:name]
	let context.proxy = a:proxy
	return 1
endfunction
"}}}

" 外部URLへリクエストを送る際のUSER-AGENTを設定
" (設定しない場合はcURLのデフォルトを使用)
function! cursoroverdictionary#set_user_agent(name, agent) "{{{
	if s:has_external_engine(a:name) == 0
		return 0
	endif
	let context = s:external_engines[a:name]
	let context.user_agent = a:agent
	return 1
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

" 任意の検索エンジンによる検索処理をoperator-userから呼び出せるようにします
function! s:add_operator_user(name) "{{{

	if s:has_external_engine(a:name) == 0
		return 0
	endif

	silent! call operator#user#define('cod-' . a:name, 'cursoroverdictionary#operator_default', "call cursoroverdictionary#set_engine_in_operator_user('" . a:name . "')")

	return 1
endfunction
"}}}

" vim:foldmethod=marker


