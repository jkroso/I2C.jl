@use "github.com/jkroso/Prospects.jl" Field
@use "../types.jl" Command AbstractI2CBus

mutable struct I2CBus <: AbstractI2CBus
  path::String
  io::IOStream
  current_slave::UInt8
  I2CBus(path="/dev/i2c-1") = new(path, open(path, "w+"), 0x00)
end

Base.setproperty!(bus::I2CBus, f::Symbol, v) = setproperty!(bus, Field{f}(), v)

Base.setproperty!(b::I2CBus, ::Field{:slave}, addr) = begin
  device = getfield(b, :current_slave)
  device == addr && return addr
  ret = @ccall ioctl(fd(b.io)::Cint, 0x0703::Culong, addr::UInt8)::Cint
  ret < 0 && error("Error in ioctl", Libc.errno())
  setfield!(b, :current_slave, addr)
end

Base.write(b::I2CBus, buf::Vector{UInt8}) = begin
  ret = @ccall write(fd(b.io)::Cint, buf::Ref{UInt8}, length(buf)::Cint)::Cint
  ret < 0 && error("Error in write", Libc.errno())
  @assert ret == length(buf) "$(length(buf)) bytes sent but $ret delivered"
  ret
end

Base.read(b::I2CBus, nb::Integer) = begin
  buf = Vector{UInt8}(undef, nb)
  ret = @ccall read(fd(b.io)::Cint, buf::Ref{UInt8}, nb::Cint)::Cint
  ret < 0 && error("Error in read", Libc.errno())
  @assert nb == ret "$nb bytes request but $ret received"
  buf
end
