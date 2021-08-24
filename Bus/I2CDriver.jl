@use "github.com/JuliaIO/LibSerialPort.jl" => SP
@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" s
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" Command AbstractI2CBus

"Communicates with the [I²CDriver](http://i2cdriver.com) over USB"
struct I2CDriver
  io::SP.SerialPort
  I2CDriver(path::String) = begin
    d = new(SP.open(path, 1000_000))
    write(d.io, '1') # set clock rate to 100Hz
    write(d.io, 'e', 0x01) # echo test
    @assert read(d.io, UInt8) == 0x01
    d
  end
end

start_write(b::I2CDriver, addr::UInt8) = begin
  write(b.io, 's', addr<<1)
  check_write(b)
end

start_read(b::I2CDriver, addr::UInt8) = begin
  write(b.io, 's', (addr<<1) | 0x01)
  check_write(b)
end

check_write(b::I2CDriver) = begin
  res = read(b.io, UInt8)
  @assert (res & 0x04) == 0x00 "bus arbitration is lost during the transmission"
  @assert (res & 0x02) == 0x00 "transmission timed out"
  (res & 0x01) == 0x01 # transmission acknowledged
end

Base.read(b::I2CDriver, nb::Integer) = begin
  @assert nb <= 64 "Can't read more than 64 bytes at once"
  write(b.io, 0x80|(UInt8(nb)-0x01))
  read(b.io, nb)
end

Base.write(b::I2CDriver, byte::UInt8) = begin
  write(b.io, 0xc0, byte)
  check_write(b)
end

Base.write(b::I2CDriver, bytes::Vector{UInt8}) = begin
  nb = length(bytes)
  @assert nb <= 64 "Can't write more that 64 bytes at once"
  write(b.io, 0xc0|(UInt8(nb)-0x01), bytes)
  check_write(b)
end

read_register(b::I2CDriver, slave::UInt8, addr::UInt8, nb::Integer) = begin
  write(b.io, 'r', slave, addr, UInt8(nb))
  read(b.io, nb)
end

"Sends an I²C stop symbol"
stop(b::I2CDriver) = write(b.io, 'p')

"""
Attempts an I²C bus reset. This consists of:
  - 10 pulses of SCK with SDA high
  - an I²C STOP symbol
"""
reset(b::I2CDriver) = begin
  write(b.io, 'x')
  res = read(b.io, UInt8)
  (res & 0x03) == 0x03 # true if the reset worked
end

"Search for valid device addresses connected to the I²C driver"
scan(b::I2CDriver) = begin
  write(b.io, 'd')
  bytes = read(b.io, 112)
  addrs = 0x08:0x77
  [addrs[i] for i in 1:112 if (bytes[i]&0x01) == 0x01]
end

"""
This is an API for the device made by [I2CDriver](https://i2cdriver.com/)
"""
mutable struct I2CBus <: AbstractI2CBus
  driver::I2CDriver
  slave::UInt8
  I2CBus(path="/dev/cu.usbserial-DM02VXTS") = new(I2CDriver(path), 0x00)
end

Base.write(b::I2CBus, byte::UInt8) = begin
  @assert start_write(b.driver, b.slave)
  nb = write(b.driver, byte)
  stop(b.driver)
  nb
end

Base.write(b::I2CBus, buf::Vector{UInt8}) = begin
  @assert start_write(b.driver, b.slave)
  nb = write(b.driver, buf)
  stop(b.driver)
  nb
end

Base.read(b::I2CBus, nb::Integer) = begin
  @assert start_read(b.driver, b.slave)
  bytes = read(b.driver, nb)
  stop(b.driver)
  @assert nb == length(bytes) "$nb bytes request but $(length(bytes)) received"
  bytes
end

Base.read(b::I2CBus, c::Command) = begin
  if c.delay > 0s
    @assert start_write(b.driver, b.slave)
    write(b.driver, c.byte)
    sleep(c.delay)
    @assert start_read(b.driver, b.slave)
    bytes = read(b.driver, c.length)
    stop(b.driver)
  else
    bytes = read_register(b.driver, b.slave, c.byte, c.length)
  end
  @assert c.length == length(bytes) "$(c.length) bytes request but $(length(bytes)) received"
  bitcat(c.type, bytes)
end
