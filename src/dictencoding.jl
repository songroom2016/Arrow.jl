
# TODO is this really a reasonable default way of doing nulls?

const ReferenceType = AbstractPrimitive{T} where T<:Union{Int32,Union{Int32,Missing}}


"""
    DictEncoding{P<:ArrowVector,J} <: ArrowVector{J}
"""
struct DictEncoding{J,R<:ReferenceType,P<:ArrowVector} <: ArrowVector{J}
    refs::R
    pool::P
end
export DictEncoding

function DictEncoding{J}(refs::R, pool::P) where {J,R<:ReferenceType,P<:ArrowVector}
    DictEncoding{J,R,P}(refs, pool)
end

function DictEncoding{J}(data::Vector{UInt8}, refs_idx::Integer, len::Integer, pool::P
                        ) where {J,P<:ArrowVector}
    refs = Primitive{Int32}(data, refs_idx, len)
    DictEncoding{J}(refs, pool)
end
function DictEncoding{Union{J,Missing}}(data::Vector{UInt8}, refs_bmask_idx::Integer,
                                        refs_values_idx::Integer,
                                        len::Integer, pool::P) where {J,P<:ArrowVector}
    refs = NullablePrimitive{Int32}(data, refs_bmask_idx, refs_values_idx, len)
    DictEncoding{Union{J,Missing}}(refs, pool)
end

function DictEncoding(data::Vector{UInt8}, refs_idx::Integer, pool_idx::Integer,
                      x::CategoricalArray{J,1,U}) where {J,U}
    refs = Primitive{Int32}(data, refs_idx, getrefs(x))
    pool = Primitive{J}(data, pool_idx, getlevels(x))
    DictEncoding{J}(refs, pool)
end
function DictEncoding(data::Vector{UInt8}, refs_bmask_idx::Integer, refs_values_idx::Integer,
                      pool_idx::Integer, x::CategoricalArray{Union{J,Missing},1,U}) where {J,U}
    refs = NullablePrimitive{Int32}(data, refs_bmask_idx, refs_values_idx, getrefs(x))
    pool = Primitive{J}(data, pool_idx, getlevels(x))
    DictEncoding{J}(refs, pool)
end

function DictEncoding(data::Vector{UInt8}, i::Integer, x::CategoricalArray{J,1,U}
                     ) where {J,U}
    refs = Primitive{Int32}(data, i, getrefs(x))
    pool = createpool(data, i+refsbytes(x), x)
    DictEncoding{T}(refs, pool)
end
function DictEncoding(data::Vector{UInt8}, i::Integer, x::CategoricalArray{Union{J,Missing},1,U}
                     ) where {J,U}
    refs = NullablePrimitive{Int32}(data, i, getrefs(x))
    pool = createpool(data, i+refsbytes(x), x)
    DictEncoding{J}(refs, pool)
end

function DictEncoding(::Type{<:Array}, x::CategoricalArray)
    b = Vector{UInt8}(totalbytes(x))
    DictEncoding(b, 1, x)
end

function DictEncoding(x::CategoricalArray{J,1,U}) where {J,U}
    refs = arrowformat(getrefs(x))
    pool = arrowformat(getlevels(x))
    DictEncoding{J}(refs, pool)
end

DictEncoding(v::AbstractVector) = DictEncoding(CategoricalArray(v))


DictEncoding{J}(d::DictEncoding{J}) where J = DictEncoding{J}(d.refs, d.pools)
DictEncoding{J}(d::DictEncoding{T}) where {J,T} = DictEncoding{J}(convert(AbstractVector{J}, d[:]))
DictEncoding(d::DictEncoding{J}) where J = DictEncoding{J}(d)


length(d::DictEncoding) = length(d.refs)

references(d::DictEncoding) = d.refs
levels(d::DictEncoding) = d.pool
export references, levels


function createpool(data::Vector{UInt8}, i::Integer, x::CategoricalArray{J,1,U}) where {J,U}
    Primitive{J}(data, i, getlevels(x))
end
function createpool(data::Vector{UInt8}, i::Integer, x::CategoricalArray{T,1,U}
                   ) where {J<:AbstractString,U,T<:Union{J,Union{J,Missing}}}
    List{J}(data, i, getlevels(x))
end


# both defined to avoid method ambiguity
isnull(d::DictEncoding, i::Integer) = isnull(d.refs, i)
isnull(d::DictEncoding, idx::AbstractVector{<:Integer}) = isnull(d.refs, idx)

function getindex(d::DictEncoding{J}, i::Integer)::J where J
    isnull(d, i) ? missing : d.pool[d.refs[i]+1]
end
function getindex(d::DictEncoding{J}, idx::AbstractVector{<:Integer}) where J
    J[getindex(d, i) for i ∈ idx]
end
function getindex(d::DictEncoding{J}, idx::AbstractVector{Bool}) where J
    J[getindex(d, i) for i ∈ 1:length(d) if idx[i]]
end


nullcount(d::DictEncoding{Union{J,Missing}}) where J = nullcount(d.refs)


#====================================================================================================
    utilities specific to DictEncoding
====================================================================================================#
getrefs(x::CategoricalArray) = convert(Vector{Int32}, x.refs) .- Int32(1)
function getrefs(x::CategoricalArray{Union{J,Missing},1,U}) where {J,U}
    refs = Vector{Union{Int32,Missing}}(length(x))
    for i ∈ 1:length(x)
        x.refs[i] == 0 ? (refs[i] = missing) : (refs[i] = x.refs[i] - 1)
    end
    refs
end

getlevels(x::CategoricalArray) = x.pool.index

refsbytes(len::Integer) = padding(sizeof(Int32)*len)
refsbytes(::Type{Union{J,Missing}}, len::Integer) where J = bitmaskbytes(len) + refsbytes(len)
refsbytes(x::AbstractVector) = refsbytes(length(x))
refsbytes(::Type{Union{J,Missing}}, x::AbstractVector) where J = refsbytes(Union{J,Missing}, length(x))
refsbytes(x::AbstractVector{Union{J,Missing}}) where J = refsbytes(Union{J,Missing}, length(x))

totalbytes(x::CategoricalArray) = refsbytes(x) + totalbytes(getlevels(x))
function totalbytes(x::CategoricalArray{Union{J,Missing},1,U}) where {J,U}
    refsbytes(Union{J,Missing}, x) + totalbytes(getlevels(x))
end

