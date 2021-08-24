@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" °C Percent ppm ppb ms s
@use "../bitmanipulation.jl" bitcat bitsplit tobits
@use "../LabeledBits.jl" LabeledBits
@use "../types.jl" I2CDevice Command
@use "../Bus" i2c


const ALG_RESULT_DATA = Command(0x02, 6)
const ENV_DATA = Command(0x05, 4)
const BASELINE = Command(0x11, 2, UInt16)
const SW_RESET = Command(0xFF, 4)
const START_COMMAND = Command(0xF4, 0)
const HARDWARE_ID = Command(0x20, 1, UInt8)

const Errors = [
  "WRITE_REG_INVALID" => "The CCS811 received an I²C write request addressed to this station but with invalid register address ID",
  "READ_REG_INVALID" => "The CCS811 received an I²C read request to an invalid register address",
  "MEASMODE_INVALID" => "The CCS811 received an I²C request to write an unsupported mode to MEAS_MODE",
  "MAX_RESISTANCE" => "The sensor resistance measurement has reached or exceeded the maximum range",
  "HEATER_FAULT" => "The Heater current in the CCS811 is not in range",
  "HEATER_SUPPLY" => "The Heater voltage is not being applied correctly"
]

throw_error(n::UInt8) = begin
  buf = PipeBuffer()
  for (i, bit) in enumerate(reverse(tobits(n)))
    if bit && i <= length(Errors)
      join(buf, Errors[i], ": ")
      println(buf)
    end
  end
  error(read(buf, String))
end

"""
An eCO2 and TVOC sensor

[Documentation](https://cdn-learn.adafruit.com/assets/assets/000/044/636/original/CCS811_DS000459_2-00-1098798.pdf)
"""
mutable struct CCS811 <: I2CDevice
  addr::UInt8
  bus::typeof(i2c)
  status::LabeledBits
  mode::LabeledBits
  CCS811(addr=0x5a, bus=i2c; drive_mode=0x03) = begin
    d = new(addr, bus)
    d.status = LabeledBits(d, 0x00, "firmware _ _ app_valid data_ready _ _ error", writeable=false)
    d.mode = LabeledBits(d, 0x01, "_ drive_mode*3 interrupt thresh _ _")
    reset(d)
    @assert read(d, HARDWARE_ID) == 0x81
    write(d, START_COMMAND)
    sleep(100ms)
    d.mode.drive_mode = drive_mode
    d
  end
end

Base.propertynames(::CCS811) = [:CO2, :TVOC, :values, :baseline, :status, :mode, :bus, :addr]

"Equivalent Carbon Dioxide in parts per million. Clipped to between 400 and 8192ppm"
Base.getproperty(d::CCS811, ::Field{:CO2}) = d.values[1]

"Total Volatile Organic Compound in parts per billion"
Base.getproperty(d::CCS811, ::Field{:TVOC}) = d.values[2]

"Get both CO2 and TVOC readings and check for errors"
Base.getproperty(d::CCS811, ::Field{:values}) = begin
  while true
    data = read(d, ALG_RESULT_DATA)
    co2 = bitcat(data[1:2])ppm
    voc = bitcat(data[3:4])ppb
    status = tobits(data[5])
    @assert status[1] "Firmware in boot mode"
    @assert status[4] "No application firmware loaded"
    if !status[5]
      sleep(1s) # Data wasn't ready to be read
      continue
    end
    status[6] && throw_error(data[6])
    return (co2, voc)
  end
end

Base.reset(d::CCS811) = (write(d, SW_RESET, UInt8[0x11, 0xE5, 0x72, 0x8A]); sleep(100ms))

"Set humidity and temperature so the device can compensate for them"
Base.setproperty!(d::CCS811, ::Field{:environment}, (humidity, temp)) = begin
  h = UInt16(512round(UInt, (humidity::Percent).value))
  t = UInt16(512round(UInt, (temp::°C).value + 25))
  write(d, ENV_DATA, vcat(bitsplit(h), bitsplit(t)))
end

"""
A two byte read/write register which contains an encoded version of the
current baseline used in Algorithm Calculations

You should save this to disk just before powering off the sensor
"""
Base.getproperty(d::CCS811, ::Field{:baseline}) = read(d, BASELINE)

"""
A previously stored value may be written back to this two byte register and
the Algorithms will use the new value in its calculations (until it adjusts
it as part of its internal Automatic Baseline Correction)

You should wait 20mins after powering up the sensor to write this
"""
Base.setproperty!(d::CCS811, ::Field{:baseline}, n::UInt16) = write(d, BASELINE, bitsplit(n))
