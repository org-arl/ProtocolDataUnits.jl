module PDUs

export PDU, BIG_ENDIAN, LITTLE_ENDIAN

## data types

"""
Parent data type for all PDUs.
"""
abstract type PDU end

"""
PDU information with fields:

- `length`: length of PDU in bytes, if known, `missing` otherwise
- `get`: function that returns value of field `s` in the PDU
"""
struct PDUInfo{T}
  length::Union{Missing,Int}
  get::T
end

# PDU equality is defined as equality of all fields
function Base.:(==)(a::T, b::T) where T <: PDU
  flds = fieldnames(T)
  getfield.(Ref(a), flds) == getfield.(Ref(b), flds)
end

# pretty printing of PDUs
function Base.show(io::IO, pdu::T) where T <: PDU
  print(io, "$(T) « ")
  first = true
  for f ∈ fieldnames(T)
    first || print(io, ", ")
    print(io, "$(f)=$(getfield(pdu, f))")
    first = false
  end
  print(io, " »")
end

## constants

const BIG_ENDIAN = (hton, ntoh)
const LITTLE_ENDIAN = (identity, identity)

## defaults

"""
    byteorder(::Type{T})

Byte order used for PDUs of type `T`. Defaults to `BIG_ENDIAN`. To change byte
order, define a method for this function.

# Example:
```
PDUs.byteorder(::Type{MyPDU}) = LITTLE_ENDIAN
```
"""
byteorder(::Type{<:PDU}) = BIG_ENDIAN

"""
    byteorder(::Type{T}, ::Val{s})

Byte order used for PDUs of type `T` for field `s`. Defaults to the same byte
order as the PDU. To change byte order, define a method for this function.

# Example:
```
PDUs.byteorder(::Type{MyPDU}, ::Val{:myfield}) = LITTLE_ENDIAN
```
"""
byteorder(T::Type{<:PDU}, fld) = byteorder(T)

"""
    length(::Type{T}, ::Val{s}, info::PDUInfo)

Length of field `s` in PDU of type `T`. Defaults to `nothing`, which indicates
that the length is not known, and wire-encoding is used to store length as part of
PDU. The length is specified in number of elements for vectors, and number of bytes
for strings.

# Examples:
```
# length of field x is 4 bytes less than length of PDU
PDUs.length(::Type{MyPDU}, ::Val{:x}, info) = info.length - 4

# length of field x is given by the value of field n in the PDU
PDUs.length(::Type{MyPDU}, ::Val{:x}, info) = info.get(:n)
```
"""
Base.length(T::Type{<:PDU}, V::Val, info) = nothing

## API

"""
    Vector{UInt8}(pdu::PDU)

Encodes a PDU into a vector of bytes.
"""
function Vector{UInt8}(pdu::PDU)
  io = IOBuffer()
  try
    write(io, pdu)
    take!(io)
  finally
    close(io)
  end
end

"""
    write(io::IO, pdu::PDU)

Encodes a PDU into a vector of bytes written to stream `io`.
"""
function Base.write(io::IO, pdu::T) where {T<:PDU}
  for (f, F) ∈ zip(fieldnames(T), fieldtypes(T))
    htop = byteorder(T, Val(f))[1]
    if F <: Number
      write(io, htop(getfield(pdu, f)))
    elseif F <: NTuple{N,<:Number} where N
      write(io, htop.([getfield(pdu, f)...]))
    elseif F <: AbstractVector{<:Number} || F <: AbstractString
      n = length(T, Val(f), PDUInfo(missing, s -> getfield(pdu, s)))
      v = getfield(pdu, f)
      v = F <: AbstractString ? Vector{UInt8}(v) : htop.(v)
      if n === nothing
        varwrite(io, v)
      else
        if n === missing
          write(io, v)
        else
          write(io, n > length(v) ? vcat(v, zeros(eltype(v), n - length(v))) : @view v[1:n])
        end
      end
    else
      write(io, getfield(pdu, f))
    end
  end
  nothing
end

"""
    (T::Type{<:PDU})(buf::Vector{UInt8})

Decodes a vector of bytes to give a PDU.
"""
function (T::Type{<:PDU})(buf::Vector{UInt8})
  io = IOBuffer(buf)
  try
    read(io, T; nbytes=length(buf))
  finally
    close(io)
  end
end

"""
    read(io::IO, T::PDU)
    read(io::IO, T::PDU; nbytes)

Decodes a vector of bytes from stream `io` to give a PDU. If `nbytes` is specified,
the PDU is assumed to be of length `nbytes` bytes.
"""
function Base.read(io::IO, T::Type{<:PDU}; nbytes=missing)
  data = Pair{Symbol,Any}[]
  for (f, F) ∈ zip(fieldnames(T), fieldtypes(T))
    ptoh = byteorder(T, Val(f))[2]
    if F <: Number
      push!(data, f => ptoh(read(io, F)))
    elseif F <: NTuple{N,<:Number} where N
      push!(data, f => tuple(ptoh.([read(io, eltype(F)) for _ ∈ 1:fieldcount(F)])...))
    elseif F <: AbstractVector{<:Number} || F <: AbstractString
      n = length(T, Val(f), PDUInfo(nbytes, s -> lookup(data, s)))
      V = F <: AbstractString ? UInt8 : eltype(F)
      v = n === nothing ? varread(io, V) : V[read(io, V) for _ ∈ 1:n]
      push!(data, f => F <: AbstractString ? strip(String(v), ['\0']) : ptoh.(v))
    else
      push!(data, f => read(io, F))
    end
  end
  T(map(kv -> kv[2], data)...)
end

## private helpers

"""
    varwrite(io, v)

Writes vector `v` to IO stream `io` in a variable-length wire format.
"""
function varwrite(io::IO, v::AbstractVector)
  n = length(v)
  while n > 127
    write(io, UInt8((n & 0x7f) | 0x80))
    n >>= 7
  end
  write(io, UInt8(n))
  write(io, v)
end

"""
    varread(io)
    varread(io, T)

Reads vector from IO stream `io` in a variable-length wire format. If type `T` is
unspecified, it is assumed to be `UInt8`.
"""
function varread(io::IO, T=UInt8)
  n = 0
  i = 0
  while true
    b = read(io, UInt8)
    n |= (b & 0x7f) << i
    i += 7
    b & 0x80 == 0 && break
  end
  T[read(io, T) for _ ∈ 1:n]
end

"""
    lookup(data, s)

Lookup value corresponding to symbol `s` in vector of key-value pairs `data`.
If the symbol is not found, `nothing` is returned.
"""
function lookup(data::Vector{Pair{Symbol,Any}}, s::Symbol)
  i = findfirst(kv -> first(kv) === s, data)
  i === nothing && return nothing
  data[i][2]
end

end # module
