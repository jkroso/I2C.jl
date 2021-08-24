@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" ms lx
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" Command I2CDevice
@use "../Bus" i2c AbstractI2CBus

"""
Light sensor

[Datasheet](https://www.mouser.com/datasheet/2/348/bh1750fvi-e-186247.pdf)
"""
mutable struct BH1750 <: I2CDevice
  addr::UInt8
  bus::AbstractI2CBus
  BH1750(addr=0x23, bus=i2c) = begin
    d = new(addr, i2c)
    write(d, 0x11)
    sleep(180ms)
    d
  end
end

Base.getproperty(d::BH1750, ::Field{:lux}) = lx(bitcat(read(d, 2)) * 5//12)
