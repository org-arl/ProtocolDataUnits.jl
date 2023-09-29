using Test
using ProtocolDataUnits

@testset "basic" begin

  Base.@kwdef struct Eth2 <: PDU
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

  ProtocolDataUnits.byteorder(::Type{Eth2}) = LITTLE_ENDIAN

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

  struct TestPDU <: PDU
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

  struct InnerPDU <: PDU
    a::UInt16
    b::String
  end

  struct OuterPDU <: PDU
    n::UInt16
    inner::InnerPDU
  end

  f1in = InnerPDU(0x1234, "hello")
  f1 = OuterPDU(0x5678, f1in)
  buf = Vector{UInt8}(f1)
  f2 = OuterPDU(buf)

  @test f1.n == f2.n
  @test f1.inner == f2.inner
  @test f1 == f2
  @test length(buf) == 10
  @test buf == [0x56, 0x78, 0x12, 0x34, 0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

  Base.length(::Type{InnerPDU}, ::Val{:b}, info) = info.get(:a)

  f1in = InnerPDU(0x05, "hello")
  f1 = OuterPDU(0x5678, f1in)
  buf = Vector{UInt8}(f1)
  f2 = OuterPDU(buf)

  @test f1.n == f2.n
  @test f1.inner == f2.inner
  @test f1 == f2
  @test length(buf) == 9
  @test buf == [0x56, 0x78, 0x00, 0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

  Base.length(::Type{InnerPDU}, ::Val{:b}, info) = info.length - 2
  Base.length(::Type{OuterPDU}, ::Val{:inner}, info) = info.length - 2

  f1in = InnerPDU(0x1234, "hello")
  f1 = OuterPDU(0x5678, f1in)
  buf = Vector{UInt8}(f1)
  f2 = OuterPDU(buf)

  @test f1.n == f2.n
  @test f1.inner == f2.inner
  @test f1 == f2
  @test length(buf) == 9
  @test buf == [0x56, 0x78, 0x12, 0x34, 0x68, 0x65, 0x6c, 0x6c, 0x6f]

end
