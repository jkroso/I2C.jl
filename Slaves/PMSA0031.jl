@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/Units.jl" s nm µm µg m m³ litre
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" I2CDevice Command
@use "../Bus" i2c AbstractI2CBus

"""
Air quality sensor

[Datasheet](https://cdn-shop.adafruit.com/product-files/4632/4505_PMSA003I_series_data_manual_English_V2.6.pdf)
"""
mutable struct PMSA0031 <: I2CDevice
  addr::UInt8
  bus::AbstractI2CBus
  PMSA0031(addr=0x12, bus=i2c) = begin
    d = new(addr, i2c)
    sleep(2s) # time for device to power up
    @assert read(d, Command(0x00, 2)) == [0x42, 0x4d]
    d
  end
end

Base.getproperty(d::PMSA0031, ::Field{:data}) = begin
  data = read(d, 32)
  @assert sum(data[1:30]) == bitcat(data[31:32]) "checksum failed"
  (PM1 = bitcat(data[5:6])µg/m³,
   PM2_5 = bitcat(data[7:8])µg/m³,
   PM10 = bitcat(data[9:10])µg/m³,
   APM1 = bitcat(data[11:12])µg/m³,
   APM2_5 = bitcat(data[13:14])µg/m³,
   APM10 = bitcat(data[15:16])µg/m³,
   g003 = 10bitcat(data[17:18])/litre,
   g005 = 10bitcat(data[19:20])/litre,
   g01 = 10bitcat(data[21:22])/litre,
   g25 = 10bitcat(data[23:24])/litre,
   g5 = 10bitcat(data[25:26])/litre,
   g10 = 10bitcat(data[27:28])/litre)
end
