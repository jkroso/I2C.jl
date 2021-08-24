@use "github.com/jkrumbiegel/Animations.jl" Animation sineio at
@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" ms Percent Time s
@use "../types.jl" Command I2CDevice
@use "../Bus" i2c AbstractI2CBus

"4 Channel Leading edge AC Dimmer"
mutable struct Dimmer <: I2CDevice
  addr::UInt8
  bus::AbstractI2CBus
  Dimmer(addr=0x27, bus=i2c) = new(addr, i2c)
end

setchannel(d::Dimmer, channel::UInt8, p::Percent) = begin
  d.bus.slave = d.addr
  write(d.bus, UInt8[channel, max(0, min(abs(100-round(p.value)), 100))])
end

Base.setproperty!(d::Dimmer, ::Field{:channel1}, x::Percent) = setchannel(d, 0x80, x)
Base.setproperty!(d::Dimmer, ::Field{:channel2}, x::Percent) = setchannel(d, 0x81, x)
Base.setproperty!(d::Dimmer, ::Field{:channel3}, x::Percent) = setchannel(d, 0x82, x)
Base.setproperty!(d::Dimmer, ::Field{:channel4}, x::Percent) = setchannel(d, 0x83, x)

animate(d::Dimmer, from, to; duration::Time=0.1s, channel=1) = begin
  len = convert(s, duration).value
  a = Animation(0.0, from, sineio(), len, to)
  start_time = time()
  chan = UInt8(0x80+channel-1)
  while true
    t = time() - start_time
    setchannel(d, chan, at(a, t))
    t >= len && break
  end
end

# const d = Dimmer()
# d.channel1 = 2Percent
#
# for _ in 1:100
#   time = 2000ms
#   animate(d, 0Percent, 100Percent, duration=time)
#   animate(d, 100Percent, 0Percent, duration=time)
# end
