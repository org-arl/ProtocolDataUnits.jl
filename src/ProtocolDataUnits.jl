module ProtocolDataUnits

export AbstractPDU, PDU, BIG_ENDIAN, LITTLE_ENDIAN, WireEncoded, PadTo

const PDU = ProtocolDataUnits

## data types

"""
Parent data type for all PDUs.
"""
abstract type AbstractPDU end

"""
Tag structure to indicate fixed length fields in PDU.

# Example:
```julia
Base.length(::Type{MyPDU}, ::Val{:x}, info) = PadTo(16)
```
"""
struct PadTo
  n::Int64
end

"""
Tag structure to indicate variable length fields in PDU, with length stored
within the PDU using wire-encoding.
"""
struct WireEncoded end

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
function Base.:(==)(a::T, b::T) where T <: AbstractPDU
  flds = fieldnames(T)
  getfield.(Ref(a), flds) == getfield.(Ref(b), flds)
end

# pretty printing of PDUs
function Base.show(io::IO, pdu::T) where T <: AbstractPDU
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
```julia
PDU.byteorder(::Type{MyPDU}) = LITTLE_ENDIAN
```
"""
byteorder(::Type{<:AbstractPDU}) = BIG_ENDIAN

"""
    byteorder(::Type{T}, ::Val{s})

Byte order used for PDUs of type `T` for field `s`. Defaults to the same byte
order as the PDU. To change byte order, define a method for this function.

# Example:
```julia
PDU.byteorder(::Type{MyPDU}, ::Val{:myfield}) = LITTLE_ENDIAN
```
"""
byteorder(T::Type{<:AbstractPDU}, fld) = byteorder(T)

"""
    length(::Type{T}, ::Val{s}, info::PDUInfo)

Length of field `s` in PDU of type `T`. Defaults to `nothing` (unknown) for vectors,
and `WireEncoded()` (stored in the PDU) for strings. The length is specified in
number of elements for vectors, and number of bytes for strings.

# Examples:
```julia
# length of field x is 4 bytes less than length of PDU
Base.length(::Type{MyPDU}, ::Val{:x}, info) = info.length - 4

# length of field x is given by the value of field n in the PDU
Base.length(::Type{MyPDU}, ::Val{:x}, info) = info.get(:n)

# length of field x is 16, and is zero-padded to size if necessary
Base.length(::Type{MyPDU}, ::Val{:x}, info) = PadTo(16)

# length of field x is variable and stored in the PDU using wire-encoding
Base.length(::Type{MyPDU}, ::Val{:x}, info) = WireEncoded()
```
"""
Base.length(T::Type{<:AbstractPDU}, V::Val, info) = fieldtype(T, V, info) <: AbstractString ? WireEncoded() : nothing

"""
    fieldtype(::Type{T}, ::Val{s}, info::PDUInfo)

Concrete type of field `s` in PDU of type `T`. Defaults to the type of the field
in the PDU. To specialize the type based on auxillary information in the PDU,
define a method for this function.

# Example:
```julia
# field x::Union{Int32,Int64} is Int32 if xtype is 4, Int64 otherwise
PDU.fieldtype(::Type{MyPDU}, ::Val{:x}, info) = info.get(:xtype) == 4 ? Int32 : Int64
```
"""
fieldtype(T::Type{<:AbstractPDU}, ::Val{V}, info) where V = Base.fieldtype(T, V)

## hooks

"""
    preencode(pdu::AbstractPDU)

Pre-encode hook. This function is called before encoding a PDU into a vector
of bytes. It may return a new PDU, which is then encoded instead of the original PDU.
The pre-encode hook should not change the type of the PDU.

# Example:
```julia
using Accessors, CRC32

# assumes MyPDU has field crc::UInt32 as the last field
function PDU.preencode(pdu::MyPDU)
  bytes = Vector{UInt8}(pdu; hooks=false)
  crc = crc32(bytes[1:end-4])
  @set pdu.crc = crc
end
```
"""
preencode(pdu::AbstractPDU) = pdu

"""
    postdecode(pdu::AbstractPDU)

Post-decode hook. This function is called after decoding a PDU from a vector
of bytes. It may return a new PDU, which is then returned instead of the original PDU.
The post-decode hook should not change the type of the PDU. The post-decode hook
may also be used to validate the PDU, and throw an error if the PDU is invalid.

# Example:
```julia
using CRC32

# assumes MyPDU has field crc::UInt32 as the last field
function PDU.postdecode(pdu::MyPDU)
  bytes = Vector{UInt8}(pdu; hooks=false)
  pdu.crc == crc32(bytes[1:end-4]) || throw(ErrorException("CRC check failed"))
  pdu
end
```
"""
postdecode(pdu::AbstractPDU) = pdu

## API

"""
    PDU.encode(pdu::AbstractPDU; hooks=true)

Encodes a PDU into a vector of bytes. If `hooks` is `true`, the pre-encode hook
is called before encoding the PDU.
"""
function encode(pdu::AbstractPDU; hooks=true)
  io = IOBuffer()
  try
    write(io, pdu; hooks)
    take!(io)
  finally
    close(io)
  end
end

"""
    write(io::IO, pdu::AbstractPDU; hooks=true)

Encodes a PDU into a vector of bytes written to stream `io`. If `hooks` is `true`,
the pre-encode hook is called before encoding the PDU.
"""
function Base.write(io::IO, pdu::T; hooks=true) where {T<:AbstractPDU}
  pdu = hooks ? preencode(pdu) : pdu
  info = PDUInfo(missing, s -> getfield(pdu, s))
  for f ∈ fieldnames(T)
    F = fieldtype(T, Val(f), info)
    htop = byteorder(T, Val(f))[1]
    if F <: Number
      write(io, htop(getfield(pdu, f)))
    elseif F <: NTuple{N,<:Number} where N
      write(io, htop.([getfield(pdu, f)...]))
    elseif F <: AbstractVector{<:Number} || F <: AbstractString
      nn = length(T, Val(f), info)
      if nn isa PadTo
        n = nn.n
        autopad = true
      else
        n = nn
        autopad = false
      end
      v = getfield(pdu, f)
      v = F <: AbstractString ? Vector{UInt8}(v) : htop.(v)
      if n === WireEncoded()
        varwrite(io, v)
      elseif n === nothing
        throw(ArgumentError("Length of field $(f) is unknown"))
      else
        if n === missing
          write(io, v)
        else
          length(v) > n && throw(ArgumentError("Value too long for field $(f) (expected $n, actual $(length(n)))"))
          if length(v) < n
            autopad || throw(ArgumentError("Value too short for field $(f) (expected $n, actual $(length(n)))"))
            v = vcat(v, zeros(eltype(v), n - length(v)))
          end
          write(io, v)
        end
      end
    elseif F != Nothing
      write(io, getfield(pdu, f))
    end
  end
  nothing
end

"""
    PDU.decode(buf::Vector{UInt8}, T::Type{<:AbstractPDU}; hooks=true)

Decodes a vector of bytes to give a PDU. If `hooks` is `true`, the post-decode hook
is called after decoding the PDU.
"""
function decode(buf::Vector{UInt8}, T::Type{<:AbstractPDU}; hooks=true)
  io = IOBuffer(buf)
  try
    read(io, T; nbytes=length(buf))
  finally
    close(io)
  end
end

"""
    read(io::IO, T::AbstractPDU; hooks=true)
    read(io::IO, T::AbstractPDU; nbytes, hooks=true)

Decodes a vector of bytes from stream `io` to give a PDU. If `nbytes` is specified,
the PDU is assumed to be of length `nbytes` bytes. If `hooks` is `true`, the
post-decode hook is called after decoding the PDU.
"""
function Base.read(io::IO, T::Type{<:AbstractPDU}; nbytes=missing, hooks=true)
  data = Pair{Symbol,Any}[]
  info = PDUInfo(nbytes, s -> lookup(data, s))
  for f ∈ fieldnames(T)
    F = fieldtype(T, Val(f), info)
    ptoh = byteorder(T, Val(f))[2]
    if F <: Number
      push!(data, f => ptoh(read(io, F)))
    elseif F <: NTuple{N,<:Number} where N
      push!(data, f => tuple(ptoh.([read(io, eltype(F)) for _ ∈ 1:fieldcount(F)])...))
    elseif F <: AbstractVector{<:Number} || F <: AbstractString
      nn = length(T, Val(f), info)
      n = nn isa PadTo ? nn.n : nn
      V = F <: AbstractString ? UInt8 : eltype(F)
      v = n === WireEncoded() ? varread(io, V) : V[read(io, V) for _ ∈ 1:n]
      push!(data, f => F <: AbstractString ? strip(String(v), ['\0']) : ptoh.(v))
    elseif F == Nothing
      push!(data, f => nothing)
    else
      n = length(T, Val(f), PDUInfo(nbytes, s -> lookup(data, s)))
      push!(data, f => read(io, F; nbytes=something(n, missing)))
    end
  end
  pdu = T(map(kv -> kv[2], data)...)
  hooks ? postdecode(pdu) : pdu
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
