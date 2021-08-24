@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/JuliaPy/PyCall.jl" pyimport PyObject
@use "github.com/jkroso/Units.jl" s
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" Command AbstractI2CBus

const Pin = pyimport("adafruit_blinka.microcontroller.ftdi_mpsse.mpsse.pin").Pin
const ftdi = pyimport("pyftdi.i2c")
const i2c = ftdi.I2cController()
i2c.configure("ftdi://ftdi:ft232h/1", frequency=100_000)
Pin.mpsse_gpio = i2c.get_gpio()

mutable struct I2CBus <: AbstractI2CBus
  slave::Union{PyObject,Nothing}
  I2CBus() = new(nothing)
end

Base.setproperty!(bus::I2CBus, f::Symbol, v) = setproperty!(bus, Field{f}(), v)
Base.setproperty!(b::I2CBus, ::Field{:slave}, addr) = setfield!(b, :slave, i2c.get_port(addr))

Base.write(b::I2CBus, byte::UInt8) = begin
	b.slave.write(UInt8[byte], relax=true)
  1
end

Base.write(b::I2CBus, buf::Vector{UInt8}) = begin
	b.slave.write(buf, relax=true)
  length(buf)
end

Base.read(b::I2CBus, nb::Integer) = begin
	bytes = b.slave.read(nb, relax=true)
  @assert nb == length(bytes) "$nb bytes request but $(length(bytes)) received"
  bytes
end

Base.read(b::I2CBus, c::Command) = begin
	out = if c.delay > 0s
		b.slave.write(UInt8[c.byte], relax=false)
		sleep(c.delay)
		b.slave.read(c.length, relax=true)
	else
		b.slave.exchange(UInt8[c.byte], c.length, relax=true)
	end
	bitcat(c.type, out)
end

isaddr(addr) = i2c.poll(addr)
scan(::I2CBus) = [addr for addr in 0x08:0x79 if isaddr(addr)]
