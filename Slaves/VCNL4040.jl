@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" ms lx
@use "../LabeledBits.jl" LabeledBits
@use "../types.jl" Command I2CDevice
@use "../Bus" i2c AbstractI2CBus


const DEVICE_ID = Command(0x0C, 2, UInt16)
const PS_DATA = Command(0x08, 2, UInt16)
const WHITE_DATA = Command(0x0A, 2, UInt16)
const LIGHT_DATA = Command(0x09, 2, UInt16)

# Delay in ms: 80     160 320  640
@enum Accuracy lowest low med high

"""
Light and proximity sensor

[Datasheet](https://www.vishay.com/docs/84274/vcnl4040.pdf)
"""
mutable struct VCNL4040 <: I2CDevice
  bus::AbstractI2CBus
  addr::UInt8
  accuracy::Accuracy
  config::LabeledBits
  LIGHT_DATA::Command
  VCNL4040(bus=i2c, addr=0x60; accuracy=high) = begin
    d = new(bus, addr, accuracy)
    @assert read(d, DEVICE_ID) == 0x8601
    d.config = LabeledBits(d, 0x00, "integration_time*2 _*2 interrupt_persistence*2 enable_interrupt shutdown _*8", width=2)
    d.config.integration_time = UInt8(accuracy)
    d.config.shutdown = false
    d.config.interrupt_persistence = 0x00
    d.LIGHT_DATA = Command(0x09, 2, UInt16, delay=80ms*2^Int(accuracy))
    d
  end
end

Base.getproperty(d::VCNL4040, ::Field{:lux}) = lx(read(d, d.LIGHT_DATA) * (0.1 / (1 << Int(d.accuracy))))
