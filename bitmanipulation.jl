"Reinterpret several UInt8s as a single larger number"
bitcat(a::UInt8) = a
bitcat(a::UInt8, b::UInt8) = (UInt16(a) << 8) | b
bitcat(a::UInt8, b::UInt8, c::UInt8) = (UInt32(a) << 16) | (UInt16(a) << 8) | b
bitcat(a::UInt8, b::UInt8, c::UInt8, d::UInt8) = (UInt32(a) << 24) | (UInt32(a) << 16) | (UInt16(a) << 8) | b
bitcat(v::AbstractArray{UInt8}) = bitcat(v...)
bitcat(::Type{UInt8}, v::AbstractArray{UInt8}) = v[1]
bitcat(::Type{UInt16}, v::AbstractArray{UInt8}) = bitcat(v[1], v[2])
bitcat(::Type{UInt32}, v::AbstractArray{UInt8}) = bitcat(v...)
bitcat(::Type{Vector{UInt8}}, v::AbstractArray{UInt8}) = v

"Split a bigger number into several UInt8s"
bitsplit(a::UInt8) = UInt8[a]
bitsplit(a::UInt16) = UInt8[a>>>8, a & 0xff]
bitsplit(a::UInt32) = UInt8[a>>>24, (a>>>16) & 0xff, (a>>>8) & 0xff, a & 0xff]

"Converts a number to a BitVector"
tobits(n::Unsigned) = BitVector(bit == '1' for bit in bitstring(n))

"Converts a BitVector representation of a byte into a byte"
tobyte(x::BitVector) = begin
  l = length(x)
  l <= 08 && return convert(UInt8, reverse(x).chunks[1])
  l <= 16 && return convert(UInt16, reverse(x).chunks[1])
  l <= 24 && return convert(UInt32, reverse(x).chunks[1])
  l <= 32 && return convert(UInt32, reverse(x).chunks[1])
  convert(UInt64, reverse(x).chunks[1])
end
