# A bus takes an I2C device/engine and presents it with the AbstractI2CBus interface
# This file just picks the right engine depending on what's connected to the computer
@use "../types.jl" AbstractI2CBus

const I2CBus = if ispath("/dev/i2c-1")
  @use("./RaspberryPi.jl").I2CBus
elseif ispath("/dev/cu.usbserial-DM02VXTS")
  @use("./I2CDriver.jl").I2CBus
elseif ispath("/dev/cu.usbmodem14601")
  if get(ENV, "I2CBUS", "") == "MCP2221"
    @use("./MCP2221.jl").I2CBus
  else
    @use("./Pico.jl").I2CBus
  end
elseif get(ENV, "I2CBUS", "") == "FT232"
  @use("./FT232.jl").I2CBus
else
  error("I2CBus not available, make sure your driver is plugged in or try setting the environment variable I2CBUS to MCP2221 or FT232")
end

@assert I2CBus <: AbstractI2CBus
const i2c = I2CBus()
