" variables {{{1
let s:cur_project_file = "" 

let s:file_filter = []
let s:file_ignore_pattern = []
let s:folder_filter = []
let s:folder_filter_mode = "include" 
" }}}

" functions {{{1

" exproject#foldtext {{{2
function exproject#foldtext()
    let line = getline(v:foldstart)
    let line = substitute(line,'\[F\]\(.\{-}\) {.*','\[+\]\1 ','')
    return line
endfunction

" exproject#open {{{2
function exproject#open(filename)
    " if the filename is empty, use default project file
    let filename = a:filename
    if filename == ""
        let filename = g:ex_project_file
    endif

    " if we open a different project, close the old one first.
    if filename !=# s:cur_project_file
        if s:cur_project_file != ""
            let winnr = bufwinnr(s:cur_project_file)
            if winnr != -1
                call ex#window#close(winnr)
            endif
        endif

        " reset project filename and title.
        let s:cur_project_file = a:filename
    endif

    " open and goto the window
    let winnr = bufwinnr(s:cur_project_file)
    if winnr == -1
        call exproject#open_window()
    else
        exe winnr . 'wincmd w'
    endif
endfunction

" exproject#open_window {{{2

function! s:init_buffer()
    " NOTE: this maybe a BUG of Vim.
    " When I open exproject window and read the file through vimentry scripts,
    " the events define in exproject/ftdetect/exproject.vim will not execute.
    " I guess this is because when you are in BufEnter event( the .vimentry
    " enters ), and open the other buffers, the Vim will not trigger other
    " buffers' event 
    " This is why I set the filetype manually here. 
    set filetype=exproject
endfunction

function exproject#open_window()
    call ex#window#open( 
                \ s:cur_project_file, 
                \ g:ex_project_winsize,
                \ g:ex_project_winpos,
                \ 0,
                \ 1,
                \ function('s:init_buffer')
                \ )
endfunction

" exproject#toggle_widnow {{{2
function exproject#toggle_widnow()
    let result = exproject#close_window()
    if result == 0
        call exproject#open_window()
    endif
endfunction

" exproject#close_window {{{2
function exproject#close_window()
    if s:cur_project_file != ""
        let winnr = bufwinnr(s:cur_project_file)
        if winnr != -1
            call ex#window#close(winnr)
            return 1
        endif
    endif
    return 0
endfunction

" exproject#confirm_select {{{2
" modifier: '' or 'shift'

function exproject#confirm_select(modifier) " <<<
    " check if the line is valid file line
    let curline = getline('.') 
    if match(curline, '\C\[.*\]') == -1
        call ex#warning('Please select a folder/file')
        return
    endif

    let editcmd = 'e'
    if a:modifier == 'shift'
        let editcmd = 'bel sp'
    endif

    " initial variable
    let cursor_line = line('.')
    let cursor_col = col('.')

    " if this is a fold, do fold operation or open the path by terminal
    if foldclosed('.') != -1 || match(curline, '\C\[F\]') != -1
        if a:modifier == 'shift'
            " TODO: call ex#terminal ( 'remain', 'nowait', 'cd '. s:exPJ_GetPath(s:exPJ_cursor_line) )
        else
            normal! za
        endif
        return
    endif

    let fullpath = exproject#getpath(cursor_line) . exproject#getname(cursor_line)

    silent call cursor(cursor_line,cursor_col)

    " simplify the file name
    let fullpath = fnamemodify( fullpath, ':p' )
    let fullpath = escape(fullpath,' ')

    " switch filetype
    let filetype = fnamemodify( fullpath, ':e' )
    if filetype == 'err'
        " TODO:
        " call ex#hint('load quick fix list: ' . fullpath)
        " call exUtility#GotoPluginBuffer()
        " silent exec 'QF '.fullpath
        " " NOTE: when open error by QF, we don't want to exec exUtility#OperateWindow below ( we want keep stay in the exQF plugin ), so return directly 
        return 
    elseif filetype == 'exe'
        " TODO:
        " call ex#hint('debug ' . fullpath)
        " call exUtility#GotoEditBuffer()
        " call exUtility#Debug( fullpath )
        return
    else " default
        " put the edit file
        call ex#hint(fnamemodify(fullpath, ':p:.'))

        " goto edit window
        call ex#window#goto_edit_window()

        " do not open again if the current buffer is the file to be opened
        if fnamemodify(expand('%'),':p') != fnamemodify(fullpath,':p')
            silent exec editcmd.' '.fullpath
        endif
    endif

    " TODO:
    " " go back if needed
    " call exUtility#OperateWindow ( s:exPJ_select_title, g:exPJ_close_when_selected, g:exPJ_backto_editbuf, 0 )
endfunction

" exproject#search_for_pattern {{{2
function exproject#search_for_pattern( linenr, pattern )
    for linenum in range(a:linenr , 1 , -1)
        if match( getline(linenum) , a:pattern ) != -1
            return linenum
        endif
    endfor
    return 0
endfunction

" exproject#getname {{{2
function exproject#getname( linenr )
    let line = getline(a:linenr)
    let line = substitute(line,'.\{-}\[.\{-}\]\(.\{-}\)','\1','')
    let idx_end_1 = stridx(line,' {')
    let idx_end_2 = stridx(line,' }')
    if idx_end_1 != -1
        let line = strpart(line,0,idx_end_1)
    elseif idx_end_2 != -1
        let line = strpart(line,0,idx_end_2)
    endif
    return line
endfunction

" exproject#getpath {{{2
" Desc: Get the full path of the line, by YJR
function exproject#getpath( linenr )
    let foldlevel = exproject#getfoldlevel(a:linenr)
    let fullpath = ""

    " recursively make full path
    if match(getline(a:linenr),'[^^]-\C\[F\]') != -1
        let fullpath = exproject#getname( a:linenr )
    endif

    let level_pattern = repeat('.',foldlevel-1)
    let searchpos = a:linenr
    while foldlevel > 1 " don't parse level:0
        let foldlevel -= 1
        let level_pattern = repeat('.',foldlevel*2)
        let fold_pattern = '^'.level_pattern.'-\C\[F\]'
        let searchpos = exproject#search_for_pattern(searchpos , fold_pattern)
        if searchpos
            let fullpath = exproject#getname(searchpos).'/'.fullpath
        else
            call ex#warning('Fold not found')
            break
        endif
    endwhile

    return fullpath
endfunction

" exproject#getfoldlevel {{{2
function exproject#getfoldlevel(linenr) " <<<
    let curline = getline(a:linenr)
    let curline = strpart(curline,0,strridx(curline,'|')+1)
    let str_len = strlen(curline)
    return str_len/2
endfunction

" exproject#build_tree {{{2

" function s:build_tree(dir, file_filter, dir_filter, filename_list )
"     " show progress
"     echon "processing: " . a:dir . "\r"

"     " get short_dir
"     " let short_dir = strpart( a:dir, strridx(a:dir,'\')+1 )
"     let short_dir = fnamemodify( a:dir, ":t" )

"     " if directory
"     if isdirectory(a:dir) == 1
"         " split the first level to file_list
"         let file_list = split(globpath(a:dir,'*'),'\n') " NOTE, globpath('.','.*') will show hidden folder
"         silent call sort( file_list, "exUtility#FileNameSort" )

"         " sort and filter the list as we want (file|dir )
"         let list_idx = 0
"         let list_last = len(file_list)-1
"         let list_count = 0
"         while list_count <= list_last
"             if isdirectory(file_list[list_idx]) == 0 " remove not fit file types
"                 let suffix = fnamemodify ( file_list[list_idx], ":e" ) 
"                 " move the file to the end of the list
"                 if ( match ( suffix, a:file_filter ) != -1 ) ||
"                  \ ( suffix == '' && match ( 'NULL', a:file_filter ) != -1 ) 
"                     let file = remove(file_list,list_idx)
"                     silent call add(file_list, file)
"                 else " if not found file type in file filter
"                     silent call remove(file_list,list_idx)
"                 endif
"                 let list_idx -= 1
"             elseif a:dir_filter != '' " remove not fit dirs
"                 if match( file_list[list_idx], a:dir_filter ) == -1 " if not found dir name in dir filter
"                     silent call remove(file_list,list_idx)
"                     let list_idx -= 1
"                 endif
"             " DISABLE: in our case, globpath never search hidden folder. { 
"             " elseif len (s:ex_level_list) == 0 " in first level directory, if we .vimfiles* folders, remove them
"             "     if match( file_list[list_idx], '\<.vimfiles.*' ) != -1
"             "         silent call remove(file_list,list_idx)
"             "         let list_idx -= 1
"             "     endif
"             " } DISABLE end 
"             endif

"             "
"             let list_idx += 1
"             let list_count += 1
"         endwhile

"         silent call add(s:ex_level_list, {'is_last':0,'short_dir':short_dir})
"         " recuseve browse list
"         let list_last = len(file_list)-1
"         let list_idx = list_last
"         let s:ex_level_list[len(s:ex_level_list)-1].is_last = 1
"         while list_idx >= 0
"             if list_idx != list_last
"                 let s:ex_level_list[len(s:ex_level_list)-1].is_last = 0
"             endif
"             if s:build_tree(file_list[list_idx],a:file_filter,'',a:filename_list) == 1 " if it is empty
"                 silent call remove(file_list,list_idx)
"                 let list_last = len(file_list)-1
"             endif
"             let list_idx -= 1
"         endwhile

"         silent call remove( s:ex_level_list, len(s:ex_level_list)-1 )

"         if len(file_list) == 0
"             return 1
"         endif
"     endif

"     " write space
"     let space = ''
"     let list_idx = 0
"     let list_last = len(s:ex_level_list)-1
"     for level in s:ex_level_list
"         if level.is_last != 0 && list_idx != list_last
"             let space = space . '  '
"         else
"             let space = space . ' |'
"         endif
"         let list_idx += 1
"     endfor
"     let space = space.'-'

"     " get end_fold
"     let end_fold = ''
"     let rev_list = reverse(copy(s:ex_level_list))
"     for level in rev_list
"         if level.is_last != 0
"             let end_fold = end_fold . ' }'
"         else
"             break
"         endif
"     endfor

"     " judge if it is a dir
"     if isdirectory(a:dir) == 0
"         " if file_end enter a new line for it
"         if end_fold != ''
"             let end_space = strpart(space,0,strridx(space,'-')-1)
"             let end_space = strpart(end_space,0,strridx(end_space,'|')+1)
"             silent put! = end_space " . end_fold
"         endif
"         " put it
"         " let file_type = strpart( short_dir, strridx(short_dir,'.')+1, 1 )
"         let file_type = strpart( fnamemodify( short_dir, ":e" ), 0, 1 )
"         silent put! = space.'['.file_type.']'.short_dir . end_fold

"         " add file with full path as tag contents
"         let filename_path = exUtility#Pathfmt(fnamemodify(a:dir,':.'),'unix')
"         silent call add ( a:filename_list, short_dir."\t".'../'.filename_path."\t1" )
"         " KEEPME: we don't use this method now { 
"         " silent call add ( a:filename_list[1], './'.filename_path )
"         " silent call add ( a:filename_list[2], '../'.filename_path )
"         " } KEEPME end 
"         return 0
"     else

"         "silent put = strpart(space, 0, strridx(space,'\|-')+1)
"         if len(file_list) == 0 " if it is a empty directory
"             if end_fold == ''
"                 " if dir_end enter a new line for it
"                 let end_space = strpart(space,0,strridx(space,'-'))
"             else
"                 " if dir_end enter a new line for it
"                 let end_space = strpart(space,0,strridx(space,'-')-1)
"                 let end_space = strpart(end_space,0,strridx(end_space,'|')+1)
"             endif
"             let end_fold = end_fold . ' }'
"             silent put! = end_space
"             silent put! = space.'[F]'.short_dir . ' {' . end_fold
"         else
"             silent put! = space.'[F]'.short_dir . ' {'
"         endif
"     endif

"     return 0
" endfunction

function exproject#build_tree()
    " TODO: call exUtility#SetLevelList(-1, 1)

    " get entry dir
    let entry_dir = getcwd()
    if exists('g:ex_cwd')
        let entry_dir = g:ex_cwd
    endif

    echo "Creating ex_project: " . entry_dir . "\r"
    silent exec '1,$d _'

    " TODO:
    " let filename_list = []
    " let project_file_filter = exUtility#GetProjectFilter ( "file_filter" )
    " let project_dir_filter = exUtility#GetProjectFilter ( "dir_filter" )
    " call s:build_tree( 
    "             \ entry_dir, 
    "             \ exUtility#GetFileFilterPattern(project_file_filter), 
    "             \ exUtility#GetDirFilterPattern(project_dir_filter), 
    "             \ filename_list )

    "
    silent keepjumps normal! gg
    echo "ex_project: " . entry_dir . " created!\r"
endfunction

" }}}1

" vim:ts=4:sw=4:sts=4 et fdm=marker:
