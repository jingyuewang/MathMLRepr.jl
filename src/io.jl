import Base: show
import Base: *

# LATEX is not a subtype of AbstractString, so we can not use LaTeXString here.
mutable struct LATEX{T}
    content::T
end

# A LATEX object `x` is not necessariy a single equation and not
# necessarily an inline display. What is written into `io` depends on the content
# of `x` which reflects the user's intention. For example, if `x` is "$a=1$",
# the bytes written into `io` should be "<math display="inline">
# <mi>a</mi><mo>=</mo><mn>1</mn></math>". If `x` is "a=1", then the bytes
# written should be "<mi>a</mi><mo>=</mo><mn>1</mn>", i.e., there is no wrapping
# top element. The interpretation for this case is left to the package to decide
# if it should be displayed inline or as a block (I interpret this case as a
# block display case in function `tex_to_mm()`, but it can change).
function tex_to_mml(x::AbstractString)
    ts = TokenStream(x)
    inner_math = exlist_to_mml(parse!(ts))
    if ts.top !== nothing && ts.top.val == "inline"
        o = mml_element(:math, inner_math) 
    else
        o = mml_element_attr(:math, inner_math, "display=\"block\"")
    end
end
tex_to_mml(x::LATEX{String}) = tex_to_mml(x.content)

function show(io::IO, mime::MIME"text/mathml+xml", x::LATEX)
    if !isempty(x.content)
        write(io, tex_to_mml(x.content))
    end
end

show(io::IO, mime::MIME"text/mathml+xml", x::T) where T<:Number =
    write(io, mml_element(:math, expr_to_mml(num_to_expr(x))))

function show(io::IO, mime::MIME"text/mathml+xml", x::Vector{<:Number})
    if !isempty(x)
        write(io, mml_element(:math, expr_to_mml(vector_to_expr(x))))
    end
end

function show(io::IO, mime::MIME"text/mathml+xml", x::AbstractMatrix)
    if !isempty(x)
        write(io, mml_element(:math, expr_to_mml(matrix_to_expr(x))))
    end
end

# Some show() function are needed by DataFrames to render LaTeX. But even with
# these functions we still do not have a full LaTeX support anyway, so these
# functions are just experimental.
function show(io::IO, mime::MIME"text/latex", x::T) where T<:Number
    write(io, expr_to_tex(num_to_expr(x)))
end

function show(io::IO, mime::MIME"text/latex", x::String)
    write(io, "\\mathrm{"*x*"}")
    #write(io, expr_to_tex(num_to_expr(x)))
end

## Some add-on's to LATEX{T}

## Convert native Julia types to LATEX
tex(x::Number) = LATEX(num_to_tex(x))
tex(x::String) = LATEX(x)
tex(x::Vector{<:Number}) = LATEX(vector_to_tex(x))
tex(x::Matrix{<:Number}) = LATEX(matrix_to_tex(x))
tex(x) = @error("Conversion from type: $(typeof(x)) to LaTeX not implemented.")
texcon(args...) = foldl(*, map(tex, args), init=LATEX(""))

if isdefined(Meta, :parseatom)
    const parseatom = Meta.parseatom
else
    parseatom(s, i; filename=nothing) = Meta.parse(s, i; greedy=false)
end

# code forked from `@L_str` in `LaTeXStrings.jl`, 
macro l_str(s::String)
    i = firstindex(s)
    buf = IOBuffer(maxsize=ncodeunits(s))
    ex = Expr(:call, GlobalRef(MathMLRepr, :texcon))
    while i <= ncodeunits(s)
        c = @inbounds s[i]
        i = nextind(s, i)
        if c === '%' && i <= ncodeunits(s)
            c = @inbounds s[i]
            if c === '$'
                position(buf) > 0 && push!(ex.args, String(take!(buf)))
                atom, i = parseatom(s, nextind(s, i), filename=string(__source__.file))
                Meta.isexpr(atom, :incomplete) && error(atom.args[1])
                atom !== nothing && push!(ex.args, atom)
                continue
            else
                print(buf, '%')
            end
        else
            print(buf, c)
        end
    end
    position(buf) > 0 && push!(ex.args, String(take!(buf)))
    return esc(ex)
end

function *(x::LATEX, y::LATEX)
    return LATEX(x.content*y.content)
end

## convert the HTML/LaTeX input to HTML/MathML
# In the input, LaTeX segments are enclosed by $-pair (for inline display)
# and $$-pair (for block display). No string interpolation in any form.
#
# The algorithm is simple: Suppose we have correctly registered the beginning
# position of the current text segment (either a HTML or a LaTeX segment),
# saved in variable `seg_begin` and start to search the next dolloar char `$`.
# When we encounter one, there are 4 possible cases ( `.` indicates a non-dollar
# char):
#
#     1. ...$...$...
#           i           in this case, we simply extract the substring
#                       `s[seg_begin: i-1]` and move `seg_begin` to `i`
#
#     1. ...$...$...
#               i       in this case, we parse the substring `s[seg_begin, i]`
#                        and move `seg_begin` to `i+1`
#
#     1. ...$$...$$...
#           i           in this case, we simply extract the substring
#                       `s[seg_begin, i-1]` and move `seg_begin` to `i`
#
#     1. ...$$...$$...
#                i      in this case, we parse the substring `s[seg_begin, i+1]`
#                       and move `seg_begin` to `i+2`
#
# Keep going until the input string is consumed. A variable `TEX_BEGIN_OR_END`
# indicates if we are already inside a LaTeX segment. 
#
# Note that this algorithm green lights two incorrect types of LaTeX segments
# in parsing: "...$....$$...", and "...$$...$..." are not warned. However when
# such strings got passed into function `tex_to_mml()`, the invalidity
# would be eventually identified there (in function `split_top_element()`).
function htlatex_to_htmml(h::HTML{<:AbstractString})
    _BEGIN, _END = true, false
    s, o = h.content, ""
    seg_begin = i = firstindex(s)
    TEX_BEGIN_OR_END = _END
    while i <= ncodeunits(s)
        c = s[i]
        if c == '$'
            # We encounter a `$` at position `i`, flip the flag to indicate
            # if we are inside a LaTeX segment. Then peek into the next
            # position to see if this is a double-dollar.
            TEX_BEGIN_OR_END = !TEX_BEGIN_OR_END
            j = nextind(s, i)
            if (j <= ncodeunits(s) && s[j] != '$') || j > ncodeunits(s)
                # not a double-dollar
                j = -1
            end
            # if `i` is at a double-dolloar `$$`, `j` points at the second `$`,
            # otherwise, `j = -1`
            if TEX_BEGIN_OR_END == _BEGIN
                # `i` points at the position of a beginning token of a
                # LaTeX segment.
                # In a special case where the first char of `s` is
                # `$`, prevind(s,i) is less than seg_begin=i, but
                # this is fine, s[seg_begin:prevind(s,i)] simply
                # returns an empty string
                o *= s[seg_begin:prevind(s, i)]
                seg_begin = i
                # if a double-dollar is encountered, move `i` one more pos.
                if (j >= 0) i = j end
            else
                # `i` points at the position of an ending token of a
                # LaTeX segment. Now `seg_begin` points at the beginning
                # token of this LaTeX segment. We parse it before
                # concatenating strings
                if (j >= 0) i = j end
                o *= tex_to_mml(s[seg_begin:i])
                seg_begin = nextind(s, i)
            end
        end
        i = nextind(s, i)
    end
    if seg_begin <= ncodeunits(s)
        o *= s[seg_begin:end]
    end
    return HTML(o)
end


## Helper functions
function dshow(tex::String)
    t = TokenStream(tex)
    nodes = parse!(t)
    print("\e]72;")
    if t.top !== nothing && t.top.val == "inline"
        print(mml_element(:math, exlist_to_mml(nodes)))
    else
        print(mml_element_attr(:math, exlist_to_mml(nodes), "display=\"block\""))
    end
    print("\a\n")
end

function join(x::HTML{<:AbstractString}, y::HTML{<:AbstractString})
    return HTML(x.content*y.content)
end

LATEX_to_HTML(x::LATEX) = HTML(tex_to_mml(x.content))
# htprint(..., "%i", arg, ...) will inline the next LATEX object `arg` (i.e., enclosing
# it with `$...$`. If the next argument `arg` is not a LATEX object, this flag will be
# quietly ignored. To print the string literal "%i", use escape "\\%i"
function htprint(args...)
    s = HTML("")
    inline_it = false
    for arg in args
        if arg isa HTML
            s = join(s, arg)
        elseif arg isa String
            if arg == "\\%in"
                s = join(s, HTML("%in"))
            elseif arg == "%in"
                inline_it = true
                continue
            else
                s = join(s, HTML(arg))
            end
        elseif arg isa LATEX
            if inline_it
                arg.content = '$'*arg.content*'$'
            end
            s = join(s, LATEX_to_HTML(arg))
        else
            @error "Unknown type: " typeof(arg)
        end
        if inline_it === true; inline_it = false; end
    end
    display("text/html", s)
end

macro rm_str(x::String)
    return HTML("<span style=\"font-family:Times New Roman; font-size:130%\"> $x </span>")
end
