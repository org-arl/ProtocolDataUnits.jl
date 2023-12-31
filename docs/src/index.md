# ProtocolDataUnits.jl
**Encoders and decoders for Protocol Data Units (PDUs)**

```@meta
CurrentModule = ProtocolDataUnits
```

[PDUs](https://en.wikipedia.org/wiki/Protocol_data_unit) encode information as byte streams that can be transmitted across a network or stored. `ProtocolDataUnits.jl` simplifies the process of encoding and decoding information as PDUs in a declarative way.

## Getting started

The usage of the package is best illustrated with a simple example:

```julia
using ProtocolDataUnits

# define PDU format
Base.@kwdef struct EthernetFrame <: AbstractPDU
  dstaddr::NTuple{6,UInt8}    # fixed length
  srcaddr::NTuple{6,UInt8}    # fixed length
  ethtype::UInt16             # fixed length
  payload::Vector{UInt8}      # variable length
  crc::UInt32 = 0             # fixed length
end

# declare that the variable length of the payload can be computed
Base.length(::Type{EthernetFrame}, ::Val{:payload}, info) = info.length - 18

# create an Ethernet frame
frame = EthernetFrame(
  dstaddr = (0x01, 0x02, 0x03, 0x04, 0x05, 0x06),
  srcaddr = (0x11, 0x12, 0x13, 0x14, 0x15, 0x16),
  ethtype = 0x0800,
  payload = [0x01, 0x02, 0x03, 0x04, 0x11, 0x12, 0x13, 0x14]
)

# convert to a byte array
bytes = PDU.encode(frame)

# convert back to Ethernet frame
decoded = PDU.decode(bytes, EthernetFrame)

# check that they are the same
@assert frame == decoded
```

The package can do much more, including nested PDUs, wire-encoding, CRC computation, etc.

## Basic usage

A PDU is declared as a `struct` subtyped from `PDU`. It may contain fields of the following types:

* `Number` types (various sized integers and floats)
* `NTuple` of `Number` types
* `AbstractVector` of `Number` types
* `AbstractString`
* Other `PDU`s
* `Nothing`
* Any other data type `T` that supports `read(::IO, ::Type{T})` and `write(::IO, ::T)`
* `Union` of any of the above types

The size (in bytes) of numeric types, tuples of numeric types and `nothing` is known. However, vectors, strings and other data types may have variable sizes. If the size is unknown, a wire-encoded size/length field is implicitly added to the PDU representation when encoding it, and is used during decoding to infer size/length. Alternatively, the size/length of specific fields may be declared by defining a `length()` for specific fields in a PDU.

By default, network byte order (big endian) is used for multi-byte numeric values. That may be overridden for the PDU or for specific fields by declaring a [`byteorder()`](@ref).

When a field is of a union type, a `fieldtype()` definition must be available to resolve which concrete type to expect when decoding a PDU from bytes.

PDUs are encoded into bytes in one of two ways:
```julia
bytes = PDU.encode(pdu)         # returns a vector of bytes
write(io, pdu)                  # writes bytes to an IOStream
```

PDUs are decoded from bytes in one of two ways:
```julia
pdu = PDU.decode(bytes, MyPDU)  # creates a MyPDU from bytes
pdu = read(io, MyPDU)           # creates a MyPDU by reading bytes from an IOStream
```

Usage is best illustrated through a series of examples.

## PDUs with fixed length fields

Lets define a simple PDU where all field sizes are known:
```julia
struct MySimplePDU <: AbstractPDU
  a::Int16
  b::UInt8
  c::UInt8
  d::NTuple{2,Int32}
  e::Float32
  f::Float64
end

pdu = MySimplePDU(1, 2, 3, (4,5), 6f0, 7.0)
```
and then encode it into bytes:
```julia
bytes = PDU.encode(pdu)
```
This yields `bytes = [0x00, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x05, 0x40, 0xc0, 0x00, 0x00, 0x40, 0x1c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]`.

We can change the byte ordering for the PDU to little-endian:
```julia
PDU.byteorder(::Type{MySimplePDU}) = LITTLE_ENDIAN
```

Now:
```julia
bytes = PDU.encode(pdu)
```
yields `[0x01, 0x00, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1c, 0x40]`.

The bytes can be converted back to a PDU:
```julia
pdu2 = PDU.decode(bytes, MySimplePDU)
```
and we can verify that the recovered PDU has the same contents as the original: `@assert pdu == pdu2`.

## PDUs with variable length fields

We can define a slightly more complex PDU containing strings of potentially unknown length:
```julia
struct MyLessSimplePDU <: AbstractPDU
  a::Int16
  b::String
end

pdu = MyLessSimplePDU(1, "hello world!")
```
We can convert the PDU to bytes and back:
```julia
bytes = PDU.encode(pdu)
pdu2 = PDU.decode(bytes, MyLessSimplePDU)
@assert pdu == pdu2
```
The PDU will have a size of 15 bytes (2 bytes for `a`, 12 bytes for `b = "hello world!"`, and 1 byte to store the length of `b`). The length of the string is encoded as a variable length number using wire-encoding.

If we knew the maximum length of the string beforehand (say 14 bytes), and wanted a fixed length PDU (14+2=16 bytes), we could declare the length:
```julia
Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = PadTo(14)

bytes = PDU.encode(pdu)
@assert length(bytes) == 16

pdu2 = PDU.decode(bytes, MyLessSimplePDU)
@assert pdu == pdu2
```
Since the string `b = "hello world!"` occupies only 12 bytes, it is padded with two null (`'\0`) bytes. If the length of `b` was larger than the allocated length, the encoding will throw an exception.

We could also support variable length strings without having to store the length in the PDU if we knew the size of the PDU while decoding. To do so, we need to declare that the length of the string must be 2 bytes less than the length of the whole PDU:
```julia
Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = info.length - 2
```
The `info` object provides information on the PDU being encoded or decoded. `info.length` tells us the size of the PDU in bytes, if known (otherwise it is `missing`). Now, we can encode arbitrary length strings in our PDU without the overhead of storing the length of the string:
```julia
bytes = PDU.encode(pdu)
@assert length(bytes) == 2 + length("hello world! how are you?")

pdu2 = PDU.decode(bytes, MyLessSimplePDU)
@assert pdu2.b == "hello world! how are you?"
@assert pdu == pdu2
```

We can also define field lengths that depend on the value of preceding fields. For example, if we happened to know that the length of string `b` is always `2a`, we can declare:
```julia
Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = 2 * info.get(:a)
```
Here `info.get()` provides us access to fields that are decoded earlier in the byte stream.
```julia
pdu = MyLessSimplePDU(6, "hello world!")

bytes = PDU.encode(pdu)
@assert length(bytes) == 2 + 2*6

pdu2 = PDU.decode(bytes, MyLessSimplePDU)
@assert pdu2.b == "hello world!"
```
Had we set an `a` that is too small or big, we would get an exception complaining about the length. If we wanted the string to be null padded automatically, we could specify that:
```julia
Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = PadTo(2 * info.get(:a))

# string is null padded to 16 bytes
pdu = MyLessSimplePDU(8, "hello world!")
bytes = PDU.encode(pdu)
@assert length(bytes) == 2 + 2*8
pdu2 = PDU.decode(bytes, MyLessSimplePDU)
@assert pdu2.b == "hello world!"
```

Variable length vector fields work exactly in the same way, with length being defined as the number of elements in the vector (not number of bytes). However, for vectors, the default length is `nothing` (unknown), and so we need an explicit declaration to change it to wire-encoding if we want the vector length to be stored in the PDU:
```julia
struct MyVectorPDU <: AbstractPDU
  a::Int16
  b::Vector{Float64}
end

Base.length(::Type{MyVectorPDU2}, ::Val{:b}, info) = WireEncoded()

# vector length is in number of Float64, but info.length is in number of bytes
Base.length(::Type{MyVectorPDU}, ::Val{:b}, info) = (info.length - 2) ÷ sizeof(Float64)

pdu = MyVectorPDU(1, [1.0, 2.0, 3.0])
bytes = PDU.encode(pdu)
@assert length(bytes) == 2 + 3 * sizeof(Float64)
pdu2 = PDU.decode(bytes, MyVectorPDU)
@assert pdu == pdu2
```

## PDUs with nested PDUs

We can even nest PDUs:
```julia
struct InnerPDU <: AbstractPDU
  a::Int8
  b::Float32
end

struct OuterPDU <: AbstractPDU
  x::Int16
  y::InnerPDU
  z::Int8
end

pdu = OuterPDU(1, InnerPDU(2, 3f0), 4)
```
and encode and decode them effortlessly:
```julia
bytes = PDU.encode(pdu)
@assert length(bytes) == 2 + (1 + 4) + 1

pdu2 = PDU.decode(bytes, OuterPDU)

@assert pdu2.y == pdu.y   # inner PDU matches
@assert pdu == pdu       # so does the outer PDU2
```

We can infer sizes of variable length fields in nested PDUs too:
```julia
struct InnerPDU2 <: AbstractPDU
  a::Int8
  b::String
end

struct OuterPDU2 <: AbstractPDU
  x::Int16
  y::InnerPDU2
  z::Int8
end

Base.length(::Type{InnerPDU2}, ::Val{:b}, info) = info.length - 1
Base.length(::Type{OuterPDU2}, ::Val{:y}, info) = info.length - 3

pdu = OuterPDU2(1, InnerPDU2(2, "hello world!"), 4)

bytes = PDU.encode(pdu)
@assert length(bytes) == 2 + (1 + 12) + 1

pdu2 = PDU.decode(bytes, OuterPDU2)

@assert pdu2.y == pdu.y
@assert pdu == pdu2
```

## PDUs with dependent fields

A PDU may contain a field that is dependent on another field. We saw in an example above, where `MyVectorPDU` has field `a` which specified the number of elements in field `b`. A good way to ensure consistency is to populate dependent fields at construction:
```julia
struct MyVectorPDU2 <: AbstractPDU
  a::Int16
  b::Vector{Float64}
end

MyVectorPDU2(b::Vector{Float64}) = MyVectorPDU2(length(b), b)

pdu = MyVectorPDU2([1.0, 2.0, 3.0])
@assert pdu.a == 3
```

However, since vector `b` can be mutated after construction, the consistency at construction does not guarantee consistency at encoding. We could enforce consistency an encoding using a pre-encode hook:
```julia
using Accessors

function PDU.preencode(pdu::MyVectorPDU2)
  @set pdu.a = length(pdu.b)
end
```
This will ensure that field `a` is populated correctly at time of encoding:
```julia
push!(pdu.b, 4.0)           # add 4th element to b
@assert pdu.a == 3          # now pdu is inconsistent, since pdu.a == 3

bytes = PDU.encode(pdu)
@assert bytes[2] == 4       # encoded bytes show 4 elements correctly

pdu2 = PDU.decode(bytes, MyVectorPDU2)
@assert pdu2.a == 4         # decoded pdu also shows 4 elements correctly
@assert length(pdu2.b) == 4 # and it indeed contains 4 elements
```

## PDUs with CRCs

Sometimes we may want to pre-process PDUs to compute CRC, or post-process them to modify their content or perform CRC checks. To see, how we can do this, let's go back to our example of `EthernetFrame` and define a pre-encoding hook to compute CRC, and a post-decoding hook to check the CRC:
```julia
using CRC32

function PDU.preencode(pdu::EthernetFrame)
  bytes = PDU.encode(pdu; hooks=false)   # encode without computing CRC
  crc = crc32(bytes[1:end-4])               # compute CRC
  @set pdu.crc = crc                        # make a new frame with CRC filled in
end

function PDU.postdecode(pdu::EthernetFrame)
  bytes = PDU.encode(pdu; hooks=false)   # re-encode the frame for CRC computation
  pdu.crc == crc32(bytes[1:end-4]) || throw(ErrorException("CRC check failed"))
  pdu                                       # return unaltered pdu if CRC OK
end

frame = EthernetFrame(
  dstaddr = (0x01, 0x02, 0x03, 0x04, 0x05, 0x06),
  srcaddr = (0x11, 0x12, 0x13, 0x14, 0x15, 0x16),
  ethtype = 0x0800,
  payload = [0x01, 0x02, 0x03, 0x04, 0x11, 0x12, 0x13, 0x14]
)

buf = PDU.encode(frame)
frame2 = EthernetFrame(buf)
@assert frame.payload == frame2.payload
```
However, if there was an error in the buffer, the CRC check would fail:
```julia
buf[5] += 1
EthernetFrame(buf)      # should throw an exception
```

## PDUs with union types

Consider a PDU with the first byte specifying the header length, which is followed by a header and then a payload. Two versions of headers may be used, depending on the application needs, with the header length allowing the receiver to differentiate between the two. We can define the PDU with a header field that uses a union type:
```julia
struct Header_v1 <: AbstractPDU
  src::UInt32
  dst::UInt32
  port::UInt8
end

struct Header_v2 <: AbstractPDU
  src::UInt64
  dst::UInt64
  port::UInt16
end

struct AppPDU <: AbstractPDU
  hdrlen::UInt8
  hdr::Union{Header_v1,Header_v2}
  payload::Vector{UInt8}
end

# convenience constructors to auto-populate hdrlen
AppPDU(hdr::Header_v1, payload) = AppPDU(9, hdr, payload)
AppPDU(hdr::Header_v2, payload) = AppPDU(18, hdr, payload)

# hdr is v2 if hdrlen field matches it's size, otherwise default to v1
function PDU.fieldtype(::Type{AppPDU}, ::Val{:hdr}, info)
  info.get(:hdrlen) == 18 && return Header_v2
  Header_v1
end

# payload length is the frame length less the header
Base.length(::Type{AppPDU}, ::Val{:payload}, info) = info.length - info.get(:hdrlen) - 1
```

We can now create either type of PDU and decode it without having a priori knowledge of the header type:
```julia
# v1 header
pdu = AppPDU(Header_v1(1, 2, 3), UInt8[4, 5, 6])
bytes = PDU.encode(pdu)
@assert length(bytes) == 13
pdu2 = PDU.decode(bytes, AppPDU)
@assert pdu.hdr isa Header_v1
@assert pdu == pdu2

# v2 header
pdu = AppPDU(Header_v2(1, 2, 3), UInt8[4, 5, 6])
bytes = PDU.encode(pdu)
@assert length(bytes) == 22
pdu2 = PDU.decode(bytes, AppPDU)
@assert pdu.hdr isa Header_v2
@assert pdu == pdu2
```

## PDUs as parametrized types

For type stability, it is often desirable not to use a union type as a field in the `struct`, but instead use a parametrized `struct`. We support parametrized PDUs too:
```julia
struct ParamAppPDU{T} <: AbstractPDU
  hdrlen::UInt8
  hdr::T
  payload::Vector{UInt8}
end

# convenience constructors to auto-populate hdrlen
ParamAppPDU(hdr::Header_v1, payload) = ParamAppPDU{Header_v1}(9, hdr, payload)
ParamAppPDU(hdr::Header_v2, payload) = ParamAppPDU{Header_v2}(18, hdr, payload)

# hdr is v2 if hdrlen field matches it's size, otherwise default to v1
function PDU.fieldtype(::Type{<:ParamAppPDU}, ::Val{:hdr}, info)
  info.get(:hdrlen) == 18 && return Header_v2
  Header_v1
end

# payload length is the frame length less the header
Base.length(::Type{<:ParamAppPDU}, ::Val{:payload}, info) = info.length - info.get(:hdrlen) - 1

pdu = ParamAppPDU(Header_v1(1, 2, 3), UInt8[4, 5, 6])
bytes = PDU.encode(pdu)
@assert length(bytes) == 13
pdu2 = PDU.decode(bytes, ParamAppPDU)
@assert pdu.hdr isa Header_v1
@assert pdu == pdu2
```

## PDUs with optional fields

Extending the idea of union fields, we can define PDUs with optional fields:
```julia
struct App2PDU <: AbstractPDU
  hdrlen::UInt8
  hdr::Union{Header_v1,Header_v2,Nothing}
  payload::Vector{UInt8}
end

# convenience constructor to auto-populate hdrlen
function App2PDU(; hdr=nothing, payload=UInt8[])
  hdrlen = 0
  hdr isa Header_v1 && (hdrlen = 9)
  hdr isa Header_v2 && (hdrlen = 18)
  App2PDU(hdrlen, hdr, payload)
end

# hdr is v1, v2 or nothing, depending on hdrlen
function PDU.fieldtype(::Type{App2PDU}, ::Val{:hdr}, info)
  info.get(:hdrlen) == 9 && return Header_v1
  info.get(:hdrlen) == 18 && return Header_v2
  Nothing
end

# payload length is the frame length less the header
Base.length(::Type{App2PDU}, ::Val{:payload}, info) = info.length - info.get(:hdrlen) - 1
```
and work PDUs with or without headers:
```julia
# v1 header
pdu = App2PDU(hdr=Header_v1(1, 2, 3), payload=UInt8[4, 5, 6])
bytes = PDU.encode(pdu)
@assert length(bytes) == 13
pdu2 = PDU.decode(bytes, App2PDU)
@assert pdu.hdr isa Header_v1
@assert pdu == pdu2

# no header
pdu = App2PDU(payload=UInt8[4, 5, 6, 7, 8, 9])
bytes = PDU.encode(pdu)
@assert length(bytes) == 7
pdu2 = PDU.decode(bytes, App2PDU)
@assert pdu.hdr === nothing
@assert pdu == pdu2
```
