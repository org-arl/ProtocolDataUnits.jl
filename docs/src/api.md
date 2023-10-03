# API Reference

```@docs
ProtocolDataUnits.AbstractPDU
ProtocolDataUnits.byteorder
Base.length(::Type{<:AbstractPDU}, ::Val{Symbol}, ProtocolDataUnits.PDUInfo)
ProtocolDataUnits.fieldtype
ProtocolDataUnits.PDUInfo
ProtocolDataUnits.encode(::AbstractPDU)
ProtocolDataUnits.decode(::Vector{UInt8}, ::Type{<:AbstractPDU})
Base.read(io::IO, ::Type{<:AbstractPDU})
Base.write(io::IO, ::AbstractPDU)
ProtocolDataUnits.preencode
ProtocolDataUnits.postdecode
```
