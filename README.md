[![CI](https://github.com/org-arl/ProtocolDataUnits.jl/workflows/CI/badge.svg)](https://github.com/org-arl/ProtocolDataUnits.jl/actions)
[![doc-stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://org-arl.github.io/ProtocolDataUnits.jl/stable)
[![doc-dev](https://img.shields.io/badge/docs-latest-blue.svg)](https://org-arl.github.io/ProtocolDataUnits.jl/dev)

# ProtocolDataUnits.jl
**Encoders and decoders for Protocol Data Units (PDUs)**

[PDUs](https://en.wikipedia.org/wiki/Protocol_data_unit) encode information as byte streams that can be transmitted across a network or stored. `ProtocolDataUnits.jl` simplifies the process of encoding and decoding information as PDUs in a declarative way.

## Illustrative Example

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

The package can do much more, including nested PDUs, wire-encoding, CRC computation, etc. For more information, read the [documentation](https://org-arl.github.io/ProtocolDataUnits.jl/stable).

## Relationship with Other Packages

[ProtoBuf.jl](https://github.com/JuliaIO/ProtoBuf.jl) implements the [Protocol Buffers](https://protobuf.dev) specification for encoding/decoding data structures into byte streams. While the functionality sounds similar with `ProtocolDataUnits.jl`, both serve very different needs. Protocol Buffers provide a great way to encode information in a well-defined way but do not provide the flexibility to declare the format of the encoded information. On the other hand, `ProtocolDataUnits.jl` allows the developer to declare the byte stream format (typically based on networking specifications), and encode/decode the byte streams into structures.
