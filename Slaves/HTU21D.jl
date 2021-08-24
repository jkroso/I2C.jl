@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" °C Percent ms
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" I2CDevice Command
@use "../Bus" i2c AbstractI2CBus

const Temperature = Command(0xE3, 3, delay=100ms)
const Humidity = Command(0xE5, 3, delay=100ms)

struct HTU21D <: I2CDevice
  addr::UInt8
  bus::AbstractI2CBus
  HTU21D(addr::Integer=0x40, bus=i2c) = reset(new(addr, bus))
end

Base.reset(d::HTU21D) = (write(d, 0xFE); sleep(100ms); d)
Base.propertynames(::HTU21D) = (:addr, :bus, :temperature, :humidity, :dew_point)

Base.getproperty(htu::HTU21D, ::Field{:temperature}) = begin
  raw_temp = get_value(htu, Temperature)
  °C(-46.85 + 175.72(raw_temp/2^16))
end

Base.getproperty(htu::HTU21D, ::Field{:humidity}) = begin
  raw_hum = get_value(htu, Humidity)
  Percent(-6 + 125(raw_hum/2^16))
end

get_value(device, command) = begin
  data = read(device, command)
  @assert checksum(data[1:end-1], data[end])
  bitcat(data[1], data[2])
end

# Magic numbers taken from the sensor's datasheet http://www.farnell.com/datasheets/2207166.pdf
const A = 8.1332
const B = 1762.39
const C = 235.66

Base.getproperty(htu::HTU21D, ::Field{:partial_pressure}) = 10^(A-(B/(htu.temperature.value+C)))
Base.getproperty(htu::HTU21D, ::Field{:dew_point}) = begin
  RH = htu.humidity.value
  PP = htu.partial_pressure
  °C(-(B/(log10(RH*(PP/100))-A)+C))
end

"""
CRC Checksum to check data integrity
[Implementation reference](https://www.mouser.com/pdfDocs/SFM4100_CRC_Checksum_Calculation.pdf)
"""
checksum(bytes, check) = begin
  POLYNOMIAL = 0x131 # P(x)=x^8+x^5+x^4+1 = 100110001
  crc = 0x00
  for byte in bytes
    crc = crc ⊻ byte
    for bit in 1:8
      if (crc & 0x80) != 0x00
        crc = (crc << 1) ⊻ POLYNOMIAL
      else
        crc = (crc << 1)
      end
    end
  end
  crc == check
end
