-- Default settings, do not change
local options = {
  -- Unique identifier for this matrix on rednet, required for rednet functionality
  rednet_identifier = '',

  -- Energy type being displayed (J, FE)
  energy_type = 'FE',

  -- Update frequency, in seconds
  update_frequency = 1,

  -- Text scale on the monitor
  text_scale = 1,

  -- Output debug data to the computer's internal display
  debug = true,
}

--------------------------------------------------
--- Internal variables, DO NOT CHANGE
--------------------------------------------------

--- This will be used as the installer source (GitHub raw URL)
local INSTALLER_URL = 'https://raw.githubusercontent.com/GawrrVR/cctw/main/startup.lua'

--- Supported energy suffixes
local energy_suffixes = { 'k', 'M', 'G', 'T', 'P' }

--- Supported time periods when converting seconds
local time_periods = {
  { 'weeks', 604800 },
  { 'days', 86400 },
  { 'hours', 3600 },
  { 'minutes', 60 },
  { 'seconds', 1 },
}

--- This is our Induction Matrix, we'll auto-detect it later
local induction_matrix = nil

--- This is our Monitor, we'll auto-detect it later
local monitor = nil

--- This is our Modem, we'll auto-detect it later
local modem = nil

--- Prefix used for rednet channels
local rednet_prefix = 'WL_Mek_Matrix'

--------------------------------------------------
--- Helper functions
--------------------------------------------------

--- Reads a file's contents
---@return string
function file_read (file)
  local handle = fs.open(file, 'r')
  local data = handle.readAll()
  handle.close()
  return data
end

--- Writes data to a file (overrides existing data)
function file_write (file, data)
  local handle = fs.open(file, 'w')
  handle.write(data)
  handle.close()
end

--- Holds the current buffer of data being printed
local machine_term = term.current()
local print_buffer = {}

--- Writes data to the output monitor buffer
function print_r (text, color)
  table.insert(print_buffer, {text, color})
end

--- Writes formatted data to the output monitor buffer
function print_f (format, ...)
  local n = select('#', ...)
  if n > 0 and type(select(n, ...)) == 'number' then
    local args = {}
    for i = 1, n-1 do
      args[i] = select(i, ...)
    end
    print_r(string.format(format, table.unpack(args)), select(n, ...))
  else
    print_r(string.format(format, ...))
  end
end

--- Writes the buffer into the output monitor
function print_flush ()
  if monitor then
    term.redirect(monitor)
    term.clear()
    term.setCursorPos(1, 1)
    for _, item in ipairs(print_buffer) do
      if item[2] then
        term.setTextColor(item[2])
      end
      print(item[1])
    end
    term.setTextColor(colors.white)
    term.redirect(machine_term)
  end
  print_buffer = {}
end

--- Writes debug info to the machine
function debug (...)
  if options.debug then
    print(...)
  end
end

--- Rounds a number with N decimals
function round_decimal (number, decimals)
  local multiplier = math.pow(10, decimals or 0)
  return math.floor(number * multiplier) / multiplier
end

--- Rounds a percentage (0..1) to a number of decimals
function round_percentage (number, decimals)
  return ('%s%%'):format(round_decimal(100 * number, decimals or 1))
end

--- The current energy type
local energy_type = 'J'

--- Converts energy values
local energy_convert = function (energy) return energy end
if mekanismEnergyHelper and mekanismEnergyHelper[('joulesTo%s'):format(options.energy_type)] then
  energy_type = options.energy_type
  energy_convert = mekanismEnergyHelper[('joulesTo%s'):format(options.energy_type)]
end

--- Prints an energy value
local energy_string = function (energy, decimals)
  local prefix = ''
  local suffix = ''

  -- Prepares a prefix for negative numbers
  if energy < 0 then
    prefix = '-'
  end

  -- We need a positive number here for calculating multipliers (k, M, G, T), we'll add the minus later, we also convert it to the right unit
  local amount = energy_convert(math.abs(energy))

  -- Finds the proper suffix/multiplier
  for _, multiplier in pairs(energy_suffixes) do
    -- Stops when amount is less than 1000
    if amount < 1000 then
      break
    end

    -- Updates suffix and amount to new value
    amount = amount / 1000
    suffix = multiplier
  end

  -- Returns the formatted string
  return ('%s%s%s%s'):format(prefix, round_decimal(amount, decimals or 1), suffix, energy_type)
end

--- Generates an ETA string when given a number of seconds
function eta_string (seconds)
  -- Makes sure we're only dealing with integers
  seconds = math.floor(seconds)

  -- Processes time periods
  local time = {}
  for _, period in pairs(time_periods) do
    local count = math.floor(seconds / period[2])
    time[period[1]] = count
    seconds = seconds - (count * period[2])
  end

  -- If we have more than 72h worth of storage, switch to week, day, hour format
  if time.weeks > 0 then
    return ('%dwk %dd %dh'):format(time.weeks, time.days, time.hours)
  elseif time.days >= 3 then
    return ('%dd %dh'):format(time.days, time.hours)
  end

  -- For all other cases, we'll just use H:MM:SS
  return ('%d:%02d:%02d'):format(time.hours, time.minutes, time.seconds)
end

local function center_text(text, w)
  local len = #text
  if len >= w then return text end
  local spaces = w - len
  local left = math.floor(spaces / 2)
  return string.rep(" ", left) .. text .. string.rep(" ", spaces - left)
end

--- Prints the Induction Matrix information
function print_matrix_info (matrix_info)
  local width = monitor.getSize()
  local border = "+" .. string.rep("-", width - 2) .. "+"
  local function bordered_line(text, color)
    return "| " .. center_text(text, width - 4) .. " |", color
  end

  print_r(border, colors.white)
  print_r(bordered_line("Matrix Monitor", colors.yellow))
  print_r(border, colors.white)
  print_r(bordered_line("", colors.white))

  local bar_length = 10
  local filled = math.floor(matrix_info.energy_percentage * bar_length)
  local bar = "[" .. string.rep("=", filled) .. string.rep(" ", bar_length - filled) .. "]"
  print_r(bordered_line("Puissance: " .. energy_string(matrix_info.energy_stored), colors.white))
  print_r(bordered_line("Limite: " .. energy_string(matrix_info.energy_capacity), colors.white))
  print_r(bordered_line("Charge: " .. round_percentage(matrix_info.energy_percentage) .. " " .. bar, colors.white))
  print_r(bordered_line("", colors.white))
  print_r(bordered_line("Input: " .. energy_string(matrix_info.io_input) .. "/t", colors.white))
  print_r(bordered_line("Output: " .. energy_string(matrix_info.io_output) .. "/t", colors.white))
  print_r(bordered_line("Max IO: " .. energy_string(matrix_info.io_capacity) .. "/t", colors.white))
  print_r(bordered_line("", colors.white))

  local change_text = "Change: " .. energy_string(matrix_info.change_amount_per_second) .. "/s"
  print_r(bordered_line(change_text, colors.white))
  print_r(bordered_line("", colors.white))

  local status_text = "Status: "
  local status_color = colors.white
  if matrix_info.is_charging then
    status_text = status_text .. "Charge. " .. eta_string((matrix_info.energy_capacity - matrix_info.energy_stored) / matrix_info.change_amount_per_second)
    status_color = colors.green
  elseif matrix_info.is_discharging then
    status_text = status_text .. "Décharge. " .. eta_string(matrix_info.energy_stored / math.abs(matrix_info.change_amount_per_second))
    status_color = colors.red
  else
    status_text = status_text .. "~"
  end
  print_r(bordered_line(status_text, status_color))
  print_r(border, colors.white)
end

--------------------------------------------------
--- Program initialization
--------------------------------------------------

args = {...}

-- Loads custom options from filesystem
if fs.exists('config') then
  debug('Loading settings from "config" file...')

  -- Reads custom options
  local custom_options = textutils.unserialize(file_read('config'))

  -- Overrides each of the existing options
  for k, v in pairs(custom_options) do
    options[k] = v
  end
end

-- Writes back config file
print('Updating config file...')
file_write('config', textutils.serialize(options))

-- Handles special case when "install" is executed from the pastebin
if 'install' == args[1] then
  print('Installing Matrix Monitor...')

  -- Are we on first install? If so, we'll run open the config for editing later
  local has_existing_install = fs.exists('startup.lua')

  -- Removes existing version
  if fs.exists('startup.lua') then
    fs.delete('startup.lua')
  end

  -- Downloads script from GitHub
  local response = http.get(INSTALLER_URL)
  if response then
    local content = response.readAll()
    response.close()
    file_write('startup.lua', content)
  else
    error('Failed to download from GitHub')
  end

  -- Runs config editor
  if not has_existing_install then
    print('Opening config file for editing...')
    sleep(2.5)
    shell.run('edit', 'config')
  end

  -- Reboots the computer after everything is done
  print('Install complete! Restarting computer...')
  sleep(2.5)
  os.reboot()
end

-- Detects peripherals
monitor = peripheral.find('monitor')
modem = peripheral.find('modem')

--- The rednet channel/protocol we'll be using
local rednet_channel = nil

-- Checks for an existing monitor
if monitor then
  debug('Monitor detected, enabling output!')
  monitor.setTextScale(options.text_scale)
else
  debug('No monitor detected, entering headless mode!')

  -- Makes sure we have a connected modem
  if not modem then
    error('No monitor or modem detected, cannot enter headless mode!')
  end
end

-- Conencts to rednet if modem available
if peripheral.find('modem') then
  if not options.rednet_identifier or options.rednet_identifier == '' then
    debug('Modem has been found, but no wireless identifier found on configs, will not connect!')
  else
    peripheral.find('modem', rednet.open)
    debug('Connected to rednet!')
    rednet_channel = ('%s#%s'):format(rednet_prefix, options.rednet_identifier)
  end
end

--------------------------------------------------
--- Main runtime
--------------------------------------------------

debug('Entering main loop...')

--- This will be updated after every energy collection, it is used to calculate how much power is actually being added/removed from the system
local energy_stored_previous = nil

while true do
  local status, err = pcall(function () 
    -- Attempts to auto-detect missing Induction Port
    if not induction_matrix then
      induction_matrix = peripheral.find('inductionPort')

      -- Checks if it worked
      if not induction_matrix then
        error('Induction Port not connected!')
      end
    end

    --- This is our main information
    local matrix_info = {
      energy_stored = induction_matrix.getEnergy(),
      energy_capacity = induction_matrix.getMaxEnergy(),
      energy_percentage = induction_matrix.getEnergyFilledPercentage(),
      io_input = induction_matrix.getLastInput(),
      io_output = induction_matrix.getLastOutput(),
      io_capacity = induction_matrix.getTransferCap(),
    }

    -- Detects power changes
    if not energy_stored_previous then
      energy_stored_previous = matrix_info.energy_stored
    end

    -- Calculates power changes and adds them to our information
    matrix_info.change_interval = options.update_frequency
    matrix_info.change_amount = matrix_info.energy_stored - energy_stored_previous
    matrix_info.change_amount_per_second = matrix_info.change_amount / options.update_frequency

    -- General stats
    matrix_info.is_charging = matrix_info.change_amount > 0
    matrix_info.is_discharging = matrix_info.change_amount < 0

    -- Sets the new "previous" value
    energy_stored_previous = matrix_info.energy_stored

    -- Broadcasts our matrix info if we have a modem
    if rednet.isOpen() and rednet_channel then
      rednet.broadcast(textutils.serialize(matrix_info), rednet_channel)
    end

    -- Prints the matrix information
    print_matrix_info(matrix_info)
  end)

  -- Checks for errors (might be disconnected)
  if not status then
    -- Clears buffer first
    print_buffer = {}

    -- Shows error message
    local width = monitor.getSize()
    local border = "+" .. string.rep("-", width - 2) .. "+"
    local function bordered_line(text, color)
      return "| " .. center_text(text, width - 4) .. " |", color
    end

    print_r(border, colors.white)
    print_r(bordered_line("Error reading data", colors.red))
    print_r(bordered_line("Check connections.", colors.red))
    print_r(border, colors.white)
    print_r(bordered_line(err, colors.red))
    print_r(border, colors.white)
  end

  -- Outputs text to screen
  print_flush()

  -- Waits for next cycle
  os.sleep(options.update_frequency)
end
