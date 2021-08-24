@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" °C ms Pascal
@use "../types.jl" Command AbstractI2CBus I2CDevice
@use "../Bus" i2c

const WHOAMI = Command(0x0C, 1, UInt8)
const CONTROL1 = Command(0x26, 1, UInt8)
const STATUS = Command(0x00, 1, UInt8)
const PRESSURE = Command(0x01, 3, UInt32)
const TEMPERATURE = Command(0x04, 2, UInt16)

"""
Precision pressure sensor with altimetry

[Datasheet](https://www.nxp.com/docs/en/data-sheet/MPL3115A2.pdf)
"""
struct MPL3115A2 <: I2CDevice
  bus::AbstractI2CBus
  addr::UInt8
  MPL3115A2(bus=i2c, addr=0x60) = begin
    d = new(bus, addr)
    @assert read(d, WHOAMI) == 0xc4 "Failed to find a MPL3115A2 device"
    write(d, [0x26, 0x38])
    write(d, [0x13, 0x07])
    write(d, [0x26, 0x39])
    d
  end
end

Base.propertynames(::MPL3115A2) = [:temperature, :pressure, :bus, :addr]

Base.getproperty(d::MPL3115A2, ::Field{:pressure}) = begin
  data = read(d, PRESSURE) >> 4
  Pascal(data/4)
end

Base.getproperty(d::MPL3115A2, ::Field{:temperature}) = begin
  data = read(d, TEMPERATURE) >> 4
  °C(data/16)
end


d = MPL3115A2()
d.pressure
d.temperature
