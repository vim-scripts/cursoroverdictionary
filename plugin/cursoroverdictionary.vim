" cursoroverdictionary.vim -- �J�[�\���ʒu�̉p�P����\��
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

" DB�t�@�C���̃p�X
if exists("g:CODDatabasePath")==0"{{{
	let g:CODDatabasePath='~/.cursoroverdictionary_db'
endif"}}}

" �E�C���h�E��\���������
if exists("g:CODDirection")==0"{{{
	let g:CODDirection='rightbelow'
endif"}}}

" �E�C���h�E�����\�����̕��E����
if exists("g:CODWindowHeight")==0"{{{
	let g:CODWindowHeight='10'
endif"}}}

" stemming�������̒u���p�^�[�����X�g
if exists("g:CODAdditionalStemmingPatterns")== 0"{{{
	let g:CODAdditionalStemmingPatterns=[]
endif "}}}

" Functions

" autocmd�̉���
function! s:delete_augroup()"{{{
	augroup CODCursorEvent
		autocmd!
	augroup END
endfunction"}}}

" �o�̓o�b�t�@ & �E�C���h�E�̍쐬
function! s:Open(update)"{{{
	" s:open_result_buffer@quickrun.vim
	let bname = 'CursorOverDictionary'
	let cur_winnr = winnr()

	" �o�b�t�@�����݂��Ȃ���΁A�o�̓E�C���h�E�ƂƂ��ɍ쐬
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
		" �o�b�t�@�̓E�C���h�E��ɕ\������Ă��邩? �Ȃ���΃E�C���h�E�����쐬
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

" �o�̓o�b�t�@ & �E�C���h�E�̔j��
function! s:Close()"{{{
	let bname = '^CursorOverDictionary$'
	silent! execute 'bwipeout!' bufnr(bname)
endfunction"}}}

" �E�C���h�E�̃g�O��
function! s:Toggle()"{{{
	let win_nr = winnr('$')
	call s:Open(1)
	if win_nr == winnr('$')
		call s:Close()
	endif
endfunction"}}}

python << END_OF_PYTHON_PART

# Python�X�N���v�g�p�G���[���b�Z�[�W�o��
def echoError(msg):#{{{
	msg = msg.replace("'","''")
	import vim
	vim.command("echoerr 'Error:" + msg + "'")
#}}}

# sqlite���C�u�����̃C���|�[�g
def importSQLite():#{{{
	try:
		import sqlite3
		return sqlite3, True
	except ImportError:
		import sqlite
		return sqlite, False
#}}}

END_OF_PYTHON_PART

" �w�肵��pdict�t�@�C�����f�[�^�x�[�X�ɓo�^
function! s:RegistDict(add, ...)"{{{
	if a:0 == 0
		return 
	endif
python << END_OF_PYTHON_PART
import vim

try:
	_sqlite, isSQLite3 = importSQLite()
	pdict_path = vim.eval("expand(a:1)")

	# pdic�����t�@�C���̕����R�[�h
	enc = vim.eval('&enc')
	fencode=enc
	# fencode���L�����ǂ����̃e�X�g
	"test".decode(fencode)

	fIn = open(pdict_path)

	dbFile = vim.eval("expand(g:CODDatabasePath)")
	conn = _sqlite.connect(dbFile)

	cur = conn.cursor()

	if isSQLite3 == False:
		try: cur.con.encoding = (enc,)
		except: pass

	# DB�̍쐬
	# sqlite�ł�if not exists���g���Ȃ��̂ŃG���[���Ԃ��Ă���(sqlite3�ł͎g�p�\)
	try:
		cur.execute(u"create table words (keyword TEXT PRIMARY KEY, description TEXT);")
	except: pass

	add = vim.eval('a:add')
	for line in fIn:
		line = line.decode(fencode,'ignore')

		# �����Ńt�@�C������s���ǂݍ��݁A�P��Ɛ������ɕ�������
		keyword, description = line.split(" /// ")
		description = description.strip("\r\n")
		# �擾�����f�[�^���f�[�^�x�[�X�ɗ�������
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
			# �����̃L�[���폜������ōēo�^�����݂�
			cur.execute(u"delete from words where keyword=" + del_param, (keyword,))
			cur.execute(u"insert into words values" + param, (keyword, description))


	conn.commit()
	conn.close()
except UnicodeDecodeError:
	echoError('�f�[�^�x�[�X�o�^���ɕ����R�[�h��ϊ��ł��܂���ł����B('+fencode +'->utf-8)')
except ImportError:
	echoError('sqlite��import�Ɏ��s���܂���(python�̃o�[�W�������Â�?)')
except _sqlite.IntegrityError:
	echoError('�L�[���[�h�u%s�v�͊��ɓo�^�ς݂ł�'%(keyword.encode(enc),))
except _sqlite.OperationalError:
	echoError('DB�̑��쒆�ɃG���[���������܂���(Diskfull���A�����Ȃ���Bug)')
except IOError:
	echoError("�w�肳�ꂽ�t�@�C���͑��݂��܂��� : " + pdict_path)
except LookupError:
	echoError('�s���ȕ����R�[�h�`���ł� : ' + fencode)
END_OF_PYTHON_PART
endfunction"}}}

" �o�̓E�C���h�E�ԍ����擾
function! s:get_output_winnr()"{{{
	let bname = 'CursorOverDictionary'
	if bufexists(bname) == 0
		return -1
	endif
	return bufwinnr(bufnr('^'.bname.'$'))
endfunction"}}}

" �J�[�\���ʒu�̒P��̐��������o�̓E�C���h�E�ɕ\��
function! s:UpdateWord()"{{{
	" �r�W���A�����[�h�̎��͉������Ȃ�
	if mode() =~# "[vV\<C-v>]"
		return
	endif

	" �o�̓o�b�t�@���Ȃ��A�܂��̓E�C���h�E�ɕ\������Ă��Ȃ��ꍇ�͉������Ȃ�
	let [orgnr, outputnr] = [winnr(), s:get_output_winnr()]
	if outputnr == -1
		return
	endif

	" ���݂̃E�C���h�E���o�̓E�C���h�E�̏ꍇ�͉������Ȃ�
	if outputnr == orgnr
		return
	endif

	" ���݈ʒu�̒P�ꂪ�Ȃ��ꍇ�͉������Ȃ�
	let cursor_word = expand("<cword>")
	if len(cursor_word) == 0
		return
	endif

	" �P�ꂪ�O��Ɠ����������牽�����Ȃ�
	execute outputnr 'wincmd w'
	let last_word = ''
	if exists("b:last_word")
		let last_word = b:last_word
	endif
	execute orgnr 'wincmd w'
	if last_word ==# cursor_word
		return
	endif

	" ���݈ʒu�̒P��̐��������擾
	let [word, description] = s:getDesctiption(cursor_word)
	call s:set_current_word(word)
	call s:update_window(word, description)
endfunction"}}}

" �w�肵���P����u���݂̒P��v�Ƃ��ċL��
function! s:set_current_word(word)"{{{
	let [output_winnr, cur_winnr] = [s:get_output_winnr(), winnr()]
	if output_winnr == -1
		return
	endif
	execute output_winnr 'wincmd w'
	let b:last_word = a:word
	execute cur_winnr 'wincmd w'
endfunction"}}}

" �o�̓E�C���h�E�̓��e���X�V
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

	"�����̓��e��S�폜���A�V�������e�ɒu��������
	let org_ul = &undolevels
	try
		" �ꎞ�I��undo/redo�@�\�𖳌������ύX���e��undo�c���[�Ɏc��Ȃ��悤�ɂ���
		" (�ꎞ�I�Ƃ͂����O���[�o���Ȓl��ς��邱�Ƃɂ�镛��p�����肻���E�E)
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

# �P��ɑΉ�������������擾
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
			# �Ȃ񂩁A������memory-leak�̂悤�ȋ���.�g�����Ԉ���Ă�̂��낤��?

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

# 'VC'�̌J��Ԃ������擾
def get_VC_count(word):#{{{
	return len(re.findall("[aiueo][bcdfghjklmnpqrstvwxz]y?", word))
#}}}

internal_patlist = [
	# studies -> study
	['ies$', 'y'],
	# released -> release
	['ed$', 'e'],
	# ��r
	['er$', ''],
	# �ŏ㋉
	['est', ''],
]

# �w�肵���p�P��̃X�e�~���O���s���B
# Porter Stemming Algorithm : http://tartarus.org/~martin/PorterStemmer/
def stemWord(word):#{{{
	import re
	
	word = word.lower()
	
	result = [ word ]
	
	# Porter�A���S���Y���ŏE���Ȃ��P��p�̕ϊ�(���[�U���Œ�`)
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

	# �P��͕ꉹ���܂ނ�?
	def hasVowel(word): return re.search('[aiueo]', word) != None
	# �����͎q����?
	def isConstant(chr): return re.match('[bcdfghjklmnpqrstvwxz]', chr) != None
	# m > n��]������֐���Ԃ�
	def mGT(n):
		def greaterThan(_): return get_VC_count(_) > n
		return greaterThan
	# m == n��]������֐���Ԃ�
	def mEQ(n):
		def equal(_): return get_VC_count(_)  == n
		return equal
	# �P�ꂪCVC�ŏI�[����Ă��邩�𔻒�
	def cvcEnds(_):
		if len(_) < 3 or isConstant(_[-3]) == False or \
		   hasVowel(_[-2]) == False or isConstant(_[-1]) == False:
			return False
		return _[-1] not in 'wxy'
	# SS$ -> S$
	def DtoSLtr(_):
		return _[:-1], 1
	# �P��̖����񕶎���SS�̂悤�ɘA�����邩?
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

" �w�肳�ꂽ�P��̐��������f�[�^�x�[�X����擾
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
	# �s���̉��s������
	word = word.rstrip("\r\n")
	# �O��̋󔒂��폜
	word = word.strip(" \t")
	
	keyword, desc = getDesctiption(conn, word)
	# �Ή������������������Ȃ������ꍇ�́A�P���ό`���čĎ��s
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
  " set cb=unnamed�Ȋ����ƁAyank,paste��"*���W�X�^���g����̂ł���������ł���悤��
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

" �I�����ꂽ�e�L�X�g�𒲂ׂ�
function! s:Selected()"{{{
	let word = s:selected_text()
	if len(word) == 0
		return
	endif

	let [ keyword, description ] = s:getDesctiption(word)
	if len(description) == 0
		echoerr "�P��͌�����܂���ł���: " . word
		return
	endif

	call s:Open(0)

	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)

"	normal! gv
endfunction"}}}

" �p�����[�^�Ŏw�肳�ꂽ�L�[���[�h�𒲂ׂ�
" �w�肳��Ȃ������ꍇ�̓v�����v�g����
function! s:SearchKeyword(...)"{{{
	let word = ''
	if a:0 == 0
		let word = input("�P������:")
		if len(word) == ''
			return 
		endif
	else
		let word = join(a:000, ' ')
	endif

	let [ keyword, description ] = s:getDesctiption(word)
	if len(description) == 0
		echoerr "�P��͌�����܂���ł���: " . word
		return
	endif

	call s:Open(0)

	" �����Ō��݂̃J�[�\���ʒu�̒P���b:last_word�ϐ��ɓo�^���Ă���
	" (�������Ȃ��ƁACursorMoved�C�x���g���������ăE�C���h�E�̓��e���㏑������Ă��܂�)
	call s:set_current_word(expand('<cword>'))
	call s:update_window(keyword, description)
endfunction"}}}

" Commands

" �E�C���h�E��\��
command! CODOpen call <SID>Open(1)
" �E�C���h�E��j��
command! CODClose call <SID>Close()
" �E�C���h�E�̃g�O���\��
command! CODToggle call <SID>Toggle()

" pdict�t�@�C���̃C���|�[�g
command! -bang -nargs=+ CODRegistDict call <SID>RegistDict(len("<bang>")!=0, <f-args>)

" �I�������P��E���̐�������\��
command! CODSelected call <SID>Selected()

" �L�[���[�h���R�}���h���C���p�����[�^�Ŏw��(�w��Ȃ��̏ꍇ�͑Θb���[�h)
command! -nargs=* CODSearch call <SID>SearchKeyword(<f-args>)

" vim:foldmethod=marker

