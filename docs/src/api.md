# API Reference

```@docs
ProtocolDataUnits.AbstractPDU
ProtocolDataUnits.byteorder
Base.length(::Type{<:AbstractPDU}, ::Val{Symbol}, ProtocolDataUnits.PDUInfo)
ProtocolDataUnits.fieldtype
ProtocolDataUnits.PDUInfo
Base.read(io::IO, ::Type{<:AbstractPDU})
Base.write(io::IO, ::AbstractPDU)
Base.Vector{UInt8}(::AbstractPDU)
ProtocolDataUnits.preencode
ProtocolDataUnits.postdecode
```
