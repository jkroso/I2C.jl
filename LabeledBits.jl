@use "./bitmanipulation.jl" tobits tobyte bitsplit
@use "./types.jl" Command I2CDevice

struct LabeledBits
  writeable::Bool
  names::Dict{Symbol,Union{Number,UnitRange}}
  device::I2CDevice
  register::UInt8
  width::UInt8
  LabeledBits(device::I2CDevice, reg::Integer, names; writeable=true, width=1) = begin
    pairs = Pair[]
    i = 0
    for n in split(names)
      i += 1
      n == "_" && continue
      if occursin('*', n)
        n, bits = split(n, '*')
        w = parse(Int, bits)
        n != "_" && push!(pairs, Symbol(n) => i:(i+w-1))
        i += w
      else
        push!(pairs, Symbol(n) => i)
      end
    end
    new(writeable, Dict{Symbol,Union{Number,UnitRange}}(pairs), device, reg, width)
  end
end

label_index(lb, name) = begin
  names = getfield(lb, :names)
  @assert haskey(names, name) "invalid bit label $name"
  names[name]
end

values(lb::LabeledBits) = begin
  d = getfield(lb, :device)
  reg = getfield(lb, :register)
  width = getfield(lb, :width)
  T = width == 1 ? UInt8 : UInt16
  tobits(read(d, Command(reg, width, T)))
end

tovalue(x::Any) = x
tovalue(x::BitVector) = tobyte(x)

Base.propertynames(lb::LabeledBits) = collect(Symbol, keys(getfield(lb, :names)))
Base.getproperty(lb::LabeledBits, f::Symbol) = tovalue(values(lb)[label_index(lb, f)])

Base.setproperty!(lb::LabeledBits, f::Symbol, value) = begin
  @assert getfield(lb, :writeable) "This LabeledBits isn't writable"
  bits = values(lb)
  set_bits!(bits, label_index(lb, f), value)
  device = getfield(lb, :device)
  command = getfield(lb, :register)
  write(device, UInt8[command, bitsplit(tovalue(bits))...])
  value
end

set_bits!(bits::BitVector, i::Any, val::Any) = bits[i] = val
set_bits!(bits::BitVector, i::UnitRange, val::Integer) = begin
  valbits = tobits(val)
  bits[i] = valbits[(lastindex(valbits)-length(i)+1):lastindex(valbits)]
end
