module MathMLRepr

include("token.jl")
include("lexer.jl")
include("parser.jl")
include("serializer.jl")
include("io.jl")
include("julia_expr.jl")

export
    ### TYPES
    Token,
    TokenStream,
    CompoExpr,
    LATEX,

    ### FUNCTIONS
    # core functions
    scan_tex,
    parse!,
    expr_to_mml,
    expr_to_tex,
    exlist_to_mml,
    exlist_to_tex,
    mml_element,
    mml_element_attr,
    htlatex_to_htmml,
    # pretty-printing 
    print_token_stream,
    print_expr,
    pretty_print_mml,
    # conversion from Julia expressions
    num_to_expr,
    num_to_tex,
    vector_to_expr,
    vector_to_tex,
    matrix_to_expr,
    matrix_to_tex,
    ## io
    *,
    tex_to_mml,
    tex,
    texcon,
    show,
    dshow,
    htprint,
    LATEX_to_HTML,
    ## MACROS
    @l_str,
    @rm_str

  function __init__()
#    println("hello world from latex2mathml")
end # __init__

end
