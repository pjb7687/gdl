/* *************************************************************************
                                gdlc.tree.g 
the GDL tree parser
used after the lexer/parser (gdlc.g)
calls the compiler (dcompiler.cpp)
put out trees suitable to be interpreted (gdlc.i.g)
                             -------------------
    begin                : July 22 2002
    copyright            : (C) 2002 by Marc Schellens
    email                : m_schellens@hotmail.com
 ***************************************************************************/

/* *************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

// possible source of errors:
// #id and id (as label) are not the same because tree generation is ON
// #id refers to the generated (output) tree id to the input tree

header {
#include "objects.hpp"
#include "dcompiler.hpp"
#include "dnodefactory.hpp"
}

options {
	language="Cpp";
	genHashLines = false;
	namespaceStd="std";         // cosmetic option to get rid of long defines
	namespaceAntlr="antlr";     // cosmetic option to get rid of long defines
}	

// the GDL TreeParser  ****************************************
class GDLTreeParser extends TreeParser;

options {
	importVocab = GDL;	// use vocab generated by lexer
	buildAST = true;
  	ASTLabelType = "RefDNode";
//    defaultErrorHandler = true;
    defaultErrorHandler = false;
}
{
  private:
    DCompiler       comp; // each tree parser has its own compiler

  public:
  // constructor with processed file
  GDLTreeParser(const std::string& f, const std::string& sub)
    : antlr::TreeParser(), comp(f, NULL, sub)
    {
        //       setTokenNames(_tokenNames);
        //       setASTNodeFactory( DNode::factory );
        initializeASTFactory( DNodeFactory);
        setASTFactory( &DNodeFactory );
    }
  // constructor for command line/execute
  GDLTreeParser( EnvT* env)
    : antlr::TreeParser(), comp( "", env, "")
    {
        initializeASTFactory( DNodeFactory);
        setASTFactory( &DNodeFactory );
    }

  bool ActiveProCompiled() const { return comp.ActiveProCompiled();} 
}

// file parsing
translation_unit
	: (   procedure_def
		| function_def
		| forward_function)*
        exception 
        catch [ GDLException& e] 
        { 
            throw;
        }
        catch [ antlr::NoViableAltException& e] 
        {
            // SYNTAX ERROR
            throw GDLException( e.getLine(), e.getColumn(), "Compiler syntax error: "+e.getMessage());
        }
        catch [ antlr::RecognitionException& e] 
        {
            // SYNTAX ERROR
            throw GDLException( e.getLine(), e.getColumn(), "General syntax error: "+e.getMessage());
        }
	;

// intercative usage
interactive
  : (statement)+
        exception 
        catch [ GDLException& e] 
        { 
            throw;
        }
        catch [ antlr::NoViableAltException& e] 
        {
            // SYNTAX ERROR
            throw GDLException( e.getLine(), e.getColumn(), "Compiler syntax error: "+e.getMessage());
        }
        catch [ antlr::RecognitionException& e] 
        {
            // SYNTAX ERROR
            throw GDLException( e.getLine(), e.getColumn(), "General syntax error: "+e.getMessage());
        }
  ;

forward_function!
	: #(FORWARD 
	  (id:IDENTIFIER
		{
		  comp.ForwardFunction(id->getText());
		}	
	  )+
	)
	;

parameter_declaration!
  : #(PARADECL 
	  (id:IDENTIFIER 
		{
		  comp.AddPar(id->getText());
		}
	  | keyword_declaration
	  )+
	)
  ;

keyword_declaration!
	: #(KEYDECL key:IDENTIFIER val:IDENTIFIER)
	{
	  comp.AddKey(key->getText(),val->getText());
	}
	;

procedure_def!
    : #(PRO 
            name:IDENTIFIER
            (METHOD obj:IDENTIFIER
                {
                    comp.StartPro(name->getText(),obj->getText());
                }
            |
                {
                    comp.StartPro(name->getText());
                }
            ) 
            (parameter_declaration)?
            (statement_list
                {
                    comp.SetTree( returnAST);
                }
            )?
            {
                comp.EndPro();
            }
        )
    ;

function_def!
    : #(FUNCTION 
            name:IDENTIFIER
            (METHOD obj:IDENTIFIER
                {
                    comp.StartFun(name->getText(),obj->getText());
                }
            |
                {
                    comp.StartFun(name->getText());
                }
            ) 
            (parameter_declaration)? 
            (statement_list
                {
                    comp.SetTree( returnAST);
                }
            )?
            {
                comp.EndFun();
            }
        )
    ;

common_block!//
  : #(COMMONDEF id:IDENTIFIER
	  {
		DCommonBase* actCommon=comp.CommonDef(id->getText());
	  }
	  (	cv:IDENTIFIER
		{
		  comp.CommonVar(actCommon,cv->getText());
		}
	  )+		
	)
  | #(COMMONDECL id2:IDENTIFIER
	  {
		comp.CommonDecl(id2->getText());
	  }
	)
  ;		

// removes last pair of braces (multiple braces already removed in brace_expr)
unbrace_expr! 
	: ex:expr
		{
            // remove last pair of braces
            if( #ex->getType()==EXPR) 
                // note: ex_AST is crucial here (ANTLR uses ex instead here)
                #unbrace_expr= #( NULL, ex_AST->getFirstChild()); 
            else
                #unbrace_expr= #( NULL, ex); 
		}
    ;

// more than one ELSE is allowed: first is executed, *all*
// (including expr) later branches are ignored
labeled_expr
    : ex:expr
        {
         if( #ex->getType() != EXPR)   
            #labeled_expr = #([EXPR, "expr"],#labeled_expr);
        }
    ;


caseswitch_body 
	: #(BLOCK labeled_expr 
            (statement_list)? 
        )
	| #(ELSEBLK 
            (statement_list)?
        )
	;	

switch_statement
{
    int labelStart = comp.NDefLabel();
}
	: #(s:SWITCH expr (caseswitch_body)*)
        {
            #s->SetLabelRange( labelStart, comp.NDefLabel());
        }
	;

case_statement
{
    int labelStart = comp.NDefLabel();
}
	: #(c:CASE expr (caseswitch_body)*)
        {
            #c->SetLabelRange( labelStart, comp.NDefLabel());
        }
	;

block
	: #(BLOCK (statement_list)?)
	;

statement_list // note: proper syntax is provided already by the parser
    : ( statement | label )+
    ;

statement
    : assign_expr
    | comp_assign_expr   
	| procedure_call
	| for_statement 
	| repeat_statement
	| while_statement
	| jump_statement
	| if_statement
	| case_statement
	| switch_statement
    | forward_function
	| common_block
	| block
    | #(DEC unbrace_expr)
    | #(INC unbrace_expr)
	| BREAK    // only in loops or switch_statement
	| CONTINUE // only in loops
	;

repeat_statement
{
    int labelStart = comp.NDefLabel();
}
	: #(r:REPEAT block expr)
        {
            #r->SetLabelRange( labelStart, comp.NDefLabel());
        }
	;

while_statement!
{
    int labelStart = comp.NDefLabel();
}
	: #(w:WHILE e:expr s:statement)
        {
            #w->SetLabelRange( labelStart, comp.NDefLabel());

            // swap e <-> s for easier access in interpreter
            #while_statement=#( w, s, e);
        }
	;

for_statement //!
{
    int labelStart = comp.NDefLabel();
}
	: #(f:FOR i:IDENTIFIER 
        	{ 
                #i->setType(VAR);
                comp.Var(#i);	
            }
            expr expr 
            (expr
                { 
                #f->setType(FOR_STEP);
                #f->setText("for_step");
                }
            )? 
            block)
        {
        #f->SetLabelRange( labelStart, comp.NDefLabel());
        }
	;

label!
  : #(i:IDENTIFIER COLON)
	{ 
	  #label=#[LABEL,i->getText()];
	  comp.Label(#label); 
	}	
  ;

jump_statement!//
  : #(GOTO i1:IDENTIFIER)
	{ 
	  #jump_statement=astFactory->create(GOTO,i1->getText());
//	  #jump_statement=#[GOTO,i1->getText()]; // doesn't work
	  comp.Goto(#jump_statement); 
	}	
  | #(RETURN {bool exprThere=false;} (e:expr {exprThere=true;})?)
	{
	  if( comp.IsFun())
	  	{
		if( !exprThere)	throw GDLException(	_t, 
                    "Return statement in functions "
                    "must have 1 value.");
		#jump_statement=#([RETF,"retf"],e);
		}
	  else
	  	{
		if( exprThere) throw GDLException(	_t, 
                    "Return statement in "
                    "procedures cannot have values.");
		#jump_statement=#[RETP,"retp"]; // astFactory.create(RETP,"retp");
	  	}
	}
  | #(ON_IOERROR i2:IDENTIFIER)
	{
      if( i2->getText() == "NULL")
            {
                #jump_statement=astFactory->create(ON_IOERROR_NULL,
                                                   "on_ioerror_null");
            }
      else
            {
                #jump_statement=astFactory->create(ON_IOERROR,i2->getText());
//	            #jump_statement=#[ON_IOERROR,i2->getText()];
                comp.Goto(#jump_statement); // same handling		 
            }
	}
  ;

if_statement!//
{
    int labelStart = comp.NDefLabel();
}
	: #(i:IF e:expr s1:statement 
            (
                {
                #if_statement=#(i,e,s1);
                }
            | s2:statement
                {
                #i->setText( "if_else");
                #i->setType( IF_ELSE);
                #if_statement=#(i,e,s1,s2);
                }
            )
        )
        {
        #i->SetLabelRange( labelStart, comp.NDefLabel());
        }
	;

procedure_call
	: #(MPCALL expr IDENTIFIER (parameter_def)*
        )
	| #(MPCALL_PARENT expr IDENTIFIER
            IDENTIFIER (parameter_def)*
        )
	| #(p:PCALL id:IDENTIFIER (parameter_def)*
            {
                // first search library procedures
                int i=LibProIx(#id->getText());
                if( i != -1)
                {
                    #p->setType(PCALL_LIB);
                    #p->setText("pcall_lib");
                    #id->SetProIx(i);
                }
                else
                {
                    // then search user defined procedures
                    i=ProIx(#id->getText());
                    #id->SetProIx(i);
                }
            }
        )
	;	    

parameter_def
    : key_parameter
    | pos_parameter
    ;

key_parameter!//
{
    RefDNode variable;
}
	: #(d:KEYDEF i:IDENTIFIER k:unbrace_expr
            {
                variable=comp.ByReference(#k);
                if( variable != static_cast<RefDNode>(antlr::nullAST))
                {
                    if( variable == #k)
                    {
                        #d=#[KEYDEF_REF,"keydef_ref"];
                        #key_parameter=#(d,i,variable);
                    }
                    else
                    {
                        #d=#[KEYDEF_REF_EXPR,"keydef_ref_expr"];
                        #key_parameter=#(d,i,k,variable);
                    }
                }
                else 
                {
                    int t = #k->getType();
                    if( t == FCALL_LIB || t == MFCALL_LIB || 
                        t == MFCALL_PARENT_LIB)
                    {
                        #d=#[KEYDEF_REF_CHECK,"keydef_ref_check"];
                        #key_parameter=#(d,i,k);
                    }
                    else
                    {
                        #key_parameter=#(d,i,k);
                    }
                }
            }
        )
    ;

pos_parameter!//
{
    RefDNode variable;
}
	: e:unbrace_expr
        {
            variable=comp.ByReference(#e);
            if( variable != static_cast<RefDNode>(antlr::nullAST))
            {
                if( variable == #e)
                    {
                        #pos_parameter=#([REF,"ref"],variable);
                    }
                    else
                    {
                        #pos_parameter=#([REF_EXPR,"ref_expr"],e,variable);
                    }
            }
            else 
            {
                int t = #e->getType();
                if( t == FCALL_LIB || t == MFCALL_LIB || 
                    t == MFCALL_PARENT_LIB)
                {
                    // something like: CALLAPRO,reform(a,/OVERWRITE)
                    #pos_parameter=#([REF_CHECK,"ref_check"],e);
                }
                else
                {
                    #pos_parameter= #( NULL, e);
                }
            }
        }
	;

// counts the [[[ ]]]
// 0 -> [ ]   (add dim if scalar)
// 1 -> [[ ]] ...
array_def returns [int depth]
{
    RefDNode sPos;
}
	: #(a:ARRAYDEF {sPos=_t;} (expr)*)
        {
            depth=0;
            for( RefDNode e=sPos; 
                e != static_cast<RefDNode>(antlr::nullAST);
                e=e->getNextSibling())
            {
                if( e->getType() != ARRAYDEF)
                {
                    depth=0;
                    break;
                }
                else
                {
                    int act=array_def(e); // recursive call
                    act=act+1;
                    if( depth == 0)
                    {
                        depth=act;
                    }
                    else
                    {
                        if( depth > act) depth=act;
                    }
                }   
            }
            #a->SetArrayDepth(depth);
        }
	;

struct_def
{
    bool noTagName = false;
}
	: #(n:NSTRUC_REF // parser delivers always nstruct_ref 
            IDENTIFIER 
            ((expr {noTagName = true;} | IDENTIFIER expr | INHERITS IDENTIFIER)+
                {   
                    // set to nstruct if defined here
                    #n->setType(NSTRUC); 
                    #n->setText("nstruct");
                    #n->DefinedStruct( noTagName);
                }
            )?
        )
	| #(STRUC (tag_def)+)
	;

tag_def
	: IDENTIFIER expr
	;	

arrayindex_list
	: (arrayindex)+
	;	

// type: 0->data, 1-> [*], 2-> [s], 3-> [s:*], 4-> [s:e]
arrayindex
	: #(ax:ARRAYIX 
			( ALL 
                { 
                    #ax->setType(ARRAYIX_ALL); // 1
                    #ax->setText("*");
                }
			| ( expr // 0 or 2
                    ( !ALL
                        { 
                            #ax->setType(ARRAYIX_ORANGE); // 3
                            #ax->setText("s:*");
                        }
                    | expr
                        { 
                            #ax->setType(ARRAYIX_RANGE); // 4
                            #ax->setText("s:e");
                        }
                    )?
                )
			)
		)
	;

// removes last pair of braces
// for non functions
lassign_expr!//
	: ex:expr
		{
            // remove last pair of braces
			if( #ex->getType()==EXPR)
            {
                int cT = #ex->getFirstChild()->getType();
                if( cT != FCALL && 
                    cT != MFCALL && 
                    cT != MFCALL_PARENT &&
                    cT != FCALL_LIB && 
                    cT != MFCALL_LIB && 
                    cT != MFCALL_PARENT_LIB)
                        #ex=#ex->getFirstChild();
            }

            if( #ex->getType()==ASSIGN)
            throw GDLException(	_t, "Assign expression is not allowed as "
                                    "l-expression in assignment");

            #lassign_expr=#( NULL, ex);
		}
    ;

assign_expr!
	: #(a:ASSIGN l:lassign_expr r:expr)
        { #assign_expr=#(a,r,l);}
    ;

// +=, *=, ...
comp_assign_expr!
    : #(a1:AND_OP_EQ l1:lassign_expr r1:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([AND_OP,"and"],l1,r1),l1);} 
    | #(a2:ASTERIX_EQ l2:lassign_expr r2:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([ASTERIX,"*"],l2,r2),l2);} 
    | #(a3:EQ_OP_EQ l3:lassign_expr r3:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([EQ_OP,"eq"],l3,r3),l3);} 
    | #(a4:GE_OP_EQ l4:lassign_expr r4:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([GE_OP,"ge"],l4,r4),l4);}
    | #(a5:GTMARK_EQ l5:lassign_expr r5:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([GTMARK,">"],l5,r5),l5);}
    | #(a6:GT_OP_EQ l6:lassign_expr r6:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([GT_OP,"gt"],l6,r6),l6);}
    | #(a7:LE_OP_EQ l7:lassign_expr r7:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([LE_OP,"le"],l7,r7),l7);}
    | #(a8:LTMARK_EQ l8:lassign_expr r8:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([LTMARK,"<"],l8,r8),l8);}
    | #(a9:LT_OP_EQ l9:lassign_expr r9:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([LT_OP,"lt"],l9,r9),l9);}
    | #(a10:MATRIX_OP1_EQ l10:lassign_expr r10:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([MATRIX_OP1,"#"],l10,r10),l10);}
    | #(a11:MATRIX_OP2_EQ l11:lassign_expr r11:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([MATRIX_OP2,"##"],l11,r11),l11);}
    | #(a12:MINUS_EQ l12:lassign_expr r12:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([MINUS,"-"],l12,r12),l12);}
    | #(a13:MOD_OP_EQ l13:lassign_expr r13:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([MOD_OP,"mod"],l13,r13),l13);}
    | #(a14:NE_OP_EQ l14:lassign_expr r14:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([NE_OP,"ne"],l14,r14),l14);}
    | #(a15:OR_OP_EQ l15:lassign_expr r15:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([OR_OP,"or"],l15,r15),l15);}
    | #(a16:PLUS_EQ l16:lassign_expr r16:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([PLUS,"+"],l16,r16),l16);}
    | #(a17:POW_EQ l17:lassign_expr r17:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([POW,"^"],l17,r17),l17);}
    | #(a18:SLASH_EQ l18:lassign_expr r18:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([SLASH,"/"],l18,r18),l18);}
    | #(a19:XOR_OP_EQ l19:lassign_expr r19:expr) 
        { #comp_assign_expr=#([ASSIGN,":="],([XOR_OP,"xor"],l19,r19),l19);} 
    ;

// the expressions *************************************/

// system variables have as variable ptr NULL initially
sysvar!//
  : #(SYSVAR i:SYSVARNAME)
	{ 
      std::string sysVarName = i->getText();
      // here we create the real sysvar node      
	  #sysvar=astFactory->create(SYSVAR, sysVarName.substr(1));
//	  #sysvar=#[SYSVAR,i->getText()];
	  comp.SysVar(#sysvar); // sets var to NULL
	}	
  ;

// variables are converted to:
// VAR    with index into functions/procedures variable list or
// VARPTR for common block variables with a ptr to the
//        variable in the common block
var!//
  : #(VAR i:IDENTIFIER)
	{ 
	  #var=astFactory->create(VAR,i->getText());
//	  #var=#[VAR,i->getText()];
	  comp.Var(#var);	
	}
  ;

brace_expr!//
	: #(e:EXPR ex:expr)
		{
            // remove multiple braces
			while( #ex->getType()==EXPR) #ex=#ex->getFirstChild();
	  		#brace_expr=#(e, ex);
		}
	;

// out parameter_def_list is an expression list here
arrayindex_list_to_expression_list! // ???
{
    RefDNode variable;
}
    : (#(ARRAYIX e:pos_parameter)
            {
                #arrayindex_list_to_expression_list=
                    #(NULL, arrayindex_list_to_expression_list, e);
            }
        )+
  ;

// for function calls the arrayindex list is properly converted
arrayexpr_fn!//
{
    std::string id_text;
    bool isVar;
}   
  	: #(ARRAYEXPR_FN 
            // always here: #(VAR IDENTIFIER)
            #(va:VAR id:IDENTIFIER)
            { 
                id_text=#id->getText(); 
                isVar = comp.IsVar( id_text);
            }

            (   { isVar}? al:arrayindex_list
            |   el:arrayindex_list_to_expression_list
            )
            { 
                if( !isVar)
                {   // no variable -> function call

                    // first search library functions
                    int i=LibFunIx(id_text);
                    if( i != -1)
                    {
                        #id->SetFunIx(i);
                        #arrayexpr_fn=
                        #([FCALL_LIB,"fcall_lib"], id, el);
                    }
                    else
                    {
                        // then search user defined functions
                        i=FunIx(id_text);
                        #id->SetFunIx(i);

                        #arrayexpr_fn=
                        #([FCALL,"fcall"], id, el);
                    }
                }
                else
                {   // variable -> arrayexpr
                    
                    // make var
                    #va=astFactory->create(VAR,#id->getText());
//                    #va=#[VAR,id->getText()];
                    comp.Var(#va);	

                    #arrayexpr_fn=
                    #([ARRAYEXPR,"arrayexpr"], al, va);
                }
            }
        )  
    ;

// only here a function call is ok also
primary_expr
{
int dummy;
}
    : assign_expr
    | comp_assign_expr   
	| #(MFCALL expr IDENTIFIER (parameter_def)*
        )
	| #(MFCALL_PARENT expr IDENTIFIER
            IDENTIFIER (parameter_def)*
        )
	| #(f:FCALL id:IDENTIFIER (parameter_def)*
            {
                // first search library functions
                int i=LibFunIx(id->getText());
                if( i != -1)
                {
                    #f->setType(FCALL_LIB);
                    #f->setText("fcall_lib");
                    #id->SetFunIx(i);
                }
                else
                {
                    // then search user defined functions
                    i=FunIx(#id->getText());
                    #id->SetFunIx(i);
                }
            }
        ) 	
  	| arrayexpr_fn // converts fo FCALL(_LIB) or ARRAYEXPR
	| CONSTANT
	| dummy=array_def
	| struct_def
	;

op_expr
    :	#(QUESTION expr expr expr)	// trinary operator
	|	#(AND_OP expr expr)			// binary/unary operators...
	|	#(OR_OP expr expr)
	|	#(XOR_OP expr expr)
	|	#(LOG_AND expr expr)			// binary/unary operators...
	|	#(LOG_OR expr expr)
	|	#(EQ_OP expr expr)
	|	#(NE_OP expr expr)
	|	#(LE_OP expr expr)
	|	#(LT_OP expr expr)
	|	#(GE_OP expr expr)
	|	#(GT_OP expr expr)
	|	#(NOT_OP expr)
	|	#(PLUS expr expr)
	|	#(MINUS expr expr)
	|	#(LTMARK expr expr)
	|	#(GTMARK expr expr)
//	|	#(UPLUS e:expr { #op_expr=#e;}) // elimintated
	|	#(UMINUS expr)
	|	#(LOG_NEG expr)
	|	#(ASTERIX expr expr)
	|	#(MATRIX_OP1 expr expr)
	|	#(MATRIX_OP2 expr expr)
	|	#(SLASH expr expr)
	|	#(MOD_OP expr expr)
	|	#(POW expr expr)
	|	#(DEC unbrace_expr)
	|	#(INC unbrace_expr)
	|	#(POSTDEC unbrace_expr)
	|	#(POSTINC unbrace_expr)
	|   primary_expr
	;

// array and struct accessing
indexable_expr // only used by array_expr
	: var
	| sysvar
    | brace_expr
    ;
array_expr // only used by expr
	: #(ARRAYEXPR arrayindex_list indexable_expr)
	| indexable_expr
	;

tag_expr
    : brace_expr
    | IDENTIFIER
    ;

tag_array_expr
	: #(ARRAYEXPR arrayindex_list tag_expr)
    | tag_expr
    ;

// the everywhere used expression
expr
	: array_expr
    | #(DOT array_expr (tag_array_expr)+)
	| #(DEREF expr)    // deref
	| op_expr
	;

