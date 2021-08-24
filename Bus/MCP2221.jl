@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/laborg/HidApi.jl" => HID
@use "github.com/jkroso/Units.jl" ms s Hz
@use "../bitmanipulation.jl" bitcat
@use "../types.jl" Command AbstractI2CBus

HID.init()

# The devices internal clock speed
const CLOCK = 12_000_000Hz

# from the [C driver](http://ww1.microchip.com/downloads/en/DeviceDoc/mcp2221_0_1.tar.gz)
# others (???) determined during driver developement
const RESP_ERR_NOERR = 0x00
const RESP_ADDR_NACK = 0x25
const RESP_READ_ERR = 0x7F
const RESP_READ_COMPL = 0x55
const RESP_READ_PARTIAL = 0x54  # ???
const RESP_I2C_IDLE = 0x00
const RESP_I2C_START_TOUT = 0x12
const RESP_I2C_RSTART_TOUT = 0x17
const RESP_I2C_WRADDRL_TOUT = 0x23
const RESP_I2C_WRADDRL_WSEND = 0x21
const RESP_I2C_WRADDRL_NACK = 0x25
const RESP_I2C_WRDATA_TOUT = 0x44
const RESP_I2C_RDDATA_TOUT = 0x52
const RESP_I2C_STOP_TOUT = 0x62
const RESP_I2C_MOREDATA = 0x43  # ???
const RESP_I2C_PARTIALDATA = 0x41  # ???
const RESP_I2C_WRITINGNOSTOP = 0x45  # ???

const CMDFLASHREAD = 0xB0
const CMDFLASHWRITE = 0xB1
const CMDFLASHPASSWD = 0xB2
const CMDI2CWRITE = 0x90
const CMDI2CWRITENOSTOP = 0x94
const CMDI2CREAD = 0x91
const CMDI2CREADREPSTART = 0x93
const CMDGPIOSET = 0x50
const CMDGPIOGET = 0x51
const CMDSRAMSET = 0x60
const CMDSRAMGET = 0x61

const RETRY_MAX = 50
const MASK_ADDR_NACK = 0x40

const PAD = 0x00
# The first byte always needs to be 0x00 according to the C library used
# https://github.com/libusb/hidapi/blob/083223e77952e1ef57e6b77796536a3359c1b2a3/hidapi/hidapi.h#L185
msg(bytes::UInt8...) = begin
	buf = zeros(UInt8, 65)
	for (i, byte) in enumerate(bytes)
		buf[i+1] = byte
	end
	buf
end

write_hid(hd::HID.HidDevice, data::Vector{UInt8}) = begin
  @assert hd.handle != C_NULL "device is closed"
  nb = HID.hid_write(hd.handle, data, length(data))
	@assert nb >= 0 "hid_write() failed: $(HID._wcharstring(HID.hid_error(hd.handle)))"
  nb
end

"[Datasheet](http://ww1.microchip.com/downloads/en/devicedoc/20005565b.pdf)"
struct MCP2221
  io::HID.HidDevice
end

MCP2221(i2c_speed=400_000Hz, VID=0x04D8, PID=0x00DD) = begin
	d = MCP2221(open(HID.find_device(VID, PID)))
	status(d).i2c.internal_state != 0x00 && reset(d)
	setI2Cclock(d, i2c_speed)
	d
end

transact(d::MCP2221, msg) = begin
	write_hid(d.io, msg)
	read(d.io, 64)
end

raw_status(d::MCP2221) = transact(d, msg(0x10))
status(d::MCP2221) = parse_status(raw_status(d))
parse_status(res) =
	(i2c=(cancel=res[3] == 0x00 ? "Not applicable" : res[3] == 0x10 ? "Pending" : "Already Idle",
	      speed=res[4] == 0x00 ? "Not applicable" : res[4] == 0x20 ? "Success" : "Failed: busy",
	      requested_speed_divider=res[5],
	      internal_state=res[9],
				transfer_length=bitcat(res[11], res[10]),
				transferred_length=bitcat(res[13], res[12]),
				buffer_counter=res[14],
				speed_divider=res[15],
				timeout=res[16],
				current_slave=bitcat(res[18], res[17]),
				SCL_pin=res[23] > 0x00,
				SDA_pin=res[24] > 0x00,
				interrupt_detector_state=res[25] > 0x00,
				slave_read_pending=res[26] > 0x00),
	 hardware=VersionNumber(res[47], res[48]),
	 firmware=VersionNumber(res[49], res[50]),
	 ADC=[bitcat(res[52], res[51]),
	      bitcat(res[54], res[53]),
				bitcat(res[56], res[55])])

Base.reset(d::MCP2221) = begin
	write_hid(d.io, msg(0x70, 0xab, 0xcd, 0xef))
	sleep(3s)
	close(d.io)
	open(d.io)
end

setI2Cclock(d::MCP2221, speed::Hz=400_000Hz) = begin
	divider = UInt8(CLOCK ÷ speed - 3)
	state = transact(d, msg(0x10, PAD, PAD, 0x20, divider))
	@assert state[4] == 0x20 "Speed divider couldn't be set to $(repr(divider))"
end

"Be careful using this. It will often put the device into an unusable state requiring a reset"
cancelI2C(d::MCP2221) = begin
	status = transact(d, msg(0x10, PAD, 0x10))
	@assert status[2] == 0x00 "Failed to cancel I2C"
	status[3] == 0x10 && sleep(1ms)
	nothing
end

const TIMEOUTS = (RESP_I2C_START_TOUT, RESP_I2C_WRADDRL_TOUT, RESP_I2C_WRADDRL_NACK, RESP_I2C_WRDATA_TOUT, RESP_I2C_STOP_TOUT)

writeI2C(d::MCP2221, addr::UInt8, data::Vector{UInt8}; stop=true) = begin
	raw_status(d)[9] == 0x00 || cancelI2C(d)
	cmd = stop ? CMDI2CWRITE : CMDI2CWRITENOSTOP
	nb = UInt16(length(data))
	written::UInt16 = 0
	retries = 0
	while written < nb
		chunk_len::UInt16 = min(nb-written, 60)
		chunk = view(data, written+1:chunk_len+written)
		res = transact(d, msg(cmd, UInt8(nb&0xff), UInt8(nb>>>8), addr<<1, chunk...))
		if res[2] != 0x00
			retries += 1
			@assert !(res[3] in TIMEOUTS) "I²C engine in an unrecoverable state"
			@assert retries < RETRY_MAX "Too many retries"
			sleep(1ms)
		else
			written += chunk_len
			# wait for the chunk to arrive at the slave
      while raw_status(d)[9] == RESP_I2C_PARTIALDATA; sleep(1ms) end
		end
	end
	# give the I²C engine a chance to return to ready state
	for retries in 1:RETRY_MAX
		state = raw_status(d)
		@assert state[20]&MASK_ADDR_NACK == 0x00 "I2C slave address was NACK'd"
		i2cstate = state[9]
		i2cstate == 0x00 && break
		CMDI2CWRITENOSTOP == cmd && RESP_I2C_WRITINGNOSTOP == i2cstate && break
		@assert !(i2cstate in TIMEOUTS) "I²C engine in an unrecoverable state"
		@assert retries <= RETRY_MAX "Too many retries"
		sleep(1ms)
	end
end

readI2C(d::MCP2221, addr::UInt8, nb::Integer; repeat_start=false, out=Vector{UInt8}(undef, nb)) = begin
	raw_status(d)[9] in (RESP_I2C_WRITINGNOSTOP, 0x00) || cancelI2C(d)
	cmd = repeat_start ? CMDI2CREADREPSTART : CMDI2CREAD
	l = UInt16(nb)
	res = transact(d, msg(cmd, UInt8(l&0xff), UInt8(l>>>8), (addr<<1)|0x01))
	@assert res[2] == 0x00 "I²C read failed"
	bytes_read = 0
	while bytes_read < nb
		for retries in 1:RETRY_MAX
			res = transact(d, msg(0x40))
			@assert res[2] == 0x00 "unrecoverable I²C read failure"
			@assert res[3] != RESP_ADDR_NACK "I²C Nack"
			res[3] in (RESP_READ_COMPL, RESP_READ_PARTIAL) && break
			res[4] == 0x00 && res[3] == 0x00 && break # successful zero length response
			@assert retries <= RETRY_MAX
			res[2] == RESP_I2C_PARTIALDATA && (sleep(1ms); continue)
			res[4] == RESP_READ_ERR && (sleep(1ms); continue)
		end
		len = res[4]
		out[bytes_read+1:bytes_read+len] = view(res, 5:4+len)
		bytes_read += len
	end
	@assert bytes_read == nb "$nb bytes requested $i bytes received"
	out
end

mutable struct I2CBus <: AbstractI2CBus
  driver::MCP2221
  slave::UInt8
  I2CBus() = new(MCP2221(), 0x00)
end

Base.write(b::I2CBus, byte::UInt8) = begin
	writeI2C(b.driver, b.slave, UInt8[byte], stop=true)
  1
end

Base.write(b::I2CBus, buf::Vector{UInt8}) = begin
	writeI2C(b.driver, b.slave, buf, stop=true)
  length(buf)
end

Base.read(b::I2CBus, nb::Integer) = begin
	bytes = readI2C(b.driver, b.slave, nb, repeat_start=false)
  @assert nb == length(bytes) "$nb bytes request but $(length(bytes)) received"
  bytes
end

# This I²C engine can't seem to read large chunks at a time without failing
# so we need to break large reads up
Base.read(b::I2CBus, c::Command) = begin
	out = Vector{UInt8}(undef, c.length)
	read = 0
	while read < c.length
		writeI2C(b.driver, b.slave, UInt8[c.byte+read], stop=false)
		c.delay > 0s && sleep(c.delay)
		chunk_size = min(32, c.length-read)
		bytes = readI2C(b.driver, b.slave, chunk_size, repeat_start=true, out=view(out, read+1:read+chunk_size))
		read += chunk_size
	end
	bitcat(c.type, out)
end
