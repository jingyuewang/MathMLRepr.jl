using Printf

# Convert some native Julia data types to MathML
const _INT_FMT=String("%i")
const _FLT_FMT=String("%.2f")

_num_format(::Type{<:Integer}) = _INT_FMT
_num_format(::Type{<:Rational}) = _INT_FMT
_num_format(::Type{<:AbstractFloat}) = _FLT_FMT
_num_format(::Type{Complex{T}}) where T <: Integer = _INT_FMT 
_num_format(::Type{Complex{T}}) where T <: Rational = _INT_FMT 
_num_format(::Type{Complex{T}}) where T <: AbstractFloat = _FLT_FMT 
_num_format(x) = _FLT_FMT

function num_to_expr(x::Integer; fmt::String=_INT_FMT)
    if x >= 0
        return NUM(@eval @sprintf($fmt, $x))
    else
        return Group(0, OPID('-'), NUM(@eval @sprintf($fmt, $(-x))))
    end
end

function num_to_expr(x::AbstractFloat; fmt::String=_FLT_FMT)
    if x >= 0
        return NUM(@eval @sprintf($fmt, $x))
    else
        return Group(0, OPID('-'), NUM(@eval @sprintf($fmt, $(-x))))
    end
end

function num_to_expr(x::Rational{T}; fmt::String=_num_format(T)) where T
    x == 0 && return NUM("0")
    r = Int(sign(x))
    if (x < 0) x = -x end
    if x.den != 1
        if r > 0
            return Frac(num_to_expr(x.num; fmt), num_to_expr(x.den; fmt))
        else
            return Group(0, OPID('-'), Frac(num_to_expr(x.num; fmt), num_to_expr(x.den; fmt)))
        end
    else
        if r > 0
            return num_to_expr(x.num; fmt)
        else
            return Group(0, OPID('-'), num_to_expr(x.num; fmt))
        end
    end
end

function num_to_expr(x::Complex{T}; fmt::String=_num_format(T)) where T
    return Group(0, num_to_expr(x.re; fmt), OPID('+'), num_to_expr(x.im; fmt), ID("𝑖"))
end

function vector_to_expr(
    x::Vector{T};
    mtype="pmatrix",
    fmt::String=_num_format(T)
) where T<:Number

    N = length(x)
    v = CompoExpr[]
   
    for (i, a) in enumerate(x)
        push!(v, num_to_expr(a; fmt))
        i < N && push!(v, Newline())
    end
    return Environment(mtype, v)
end

function matrix_to_expr(
    x::Matrix{T};
    mtype="pmatrix",
    fmt::String=_num_format(T)
) where T<:Number

    sz, N = size(x), length(x)
    v = CompoExpr[]

    for i in 1:sz[1], j in 1:sz[2]
        push!(v, num_to_expr(x[i,j]; fmt))
        if j < sz[2]
            push!(v, Ampersand())
        elseif i < sz[1]
            push!(v, Newline())
        end
    end
    return Environment(mtype, v)
end

# for LinearAlgebra.Adjoint type matrix
matrix_to_expr(x::AbstractMatrix) = matrix_to_expr(Matrix{eltype(x)}(x))

# Convert some native Julia data types to TeX/LaTeX
num_to_tex(x::Integer; fmt::String=_INT_FMT) = @eval @sprintf($fmt, $x)
num_to_tex(x::AbstractFloat; fmt::String=_FLT_FMT) = @eval @sprintf($fmt, $x)

function num_to_tex(x::Rational{T}; fmt::String=_num_format(T)) where T
    x == 0 && return "0"
    r = Int(sign(x))
    if (x < 0) x = -x end
    if x.den != 1
        if r > 0
            return "\\frac{$(num_to_tex(x.num; fmt))}{$(num_to_tex(x.den; fmt))}"
        else
            return "-\\frac{$(num_to_tex(x.num; fmt))}{$(num_to_tex(x.den; fmt))}"
        end
    else
        if r > 0
            return "$(num_to_tex(x.num; fmt))"
        else
            return "-$(num_to_tex(x.num; fmt))"
        end
    end
end

function num_to_tex(x::Complex{T}; fmt::String=_num_format(T)) where T
    return "$(num_to_tex(x.re; fmt))+$(num_to_tex(x.im; fmt))i"
end

function vector_to_tex(
    x::Vector{T};
    mtype::String="pmatrix",
    fmt::String=_num_format(T)
) where T<:Number

    N = length(x)
    s = "\\begin{$(mtype)}"
    
    for (i, a) in enumerate(x)
        s *= num_to_tex(a; fmt)
        if i < N
            s *= "\\\\"
        end
    end
    return s*"\\end{$(mtype)}"
end

function matrix_to_tex(
    x::Matrix{T};
    mtype::String="pmatrix",
    fmt::String=_num_format(T)
) where T<:Number

    sz, N = size(x), length(x)
    s = "\\begin{$(mtype)}"

    for i in 1:sz[1], j in 1:sz[2]
        s *= num_to_tex(x[i,j]; fmt)
        if j < sz[2]
            s *= "&"
        elseif i < sz[1]
            s *= "\\\\"
        end
    end
    return s*"\\end{$(mtype)}"
end
# for LinearAlgebra.Adjoint type matrix
matrix_to_tex(x::AbstractMatrix) = matrix_to_tex(Matrix{eltype(x)}(x))

