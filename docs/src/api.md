# API Reference

```@docs
ProtocolDataUnits.PDU
ProtocolDataUnits.byteorder
Base.length(::Type{<:PDU}, ::Val{Symbol}, ProtocolDataUnits.PDUInfo)
ProtocolDataUnits.fieldtype
ProtocolDataUnits.PDUInfo
Base.read(io::IO, ::Type{<:PDU})
Base.write(io::IO, ::PDU)
Base.Vector{UInt8}(::PDU)
ProtocolDataUnits.preencode
ProtocolDataUnits.postdecode
```
