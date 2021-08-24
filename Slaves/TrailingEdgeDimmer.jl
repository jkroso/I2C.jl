@use "github.com/jkrumbiegel/Animations.jl" Animation at linear
@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" ms Percent Time s Hz value
@use "../types.jl" Command I2CDevice
@use "../Bus" i2c AbstractI2CBus

const MAX = UInt8(252) # Seems to flicker above 252

"Trailing edge AC Dimmer suitable for LED lights"
mutable struct Ardutex <: I2CDevice
  addr::UInt8
  bus::AbstractI2CBus
  value::UInt8
  animation_speed::Hz
  target::Percent
  Ardutex(addr=0x10, bus=i2c) = new(addr, i2c, 0, 2Hz, 0Percent)
end

Base.setproperty!(d::Ardutex, ::Field{:value}, x::Percent) = d.value = round(UInt8, MAX*x)
Base.setproperty!(d::Ardutex, ::Field{:value}, x::Real) = d.value = round(UInt8, x)
Base.setproperty!(d::Ardutex, ::Field{:value}, x::UInt8) = begin
  d.bus.slave = d.addr
  setfield!(d, :value, x)
  write(d.bus, x)
  x
end
Base.getproperty(d::Ardutex, f::Symbol) = getproperty(d, Field{f}())
Base.getproperty(d::Ardutex, ::Field{:value}) = Percent(100getfield(d, :value)/MAX)

Base.setproperty!(d::Ardutex, ::Field{:target}, x::Percent) = begin
  d.target == x && return
  setfield!(d, :target, x)
  animate(d, d.value, x, speed=d.animation_speed)
end

"Speed is in 100%/s"
animate(d::Ardutex, from::Percent, to::Percent; speed::Hz=2Hz) = begin
  difference = abs(from - to)
  duration = difference/value(speed)
  a = Animation(0.0, from, linear(), duration, to)
  start_time = time()
  while d.target == to
    t = time() - start_time
    if t >= duration
      d.value = to
      break
    else
      d.value = at(a, t)
      yield()
    end
  end
end
