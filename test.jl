@use "./Slaves/HTU21D.jl" HTU21D
const htu21d = HTU21D()
@show htu21d.temperature
@show htu21d.humidity
@show htu21d.partial_pressure
@show htu21d.dew_point

@use "./Slaves/MS580301.jl" MS580301
const ms580301 = MS580301()
ms580301.coefficients
@show ms580301.pressure
@show ms580301.temperature

@use "./Slaves/CCS811.jl" CCS811
const ccs811 = CCS811(drive_mode=0x01)
ccs811.environment = (htu21d.humidity, htu21d.temperature)
@show ccs811.CO2
@show ccs811.TVOC
@show ccs811.baseline

@use "./Slaves/VCNL4040.jl" VCNL4040 high
const vcnl4040 = VCNL4040(accuracy=high)
@show vcnl4040.lux

@use "./Slaves/MCP9808.jl" MCP9808
const mcp9808 = MCP9808()
@show mcp9808.temperature

@use "./Slaves/AMG8833.jl" AMG8833
const amg8833 = AMG8833()
@show amg8833.temperature
@show amg8833.pixels[64]
@time amg8833.pixels

@use "./Slaves/PMSA0031.jl" PMSA0031
const pmsa0031 = PMSA0031()
@show pmsa0031.data

@use "./Slaves/BH1750.jl" BH1750
const bh1750 = BH1750()
@show bh1750.lux

@use "./Slaves/TrailingEdgeDimmer.jl" Ardutex Percent
const ardutex = Ardutex()
ardutex.target = 100Percent
ardutex.target = 50Percent
ardutex.target = 4Percent
