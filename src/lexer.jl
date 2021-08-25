# types: id, num, command (e.g., \frac{..}{..}), function (e.g., \sin(x)),
#  mtable (e.g., \begin{pmatrix}...\end{pmatrix})
#
# `f(x,y)` is by default parsed as the product of a variable f and a row vector
# (x,y), instead of as a function on x,y.  On the other hand, the latter case
# is the parsing result of f\apply(x,y) (this hardly make a visual difference
# to human's eyes, but the translated content mathml strings indeed differ.
# For the same reason, sin(x) is parsed as the product of a identifier named
# "sin" and (x).
#
# To make parsing simpler, we enforce the following conditions:
#
#   1. mtable-type objects (array, matrix, etc) can not be nested.
#   2. \text objects can not be nested.
#
# These conditions make sense in the context of terminal rendering (for quick
# checking of results, not for publishing a full manuscript).
#
# Supported mtable-type tags: array, cases, gathered, aligned, split, matrix,
#   pmatrix, bmatrix, vmatrix, Vmatrix

mutable struct CharStream
    s::String
    state::Int
    cur::Union{Char, Nothing}
    peek::Union{Char, Nothing}
end
# Upon object creation, one can peek into it by one char, but has not READ a
# char yet (the current char is nothing). To read the a char, explicitly call
# read_char!().
function CharStream(data::String)
    cs = CharStream(data, 1, nothing, nothing)
    read_char!(cs)
    return cs
end

peek_char(cs::CharStream) = cs.peek

# read one char from the stream and update internal states (cur, peek)
# return `cur`
function read_char!(cs::CharStream)
    next = iterate(cs.s, cs.state)
    if next === nothing
        cs.cur, cs.peek = cs.peek, nothing
    else
        ch, cs.state = next
        cs.cur, cs.peek = cs.peek, ch
    end
    return cs.cur
end

# assume the next (peeked) position in the char stream points to a numeric
# literal
function read_number!(s::CharStream)
    @assert isdigit(s.peek)
    num = ""
    c = peek_char(s)
    has_period = false
    while (c !== nothing) && (isdigit(c) || ((c == '.') && !has_period))
        num *= read_char!(s)
        c == '.' && (has_period = true)
        c = peek_char(s)
    end
    return num
end

# assume the next (peeked) position in the char stream points to '\'
# there is a special case: `\{` and `\{` are indeed not commands,
# but escaped chars that should be converted to <mo>. We should deal
# with this case specially: just return "{" and "}". There are
# other escaped chars, in particular '&', '_', '^'. We do not deal
# with them, i.e., we treat thoses escaped chars as errors.
function read_tex_command!(s::CharStream)
    cmd = ""
    peek_char(s) == '\\' && read_char!(s)
    c = peek_char(s)

    c in "!,:; {}|\\" && return string(read_char!(s))
    c in "&_^" && error("We do not deal with escaped &, _, ^ ")
    c === nothing && error("Can not process \\ at the end of stream")
    while c !== nothing && isletter(c)
        cmd *= read_char!(s)
        c = peek_char(s)
    end

    isempty(cmd) && error("Can not process TeX command char: $(c)")
    return cmd
end

function skip_whitespace!(s::CharStream)
    c = peek_char(s)
    while c !== nothing && isspace(c)
        read_char!(s)
        c = peek_char(s)
    end
end

# Split enclosing dollar signs from the input and use them to determine if we render the
# formula inline or as a block. We assume `s` can only be enclosed by a single-dollar
# pair: s=`$...$` or a double-dollar pair: s=`$$...$$$`, and there is no dollar sign inside
# the enclosing pair. All other cases are errored.
function split_top_element(s::String)
    i = firstindex(s)
    while isspace(s[i])
        i = nextind(s, i)
    end
    n = lastindex(s)
    while isspace(s[n])
        n = prevind(s, n)
    end

    # many boring cases
    n < i && return nothing, ""
    if n == i
        s[i] == '$' && error(raw"Invalid input \"$\"")
        return (nothing, s)
    end
    start_with_D = startswith(s[i:n], "\$")
    end_with_D = endswith(s[i:n], "\$")
    if (start_with_D && !end_with_D) || (!start_with_D && end_with_D)
        error(raw"The $ sign mismatch at the beginning and the end of input")
    end
    start_with_DD = end_with_DD = false
    if n >= i + 2
        if startswith(s[i:n], raw"$$$") || endswith(s[i:n], raw"$$$")
            error(raw"Invalid input $$$")
        end
        start_with_DD = startswith(s[i:n], raw"$$")
        end_with_DD = endswith(s[i:n], raw"$$")
        if (start_with_DD && !end_with_DD) || (!start_with_DD && end_with_DD)
            error(raw"$$ mismatch at the beginning and the end of input")
        end
    end
    start_with_DD && return (Token(TK_MATH, "block"), s[i+2:prevind(s, n-1)])
    start_with_D && return (Token(TK_MATH, "inline"), s[i+1:prevind(s, n)])
    return (nothing, s)
end

# TODO: build a dictionary (read from a unicode char text file) to map LaTeX
# command names to UCS codepoints or MML commands.

# The main function: scan a string to get a stream of token.
# We assume the input data is just one LaTeX block that represents math
# content, not textual content. The input text can either be in the form of
# "$...$" for inline display, or be in the form of "$$...$$" for block display,
# or be bare LaTeX commands that are not wrapped by dollar sign at all. Dollar
# signs inside the input data except at the starting/ending positions are not
# specially treated.
function scan_tex(data::String)
    stack = Token[]
    # process the top element <math> if "$" is present in the input data
    # This element is not pushed into the token stack, the returned `data`
    # is stripped off of dollar signs
    top, data = split_top_element(data)
    s = CharStream(data)

    while (ch = peek_char(s)) !== nothing
        if isspace(ch)
            skip_whitespace!(s)
        elseif isletter(ch)
            push!(stack, Token(TK_ID, read_char!(s)))
        elseif isdigit(ch)
            push!(stack, Token(TK_NUM, read_number!(s)))
        elseif ch in OPERATOR_IDS
            # "+-*/!:=,.\'"
            push!(stack, Token(TK_OPID, read_char!(s)))
        elseif ch in BRACKETS
            # "|<>()[]"
            push!(stack, Token(TK_PAREN, read_char!(s)))
        elseif ch == '{'
            push!(stack, Token(TK_LBRACE, read_char!(s)))
        elseif ch == '}'
            push!(stack, Token(TK_RBRACE, read_char!(s)))
        elseif ch == '&'
            push!(stack, Token(TK_AMP, read_char!(s)))
        elseif ch == '^'
            push!(stack, Token(TK_SUP, read_char!(s)))
        elseif ch == '_'
            push!(stack, Token(TK_SUB, read_char!(s)))
        elseif ch in keys(unicode_to_optoken)
            # a large unicode glyph sets that define a lot of
            # math operators
            push!(stack, unicode_to_optoken[read_char!(s)])
        elseif ch == '\\'
            # some tex commands are converted to identifiers and
            # operator identifiers. Others are real commands
            cmd = read_tex_command!(s)
            if cmd in keys(command_to_token)
                t = command_to_token[cmd]
                push!(stack, t)
                # Some commands need specical treatment:
                #   TK_BEGIN(TK_END): tokenize proceeding env names
                if t.type == TK_BEGIN || t.type == TK_END
                    # get env name and env attributes if present.
                    # Envionment names are quite simple in semantics.
                    # it is just an atomic string that represents the
                    # name of an environment, it is not a sequence of
                    # identifiers. If we did not collect environment name
                    # here, the letters in the name would be scanned into
                    # individual identifiers and we would have to recover
                    # the name later in parsing, inefficient.
                    # 
                    # format: \begin{env-name}[env-attrib]...\end{env-name}
                    #   <env-name> is a sequence of letters and '*'.
                    #   <env-attrib> is a sequence of letters, or numbers,
                    #   or special chars in "=;+-*%/ "
                    skip_whitespace!(s)
                    l = read_char!(s)
                    # unlike \frac, \begin (\end) must be followed by `{` 
                    l != '{' && error("Error! \\begin(\\end) not followed by {")
                    e, tag = "", ""
                    while peek_char(s) != nothing
                        e = read_char!(s)
                        e == '}' && break
                        if !isletter(e) && e != '*'
                            error("Error! illegal environment name")
                        end
                        tag *= e
                    end
                    e != '}' && error("Error! \\begin(\\end) tag not end with }")
                    push!(stack, Token(TK_ENV_NAME, tag))
                    # TODO: continue to process environment attributes
                end
            else
                error("unknown LaTeX command: $(cmd)")
            end
        else
            # all other chars are treated as TK_IDs
            push!(stack, Token(TK_ID, read_char!(s)))
        end
    end # while (ch = read_char!()) !== nothing
    
    return (top, stack)
end # function scan_tex


# `top` indicates if the stream is enclosed by a single-dollar pair or a
# double-dollar pair
mutable struct TokenStream
    tokens::Vector{Token}
    top::Union{Token, Nothing}  
    cur::Int
end
TokenStream() = TokenStream(Token[], nothing, 0)
TokenStream(tokens::Vector{Token}, top::Token) = TokenStream(tokens, top, 1)
function TokenStream(text::String)
    top, tokens = scan_tex(text)
    return TokenStream(tokens, top, 1)
end

# A shift operation
function get_token!(ts::TokenStream)
    if ts.cur <= length(ts.tokens)
        t = ts.tokens[ts.cur]
        ts.cur += 1
        return t
    else
        return nothing
    end
end

function peek(ts::TokenStream)
    if ts.cur <= length(ts.tokens)
        return ts.tokens[ts.cur]
    else
        return nothing
    end
end

function print_token_stream(ts::TokenStream)
    println("top: " * (ts.top === nothing ? "Nothing" : ts.top.val))
    for t in ts.tokens
        println(token_names[t.type] * ": " * t.val)
    end
    println()
end


