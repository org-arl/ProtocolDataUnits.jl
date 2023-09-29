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
Base.@kwdef struct EthernetFrame <: PDU
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
bytes = Vector{UInt8}(frame)

# convert back to Ethernet frame
decoded = EthernetFrame(bytes)

# check that they are the same
@assert frame == decoded
```

The package can do much more, including nested PDUs, wire-encoding, CRC computation, etc.

## Basic usage

A PDU is declared as a `struct` subtyped from `PDU`. It may contain fields of the following types:

* Numeric types (various sized integers and floats)
* `NTuple` of numeric types
* `AbstractVector` of numeric types
* `AbstractString`
* Other `PDU`s
* Any other data type `T` that supports `read(::IO, ::Type{T})` and `write(::IO, ::T)`

The size (in bytes) of numeric types and tuples of numeric types is known. However, vectors, strings and other data types may have variable sizes. If the size is unknown, a wire-encoded size/length field is implicitly added to the PDU representation when encoding it, and is used during decoding to infer size/length. Alternatively, the size/length of specific fields may be declared by defining a `length()` for specific fields in a PDU.

By default, network byte order (big endian) is used for multi-byte numeric values. That may be overridden for the PDU or for specific fields by declaring a [`byteorder()`](@ref).

PDUs are encoded into bytes in one of two ways:
```julia
bytes = Vector{UInt8}(pdu)  # returns a vector of bytes
write(io, pdu)              # writes bytes to an IOStream
```

PDUs are decoded from bytes in one of two ways:
```julia
pdu = MyPDU(bytes)          # creates a MyPDU from bytes
pdu = read(io, MyPDU)       # creates a MyPDU by reading bytes from an IOStream
```

Usage is best illustrated through a series of examples.

## PDUs with fixed length fields

Lets define a simple PDU where all field sizes are known:
```julia
struct MySimplePDU <: PDU
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
bytes = Vector{UInt8}(pdu)
```
This yields `bytes = [0x00, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x05, 0x40, 0xc0, 0x00, 0x00, 0x40, 0x1c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]`.

We can change the byte ordering for the PDU to little-endian:
```julia
ProtocolDataUnits.byteorder(::Type{MySimplePDU}) = LITTLE_ENDIAN
```

Now:
```julia
bytes = Vector{UInt8}(pdu)
```
yields `[0x01, 0x00, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1c, 0x40]`.

The bytes can be converted back to a PDU:
```julia
pdu2 = MySimplePDU(bytes)
```
and we can verify that the recovered PDU has the same contents as the original: `@assert pdu == pdu2`.

## PDUs with variable length fields

We can define a slightly more complex PDU containing strings of potentially unknown length:
```julia
struct MyLessSimplePDU <: PDU
  a::Int16
  b::String
end

pdu = MyLessSimplePDU(1, "hello world!")
```
We can convert the PDU to bytes and back:
```julia
bytes = Vector{UInt8}(pdu)
pdu2 = MyLessSimplePDU(bytes)
@assert pdu == pdu2
```
The PDU will have a size of 15 bytes (2 bytes for `a`, 12 bytes for `b = "hello world!"`, and 1 byte to store the length of `b`). The length of the string is encoded as a variable length number using wire-encoding.

If we knew the maximum length of the string beforehand (say 14 bytes), and wanted a fixed length PDU (14+2=16 bytes), we could declare the length:
```julia
Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = 14

bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 16

pdu2 = MyLessSimplePDU(bytes)
@assert pdu == pdu2
```
Since the string `b = "hello world!"` occupies only 12 bytes, it is padded with two null (`'\0`) bytes. If the length of `b` was larger than the allocated length, the string would be truncated:
```julia
pdu = MyLessSimplePDU(1, "hello world! how are you?")

bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 16

pdu2 = MyLessSimplePDU(bytes)
@assert pdu2.b == "hello world! h"
```

We could also support variable length strings without having to store the length in the PDU if we knew the size of the PDU while decoding. To do so, we need to declare that the length of the string must be 2 bytes less than the length of the whole PDU:
```julia
Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = info.length - 2
```
The `info` object provides information on the PDU being encoded or decoded. `info.length` tells us the size of the PDU in bytes, if known (otherwise it is `missing`). Now, we can encode arbitrary length strings in our PDU without the overhead of storing the length of the string:
```julia
bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 2 + length("hello world! how are you?")

pdu2 = MyLessSimplePDU(bytes)
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

bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 2 + 2*6

pdu2 = MyLessSimplePDU(bytes)
@assert pdu2.b == "hello world!"
```
Had we set an `a` that is too small or big, the string would have been truncated or null padded:
```julia
# string is null padded to 16 bytes
pdu = MyLessSimplePDU(8, "hello world!")
bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 2 + 2*8
pdu2 = MyLessSimplePDU(bytes)
@assert pdu2.b == "hello world!"

# string is truncated to 8 bytes
pdu = MyLessSimplePDU(4, "hello world!")
bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 2 + 2*4
pdu2 = MyLessSimplePDU(bytes)
@assert pdu2.b == "hello wo"
```

Variable length vector fields work exactly in the same way, with length being defined as the number of elements in the vector (not number of bytes):
```julia
struct MyVectorPDU <: PDU
  a::Int16
  b::Vector{Float64}
end

# vector length is in number of Float64, but info.length is in number of bytes
Base.length(::Type{MyVectorPDU}, ::Val{:b}, info) = (info.length - 2) ÷ sizeof(Float64)

pdu = MyVectorPDU(1, [1.0, 2.0, 3.0])
bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 2 + 3 * sizeof(Float64)
pdu2 = MyVectorPDU(bytes)
@assert pdu == pdu2
```

## PDUs with nested PDUs

We can even nest PDUs:
```julia
struct InnerPDU <: PDU
  a::Int8
  b::Float32
end

struct OuterPDU <: PDU
  x::Int16
  y::InnerPDU
  z::Int8
end

pdu = OuterPDU(1, InnerPDU(2, 3f0), 4)
```
and encode and decode them effortlessly:
```julia
bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 2 + (1 + 4) + 1

pdu2 = OuterPDU(bytes)

@assert pdu2.y == pdu.y   # inner PDU matches
@assert pdu == pdu       # so does the outer PDU2
```

We can infer sizes of variable length fields in nested PDUs too:
```julia
struct InnerPDU2 <: PDU
  a::Int8
  b::String
end

struct OuterPDU2 <: PDU
  x::Int16
  y::InnerPDU2
  z::Int8
end

Base.length(::Type{InnerPDU2}, ::Val{:b}, info) = info.length - 1
Base.length(::Type{OuterPDU2}, ::Val{:y}, info) = info.length - 3

pdu = OuterPDU2(1, InnerPDU2(2, "hello world!"), 4)

bytes = Vector{UInt8}(pdu)
@assert length(bytes) == 2 + (1 + 12) + 1

pdu2 = OuterPDU2(bytes)

@assert pdu2.y == pdu.y
@assert pdu == pdu2
```
