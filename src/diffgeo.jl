
#   This file is part of TensorFields.jl
#   It is licensed under the GPL license
#   TensorFields Copyright (C) 2023 Michael Reed
#       _           _                         _
#      | |         | |                       | |
#   ___| |__   __ _| | ___ __ __ ___   ____ _| | __ _
#  / __| '_ \ / _` | |/ / '__/ _` \ \ / / _` | |/ _` |
# | (__| | | | (_| |   <| | | (_| |\ V / (_| | | (_| |
#  \___|_| |_|\__,_|_|\_\_|  \__,_| \_/ \__,_|_|\__,_|
#
#   https://github.com/chakravala
#   https://crucialflow.com

export bound, boundabove, boundbelow, boundlog, isclosed
export centraldiff, centraldiff_slow, centraldiff_fast
export gradient, gradient_slow, gradient_fast, unitgradient
export integral, integrate, ∫

# analysis

boundabove(s::Section{B,T},lim=10) where {B,T<:Real} = fiber(s)≤lim ? s : (base(s)↦T(lim))
boundabove(x::T,lim=10) where T<:Real = x≤lim ? x : T(lim)
boundabove(t::TensorField,lim=10) = base(t) → boundabove.(codomain(t),lim)
boundbelow(s::Section{B,T},lim=-10) where {B,T<:Real} = fiber(s)≥lim ? s : (base(s)↦T(lim))
boundbelow(x::T,lim=-10) where T<:Real = x≥lim ? x : T(lim)
boundbelow(t::TensorField,lim=-10) = base(t) → boundbelow.(codomain(t),lim)
bound(s::Section{B,T},lim=10) where {B,T<:Real} = abs(fiber(s))≤lim ? s : (base(s)↦T(sign(fiber(s)*lim)))
bound(s::Section{B,T},lim=10) where {B,T} = (x=abs(fiber(s)); x≤lim ? s : ((lim/x)*s))
bound(x::T,lim=10) where T<:Real = abs(x)≤lim ? x : T(sign(x)*lim)
bound(z,lim=10) = (x=abs(z); x≤lim ? z : (lim/x)*z)
bound(t::TensorField,lim=10) = base(t) → bound.(codomain(t),lim)
boundlog(s::Section{B,T},lim=10) where {B,T<:Real} = (x=abs(fiber(s)); x≤lim ? s : (base(s)↦T(sign(fiber(s))*(lim+log(x+1-lim)))))
boundlog(s::Section{B,T},lim=10) where {B,T} = (x=abs(fiber(s)); x≤lim ? s : (base(s)↦T(fiber(s)*((lim+log(x+1-lim))/x))))
boundlog(z::T,lim=10) where T<:Real = (x=abs(z); x≤lim ? z : T(sign(z)*(lim+log(x+1-lim))))
boundlog(z,lim=10) = (x=abs(fiber(s)); x≤lim ? s : (base(s)↦T(fiber(s)*((lim+log(x+1-lim))/x))))
boundlog(t::TensorField,lim=10) = base(t) → boundlog.(codomain(t),lim)

isclosed(t::IntervalMap) = norm(codomain(t)[end]-codomain(t)[1]) ≈ 0

export Grid

struct Grid{N,T,A<:AbstractArray{T,N}}
    v::A
end

Base.size(m::Grid) = size(m.v)

@generated function Base.getindex(g::Grid{M},j::Int,::Val{N},i::Vararg{Int}) where {M,N}
    :(Base.getindex(g.v,$([k≠N ? :(i[$k]) : :(i[$k]+j) for k ∈ 1:M]...)))
end

# centraldiff

centraldiffdiff(f,dt,l) = centraldiff(centraldiff(f,dt,l),dt,l)
centraldiffdiff(f,dt) = centraldiffdiff(f,dt,size(f))
centraldiff(f::AbstractVector,args...) = centraldiff_slow(f,args...)
centraldiff(f::AbstractArray,args...) = centraldiff_fast(f,args...)

gradient(f::IntervalMap,args...) = gradient_slow(f,args...)
gradient(f::TensorField{B,<:AbstractArray} where B,args...) = gradient_fast(f,args...)
function gradient(f::MeshFunction)
    domain(f) → interp(domain(f),gradient(domain(f),codomain(f)))
end
function unitgradient(f::TensorField{B,<:AbstractArray} where B,d=centraldiff(domain(f)),t=centraldiff(codomain(f),d))
    domain(f) → (t./abs.(t))
end
function unitgradient(f::MeshFunction)
    t = interp(domain(f),gradient(domain(f),codomain(f)))
    domain(f) → (t./abs.(t))
end

(::Derivation)(t::TensorField) = getnabla(t)
function getnabla(t::TensorField)
    n = ndims(t)
    V = Submanifold(tangent(S"0",1,n))
    Chain(Values{n,Any}(Λ(V).b[2:n+1]...))
end

Grassmann.curl(t::TensorField) = ⋆d(t)
Grassmann.d(t::TensorField) = TensorField(fromany(∇(t)∧Chain(t)))
Grassmann.∂(t::TensorField) = TensorField(fromany(Chain(t)⋅∇(t)))

for op ∈ (:(Base.:*),:(Base.:/),:(Grassmann.:∧),:(Grassmann.:∨))
    @eval begin
        $op(::Derivation,t::TensorField) = TensorField(fromany($op(∇(t),Chain(t))))
        $op(t::TensorField,::Derivation) = TensorField(fromany($op(Chain(t),∇(t))))
    end
end
LinearAlgebra.dot(::Derivation,t::TensorField) = TensorField(fromany(Grassmann.contraction(∇(t),Chain(t))))
LinearAlgebra.dot(t::TensorField,::Derivation) = TensorField(fromany(Grassmann.contraction(Chain(t),∇(t))))

function Base.:*(n::Submanifold,t::TensorField)
    if istangent(n)
        gradient(t,indices(n)[1])
    else
        domain(t) → (Ref(n).*codomain(t))
    end
end
function Base.:*(t::TensorField,n::Submanifold)
    if istangent(n)
        gradient(t,indices(n)[1])
    else
        domain(t) → (codomain(t).*Ref(n))
    end
end
function LinearAlgebra.dot(n::Submanifold,t::TensorField)
    if istangent(n)
        gradient(t,indices(n)[1])
    else
        domain(t) → dot.(Ref(n),codomain(t))
    end
end
function LinearAlgebra.dot(t::TensorField,n::Submanifold)
    if istangent(n)
        gradient(t,indices(n)[1])
    else
        domain(t) → dot.(codomain(t),Ref(n))
    end
end

for fun ∈ (:_slow,:_fast)
    cd,grad = Symbol(:centraldiff,fun),Symbol(:gradient,fun)
    @eval begin
        function $grad(f::IntervalMap,d::AbstractVector=$cd(domain(f)))
            domain(f) → $cd(codomain(f),d)
        end
        function $grad(f::TensorField{B,<:AbstractArray} where B,d::AbstractArray=$cd(domain(f)))
            domain(f) → $cd(Grid(codomain(f)),d)
        end
        function $grad(f::IntervalMap,::Val{1},d::AbstractVector=$cd(domain(f)))
            domain(f) → $cd(codomain(f),d)
        end
        function $grad(f::TensorField{B,<:RealRegion} where B,n::Val{N},d::AbstractArray=$cd(domain(f).v[N])) where N
            domain(f) → $cd(Grid(codomain(f)),n,d)
        end
        function $grad(f::TensorField{B,<:AbstractArray} where B,n::Val,d::AbstractArray=$cd(domain(f),n))
            domain(f) → $cd(Grid(codomain(f)),n,d)
        end
        $grad(f::TensorField,n::Int,args...) = $grad(f,Val(n),args...)
        $cd(f::AbstractArray,args...) = $cd(Grid(f),args...)
        function $cd(f::Grid{1},dt::Real,l::Tuple=size(f.v))
            d = similar(f.v)
            @threads for i ∈ 1:l[1]
                d[i] = $cd(f,l,i)/$cd(i,dt,l)
            end
            return d
        end
        function $cd(f::Grid{1},dt::Vector,l::Tuple=size(f.v))
            d = similar(f.v)
            @threads for i ∈ 1:l[1]
                d[i] = $cd(f,l,i)/dt[i]
            end
            return d
        end
        function $cd(f::Grid{1},l::Tuple=size(f.v))
            d = similar(f.v)
            @threads for i ∈ 1:l[1]
                d[i] = $cd(f,l,i)
            end
            return d
        end
        function $cd(f::Grid{2},dt::AbstractMatrix,l::Tuple=size(f.v))
            d = Array{Chain{Submanifold(2),1,eltype(f.v),2},2}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]
                d[i,j] = Chain($cd(f,l,i,j).v./dt[i,j].v)
            end end
            return d
        end
        function $cd(f::Grid{2},l::Tuple=size(f.v))
            d = Array{Chain{Submanifold(2),1,eltype(f.v),2},2}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]
                d[i,j] = $cd(f,l,i,j)
            end end
            return d
        end
        function $cd(f::Grid{3},dt::AbstractArray{T,3} where T,l::Tuple=size(f.v))
            d = Array{Chain{Submanifold(3),1,eltype(f.v),3},3}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]; for k ∈ 1:l[3]
                d[i,j,k] = Chain($cd(f,l,i,j,k).v./dt[i,j,k].v)
            end end end
            return d
        end
        function $cd(f::Grid{3},l::Tuple=size(f.v))
            d = Array{Chain{Submanifold(3),1,eltype(f.v),3},3}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]; for k ∈ 1:l[3]
                d[i,j,k] = $cd(f,l,i,j,k)
            end end end
            return d
        end
        function $cd(f::Grid{2},n::Val{1},dt::AbstractVector,l::Tuple=size(f.v))
            d = Array{eltype(f.v),2}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]
                d[i,j] = $cd(f,l[1],n,i,j)/dt[i]
            end end
            return d
        end
        function $cd(f::Grid{2},n::Val{2},dt::AbstractVector,l::Tuple=size(f.v))
            d = Array{eltype(f.v),2}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]
                d[i,j] = $cd(f,l[2],n,i,j)/dt[j]
            end end
            return d
        end
        function $cd(f::Grid{2},n::Val{N},l::Tuple=size(f.v)) where N
            d = Array{eltype(f.v),2}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]
                d[i,j] = $cd(f,l[N],n,i,j)
            end end
            return d
        end
        function $cd(f::Grid{3},n::Val{1},dt::AbstractVector,l::Tuple=size(f.v))
            d = Array{eltype(f.v),3}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]; for k ∈ 1:l[3]
                d[i,j,k] = $cd(f,l[1],n,i,j,k)/dt[i]
            end end end
            return d
        end
        function $cd(f::Grid{3},n::Val{2},dt::AbstractVector,l::Tuple=size(f.v))
            d = Array{eltype(f.v),3}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]; for k ∈ 1:l[3]
                d[i,j,k] = $cd(f,l[2],n,i,j,k)/dt[j]
            end end end
            return d
        end
        function $cd(f::Grid{3},n::Val{3},dt::AbstractVector,l::Tuple=size(f.v))
            d = Array{eltype(f.v),3}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]; for k ∈ 1:l[3]
                d[i,j,k] = $cd(f,l[3],n,i,j,k)/dt[k]
            end end end
            return d
        end
        function $cd(f::Grid{3},n::Val{N},l::Tuple=size(f.v)) where N
            d = Array{eltype(f.v),3}(undef,l...)
            @threads for i ∈ 1:l[1]; for j ∈ 1:l[2]; for k ∈ 1:l[3]
                d[i,j,k] = $cd(f,l[N],n,i,j,k)
            end end end
            return d
        end
        $cd(f::Grid{1},l::Tuple,i::Int) = $cd(f,l[1],Val(1),i)
        @generated function $cd(f::Grid{N},l::Tuple,i::Vararg{Int}) where N
            :(Chain($([:($$cd(f,l[$n],Val($n),i...)) for n ∈ 1:N]...)))
        end
        $cd(f::RealRegion) = ProductSpace($cd.(f.v))
        function $cd(f::AbstractRange,l::Tuple=size(f))
            d = Vector{eltype(f)}(undef,l[1])
            @threads for i ∈ 1:l[1]
                d[i] = $cd(i,step(f),l[1])
            end
            return d
        end
        function $cd(dt::Real,l::Tuple)
            d = Vector{Float64}(undef,l[1])
            @threads for i ∈ 1:l[1]
                d[i] = $cd(i,dt,l[1])
            end
            return d
        end
    end
end

function centraldiff_slow(f::Grid,l::Int,n::Val{N},i::Vararg{Int}) where N #l=size(f)[N]
    if isone(i[N])
        18f[1,n,i...]-9f[2,n,i...]+2f[3,n,i...]-11f.v[i...]
    elseif i[N]==l
        11f.v[i...]-18f[-1,n,i...]+9f[-2,n,i...]-2f[-3,n,i...]
    elseif i[N]==2
        6f[1,n,i...]-f[2,n,i...]-3f.v[i...]-2f[-1,n,i...]
    elseif i[N]==l-1
        3f.v[i...]-6f[-1,n,i...]+f[-2,n,i...]+2f[1,n,i...]
    else
        f[-2,n,i...]+8f[1,n,i...]-8f[-1,n,i...]-f[2,n,i...]
    end
end

function centraldiff_slow(i::Int,dt::Real,l::Int)
    if i∈(1,2,l-1,l)
        6dt
    else
        12dt
    end
end

function centraldiff_fast(f::Grid,l::Int,n::Val{N},i::Vararg{Int}) where N
    if isone(i[N]) # 4f[1,k,i...]-f[2,k,i...]-3f.v[i...]
        18f[1,n,i...]-9f[2,n,i...]+2f[3,n,i...]-11f.v[i...]
    elseif i[N]==l # 3f.v[i...]-4f[-1,k,i...]+f[-2,k,i...]
        11f.v[i...]-18f[-1,n,i...]+9f[-2,n,i...]-2f[-3,n,i...]
    else
        f[1,n,i...]-f[-1,n,i...]
    end
end

centraldiff_fast(i::Int,dt::Real,l::Int) = i∈(1,l) ? 6dt : 2dt
#centraldiff_fast(i::Int,dt::Real,l::Int) = 2dt

qnumber(n,q) = (q^n-1)/(q-1)
qfactorial(n,q) = prod(cumsum([q^k for k ∈ 0:n-1]))
qbinomial(n,k,q) = qfactorial(n,q)/(qfactorial(n-k,q)*qfactorial(k,q))

richardson(k) = [(-1)^(j+k)*2^(j*(1+j))*qbinomial(k,j,4)/prod([4^n-1 for n ∈ 1:k]) for j ∈ k:-1:0]

# parallelization

select(n,j,k=:k,f=:f) = :($f[$([i≠j ? :(:) : k for i ∈ 1:n]...)])
select2(n,j,k=:k,f=:f) = :($f[$([i≠j ? :(:) : k for i ∈ 1:n if i≠j]...)])
psum(A,j) = psum(A,Val(j))
pcumsum(A,j) = pcumsum(A,Val(j))
for N ∈ 2:5
    for J ∈ 1:N
        @eval function psum(A::AbstractArray{T,$N} where T,::Val{$J})
            S = similar(A);
            @threads for k in axes(A,$J)
                @views sum!($(select(N,J,:k,:S)),$(select(N,J,:k,:A)),dims=$J)
            end
            return S
        end
    end
end
for N ∈ 2:5
    for J ∈ 1:N
        @eval function pcumsum(A::AbstractArray{T,$N} where T,::Val{$J})
            S = similar(A);
            @threads for k in axes(A,$J)
                @views cumsum!($(select(N,J,:k,:S)),$(select(N,J,:k,:A)),dims=$J)
            end
            return S
        end
    end
end

# trapezoid # ⎎, ∇

integrate(args...) = trapz(args...)

arclength(f::Vector) = sum(value.(abs.(diff(f))))
trapz(f::IntervalMap,d::AbstractVector=diff(domain(f))) = sum((d/2).*(f.cod[2:end]+f.cod[1:end-1]))
trapz1(f::Vector,h::Real) = h*((f[1]+f[end])/2+sum(f[2:end-1]))
function trapz(f::IntervalMap{B,<:AbstractRange} where B<:AbstractReal)
    trapz1(codomain(f),step(domain(f)))
end
function trapz(f::RectangleMap{B,<:Rectangle{V,T,<:AbstractRange} where {V,T}} where B)
    trapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]))
end
function trapz(f::HyperrectangleMap{B,<:Hyperrectangle{V,T,<:AbstractRange} where {V,T}} where B)
    trapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]),step(domain(f).v[3]))
end
function trapz(f::ParametricMap{B,<:RealRegion{V,T,4,<:AbstractRange} where {V,T}} where B)
    trapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]),step(domain(f).v[3]),step(domain(f).v[4]))
end
function trapz(f::ParametricMap{B,<:RealRegion{V,T,5,<:AbstractRange} where {V,T}} where B)
    trapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]),step(domain(f).v[3]),step(domain(f).v[4]),step(domain(f).v[5]))
end
trapz(f::IntervalMap,j::Int) = trapz(f,Val(j))
trapz(f::IntervalMap,j::Val{1}) = trapz(f)
trapz(f::ParametricMap,j::Int) = trapz(f,Val(j))
trapz(f::ParametricMap,j::Val{J}) where J = remove(domain(f),j) → trapz2(codomain(f),j,diff(domain(f).v[J]))
trapz(f::ParametricMap{B,<:RealRegion{V,<:Real,N,<:AbstractRange} where {V,N}} where B,j::Val{J}) where J = remove(domain(f),j) → trapz1(codomain(f),j,step(domain(f).v[J]))
gentrapz1(n,j,h=:h,f=:f) = :($h*(($(select(n,j,1))+$(select(n,j,:(size(f)[$j]))))/2+$(select(n,j,1,:(sum($(select(n,j,:(2:$(:end)-1),f)),dims=$j))))))
selectaxes(n,j) = (i≠3 ? i : 0 for i ∈ 1:10)
@generated function trapz1(f::Array{T,N} where T,::Val{J},h::Real,s::Tuple=size(f)) where {N,J}
    gentrapz1(N,J)
end
@generated function trapz1(f::Array{T,N} where T,h::D...) where {N,D<:Real}
    Expr(:block,:(s=size(f)),
         [:(i = $(gentrapz1(j,j,:(h[$j]),j≠N ? :i : :f,))) for j ∈ N:-1:1]...)
end
function gentrapz2(n,j,f=:f,d=:(d[$j]))
    z = n≠1 ? :zeros : :zero
    quote
        for k ∈ 1:s[$j]-1
            $(select(n,j,:k)) = $d[k]*($(select(n,j,:k,f))+$(select(n,j,:(k+1),f)))
        end
        $(select(n,j,:(s[$j]))) = $z(eltype(f),$((:(s[$i]) for i ∈ 1:n if i≠j)...))
        f = $(select(n,j,1,:(sum(f,dims=$j))))
    end
end
for N ∈ 2:5
    @eval function trapz(m::ParametricMap{B,T,F,$N} where {B,T,F},D::AbstractVector=diff.(domain(m).v))
        c = codomain(m)
        f,s,d = similar(c),size(c),D./2
        $(Expr(:block,vcat([gentrapz2(j,j,j≠N ? :f : :c).args for j ∈ N:-1:1]...)...))
    end
    for J ∈ 1:N
        @eval function trapz2(c::Array{T,$N} where T,j::Val{$J},D)
            f,s,d = similar(c),size(c),D/2
            $(gentrapz2(N,J,:c,:d))
        end
    end
end

integral(args...) = cumtrapz(args...)
const ∫ = integral

arctime(f) = inv(arclength(f))
function arclength(f::IntervalMap)
    int = cumsum(abs.(diff(codomain(f))))
    pushfirst!(int,zero(eltype(int)))
    domain(f) → int
end # cumtrapz(speed(f))
function cumtrapz(f::IntervalMap,d::AbstractVector=diff(domain(f)))
    i = (d/2).*cumsum(f.cod[2:end]+f.cod[1:end-1])
    pushfirst!(i,zero(eltype(i)))
    domain(f) → i
end
function cumtrapz1(f::Vector,h::Real)
    i = (h/2)*cumsum(f[2:end]+f[1:end-1])
    pushfirst!(i,zero(eltype(i)))
    return i
end
function cumtrapz(f::IntervalMap{B,<:AbstractRange} where B<:AbstractReal)
    domain(f) → cumtrapz1(codomain(f),step(domain(f)))
end
function cumtrapz(f::RectangleMap{B,<:Rectangle{V,T,<:AbstractRange} where {V,T}} where B)
    domain(f) → cumtrapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]))
end
function cumtrapz(f::HyperrectangleMap{B,<:Hyperrectangle{V,T,<:AbstractRange} where {V,T}} where B)
    domain(f) → cumtrapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]),step(domain(f).v[3]))
end
function cumtrapz(f::ParametricMap{B,<:RealRegion{V,T,<:AbstractRange,4} where {V,T}} where B)
    domain(f) → cumtrapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]),step(domain(f).v[3]),step(domain(f).v[4]))
end
function cumtrapz(f::ParametricMap{B,<:RealRegion{V,T,<:AbstractRange,5} where {V,T}} where B)
    domain(f) → cumtrapz1(codomain(f),step(domain(f).v[1]),step(domain(f).v[2]),step(domain(f).v[3]),step(domain(f).v[4]),step(domain(f).v[5]))
end
cumtrapz(f::IntervalMap,j::Int) = cumtrapz(f,Val(j))
cumtrapz(f::IntervalMap,j::Val{1}) = cumtrapz(f)
cumtrapz(f::ParametricMap,j::Int) = cumtrapz(f,Val(j))
cumtrapz(f::ParametricMap,j::Val{J}) where J = domain(f) → cumtrapz2(codomain(f),j,diff(domain(f).v[J]))
cumtrapz(f::ParametricMap{B,<:RealRegion{V,<:Real,N,<:AbstractRange} where {V,N}} where B,j::Val{J}) where J = domain(f) → cumtrapz1(codomain(f),j,step(domain(f).v[J]))
selectzeros(n,j) = :(zeros($([i≠j ? :(s[$i]) : 1 for i ∈ 1:n]...)))
selectzeros2(n,j) = :(zeros($([i≠j ? i<j ? :(s[$i]) : :(s[$i]-1) : 1 for i ∈ 1:n]...)))
gencat(n,j=n,cat=n≠2 ? :cat : j≠2 ? :vcat : :hcat) = :($cat($(selectzeros2(n,j)),$(j≠1 ? gencat(n,j-1) : :i);$((cat≠:cat ? () : (Expr(:kw,:dims,j),))...)))
gencumtrapz1(n,j,h=:h,f=:f) = :(($h/2)*cumsum($(select(n,j,:(2:$(:end)),f)).+$(select(n,j,:(1:$(:end)-1),f)),dims=$j))
@generated function cumtrapz1(f::Array{T,N} where T,::Val{J},h::Real,s::Tuple=size(f)) where {N,J}
    :(cat($(selectzeros(N,J)),$(gencumtrapz1(N,J)),dims=$J))
end
@generated function cumtrapz1(f::Array{T,N} where T,h::D...) where {N,D<:Real}
    Expr(:block,:(s=size(f)),
         [:(i = $(gencumtrapz1(N,j,:(h[$j]),j≠1 ? :i : :f,))) for j ∈ 1:N]...,
        gencat(N))
end
function gencumtrapz2(n,j,d=:(d[$j]),f=j≠1 ? :i : :f)
    quote
        i = cumsum($(select(n,j,:(2:$(:end)),f)).+$(select(n,j,:(1:$(:end)-1),f)),dims=$j)
        @threads for k ∈ 1:s[$j]-1
            $(select(n,j,:k,:i)) .*= $d[k]
        end
    end
end
for N ∈ 2:5
    @eval function cumtrapz(m::ParametricMap{B,T,F,$N} where {B,T,F},D::AbstractVector=diff.(domain(m).v))
        f = codomain(m)
        s,d = size(f),D./2
        $(Expr(:block,vcat([gencumtrapz2(N,j,:(d[$j])).args for j ∈ 1:N]...)...))
        domain(m) → $(gencat(N))
    end
    for J ∈ 1:N
        @eval function cumtrapz2(c::Array{T,$N} where T,::Val{$J})
            s,d = size(f),D/2
            $(gencumtrapz2(N,J,:d,:f))
            cat($(selectzeros(N,J)),i,dims=$J)
        end
    end
end
function linecumtrapz(γ::IntervalMap,f::Function)
    cumtrapz(domain(γ)→(f.(codomain(γ)).⋅codomain(gradient(γ))))
end

# differential geometry

export arclength, arctime, trapz, cumtrapz, linecumtrapz, psum, pcumsum
export centraldiff, tangent, tangent_fast, unittangent, speed, normal, unitnormal
export curvenormal, unitcurvenormal

tangent(f::IntervalMap) = gradient(f)
tangent(f::ScalarField) = det(gradient(graph(f)))
normal(f::ScalarField) = ⋆tangent(f)
unittangent(f::ScalarField,n=tangent(f)) = domain(f) → (codomain(n)./abs.(.⋆codomain(n)))
unittangent(f::IntervalMap) = unitgradient(f)
unitnormal(f) = ⋆unittangent(f)

function speed(f::IntervalMap,d=centraldiff(domain(f)),t=centraldiff(codomain(f),d))
    domain(f) → abs.(t)
end
function curvenormal(f::IntervalMap,d=centraldiff(domain(f)),t=centraldiff(codomain(f),d))
    domain(f) → centraldiff(t,d)
end
function unitcurvenormal(f::IntervalMap,d=centraldiff(domain(f)),t=centraldiff(codomain(f),d),n=centraldiff(t,d))
    domain(f) → (n./abs.(n))
end

export curvature, radius, osculatingplane, unitosculatingplane, binormal, unitbinormal, curvaturebivector, torsion, curvaturetrivector, trihedron, frenet, wronskian, bishoppolar, bishop, curvaturetorsion

function curvature(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),a=abs.(t))
    domain(f) → (abs.(centraldiff(t./a,d))./a)
end
function radius(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),a=abs.(t))
    domain(f) → (a./abs.(centraldiff(t./a,d)))
end
function osculatingplane(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d))
    domain(f) → (t.∧n)
end
function unitosculatingplane(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d))
    domain(f) → ((t./abs.(t)).∧(n./abs.(n)))
end
function binormal(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d))
    domain(f) → (.⋆(t.∧n))
end
function unitbinormal(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d))
    a = t./abs.(t)
    n = centraldiff(t./abs.(t),d)
    domain(f) → (.⋆(a.∧(n./abs.(n))))
end
function curvaturebivector(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d))
    a=abs.(t); ut=t./a
    domain(f) → (abs.(centraldiff(ut,d))./a.*(ut.∧(n./abs.(n))))
end
function torsion(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d),b=t.∧n)
    domain(f) → ((b.∧centraldiff(n,d))./abs.(.⋆b).^2)
end
function curvaturetrivector(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d),b=t.∧n)
    a=abs.(t); ut=t./a
    domain(f) → ((abs.(centraldiff(ut,d)./a).^2).*(b.∧centraldiff(n,d))./abs.(.⋆b).^2)
end
#torsion(f::TensorField,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d),a=abs.(t)) = domain(f) → (abs.(centraldiff(.⋆((t./a).∧(n./abs.(n))),d))./a)
function trihedron(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d))
    (ut,un)=(t./abs.(t),n./abs.(n))
    domain(f) → Chain.(ut,un,.⋆(ut.∧un))
end
function frenet(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d))
    (ut,un)=(t./abs.(t),n./abs.(n))
    domain(f) → centraldiff(Chain.(ut,un,.⋆(ut.∧un)),d)
end
function wronskian(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d))
    domain(f) → (f.cod.∧t.∧n)
end

function curvaturetorsion(f::SpaceCurve,d=centraldiff(f.dom),t=centraldiff(f.cod,d),n=centraldiff(t,d),b=t.∧n)
    a = abs.(t)
    domain(f) → Chain.(value.(abs.(centraldiff(t./a,d))./a),getindex.((b.∧centraldiff(n,d))./abs.(.⋆b).^2,1))
end

function bishoppolar(f::SpaceCurve,κ=value.(curvature(f).cod))
    d = diff(f.dom)
    τs = getindex.((torsion(f).cod).*(speed(f).cod),1)
    θ = (d/2).*cumsum(τs[2:end]+τs[1:end-1])
    pushfirst!(θ,zero(eltype(θ)))
    domain(f) → Chain.(κ,θ)
end
function bishop(f::SpaceCurve,κ=value.(curvature(f).cod))
    d = diff(f.dom)
    τs = getindex.((torsion(f).cod).*(speed(f).cod),1)
    θ = (d/2).*cumsum(τs[2:end]+τs[1:end-1])
    pushfirst!(θ,zero(eltype(θ)))
    domain(f) → Chain.(κ.*cos.(θ),κ.*sin.(θ))
end
#bishoppolar(f::TensorField) = domain(f) → Chain.(value.(curvature(f).cod),getindex.(cumtrapz(torsion(f)).cod,1))
#bishop(f::TensorField,κ=value.(curvature(f).cod),θ=getindex.(cumtrapz(torsion(f)).cod,1)) = domain(f) → Chain.(κ.*cos.(θ),κ.*sin.(θ))
