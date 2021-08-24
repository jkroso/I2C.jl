@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" °C ms
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" I2CDevice Command
@use "../Bus" i2c AbstractI2CBus

const PIXEL_TEMP_CONVERSION = 0.25
const THERMISTOR_CONVERSION = 0.0625

const POWER_CONTROL = Command(0x00, 1, UInt8)
const RESET = Command(0x01, 1, UInt8)
const FRAME_RATE = Command(0x02, 1, UInt8)
const INTERRUPT_CONTROL = Command(0x03, 1, UInt8)
const PIXELS = Command(0x80, 128)

"""
An 8x8 pixel thermal image sensor

[Datasheet](https://cdn-learn.adafruit.com/assets/assets/000/043/261/original/Grid-EYE_SPECIFICATIONS%28Reference%29.pdf)
"""
struct AMG8833 <: I2CDevice
  bus::AbstractI2CBus
  addr::UInt8
  AMG8833(bus=i2c, addr=0x69) = begin
    d = new(bus, addr)
    write(d, RESET, 0x3F)
    d
  end
end

Base.propertynames(::AMG8833) = [:pixels, :temperature, :bus, :addr]

Base.getproperty(d::AMG8833, ::Field{:temperature}) = begin
  lb = read(d, Command(0x0E, 1, UInt8))
  hb = read(d, Command(0x0F, 1, UInt8))
  u16 = bitcat(hb, lb)
  isnegative = (u16 & 0x800) == 0x800
  abs_value = u16 & 0x7FF
  t = (THERMISTOR_CONVERSION * abs_value)°C
  isnegative ? -t : t
end

Base.getproperty(d::AMG8833, ::Field{:pixels}) = begin
	data = read(d, PIXELS)
  matrix = Array{°C}(undef, 8, 8)
	for (pixel, i) in enumerate(1:2:128)
		lb = data[i]
		hb = data[i+1]
		raw = bitcat(hb, lb)
		raw &= 0xFFF # clear flags
		twos_compliment = (raw & 0x800) == 0x800 ? raw - 0x1000 : raw
		matrix[pixel] = twos_compliment * PIXEL_TEMP_CONVERSION
	end
	matrix
end
