using Test
using ProtocolDataUnits
using Accessors
using CRC32

@testset "basic" begin

  Base.@kwdef struct Eth2 <: AbstractPDU
    dstaddr::NTuple{6,UInt8} = (1,2,3,4,5,6)
    srcaddr::NTuple{6,UInt8} = (6,5,4,3,2,1)
    ethtype::UInt16 = 0x800
    payload::Vector{UInt8} = UInt8[]
    crc::UInt32 = 0xdeadbeef
  end

  f1 = Eth2()
  buf = Vector{UInt8}(f1)
  f2 = Eth2(buf)

  @test f1 == f2
  @test length(buf) == 19
  @test buf == [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x08, 0x00, 0x00, 0xde, 0xad, 0xbe, 0xef]

  f1 = Eth2(payload = UInt8.(collect(1:127)))
  buf = Vector{UInt8}(f1)
  f2 = Eth2(buf)

  @test f1 == f2
  @test length(buf) == 19 + 127

  f1 = Eth2(payload = UInt8.(collect(1:255)))
  buf = Vector{UInt8}(f1)
  f2 = Eth2(buf)

  @test f1 == f2
  @test length(buf) == 20 + 255

  Base.length(::Type{Eth2}, ::Val{:payload}, info) = info.length - 18

  f1 = Eth2()
  buf = Vector{UInt8}(f1)
  f2 = Eth2(buf)

  @test f1 == f2
  @test length(buf) == 18
  @test buf == [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x08, 0x00, 0xde, 0xad, 0xbe, 0xef]

  PDU.byteorder(::Type{Eth2}) = LITTLE_ENDIAN

  f1 = Eth2()
  buf = Vector{UInt8}(f1)
  f2 = Eth2(buf)

  @test f1 == f2
  @test length(buf) == 18
  @test buf == [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00, 0x08, 0xef, 0xbe, 0xad, 0xde]

  f1 = Eth2(payload = UInt8.(collect(1:127)))
  buf = Vector{UInt8}(f1)
  f2 = Eth2(buf)

  @test f1 == f2
  @test length(buf) == 18 + 127

  f1 = Eth2(payload = UInt8.(collect(1:255)))
  buf = Vector{UInt8}(f1)
  f2 = Eth2(buf)

  @test f1 == f2
  @test length(buf) == 18 + 255

end

@testset "strings" begin

  struct TestPDU <: AbstractPDU
    n::UInt8
    s::String
  end

  f1 = TestPDU(0x12, "hello")
  buf = Vector{UInt8}(f1)
  f2 = TestPDU(buf)

  @test f1 == f2
  @test length(buf) == 7
  @test buf == [0x12, 0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

  Base.length(::Type{TestPDU}, ::Val{:s}, info) = info.length - 1

  f1 = TestPDU(0x12, "hello")
  buf = Vector{UInt8}(f1)
  f2 = TestPDU(buf)

  @test f1 == f2
  @test length(buf) == 6
  @test buf == [0x12, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

  Base.length(::Type{TestPDU}, ::Val{:s}, info) = info.get(:n)

  f1 = TestPDU(0x07, "hello")
  buf = Vector{UInt8}(f1)
  f2 = TestPDU(buf)

  @test f1 == f2
  @test length(buf) == 8
  @test buf == [0x07, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x00]

  f2 = read(IOBuffer(buf), TestPDU)

  @test f1 == f2

end

@testset "nested" begin

  struct InnerPDU3 <: AbstractPDU
    a::UInt16
    b::String
  end

  struct OuterPDU3 <: AbstractPDU
    n::UInt16
    inner::InnerPDU3
  end

  f1in = InnerPDU3(0x1234, "hello")
  f1 = OuterPDU3(0x5678, f1in)
  buf = Vector{UInt8}(f1)
  f2 = OuterPDU3(buf)

  @test f1.n == f2.n
  @test f1.inner == f2.inner
  @test f1 == f2
  @test length(buf) == 10
  @test buf == [0x56, 0x78, 0x12, 0x34, 0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

  Base.length(::Type{InnerPDU3}, ::Val{:b}, info) = info.get(:a)

  f1in = InnerPDU3(0x05, "hello")
  f1 = OuterPDU3(0x5678, f1in)
  buf = Vector{UInt8}(f1)
  f2 = OuterPDU3(buf)

  @test f1.n == f2.n
  @test f1.inner == f2.inner
  @test f1 == f2
  @test length(buf) == 9
  @test buf == [0x56, 0x78, 0x00, 0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

  Base.length(::Type{InnerPDU3}, ::Val{:b}, info) = info.length - 2
  Base.length(::Type{OuterPDU3}, ::Val{:inner}, info) = info.length - 2

  f1in = InnerPDU3(0x1234, "hello")
  f1 = OuterPDU3(0x5678, f1in)
  buf = Vector{UInt8}(f1)
  f2 = OuterPDU3(buf)

  @test f1.n == f2.n
  @test f1.inner == f2.inner
  @test f1 == f2
  @test length(buf) == 9
  @test buf == [0x56, 0x78, 0x12, 0x34, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

end

@testset "hooks" begin

  struct ChecksumPDU <: AbstractPDU
    a::NTuple{16,UInt64}
    crc::UInt32
  end

  function PDU.preencode(pdu::ChecksumPDU)
    bytes = Vector{UInt8}(pdu; hooks=false)
    crc = crc32(bytes[1:end-4])
    @set pdu.crc = crc
  end

  function PDU.postdecode(pdu::ChecksumPDU)
    bytes = Vector{UInt8}(pdu; hooks=false)
    pdu.crc == crc32(bytes[1:end-4]) || throw(ErrorException("CRC check failed"))
    pdu
  end

  f1 = ChecksumPDU((1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16), 0xdeadbeef)
  buf = Vector{UInt8}(f1)
  f2 = ChecksumPDU(buf)
  @test f1.a == f2.a
  @test f2.crc != 0xdeadbeef

  buf[5] += 1
  @test_throws ErrorException ChecksumPDU(buf)

end

@testset "nothings" begin

  Base.@kwdef struct NothingPDU <: AbstractPDU
    a::Int64
    b::Nothing = nothing
    c::Nothing = nothing
    d::Float64
  end

  f1 = NothingPDU(a=1, d=2.0)
  buf = Vector{UInt8}(f1)
  @test length(buf) == 16

  f2 = NothingPDU(buf)
  @test f1 == f2

end

@testset "unions" begin

  Base.@kwdef struct UnionPDU1 <: AbstractPDU
    a::Int64 = 0
    b::Nothing = nothing
    c::Union{Nothing,Int64} = nothing
    d::Float64
  end

  PDU.fieldtype(::Type{UnionPDU1}, ::Val{:c}, info) = Nothing

  f1 = UnionPDU1(a=1, d=2.0)
  buf = Vector{UInt8}(f1)
  @test length(buf) == 16

  f2 = UnionPDU1(buf)
  @test f1 == f2

  PDU.fieldtype(::Type{UnionPDU1}, ::Val{:c}, info) = info.get(:a) == 1 ? Int64 : Nothing

  f1 = UnionPDU1(d=2.0)
  buf = Vector{UInt8}(f1)
  @test length(buf) == 16

  f2 = UnionPDU1(buf)
  @test f1 == f2

  f1 = UnionPDU1(a=1, c=21, d=2.0)
  buf = Vector{UInt8}(f1)
  @test length(buf) == 24

  f2 = UnionPDU1(buf)
  @test f1 == f2

  struct InnerPDU4 <: AbstractPDU
    a::Int8
    b::Float32
  end

  struct InnerPDU5 <: AbstractPDU
    a::Int16
    b::Float64
  end

  struct UnionPDU2 <: AbstractPDU
    a::Int8
    b::Union{InnerPDU4,InnerPDU5}
  end

  UnionPDU2(b::InnerPDU4) = UnionPDU2(1, b)
  UnionPDU2(b::InnerPDU5) = UnionPDU2(2, b)

  PDU.fieldtype(::Type{UnionPDU2}, ::Val{:b}, info) = info.get(:a) == 1 ? InnerPDU4 : InnerPDU5

  f1 = UnionPDU2(InnerPDU4(2, 3f0))
  buf = Vector{UInt8}(f1)
  @test length(buf) == 6
  f2 = UnionPDU2(buf)
  @test f1 == f2

  f1 = UnionPDU2(InnerPDU5(2, 3.0))
  buf = Vector{UInt8}(f1)
  @test length(buf) == 11
  f2 = UnionPDU2(buf)
  @test f1 == f2

end

@testset "docs" begin

  Base.@kwdef struct EthernetFrame <: AbstractPDU
    dstaddr::NTuple{6,UInt8}    # fixed length
    srcaddr::NTuple{6,UInt8}    # fixed length
    ethtype::UInt16             # fixed length
    payload::Vector{UInt8}      # variable length
    crc::UInt32 = 0             # fixed length
  end

  Base.length(::Type{EthernetFrame}, ::Val{:payload}, info) = info.length - 18

  frame = EthernetFrame(
    dstaddr = (0x01, 0x02, 0x03, 0x04, 0x05, 0x06),
    srcaddr = (0x11, 0x12, 0x13, 0x14, 0x15, 0x16),
    ethtype = 0x0800,
    payload = [0x01, 0x02, 0x03, 0x04, 0x11, 0x12, 0x13, 0x14]
  )

  bytes = Vector{UInt8}(frame)
  decoded = EthernetFrame(bytes)
  @test frame == decoded

  struct MySimplePDU <: AbstractPDU
    a::Int16
    b::UInt8
    c::UInt8
    d::NTuple{2,Int32}
    e::Float32
    f::Float64
  end

  pdu = MySimplePDU(1, 2, 3, (4,5), 6f0, 7.0)
  bytes = Vector{UInt8}(pdu)
  @test bytes == UInt8[0x00, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x05, 0x40, 0xc0, 0x00, 0x00, 0x40, 0x1c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

  PDU.byteorder(::Type{MySimplePDU}) = LITTLE_ENDIAN

  bytes = Vector{UInt8}(pdu)
  @test bytes == UInt8[0x01, 0x00, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1c, 0x40]

  pdu2 = MySimplePDU(bytes)
  @test pdu == pdu2

  struct MyLessSimplePDU <: AbstractPDU
    a::Int16
    b::String
  end

  pdu = MyLessSimplePDU(1, "hello world!")
  bytes = Vector{UInt8}(pdu)
  pdu2 = MyLessSimplePDU(bytes)
  @test pdu == pdu2

  Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = 14

  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 16

  pdu2 = MyLessSimplePDU(bytes)
  @test pdu == pdu2

  pdu = MyLessSimplePDU(1, "hello world! how are you?")

  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 16

  pdu2 = MyLessSimplePDU(bytes)
  @test pdu2.b == "hello world! h"

  Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = info.length - 2

  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 2 + length("hello world! how are you?")

  pdu2 = MyLessSimplePDU(bytes)
  @test pdu2.b == "hello world! how are you?"
  @test pdu == pdu2

  Base.length(::Type{MyLessSimplePDU}, ::Val{:b}, info) = 2 * info.get(:a)

  pdu = MyLessSimplePDU(6, "hello world!")

  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 2 + 2*6

  pdu2 = MyLessSimplePDU(bytes)
  @test pdu2.b == "hello world!"

  pdu = MyLessSimplePDU(8, "hello world!")
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 2 + 2*8
  pdu2 = MyLessSimplePDU(bytes)
  @test pdu2.b == "hello world!"

  pdu = MyLessSimplePDU(4, "hello world!")
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 2 + 2*4
  pdu2 = MyLessSimplePDU(bytes)
  @test pdu2.b == "hello wo"

  struct MyVectorPDU <: AbstractPDU
    a::Int16
    b::Vector{Float64}
  end

  Base.length(::Type{MyVectorPDU}, ::Val{:b}, info) = (info.length - 2) ÷ sizeof(Float64)

  pdu = MyVectorPDU(1, [1.0, 2.0, 3.0])
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 2 + 3 * sizeof(Float64)
  pdu2 = MyVectorPDU(bytes)
  @test pdu == pdu2

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

  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 2 + (1 + 4) + 1

  pdu2 = OuterPDU(bytes)

  @test pdu2.y == pdu.y   # inner PDU matches
  @test pdu == pdu2       # so does the outer PDU

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

  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 2 + (1 + 12) + 1

  pdu2 = OuterPDU2(bytes)

  @test pdu2.y == pdu.y
  @test pdu == pdu2

  struct MyVectorPDU2 <: AbstractPDU
    a::Int16
    b::Vector{Float64}
  end

  MyVectorPDU2(b::Vector{Float64}) = MyVectorPDU2(length(b), b)

  pdu = MyVectorPDU2([1.0, 2.0, 3.0])
  @test pdu.a == 3

  function PDU.preencode(pdu::MyVectorPDU2)
    @set pdu.a = length(pdu.b)
  end

  push!(pdu.b, 4.0)
  @test pdu.a == 3

  bytes = Vector{UInt8}(pdu)
  @test bytes[2] == 4

  pdu2 = MyVectorPDU2(bytes)
  @test pdu2.a == 4
  @test length(pdu2.b) == 4

  function PDU.preencode(pdu::EthernetFrame)
    bytes = Vector{UInt8}(pdu; hooks=false)
    crc = crc32(bytes[1:end-4])
    @set pdu.crc = crc
  end

  function PDU.postdecode(pdu::EthernetFrame)
    bytes = Vector{UInt8}(pdu; hooks=false)
    pdu.crc == crc32(bytes[1:end-4]) || throw(ErrorException("CRC check failed"))
    pdu
  end

  frame = EthernetFrame(
    dstaddr = (0x01, 0x02, 0x03, 0x04, 0x05, 0x06),
    srcaddr = (0x11, 0x12, 0x13, 0x14, 0x15, 0x16),
    ethtype = 0x0800,
    payload = [0x01, 0x02, 0x03, 0x04, 0x11, 0x12, 0x13, 0x14]
  )

  buf = Vector{UInt8}(frame)
  frame2 = EthernetFrame(buf)
  @test frame.payload == frame2.payload

  buf[5] += 1
  @test_throws ErrorException EthernetFrame(buf)

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

  AppPDU(hdr::Header_v1, payload) = AppPDU(9, hdr, payload)
  AppPDU(hdr::Header_v2, payload) = AppPDU(18, hdr, payload)

  function PDU.fieldtype(::Type{AppPDU}, ::Val{:hdr}, info)
    info.get(:hdrlen) == 18 && return Header_v2
    Header_v1
  end

  Base.length(::Type{AppPDU}, ::Val{:payload}, info) = info.length - info.get(:hdrlen) - 1

  pdu = AppPDU(Header_v1(1, 2, 3), UInt8[4, 5, 6])
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 13
  pdu2 = AppPDU(bytes)
  @test pdu.hdr isa Header_v1
  @test pdu == pdu2

  pdu = AppPDU(Header_v2(1, 2, 3), UInt8[4, 5, 6])
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 22
  pdu2 = AppPDU(bytes)
  @test pdu.hdr isa Header_v2
  @test pdu == pdu2

  struct ParamAppPDU{T} <: AbstractPDU
    hdrlen::UInt8
    hdr::T
    payload::Vector{UInt8}
  end

  ParamAppPDU(hdr::Header_v1, payload) = ParamAppPDU{Header_v1}(9, hdr, payload)
  ParamAppPDU(hdr::Header_v2, payload) = ParamAppPDU{Header_v2}(18, hdr, payload)

  function PDU.fieldtype(::Type{<:ParamAppPDU}, ::Val{:hdr}, info)
    info.get(:hdrlen) == 18 && return Header_v2
    Header_v1
  end

  Base.length(::Type{<:ParamAppPDU}, ::Val{:payload}, info) = info.length - info.get(:hdrlen) - 1

  pdu = ParamAppPDU(Header_v1(1, 2, 3), UInt8[4, 5, 6])
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 13
  pdu2 = ParamAppPDU(bytes)
  @test pdu.hdr isa Header_v1
  @test pdu == pdu2

  struct App2PDU <: AbstractPDU
    hdrlen::UInt8
    hdr::Union{Header_v1,Header_v2,Nothing}
    payload::Vector{UInt8}
  end

  function App2PDU(; hdr=nothing, payload=UInt8[])
    hdrlen = 0
    hdr isa Header_v1 && (hdrlen = 9)
    hdr isa Header_v2 && (hdrlen = 18)
    App2PDU(hdrlen, hdr, payload)
  end

  function PDU.fieldtype(::Type{App2PDU}, ::Val{:hdr}, info)
    info.get(:hdrlen) == 9 && return Header_v1
    info.get(:hdrlen) == 18 && return Header_v2
    Nothing
  end

  Base.length(::Type{App2PDU}, ::Val{:payload}, info) = info.length - info.get(:hdrlen) - 1

  pdu = App2PDU(hdr=Header_v1(1, 2, 3), payload=UInt8[4, 5, 6])
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 13
  pdu2 = App2PDU(bytes)
  @test pdu.hdr isa Header_v1
  @test pdu == pdu2

  pdu = App2PDU(payload=UInt8[4, 5, 6, 7, 8, 9])
  bytes = Vector{UInt8}(pdu)
  @test length(bytes) == 7
  pdu2 = App2PDU(bytes)
  @test pdu.hdr === nothing
  @test pdu == pdu2

end
