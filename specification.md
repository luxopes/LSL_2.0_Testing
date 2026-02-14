(* Kompletní formální gramatika jazyka LSL v EBNF *)
(* Založeno na analýze lexeru, parseru a AST z poskytnutého kódu *)
(* Jazyk je case-sensitive, bloky jsou ukončovány klíčovým slovem "end" (do-while může mít volitelný end) *)
(* Indentace není povinná – lexer neprodukuje Indent tokeny *)
(* Newline a whitespace (mezery, tabulátory) jsou volitelné a ignorované parserem *)
(* Komentáře (# ... a /* ... */) jsou ignorovány lexerem a nejsou součástí gramatiky *)

program      ::= { statement | newline }

statement    ::= simple_stmt newline
               | compound_stmt

simple_stmt  ::= use_stmt
               | assign_stmt
               | print_stmt
               | call_stmt
               | file_op_stmt
               | return_stmt
               | break_stmt
               | continue_stmt
               | wait_stmt
               | expr_stmt   (* libovolný výraz jako příkaz *)

compound_stmt ::= if_stmt
               | while_stmt
               | do_while_stmt
               | for_stmt
               | for_in_stmt
               | loop_stmt
               | repeat_stmt
               | switch_stmt
               | safe_stmt
               | function_def
               | class_def
               | try_stmt

(* ==================================== *)
(* Řídicí struktury *)
(* ==================================== *)

use_stmt     ::= "use" string_literal [ "as" identifier ]

if_stmt      ::= "if" expr ":" newline { statement }
                 { "elif" expr ":" newline { statement } }
                 [ "else" ":" newline { statement } ]
                 "end"

while_stmt   ::= "while" expr ":" newline { statement } "end"

do_while_stmt::= "do" ":" newline { statement } "while" expr

for_stmt     ::= "for" identifier "in" expr ".." expr [ "," expr ] ":" newline { statement } "end"

for_in_stmt  ::= "for" identifier "in" expr ":" newline { statement } "end"
               | "for" identifier "," identifier "in" expr ":" newline { statement } "end"

loop_stmt    ::= "loop" [ expr ] ":" newline { statement } "end"

repeat_stmt  ::= "repeat" ":" newline { statement } "until" expr newline "end"

switch_stmt  ::= "switch" expr ":" newline { case_block } [ default_block ] "end"
case_block   ::= "case" expr ":" newline { statement }
default_block::= "default" ":" newline { statement }

safe_stmt    ::= "safe" ":" newline { statement } [ "else" ":" newline { statement } ] "end"

function_def ::= "function" identifier "(" [ param_list ] ")" ":" newline { statement } "end"
param_list   ::= identifier { "," identifier }

class_def    ::= "class" identifier ":" newline { method_def } "end"
method_def   ::= "function" identifier "(" [ param_list ] ")" ":" newline { statement } "end"

try_stmt     ::= "try" ":" newline { statement }
                 "catch" ":" newline { statement }
                 "end"

return_stmt  ::= "return" [ expr ]

break_stmt   ::= "break"

continue_stmt::= "continue"

print_stmt   ::= "print" expr
wait_stmt    ::= "wait" expr

call_stmt    ::= "call" identifier "(" [ arg_list ] ")"

file_op_stmt ::= file_op_keyword string_literal [ "," expr ]
file_op_keyword ::= "readfile" | "writefile" | "appendfile"
                  | "createdir" | "listdir" | "deletedir"

assign_stmt  ::= assign_target assign_op expr
assign_target ::= identifier
               | postfix_expr "[" expr "]"
               | postfix_expr "." identifier
assign_op    ::= "=" | "+=" | "-=" | "*=" | "/=" | "%="

expr_stmt    ::= expr

(* ==================================== *)
(* Výrazy – přesná precedence podle parseru *)
(* ==================================== *)

expr         ::= or_expr

or_expr      ::= and_expr { "or" and_expr }

and_expr     ::= not_expr { "and" not_expr }

not_expr     ::= equality_expr | "not" equality_expr   (* "not" je zde jako prefixový operátor *)

equality_expr::= comparison_expr { ("==" | "!=") comparison_expr }

comparison_expr ::= range_expr { ("<" | ">" | "<=" | ">=") range_expr }
range_expr   ::= additive_expr [ ".." additive_expr ]

additive_expr::= multiplicative_expr { ("+" | "-") multiplicative_expr }

multiplicative_expr ::= unary_expr { ("*" | "/" | "%") unary_expr }

unary_expr   ::= [ "-" | "not" ] postfix_expr

postfix_expr ::= primary_expr { postfix_op }

postfix_op   ::= "(" [ arg_list ] ")"                  (* volání funkce nebo metody *)
               | "[" expr "]"                         (* indexování listu/dictu *)
               | "." identifier [ "(" [ arg_list ] ")" ] (* přístup k členu nebo volání metody *)

primary_expr ::= literal
               | identifier
               | "self"
               | "new" identifier "(" [ arg_list ] ")"   (* vytvoření instance třídy *)
               | list_literal
               | dict_literal
               | "(" expr ")"

(* File operation keywords mohou být použity i jako volání funkce *)
(* Pokud následuje "(", parser je bere jako identifier pro CallExpr *)

literal      ::= number
               | string_literal
               | "true"
               | "false"
               | "null"

list_literal ::= "[" [ expr { "," expr } ] "]"

dict_literal ::= "{" [ dict_pair { "," dict_pair } ] "}"
dict_pair    ::= identifier ":" expr   (* klíče jsou pouze identifikátory, ne libovolné expr *)

arg_list     ::= expr { "," expr }

(* ==================================== *)
(* Terminály *)
(* ==================================== *)

identifier   ::= letter { letter | digit | "_" }
letter       ::= "a".."z" | "A".."Z"
digit        ::= "0".."9"

number       ::= [ "-" ] digit { digit } [ "." { digit } ]

string_literal ::= '"' { character | escape_sequence } '"'
                 | "'" { character | escape_sequence } "'"
character    ::= <jakýkoli znak kromě " nebo ' nebo \>
escape_sequence ::= "\" ( "n" | "t" | "r" | "\"" | "'" | "\" )

newline      ::= "\n"
