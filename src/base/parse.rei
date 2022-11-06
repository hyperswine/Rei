#*
    PARSING LOGIC
*#

use core::expr::*
use std::expr::*

export ParserError: Token
export ParseRes: Expr | ParserError

Range: Range<Size>

Parser: {
    // associated state / components
    tokens: Vec[(Token, Range)]
    curr_index: Size
    input_string: String

    // priority slots for expressions
    low_prio: []
    med_prio: []
    high_prio: []

    // NOTE: the IDE should add : _ or : Vec<_>, String
    new: (tokens: _, input_string: _) -> Self => Self {tokens, curr_index: 0, input_string }

    // Parser API

    // peek next n tokens
    // NOTE: default args and contracts work like arg_name: ArgType <modifiers> <contracts> <default>
    // PEEK always returns a token. Thats why you should use accept() when possible, otherwise you might get EOF
    peek: (&mut self, n: (Size > 0) = 1) -> Token => self.tokens.peek(n).Token.unwrap_or(Token::EOF)

    accept: (&mut self, token: Token) -> LexData? => self.tokens[curr_index].Token == token? LexData(token) : Err()

    expect: (&mut self, token: token) -> LexData => self.accept(token).unwrap()
}

// maybe a better idea is to return Self?
// and implcitly add stuff to the expr param object?
// fn_decl()?.obj_decl()?...

// Base expressions
Parser: extend {
    // doing it this way gives you maximum control and freedom
    expr: (&mut self) -> ParseRes {
        // must be in the order defined in the grammar
        self.object_decl()!
        self.call()!
    }

    // should be least priority
    variadic_expr: (&mut self) -> ParseRes {
        let expr = self.expr()?
        self.expect(Token::Variadic)

        Ok(Variadic(expr))
    }

    // does binop do everything? yea cause it calls expr() again

    // low priority
    group_expr: (&mut self) -> ParseRes {
        self.accept(Token::LParen)?

        let expr = self.expr()

        self.expect(Token::RParen)

        Ok(Group(expr))
    }

    fn_decl: (&mut self) -> ParseRes {
        tuple_decl()!

        let fn_type = self.accept(Token::Annotation)
        let fn_type = if !fn_type => self.accept(Token::Macro)
        let fn_type = if !fn_type => self.accept(Token::LParen)?

        let params = self.params()

        let ret_type_expr = self.ret_type_expr()

        Ok(Fn(fn_type, params, ret_type_expr))
    }

    namespaced_type_expr: (&mut self) -> ParseRes {
        self.accept(Token::Identifier)?

        // while accept ::
        let ident_map = [while self.accept(Token::DoubleColon) => self.expect(Token::Identifier)]

        // NOTE: the constructor doesnt do anything fancy I think, maybe allow relative vs absolute addressing?
        Ok(NamespacedType(ident_map))
    }

    alias_obj: (&mut self) -> ParseRes => self.namespaced_type_expr()?

    primitive_expr: (&mut self) -> ParseRes => self.accept(Token::String)?: self.accept(Token::Numeric)?

    tuple_decl: (&mut self) -> ParseRes {
        self.accept(LParen)?
        let expr = self.expr().unwrap()
        self.expect(RParen)?

        Ok(Tuple(expr))
    }

    // note anon fns and objects should be declared with local (binop declares using the same obj types)
    object_decl: (&mut self) -> ParseRes {
        // get ident
        let ident = self.ident_expr()?

        // get generics
        let generics = self.generic_params()?

        self.expect(Token::Colon)

        // get object type
        let obj_type = self.obj_type_expr().unwrap()
        mut res = Object()

        // get scope or arrow expr
        // NOTE: the ?: auto unwraps the value
        // dont worry about the body type. Its just an expr in the node but we care about it here
        res.body = self.scope_expr() ?: self.arrow_expr().unwrap()

        // objects can also have a default value
        let defaults = self.default_arg()

        res.obj_type = obj_type
        res.generics = generics
        res.ident = ident
        res.defaults = defaults
        
        Ok(res)
    }

    obj_type_expr: () -> ParseRes {
        alias_decl()!
        fn_decl()!
        enum_decl()!
        data_decl()!
        mod_decl()!
        trait_decl()!
        impl_decl()!
    }

    scope_expr: (&mut self) -> ParseRes {
        self.accept(Token::LBracket)

        // maybe list comprehension?
        // Scope([while let Ok expr = self.expr() => body.push(expr)])
        body = [while let Ok expr = self.expr() => body.push(expr)]

        self.expect(Token::RBracket)

        Ok(Scope(body))
    }

    binary_expr: (&mut self) -> ParserRes {
        // try to match a self contained expr (including literal or ident)
        let lhs = self.expr()?

        // maybe have a hash table Token: Fn and do a loop?
        // NOTE: a return in for_each returns from the current outer scope
        // BINARY_OPERATORS.first(b => self.accept(b))?
        // let bin_operator = BINARY_OPERATORS.first(b => self.accept(b)).unwrap()
        let bin_op = BINARY_OPERATORS[self.next()].unwrap()

        let rhs = self.expr().unwrap()

        bin_op(lhs, bin_op, rhs)
    }

    unary_op_prefix: (&mut self) -> ParseRes {
        // first knows of Result<T, E>
        let unary_op = UNARY_OPS.first(u => self.accept(u))?
        Ok(Unary(Prefix, unary_op, self.expr()))
    }

    return_expr: (&mut self) -> ParseRes {
        self.accept(Token::Return)?
        Ok Return(self.expr().unwrap())
    }

    yield_expr: (&mut self) -> ParseRes {
        self.accept(Token::Yield)?
        Ok Yield(self.expr().unwrap())
    }

    break_expr: (&mut self) -> ParseRes => self.accept(Token::Break)?

    continue_expr: (&mut self) -> ParseRes => self.accept(Token::Continue)?

    where_expr: (&mut self) -> ParseRes {
        self.accept(Token::Where)?

        self.expect(LParen)

        let items = [while let res = self.where_item() => res]

        self.expect(RParen)

        Ok(Where(items))
    }

    where_item: (&mut self) -> ParseRes => self.condition_expr() ?: self.expr()?
}

BinaryOp: {
    binop_plus: () {}
    binop_minus: () {}
}

BinOpFn: (Expr, BinaryOperator, Expr) -> ()

// core::Index[T]
impl BinaryOp: core::Index(token: Token) -> BinOpFn? {
    // if token in BinaryOperator {
        // a static hashmap?
    // }

    // either this or a fn annotation above binop_* but might not be as easy to understand?
    static const MAP = {
        // therre may be specific binary operations based on the context?
        // hmm maybe do this during the descent?
        Plus = binop_plus
        Minus = binop_minus
    }
}