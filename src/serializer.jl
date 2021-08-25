""" Convert a presentation math expression to a MML string or a list of MML string
"""
exlist_to_mml(nodes::Vector{CompoExpr}) = foldl(*, map(expr_to_mml, nodes), init="")

expr_to_mml(n::Sub) = mml_element(:msub, _2_exprs_to_mml(n.base, n.sub))
expr_to_mml(n::Sup) = mml_element(:msup, _2_exprs_to_mml(n.base, n.sup))
expr_to_mml(n::SubSup) = mml_element(:msubsup, _3_exprs_to_mml(n.base, n.sub, n.sup))
expr_to_mml(n::Under) = mml_element(:munder, _2_exprs_to_mml(n.base, n.under))
expr_to_mml(n::Over) = mml_element(:mover, _2_exprs_to_mml(n.base, n.over))
expr_to_mml(n::UnderOver) = mml_element(
        :munderover,
       _3_exprs_to_mml(n.base, n.under, n.over))
expr_to_mml(n::Sqrt) = mml_element(:msqrt, expr_to_mml(n.base))
expr_to_mml(n::Frac) = mml_element(:mfrac, _2_exprs_to_mml(n.num, n.den))
expr_to_mml(n::Group) = mml_element(:mrow, exlist_to_mml(n.val))
# we do not really use the `mfenced` element yet. Even firefox does not
# support it as of 2021 (but MathJax does). Per MathML 3.0 specification (2nd
# edition), the following construct is equivalent to `mfenced`.
expr_to_mml(n::Fenced) = mml_element(:mrow,
    mml_delim_pairs(n.ldelim, n.rdelim, exlist_to_mml(n.val)))
# MML Binom is a hack, there is no "built-in" MML element for a Binom
expr_to_mml(n::Binom) = mml_element(
    :mrow,
    mml_delim_pairs(
        '(', ')', 
        mml_element_attr(
            :mfrac,
            _2_expr_to_mml(n.n, n.k),
            Dict("linethickness"=>"0")
        )))

function expr_to_mml(n::Environment)
    mat_delim = Dict("pmatrix"=>"()", 
                    "bmatrix"=>"[]",
                    "vmatrix"=>"||",
                    "Vmatrix"=>"∥∥")
    if n.tag == "matrix"
        return make_mml_table(n.val)
    elseif n.tag in ("pmatrix", "bmatrix", "vmatrix")
        return mml_element(
            :mrow,
            mml_delim_pairs(mat_delim[n.tag][1], mat_delim[n.tag][2], make_mml_table(n.val)))
    elseif n.tag == "verbatim"
        # We quietly ignore the `verbatim` environment for now.
        # Perhaps we don't even need a `:mrow` tag, just return the content
        #return mml_element(:mrow, exlist_to_mml(n.val))
        return exlist_to_mml(n.val)
    else
        @error("Unknown environment: "*n.tag)
    end
end

function make_mml_table(m::Vector{CompoExpr})
    # t: table, r: row, c: cell
    r, c, t = "", "", ""
    for n in m
        if n isa Ampersand
            # create a mml cell whose content is `c`
            r *= mml_element(:mtd, c) 
            c = ""
        elseif n isa Newline
            # create a mml row in `r`
            r *= mml_element(:mtd, c) 
            t *= mml_element(:mtr, r)
            r, c = "", ""
        else
            # amalgamate elements in a cell
            c *= expr_to_mml(n)
        end
    end
    # finish the last row (assume there is no ampersand or newline
    # behind the last expression in the input vector)
    r *= mml_element(:mtd, c)
    t *= mml_element(:mtr, r)
    return mml_element(:mtable, t)
end

expr_to_mml(n::ID) = mml_element(:mi, n.val)
expr_to_mml(n::NUM) = mml_element(:mn, n.val)
expr_to_mml(n::OPID) = mml_element(:mo, n.val)
expr_to_mml(n::SPACE) = mml_element_attr(:mspace, "", Dict("width"=>n.val))
expr_to_mml(n::Ampersand) = mml_element(:mo, "&")
# The following should be the correct implementation, but as of 2021/7/1 
# Firfox does not support the `linebreak="newline"` attribute.
#   "<mspace linebreak=\"newline\" width=\"2ex\" />"
#
# A dirty hack here. the <math> tag is wrapped by LaTeX2MathML.show().
# But we have no idea if the display style is `inline` or `block` here.
expr_to_mml(n::Newline) = "</math><br/><math>"
expr_to_mml(n) = mml_element(:unknown, repr(n))

mml_element(ele, content) = string("<", ele, ">", content, "</", ele, ">")

function mml_element_attr(ele, content, attr::Dict)
    s = string("<", ele, " ")
    for k in keys(attr)
        s *= k*"=\""*attr[k]*"\" "
    end
    s *= ">"*content*"</"*string(ele)*">"
    return s
end

function mml_element_attr(ele, content, attr::String)
    return string("<", ele, " ", attr, ">", content, "</",  ele, ">")
end

mml_delim_pairs(open, close, content) = (
    mml_element(:mo, open)*content*mml_element(:mo, close))

_2_exprs_to_mml(c1, c2) = expr_to_mml(c1)*expr_to_mml(c2)
_3_exprs_to_mml(c1, c2, c3) = _2_exprs_to_mml(c1, c2)*expr_to_mml(c3)

#############################################################################
## pretty_print_mml() is for debug
function pretty_print_mml(mml::String)
    # convert a utf-8 string to a vector of unicode chars so we can
    # index into it easily
    mml_chars = Char[]
    i = 1
    while i <= ncodeunits(mml)
        push!(mml_chars, mml[i])
        i = nextind(mml, i)
    end
    ele_stack = String[]
    t = 1
    while t <= length(mml_chars)
        #skip whitespaces
        while isspace(mml_chars[t]) t += 1 end
        mml_chars[t] != '<' && error("Unknown token: ", mml_chars[t])
        t = pretty_print_element(mml_chars, t, 0, ele_stack)
    end
end

const tbsz = 3
function pretty_print_element(mml::Vector{Char}, start::Int, indent::Int, ele_stack::Vector{String})
    # mml[start] must be '<'
    i, ele_name = start + 1, ""
    # get starting tag
    while mml[i] != '>'
        ele_name *= mml[i]
        i += 1
    end
    i += 1
    push!(ele_stack, ele_name)
    print(" "^indent*"<", ele_name, '>')
    if ele_name in ("mi", "mn", "mo", "mspace")
        # simple leaf elements
        while mml[i] != '<'
            print(mml[i])
            i += 1
        end
        # Now mml[i] == '<' in the ending tag of <mi>, <mn>, <mo>, <mspace>
        while mml[i] != '>' i += 1 end
        i += 1
        i <= length(mml) && while isspace(mml[i]) i += 1 end
        print("</", ele_name, ">")
        println()
        pop!(ele_stack)
        return i
    else
        # the starting tag name occupies a line
        println()
        # keep finding the next tag and print
        while true
            while isspace(mml[i]) i += 1 end
            if i > length(mml)
                break
            end
            if mml[i] == '<' && mml[i+1] != '/'
                i = pretty_print_element(mml, i, indent + tbsz, ele_stack)
            elseif mml[i+1] == '/'
                i += 2
                en2 = ""
                while mml[i] != '>'
                    en2 *= mml[i]
                    i += 1
                end
                en = pop!(ele_stack)
                # we could have sth like <mspace width=...> </mspace>
                !startswith(en, en2) && begin
                    println(ele_stack)
                    error("tag not match: ", en, " -- ", en2)
                end
                # mml[i] == '>'
                println(" "^indent*"</", en2, '>')
                i += 1
                i > length(mml) && return i
                while isspace(mml[i]) i += 1 end
                mml[i] != '<' && error("unknown tag: ", mml[i])
                return i
            else
                error("unknown tag: ", mml[i])
            end
        end
    end
end

###############################################################################
"""Convert a presentation math expression to a LaTeX string"""
exlist_to_tex(nodes::Vector{CompoExpr}) = foldl(*, map(expr_to_tex, nodes), init="")

# unicode identifiers are kept unchanged
expr_to_tex(ex::ID) = ex.val
expr_to_tex(ex::NUM) = ex.val
expr_to_tex(ex::OPID) = ex.val
expr_to_tex(ex::SPACE) = raw"\,"
expr_to_tex(::Ampersand) = "&"
expr_to_tex(::Newline) = "\\\\"

expr_to_tex(n::Sub) = "{$(expr_to_tex(n.base))}_{$(expr_to_tex(n.sub))}"
expr_to_tex(n::Sup) = "{$(expr_to_tex(n.base))}^{$(expr_to_tex(n.sup))}"
expr_to_tex(n::SubSup) =
    "{$(expr_to_tex(n.base))}_{$(expr_to_tex(n.sub))}^{$(expr_to_tex(n.sup))}"
expr_to_tex(n::Under) = "\\underset{$(n.under)}{$(n.base)}"
expr_to_tex(n::Over) = "\\underset{$(n.under)}{$(n.base)}"
expr_to_tex(n::UnderOver) = 
    "\\underset{$(n.under)}{\\overset{$(n.over)}{$(n.base)}}"
expr_to_tex(n::Sqrt) = "\\sqrt{$(n.base)}"
expr_to_tex(n::Frac) = "\\frac{$(n.base)}"
expr_to_tex(n::Group) = "{$(exlist_to_tex(n.val))}"
expr_to_tex(n::Fenced) = "\\left$(n.ldelim)$(exlist_to_tex(n.val))\\right$(n.rdelim)"
expr_to_tex(n::Binom) = "\\binom{$(n.n)}{$(n.k)}"

function expr_to_tex(n::Environment) 
    return "\\begin{$(n.tag)}"*exlist_to_tex(n.val)*"\\end{$(n.tag)}"
end

