@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" s

"""
subtypes should implment:

- `.slave`
- `.slave = addr`
- `write(bus, bytes)`
- `read(bus, bytes)`
- `read(bus, command)`
"""
abstract type AbstractI2CBus end

"""
An I2C slave device. Subtypes should implement two properties:

- `bus` an I2CBus instance
- `addr` an integer representing the address the device listens for
"""
abstract type I2CDevice end
Base.getproperty(d::I2CDevice, k::Symbol) = getproperty(d, Field{k}())
Base.setproperty!(d::I2CDevice, k::Symbol, v) = setproperty!(d, Field{k}(), v)

"An I²C command"
struct Command
  byte::UInt8
  length::UInt8
  type::DataType
  delay::s
end
Command(byte, length, type=Vector{UInt8}; delay=0s) = Command(byte, length, type, delay)

Base.write(d::I2CDevice, byte::UInt8) = begin
  d.bus.slave = d.addr
  write(d.bus, byte)
end
Base.write(d::I2CDevice, buffer::Vector{UInt8}) = begin
  d.bus.slave = d.addr
  write(d.bus, buffer)
end
Base.write(d::I2CDevice, c::Command) = (@assert(c.length == 0); write(d, c.byte))
Base.write(d::I2CDevice, c::Command, byte::UInt8) = (@assert(c.length == 1); write(d, UInt8[c.byte, byte]))
Base.write(d::I2CDevice, c::Command, buffer::Vector{UInt8}) = begin
  @assert length(buffer) == c.length
  write(d, UInt8[c.byte, buffer...])
end
Base.read(d::I2CDevice, nb::Integer) = begin
  d.bus.slave = d.addr
  read(d.bus, nb)
end
Base.read(d::I2CDevice, c::Command) = begin
  d.bus.slave = d.addr
  read(d.bus, c)
end
