# attribute
const EMPTY_ATTR = Dict{String, String}()
AttrType = Union{Dict{String, String}, Nothing}

abstract type CompoExpr end
abstract type SExpr <: CompoExpr end
abstract type CmdExpr <: SExpr end
abstract type GrpExpr <: SExpr end

struct ID <: SExpr
    val::String
    attr::AttrType
end
ID(x::String) = ID(x, nothing)

struct NUM <: SExpr
    val::String
    attr::AttrType
end
NUM(x::String) = NUM(x, nothing)

struct OPID <: SExpr
    val::Char
    attr::AttrType
end
OPID(x::String, attr) = OPID(x[1], attr)
OPID(x::String) = OPID(x, nothing)
OPID(x::Char) = OPID(x, nothing)

struct BIGOP <: SExpr
    val::Char
    size::Int
    attr::AttrType
end
BIGOP(x::Char) = BIGOP(x, 3, nothing)

struct SPACE <: SExpr
    val::String
    attr::AttrType
end
SPACE(x::String) = SPACE(x, nothing)

struct Group <: SExpr
    val::Vector{CompoExpr}
    attr::AttrType
end
Group(x::Vector{CompoExpr}) = Group(x, nothing)
function Group(::Int, args...)
    v = CompoExpr[]
    for i in args; push!(v, i); end
    return Group(v)
end

struct Environment <: SExpr
    tag::String
    val::Vector{CompoExpr}
    attr::AttrType
end
Environment(x::String, v::Vector{CompoExpr}) = Environment(x, v, nothing)

struct Fenced <: SExpr
    ldelim::Char
    rdelim::Char
    val::Vector{CompoExpr}
    attr::AttrType
end
Fenced(l::Char, r::Char, v::Vector{CompoExpr}) = Fenced(l, r, v, nothing)

# TeX built-in operators are converted into specific expression types
struct Newline <: CmdExpr
end

struct Ampersand <: CmdExpr
end

struct Sqrt <: CmdExpr
    base::SExpr
    attr::AttrType
end
Sqrt(b::SExpr) = Sqrt(b, nothing)

struct Frac <: CmdExpr
    num::SExpr
    den::SExpr
    attr::AttrType
end
Frac(n::SExpr, d::SExpr) = Frac(n, d, nothing)

struct Binom <: CmdExpr
    n::SExpr
    k::SExpr
    attr::AttrType
end
Binom(n::SExpr, k::SExpr) = Binom(n, k, nothing)

# composite expressions
struct Sub <: CompoExpr
    base::SExpr
    sub::SExpr
    attr::AttrType
end
Sub(b::SExpr, s::SExpr) = Sub(b, s, nothing)

struct Sup <: CompoExpr
    base::SExpr
    sup::SExpr
    attr::AttrType
end
Sup(b::SExpr, s::SExpr) = Sup(b, s, nothing)

struct SubSup <: CompoExpr
    base::SExpr
    sub::SExpr
    sup::SExpr
    attr::AttrType
end
SubSup(b::SExpr, sb::SExpr, Sp::SExpr) = SubSup(b, sb, sp, nothing)

struct Under <: CompoExpr
    base::SExpr
    under::SExpr
    attr::AttrType
end
Under(b::SExpr, u::SExpr) = Under(b, u, nothing)

struct Over <: CompoExpr
    base::SExpr
    over::SExpr
    attr::AttrType
end
Over(b::SExpr, o::SExpr) = Over(b, o, nothing)

struct UnderOver <: CompoExpr
    base::SExpr
    under::SExpr
    over::SExpr
    attr::AttrType
end
UnderOver(b::SExpr, u::SExpr, o::SExpr) = UnderOver(b, u, o, nothing)

# return a list of expressions
parse!(ts::TokenStream) = parse_expr_group!(ts, nothing)

# This function mainly deals with the sub/sup (`_` and `^`) operators.
# An expression that can be decomposed into simpler expressions connected
# by`_` and/or `^` is called a composite expression.
#
# We assume the input `ts` is not empty.
function parse_composite_expr!(ts::TokenStream)
    sexpr = parse_single_expr!(ts)

    # parse_single_expr!() could return nothing, example: {}
    if sexpr === nothing
        if peek(ts).val == "_"
            error("subscript _ behind an empty expression {}")
        elseif peek(ts).val == "^"
            error("superscript ^ behind an empty expression {}")
        elseif peek(ts).type == TK_FRACOVER
            error("\\over behind an empty expression {}")
        else
            return nothing
        end
    end
    peek(ts) === nothing && return sexpr
    # process composite expression. look-ahead
    if peek(ts).val == "_"
        # subscript
        get_token!(ts)
        peek(ts) == nothing && error("Illegal! expression ends with _")
        sub = parse_single_expr!(ts)
        if peek(ts) !== nothing && peek(ts).val == "^"
            get_token!(ts)
            peek(ts) == nothing && error("Illegal! expression ends with ^")
            sup = parse_single_expr!(ts)
            expr = make_sub_sup(sexpr, sub, sup)
        else
            expr = make_sub(sexpr, sub)
        end
    elseif peek(ts).val == "^"
        # superscript
        get_token!(ts)
        peek(ts) == nothing && error("Illegal! expression ends with ^")
        sup = parse_single_expr!(ts)
        if peek(ts) !== nothing && peek(ts).val == "_"
            get_token!(ts)
            peek(ts) == nothing && error("Illegal! expression ends with _")
            sub = parse_single_expr!(ts)
            expr = make_sub_sup(sexpr, sub, sup)
        else
            expr = make_sup(sexpr, sup)
        end
    elseif peek(ts).type == TK_FRACOVER
        # TODO: I should implement \over operator here (used by Maxima).
        # just implement the simplified version: Assume it is the infix
        # operator of two single-expressions
        #
        get_token!(ts)
        peek(ts) == nothing && error("Illegal! expression ends with \\over")
        den = parse_single_expr!(ts)
        expr = Frac(sexpr, den)
    else
        expr = sexpr
    end
    return expr
end

const token_type_to_expr_type = Dict(
# TODO: TK_LIM, TK_INT, TK_BIGOP should be processed specially, not
# just be treated as OPIDs.
    TK_ID     => ID,
    TK_NUM    => NUM,
    TK_OPID   => OPID,
    TK_PAREN  => OPID,
    TK_LIM    => ID,
    TK_INT    => OPID,
    TK_BIGOP  => OPID,
    TK_SPACE  => SPACE
    )

function parse_single_expr!(ts::TokenStream)
    t = get_token!(ts)
   
    if t.type in keys(token_type_to_expr_type)
        return token_type_to_expr_type[t.type](t.val)
    elseif t.type == TK_LBRACE
        v = parse_expr_group!(ts, TK_RBRACE)
        isempty(v) && return nothing
        # TODO: maybe I could do this optimization, will look at it later
        #length(v) == 1 && return v[1]
        return Group(v)
    elseif t.type == TK_SQRT
        peek(ts) === nothing && return error("unfinished \\sqrt command")
        b = parse_single_expr!(ts)
        b === nothing && return error("unfinished \\sqrt command")
        return Sqrt(b)
    elseif t.type == TK_FRAC
        #TODO: simplify this branch and the next branch
        peek(ts) === nothing && return error("unfinished \\frac command")
        num =  parse_single_expr!(ts)
        num === nothing && return error("unfinished \\frac command")
        peek(ts) === nothing && return error("unfinished \\frac command")
        den =  parse_single_expr!(ts)
        den === nothing && return error("unfinished \\frac command")
        return Frac(num, den)
    elseif t.type == TK_BINOM
        peek(ts) === nothing && return error("unfinished \\binom command")
        n =  parse_single_expr!(ts)
        n === nothing && return error("unfinished \\binom command")
        peek(ts) === nothing && return error("unfinished \\binom command")
        k =  parse_single_expr!(ts)
        k === nothing && return error("unfinished \\binom command")
        return Binom(n, k)
    elseif t.type == TK_AMP
        return Ampersand()
    elseif t.type == TK_NEWLINE
        return Newline()
    elseif t.type == TK_LEFT
        ldelimiter = get_token!(ts)
        v = parse_expr_group!(ts, TK_RIGHT)
        rdelimiter = get_token!(ts)
        return Fenced(ldelimiter.val[1], rdelimiter.val[1], v)
    elseif t.type == TK_BEGIN
        # t must be followed by a TK_ENV_NAME and optionally a TK_ENV_ATTR
        t1 = get_token!(ts)
        t1.type != TK_ENV_NAME && error("Expect a name after \\begin")
        # TODO: add support for TK_ENV_ATTR
        v = parse_expr_group!(ts, TK_END)
        # collect the envionment name right behind the the \end command
        peek(ts) === nothing && error("Expect an \\end tag, but stream ends")
        t2 = get_token!(ts)
        t2.type != TK_ENV_NAME && error("Expect a name after \\end")
        # verify the two tags following \begin and \end match
        t1.val != t2.val && error("\\begin{tag} and \\end{tag} mismatch!")
        return Environment(t1.val, v)
    elseif t.type == TK_ENV  #\bmatrix{}, ...
        # environments like \matrix{}, \pmatrix{}, ...
        tag = t.val
        t = get_token!(ts)
        t.type != TK_LBRACE && error("{ must follows a \\" + tag + " environment")
        return Environment(tag, parse_expr_group!(ts, TK_RBRACE))
    elseif t.type == TK_STYLE
        # Our handling of styling commands (\mathbb, \mathcal, \mathfrak, ...)
        # is simple. We assume there is a single group expression {...}
        # following the styling command, and inside the group expression, there
        # are only letters, each to be translated into a UCS codepoint that
        # represents a letter-variant, e.g, \mathbb{AC} should be interpreteded
        # as translations: A -> 𝔸 , C -> ℂ . The translation result is a
        # mathml group (<mrow>) that contains single letter IDs (<mi>).
        #
        # When we encounter a TK_STYLE, we translate all letters in the
        # proceeding {}. We do not do translation in scanning because there
        # may be a few optmizations that can be done here, so better keep
        # the scanning process simple.
        letter_variant = t.val   # variant can be mathbb, mathcal, ...
        t = get_token!(ts)
        t.type != TK_LBRACE &&
            error("\\", letter_variant, " command must be followed by {")
        v = CompoExpr[]
        while peek(ts) !== nothing
            t = get_token!(ts)
            t.type == TK_RBRACE && break
            # FIXME: what if t.val contains more than one element?
            !isletter(t.val[1]) && error("Incorrect input: ", t.val)
            d = LETTER_TRANSLATION[letter_variant]
            push!(v, ID(d[t.val]))
        end
        !(t.type == TK_RBRACE) && error("Incorrect \\", t.val, " command syntax")
        return (length(v) == 1 ? v[1] : Group(v))
    elseif t.type == TK_IGSTYLE
        #TODO: for now we ignore in-group styles (\bf, \it, ...)
    elseif t.type == TK_FUN
        return ID(t.val)
    else
        # Unknown tokens are treated as identifiers
        return ID(t.val, nothing)
    end
end

# Note that this function assumes the beginning token (e.g., \left, {, \begin) of
# the expression group in the input token stream `ts` is already parsed.
function parse_expr_group!(ts::TokenStream, end_tk_type::Union{Int, Nothing})
    v = CompoExpr[]

    while peek(ts) !== nothing && peek(ts).type != end_tk_type
        node = parse_composite_expr!(ts)
        node != nothing && push!(v, node)
    end

    ENDTYPE = Dict(
        TK_END    => "\\end",
        TK_RBRACE => "}",
        TK_RIGHT  => "\\right"
    )
    if peek(ts) == nothing && end_tk_type != nothing
        error("right delimiter ", ENDTYPE[end_tk_type], " is missing!")
    end

    if peek(ts) != nothing && peek(ts).type == end_tk_type
        # remove the ending token (\right, }, \end) from the token stream
        get_token!(ts)
    end
    return v
end

function make_sub(sexpr, sub)
    return Sub(sexpr, sub, nothing)
end

function make_sup(sexpr, sup)
    return Sup(sexpr, sup, nothing)
end

function make_sub_sup(sexpr, sub, sup)
    return SubSup(sexpr, sub, sup, nothing)
end

######################################################################################
# A simple nodes printer: `print_expr()`.
# This function prints a vector of `CompoExpr`s or one CompoExpr to screen.
const tabsize = 3
function print_expr(nodes::Vector{CompoExpr}, indent::Int)
    for n in nodes
        print_expr(n, indent)
    end
end
print_expr(nodes::Vector{CompoExpr}) = print_expr(nodes, 0)

function print_expr(n::Sub, indent::Int)
    println(" "^indent*"<Sub>: ")
    print_2childs(n.base, n.sub, indent + tabsize)
end
print_expr(n::Sub) = print_expr(n, 0)

function print_expr(n::Sup, indent::Int)
    println(" "^indent*"<Sup>: ")
    print_2childs(n.base, n.sup, indent + tabsize)
end
print_expr(n::Sup) = print_expr(n, 0)

function print_expr(n::SubSup, indent::Int)
    println(" "^indent*"<SubSup>: ")
    print_3childs(n.base, n.sub, n.sup, indent + tabsize)
end
print_expr(n::SubSup) = print_expr(n, 0)

function print_expr(n::Under, indent::Int)
    println(" "^indent*"<Under>: ")
    print_2childs(n.base, n.under, indent + tabsize)
end
print_expr(n::Under) = print_expr(n, 0)

function print_expr(n::Over, indent::Int)
    println(" "^indent*"<Over>: ")
    print_2childs(n.base, n.over, indent + tabsize)
end
print_expr(n::Over) = print_expr(n, 0)

function print_expr(n::UnderOver, indent::Int)
    println(" "^indent*"<UnderOver>: ")
    print_3childs(n.base, n.under, n.over, indent + tabsize)
end
print_expr(n::UnderOver) = print_expr(n, 0)

function print_expr(n::Sqrt, i::Int)
    println(" "^i*"<Sqrt>: ")
    print_expr(n.base, i + 2)
end
print_expr(n::Sqrt) = print_expr(n, 0)

function print_expr(n::Frac, i::Int)
    println(" "^i*"<Frac>: ")
    print_2childs(n.num, n.den, i + tabsize)
end
print_expr(n::Frac) = print_expr(n, 0)

function print_expr(n::Binom, i::Int)
    println(" "^i*"<Binom>: ")
    print_2childs(n.n, n.k, i + tabsize)
end
print_expr(n::Binom) = print_expr(n, 0)

function print_expr(n::Group, i::Int)
    println(" "^i*"<Group>: ")
    print_expr(n.val, i + tabsize)
end
print_expr(n::Group) = print_expr(n, 0)

function print_expr(n::Environment, i::Int)
    println(" "^i*"<Environment>: " * n.tag)
    print_expr(n.val, i + tabsize)
end
print_expr(n::Environment) = print_expr(n, 0)

function print_expr(n::Fenced, i::Int)
    println(" "^i * "<Fenced>: " * n.ldelim * " , " * n.rdelim)
    print_expr(n.val, i + tabsize)
end
print_expr(n::Fenced) = print_expr(n, 0)

print_expr(n::ID, i::Int) = println(" "^i*"<ID>: ", n.val)
print_expr(n::NUM, i::Int) = println(" "^i*"<NUM>: ", n.val)
print_expr(n::OPID, i::Int) = println(" "^i*"<OPID>: ", n.val)
print_expr(n::SPACE, i::Int) = println(" "^i*"<SPACE>: ", n.val)
print_expr(n::Ampersand, i::Int) = println(" "^i*"<Ampersand>")
print_expr(n::Newline, i::Int) = println(" "^i*"<Newline>")
print_expr(n, i::Int) = println(" "^i*"fallback: "*repr(n))

print_expr(n::ID) = print_expr(n, 0)
print_expr(n::NUM) = print_expr(n, 0)
print_expr(n::OPID) = print_expr(n, 0)
print_expr(n::SPACE) = print_expr(n, 0)
print_expr(n::Ampersand) = print_expr(n, 0)
print_expr(n::Newline) = print_expr(n, 0)

function print_2childs(c1, c2, indent)
    print_expr(c1, indent)
    print_expr(c2, indent)
end

function print_3childs(c1, c2, c3, indent)
    print_expr(c1, indent)
    print_expr(c2, indent)
    print_expr(c3, indent)
end


