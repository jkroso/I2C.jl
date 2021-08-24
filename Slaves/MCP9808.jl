@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" °C ms
@use "../types.jl" Command AbstractI2CBus I2CDevice
@use "../Bus" i2c


@enum Resolution lowest low med high

"""
A high accuracy temperature sensor

[Datasheet](https://cdn-shop.adafruit.com/datasheets/MCP9808.pdf)
"""
struct MCP9808 <: I2CDevice
  bus::AbstractI2CBus
  addr::UInt8
  resolution::Resolution
  MCP9808(bus=i2c, addr=0x18, resolution=high) = new(bus, addr, high)
end

Base.propertynames(::MCP9808) = [:temperature, :bus, :addr]

Base.getproperty(d::MCP9808, ::Field{:temperature}) = begin
  hb, lb = read(d, Command(0x05, 2, delay=33ms*2^Int(d.resolution)))
  hb = hb & 0x1F # clear flag bits
  if (hb & 0x10) == 0x10 # T < 0°C
    hb = hb & 0x0F # clear sign
    (256 - hb*16 + lb/16)°C
  else
    (hb*16 + lb/16)°C
  end
end
