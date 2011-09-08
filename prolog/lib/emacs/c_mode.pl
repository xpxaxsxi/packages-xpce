/*  $Id$

    Part of XPCE --- The SWI-Prolog GUI toolkit

    Author:        Jan Wielemaker and Anjo Anjewierden
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi.psy.uva.nl/projects/xpce/
    Copyright (C): 1985-2009, University of Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(emacs_c_mode, []).
:- use_module(library(pce)).
:- require([ between/3
	   , default/3
	   , forall/2
	   , memberchk/2
	   ]).

:- emacs_begin_mode(c, language,
		    "Mode for editing C programs",
		    [ insert_c_begin	= key('{'),
		      insert_label	= key(':'),
		      prototype_mark	= key('\\C-cRET'),
		      add_prototype	= key('\\C-c\\C-p'),
		      insert_NAME_	= key('\\C-c\\C-n'),
		      run_gdb		= button(gdb),
		      break_at_line	= button(gdb),
		      break_at_function = button(gdb),
		      gdb_go		= button(gdb) + key('\\C-c\\C-g'),
		      gdb_step		= button(gdb) + key('\\C-c\\C-s'),
		      gdb_next		= button(gdb) + key('\\C-c\\C-n'),
		      gdb_print		= button(gdb) + key('\\C-c\\C-p'),
		      prolog_manual     = button(prolog)
		    ],
		    [ '"'  = string_quote(\),
		      '''' = string_quote(\),
		      (/)  + comment_start(*),
		      (*)  + comment_end(/),

		      paragraph_end(regex('[[:blank:]]*\n|/\\*|[^\n]*\\*/'))
		    ]).

variable(indent_level, int, both, "Indentation level in spaces").
class_variable(indent_level, int, 2).

:- initialization
	send(@class, attribute, outline_regex_list,
	     chain(regex('^(\\w+\\([^)]*\\).*\n)(\\{([^}].*\n)+\\}(\\s*\n)*)'),
		   regex('^(\\w+.*\n)(\\{([^}].*\n)+\\};(\\s*\n)*)'),
		   regex('^(#\\s*define.*\\\\)\n((.*\\\\\n)+.*\n)'))).

:- pce_global(@c_undent_regex, new(regex('\\{|else|\\w+:'))).

indent_line(E, Times:[int]) :->
	"Indent according to C-mode"::
	default(Times, 1, Tms),
	(   between(1, Tms, N),
	    send(E, beginning_of_text_on_line),
	    (	(   send(E, indent_close_brace_line)
		;   send(E, indent_close_bracket_line)
		;   send(E, indent_expression_line, ')]')
		;   send(E, indent_label)
		;   send(E, indent_statement)
		;   send(E, align_with_previous_line, '\\s*(\\{\\s*)*')
		)
	    ->	true
	    ),
	    (	N == Tms
	    ->	true
	    ;	send(E, next_line)
	    ),
	    fail
	;   true
	).

backward_skip_statement(TB, Here, Start) :-
	get(TB, skip_comment, Here, 0, H1),
	get(TB, character, H1, C1),
	(   memberchk(C1, ")")			% e.g., for (...) { ... }
	->  get(TB, matching_bracket, H1, OpenPos),
	    (	get(TB, scan, OpenPos, word, 0, start, Start),
		get(TB, scan, Start, word, 0, end, EF),
		get(TB, skip_layout, EF, forward, @off, OpenPos)
	    ->	true
	    ;	Start = OpenPos
	    )
        ;   prev_word(TB, H1+1, else, StartElse)
	->  backward_skip_statement(TB, StartElse, Start)
	;   (	H1 == 0
	    ;	memberchk(C1, "{;}")
	    ),
	    get(TB, skip_comment, H1+1, H2)
	->  Start = H2
	;   get(TB, scan, H1, term, 0, start, Start)
	).

prev_word(TB, Here, Word, BeforeWord) :-
	get(TB, scan, Here, word, 0, start, SW),
	get(TB, contents, SW, Here-SW, string(Word)),
	get(TB, skip_comment, SW, 0, BeforeWord).

backward_statement(E, Here:[int], There:int) :<-
	"Find start of C-statement"::
	default(Here, E?caret, Caret),
	get(E, text_buffer, TB),
	get(TB, skip_comment, Caret, 0, H1),
	backward_skip_semicolon(TB, H1, H2),
	get(TB, character, H2, Chr),
	(   memberchk(Chr, "}")
	->  get(E, matching_bracket, H1, H3),
	    H4 is H3 - 1
	;   H4 = H2
	),
	backward_skip_statement(TB, H4, There).

backward_skip_semicolon(TB, Here, Pos) :-
	(   get(TB, character, Here, 0';)
	->  get(TB, skip_comment, Here-1, 0, Pos)
	;   Pos = Here
	).

backward_statement(E) :->
	"Go back one statement"::
	get(E, backward_statement, Start),
	send(E, caret, Start).

indent_close_brace_line(E) :->
	"Indent a line holding a bracket"::
	get(E, text_buffer, TB),
	get(E, caret, Caret),
	get(TB, character, Caret, 0'}),
	get(TB, matching_bracket, Caret, OpenPos),
	(   get(E, back_skip_if_etc, OpenPos-1, IfPos)
	->  get(E, column, IfPos, Col)
	;   get(E, column, OpenPos, Col)
	),
	send(E, align_line, Col).

indent_label(E) :->
	"Indent case and label:"::
	send(E, looking_at, 'case\\s|\\w+:'), !,
	send(E, indent_statement),
	get(E, column, Col0),
	get(E, indent_level, Inc),
	Col is Col0-Inc,
	send(E, align, Col).

indent_statement(E) :->
	"Indent statement in { ... } context"::
	get(E, text_buffer, TB),
	get(E, caret, Caret),
	get(E, matching_bracket, Caret, '}', _), % in C-body
	get(TB, skip_comment, Caret-1, 0, P0),
	get(TB, character, P0, Chr),
	(   memberchk(Chr, ";}")	% new statement
	->  get(E, backward_statement, P0+1, P1),
	    back_prefixes(E, P1, P2),
	    get(E, column, P2, Col),
	    send(E, align_line, Col)
	;   memberchk(Chr, "{")		% first in compound block
	->  (	get(E, back_skip_if_etc, P0-1, IfPos)
	    ->	get(E, column, IfPos, Col)
	    ;	get(E, column, P0, Col)
	    ),
	    get(E, indent_level, Inc),
	    send(E, align, Col + Inc)
	;   \+ memberchk(Chr, ";,"),	% for, while, if, ...
	    (   get(TB, matching_bracket, P0, P1)
	    ->  true
	    ;   P1 = P0
	    ),
	    get(TB, scan, P1, word, 0, start, P2),
	    back_prefixes(E, P2, P3),
	    get(E, column, P3, Column),
	    (   send(@c_undent_regex, match, TB, Caret)
	    ->  send(E, align, Column)
	    ;   get(E, indent_level, Inc),
	        send(E, align, Column + Inc)
	    )
	).


back_prefixes(E, P0, P) :-
	get(E, text_buffer, TB),
	get(TB, scan, P0, line, 0, start, SOL),
	(   get(regex('[({[]|:'), search, TB, P0, SOL, P1)
	->  P2 is P1 + 1
	;   P2 = SOL
	),
	get(TB, skip_comment, P2, P0, P).

back_skip_if_etc(E, Pos:int, StartIf:int) :<-
	"Find the start of an if/while/for at the same line"::
	get(E, scan, Pos, line, 0, start, SOL),
	get(E, skip_comment, Pos, SOL, Prev),
	Prev > SOL,
	(   get(E, character, Prev, 0'))
	->  get(E, matching_bracket, Prev, OpenPos),
	    get(E, scan, OpenPos, word, 0, start, StartIf)
	;   get(E, looking_at, '}\\s*else\\s*', Prev+1, SOL, Len)
	->  StartIf is Prev+1 - Len
	).

insert_c_begin(E, Times:[int], Id:[event_id]) :->
	"Insert and adjust the inserted '{'"::
	send(E, insert_self, Times, Id),
	get(E, caret, Caret),
	get(E, text_buffer, TB),
	get(TB, scan, Caret, line, 0, start, SOL),
	(   send(regex(string('\\\\s*%c', Id)), match, TB, SOL, Caret)
	->  new(F, fragment(TB, Caret, 0)),
	    send(E, indent_line),
	    send(E, caret, F?start),
	    free(F)
	;   true
	).

insert_label(E, Times:[int], Id:[event_id]) :->
	"Insert and adjust the inserted ':'"::
	send(E, insert_self, Times, Id),
	get(E, caret, Caret),
	get(E, text_buffer, TB),
	get(TB, scan, Caret, line, 0, start, SOL),
	(   send(regex('\\s*(case\\s|\\w+:)'), match, TB, SOL, Caret)
	->  new(F, fragment(TB, Caret, 0)),
	    send(E, indent_line),
	    send(E, caret, F?start),
	    free(F)
	;   true
	).


		 /*******************************
		 *	    PROTOTYPES		*
		 *******************************/

:- pce_global(@emacs_makeproto, make_makeproto).

make_makeproto(P) :-
	new(P, process(makeproto)),
	send(P, open).


prototype_mark(E) :->
	"Make a mark for local prototype definitions"::
	get(E, caret, Caret),
	get(E, text_buffer, TB),
	send(TB, attribute, attribute(prototype_mark_location,
				      fragment(TB, Caret, 0))),
	send(E, report, status, 'Prototype mark set').

add_prototype(E) :->
	"Add prototype for pointed function"::
	get(E, caret, Caret),
	get(E, text_buffer, TB),
	get(TB, scan, Caret, paragraph, 0, start, SOH),
	get(TB, find, SOH, '{', 1, end, EOH),
	get(TB, contents, SOH, EOH-SOH, Header),
	send(@emacs_makeproto, format, '%s\n}\n', Header),
	send(@pce, format, '%s\n', Header),
	get(TB, prototype_mark_location, Fragment),
	get(Fragment, end, End),
	forall(get(@emacs_makeproto, read_line, 100, Prototype),
	       send(Fragment, insert, @default, Prototype)),
	send(E, caret, End).


		 /*******************************
		 *	    GDB SUPPORT		*
		 *******************************/

run_gdb(M, Cmd:file) :->
	"Run GDB on program (same as ->gdb)"::
	send(M, gdb, Cmd).

tell_gdb_warn(M, Level:name, Fmt:char_array, Args:any ...) :->
	"Send a command to gdb"::
	get(@emacs?buffers, find_all,
	    and(message(@arg1, instance_of, emacs_gdb_buffer),
		@arg1?process?status == running),
	    ActiveGdbBuffers),
	(   get(ActiveGdbBuffers, size, 1)
	->  get(ActiveGdbBuffers, head, Buffer),
	    Msg =.. [format_data, Fmt|Args],
	    send(Buffer, Msg)
	;   Level == silent
	->  fail
	;   send(M, report, Level, 'No or multiple GDB buffers')
	).

break_at_line(M) :->
	"Set GDB break point at line of caret"::
	get(M, line_number, M?caret, CaretLine),
	get(M?text_buffer, file, File),
	get(File, base_name, Base),
	new(Cmd, string('break %s:%d\n', Base, CaretLine)),
	(   send(M, tell_gdb_warn, silent, Cmd)
	->  true
	;   send(@display, copy, Cmd),
	    send(M, report, inform, 'Copied: %s', Cmd)
	).

break_at_function(M, Function:[name]) :->
	"Set GDB breakpoint at function"::
	get(M, expand_tag, Function, TheFunction),
	send(M, tell_gdb, warning, 'break %s\n', TheFunction).

gdb_go(M) :->
	"Send `run' to GDB"::
	send(M, tell_gdb, warning, 'run\n').

gdb_step(M, Times:[int]) :->
	"Send `run' to GDB"::
	(   Times == @default
	->  send(M, tell_gdb, warning, 'step\n')
	;   send(M, tell_gdb, warning, 'step %d\n', Times)
	).

gdb_next(M, Times:[int]) :->
	"Send `run' to GDB"::
	(   Times == @default
	->  send(M, tell_gdb, warning, 'next\n')
	;   send(M, tell_gdb, warning, 'next %d\n', Times)
	).

gdb_print(M, Expression:expresion=string) :->
	"Print value of expression"::
	send(M, tell_gdb, warning, 'print %s\n', Expression).


		 /*******************************
		 *         XPCE THINGS		*
		 *******************************/

insert_NAME_(M) :->
	"Insert NAME_"::
	send(M, format, 'NAME_').

:- emacs_end_mode.

