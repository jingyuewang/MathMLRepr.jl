using Printf
using MathMLRepr

#### UNIT TEST
#

function parser_test()
    #l = raw"(a + b) * c"
    #l = raw"a_2 + 3.14"
    #l = raw"a_{2+i} + b"
    #l = raw"α + ∑_{i=0}^n 2^i"
    #l = raw"a \over b"
    l = raw"{x^2+2x+1}\over{x+1} + x^3"
    #l = raw"1+(2*3) + 1.333 \alpha a"
    #l = raw"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"
    #l = raw"\frac{2}{a+1} \times 2 b"
    #l = raw"\pmatrix{a & 1 \\ 2 & 2}"
    #l = raw"\begin{bmatrix} a_1 & b^2 \\ 2.25 & \sin x \end{bmatrix}"
    #l = raw"\pmatrix{a_1 & b^2 \\ 2.25 & \sin x}"
    #l = raw"$$\pmatrix{a_{1,1} & a_{1,2} \\ a_{2,1} & a_{2,2} }$$"
    #l = scan_tex(raw"\begin{align} a^2 = b^2 + c^2 \end{align}")
    #l = raw"∫_2^3 f(x) \,dx"
    #l = raw"\sqrt{\sqrt{\left( x^3 \right) + v}}"
    #l = raw"\frac{3}{\frac{1}{2}x^2}"
    #l = raw"\lim_{x \to \infty} f(x)"
    #l = raw"d = \mathfrak{ABC}"
    #l = raw"$$\mathfrak{E} = mc^2$$"
    #l = raw"x = \mathbf{A} + \mathbb{B} + \mathcal{C} + \mathfrak{D}"
    #l = raw"{\it integrate}(x^2, x)"
    #l = raw"$$\int_0^\infty e^{-x}\,dx, \qquad y = 2.$$"
    l = " \n\n\\begin{verbatim}\nf(x):=x^2+2*x+1;\n\\end{verbatim}\n"
    #top, tks = scan_tex(l)
    ts = TokenStream(l)
    nodes = parse!(ts)

    # print token stream
    #print_token_stream(ts)

    # print ast
    #print_expr(nodes, 0)
    #println()
    
    # print raw mml
    println(exlist_to_mml(nodes))

    # pretty-print mml
    #pretty_print_mml(exlist_to_mml(nodes))

end

parser_test()

# `t` is evaluated before being passed to `num_to_tex`, so the result is `-frac{1}{2}`
# t = -3//6 

#t = -123
#t = UInt8(127) 
#t = Float32(3.14159)
#t = Float64(3.14159)
#t = 17//231
#t = Complex(1.2, 4.8)
#t = Complex(15, 82)
#if t isa Union{Integer, Rational, Complex{<:Integer}}
#    println(num_to_tex(t, fmt="%.4d"))
#else
#    println(num_to_tex(t, fmt="%.4f"))
#end
#print_expr(num_to_expr(t))

#t = [1,2,3,4,5]
#t = [1.2, 3.4, 5.6, 7.71828]
#if t isa Union{Vector{<:Integer}}
#    println(vector_to_tex(t, fmt="%.4d"))
#else
#    println(vector_to_tex(t, fmt="%.4f"))
#end
#print_expr(vector_to_expr(t))

#t = [1 2 3; 4 5 6]
#if t isa Matrix{<:Integer}
#    println(matrix_to_tex(t, fmt="%d"))
#else
#    println(matrix_to_tex(t, fmt="%.4f"))
#end
#print_expr(matrix_to_expr(t))

#s = raw"<b>Hello World!</b>$\alpha=1$"
#s = raw"<b>Hello World!</b>$$\alpha=1$$"
#s = raw"<b>Hello World!</b>$$\alpha=1$$ Hello world"
#s = raw"$$\alpha=1$$ <b>Hello World!</b>Hello world"
#s = raw"$\alpha=1$ <b>Hello World!</b>Hello world"
#h = HTML(s)
#println(htlatex_to_htmml(h))

A = [1 2 3; 4 5 6]
B = A'
display("text/mathml+xml", A)
