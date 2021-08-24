@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" °C mbar ms
@use "../types.jl" I2CDevice Command
@use "../Bus" i2c AbstractI2CBus

"Read pressure sensitivity"
const C1 = Command(0xA2, 2, UInt16)
"Read pressure offset"
const C2 = Command(0xA4, 2, UInt16)
"Read temperature coefficient of pressure sensitivity"
const C3 = Command(0xA6, 2, UInt16)
"Read temperature coefficient of pressure offset"
const C4 = Command(0xA8, 2, UInt16)
"Read reference temperature"
const C5 = Command(0xAA, 2, UInt16)
"Read temperature coefficient of the temperature"
const C6 = Command(0xAC, 2, UInt16)
"Read sensor data"
const ADC = Command(0x00, 3, UInt32)
"Different command bytes for each accuracy level"
const PRESSURE_COMMANDS = Dict(256=>0x40, 512=>0x42, 1024=>0x44, 2048=>0x46, 4096=>0x48)
const TEMPERATURE_COMMANDS = Dict(256=>0x50, 512=>0x52, 1024=>0x54, 2048=>0x56, 4096=>0x58)
"Different wait times for each accuracy level"
const CONVERSION_TIMES = Dict(256=>0.6ms, 512=>1.17ms, 1024=>2.28ms, 2048=>4.54ms, 4096=>9.04ms)

"""
A waterproof pressure sensor

https://mouser.com/datasheet/2/418/5/NG_DS_MS5803-01BA_B-1134462.pdf
"""
mutable struct MS580301 <: I2CDevice
  addr::UInt8
  bus::AbstractI2CBus
  "accuracy level"
  osr::Int
  """
  The factory calibrates each sensor individually but leaves it up to us to
  actually adjust the readings based on that calibration
  """
  coefficients::Vector{Int64}
  MS580301(addr::Integer=0x76, bus=i2c) = begin
    d = new(addr, bus, 4096)
    write(d, 0x1E) # reset
    sleep(5ms)
    d.coefficients = Int64[read(d, C1), read(d, C2), read(d, C3), read(d, C4), read(d, C5), read(d, C6)]
    d
  end
end

Base.propertynames(::MS580301) = (:addr, :bus, :osr, :coefficients, :temperature, :pressure)

read_data(d::MS580301, CMDS::Dict) = begin
  write(d, CMDS[d.osr])
  sleep(CONVERSION_TIMES[d.osr])
  Int64(read(d, ADC))
end

convert_raw_readings((C1, C2, C3, C4, C5, C6)::Vector{Int64}, D1::Int64, D2::Int64) = begin
  # Difference between raw temp and reference temp
  dT = D2 - C5 * 2^8
  # Actual temperature in 100th of °C
  TEMP = 2000 + (dT * C6 / 2^23)

  # Pressure offset at actual temperature
  OFF  = (C2 * 2^16) + (C4 * dT / 2^7)
  # Pressure sensitivity at actual temperature
  SENS = (C1 * 2^15) + (C3 * dT / 2^8)

  # Do second order temperature correction
  if TEMP < 2000 # Colder than 20°C
    T2 = dT^2 / 2^31
    OFF2 =  3 * (TEMP - 2000)^2
    SENS2 = 7 * (TEMP - 2000)^2 / 2^3
    if TEMP < -1500
      SENS2 += 2 * (TEMP + 1500)^2
    end
  else
    T2 = 0
    OFF2 = 0
    SENS2 = 0
    if TEMP < 4500
      SENS2 -= (TEMP - 4500)^2 / 2^3
    end
  end
  TEMP -= T2
  OFF -= OFF2
  SENS -= SENS2

  # Temperature compensated pressure (10…1300mbar with 0.01mbar resolution)
  P = (((D1 * SENS) / 2^21) - OFF) / 2^15

  mbar(P/100), °C(TEMP/100)
end

Base.getproperty(ps::MS580301, ::Field{:readings}) =
  convert_raw_readings(ps.coefficients,
                       read_data(ps, PRESSURE_COMMANDS),
                       read_data(ps, TEMPERATURE_COMMANDS))
Base.getproperty(ps::MS580301, ::Field{:pressure}) = ps.readings[1]
Base.getproperty(ps::MS580301, ::Field{:temperature}) = ps.readings[2]
