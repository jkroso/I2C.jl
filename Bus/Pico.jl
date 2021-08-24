@use "github.com/JuliaIO/LibSerialPort.jl" => SP
@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" s
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" Command AbstractI2CBus

"Communicates with a custom Raspberry Pico based driver"
mutable struct I2CBus <: AbstractI2CBus
  io::SP.SerialPort
  slave::UInt8
end

I2CBus(path="/dev/cu.usbmodem14601") = begin
  bus = I2CBus(SP.open(path, 115200), 0x00)
  write(bus.io, b"et")
  sleep(0.1)
  @assert read(bus.io, String) == "t"
  bus
end

# w(addr)(len)(s|c)(data)
Base.write(b::I2CBus, byte::UInt8) = begin
  write(b.io, 'w', b.slave, 0x01, 's', byte)
  @assert read(b.io, UInt8) == 0x00 "error writing to the I²C bus"
  1
end
Base.write(b::I2CBus, buf::Vector{UInt8}) = begin
  nb = UInt8(length(buf))
  write(b.io, 'w', b.slave, nb, 's', buf)
  @assert read(b.io, UInt8) == 0x00 "error writing to the I²C bus"
  nb
end

# r(addr)(len)(s|c)
Base.read(b::I2CBus, nb::Integer) = begin
  write(b.io, 'r', b.slave, UInt8(nb), 's')
  @assert read(b.io, UInt8) == 0x00 "error reading from the I²C bus"
  bytes = read(b.io, nb)
  @assert nb == length(bytes) "$nb bytes request but $(length(bytes)) received"
  bytes
end

# w(addr)(s|c)(data)(s|c)r(addr)(len)(s|c)
Base.read(b::I2CBus, c::Command) = begin
  write(b.io, 'w', b.slave, 0x01, 'c', c.byte)
  c.delay > 0s && sleep(c.delay)
  write(b.io, 'r', b.slave, c.length, 's')
  @assert read(b.io, UInt8) == 0x00 "error writing to the I²C bus"
  @assert read(b.io, UInt8) == 0x00 "error reading from the I²C bus"
  bytes = read(b.io, c.length)
  @assert c.length == length(bytes) "$(c.length) bytes request but $(length(bytes)) received"
  bitcat(c.type, bytes)
end
