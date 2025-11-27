local options = {
  energy_type = 'FE',
  update_frequency = 0.1,
  text_scale = 1,
  debug = true,
  auto_update = true,
}

--------------------------------------------------
--- Internal variables, DO NOT CHANGE
--------------------------------------------------

local INSTALLER_URL = 'https://raw.githubusercontent.com/GawrrVR/cctw/main/startup.lua'

local energy_suffixes = { 'k', 'M', 'G', 'T', 'P' }

local time_periods = {
  { 'weeks', 604800 },
  { 'days', 86400 },
  { 'hours', 3600 },
  { 'minutes', 60 },
  { 'seconds', 1 },
}

local induction_matrix = nil

local monitor = nil

--------------------------------------------------
--- Helper functions
--------------------------------------------------

function file_read (file)
  local handle = fs.open(file, 'r')
  local data = handle.readAll()
  handle.close()
  return data
end

function file_write (file, data)
  local handle = fs.open(file, 'w')
  handle.write(data)
  handle.close()
end

local machine_term = term.current()
local print_buffer = {}

function print_r (text, color)
  table.insert(print_buffer, {text, color})
end

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

function debug (...)
  if options.debug then
    print(...)
  end
end

function round_decimal (number, decimals)
  local multiplier = math.pow(10, decimals or 0)
  return math.floor(number * multiplier) / multiplier
end

function round_percentage (number, decimals)
  return ('%s%%'):format(round_decimal(100 * number, decimals or 1))
end

local energy_type = 'J'

local energy_convert = function (energy) return energy end
if mekanismEnergyHelper and mekanismEnergyHelper[('joulesTo%s'):format(options.energy_type)] then
  energy_type = options.energy_type
  energy_convert = mekanismEnergyHelper[('joulesTo%s'):format(options.energy_type)]
end

local energy_string = function (energy, decimals)
  local prefix = ''
  local suffix = ''

  if energy < 0 then
    prefix = '-'
  end

  local amount = energy_convert(math.abs(energy))

  for _, multiplier in pairs(energy_suffixes) do
    if amount < 1000 then
      break
    end

    amount = amount / 1000
    suffix = multiplier
  end

  return ('%s%s%s%s'):format(prefix, round_decimal(amount, decimals or 1), suffix, energy_type)
end

function eta_string (seconds)
  seconds = math.floor(seconds)

  local time = {}
  for _, period in pairs(time_periods) do
    local count = math.floor(seconds / period[2])
    time[period[1]] = count
    seconds = seconds - (count * period[2])
  end

  if time.weeks > 0 then
    return ('%ds %dj %dh'):format(time.weeks, time.days, time.hours)
  elseif time.days >= 3 then
    return ('%dj %dh'):format(time.days, time.hours)
  end

  return ('%d:%02d:%02d'):format(time.hours, time.minutes, time.seconds)
end

local function center_text(text, w)
  local len = #text
  if len >= w then return text end
  local spaces = w - len
  local left = math.floor(spaces / 2)
  return string.rep(" ", left) .. text .. string.rep(" ", spaces - left)
end

function print_matrix_info (matrix_info)
  local width = monitor.getSize()

  print_r(center_text("Matrix Induction", width), colors.yellow)
  print_r("", colors.white)
  print_r(center_text("*** ENERGIE ***", width), colors.cyan)
  print_r("", colors.white)

  local bar_length = 25
  local filled = math.floor(matrix_info.energy_percentage * bar_length)
  local bar = "[" .. string.rep("#", filled) .. string.rep("-", bar_length - filled) .. "]"
  print_r(center_text(energy_string(matrix_info.energy_stored) .. " / " .. energy_string(matrix_info.energy_capacity), width), colors.green)
  print_r(center_text(round_percentage(matrix_info.energy_percentage), width), colors.green)
  print_r(center_text(bar, width), colors.yellow)
  print_r("", colors.white)
  print_r(center_text("*** TRANSFERTS I/O ***", width), colors.magenta)
  print_r("", colors.white)
  print_r(center_text("Entree: " .. energy_string(matrix_info.io_input) .. "/s", width), colors.blue)
  print_r(center_text("Sortie: " .. energy_string(matrix_info.io_output) .. "/s", width), colors.blue)
  print_r(center_text("I/O Max: " .. energy_string(matrix_info.io_capacity) .. "/s", width), colors.blue)
  print_r("", colors.white)
  print_r(center_text("*** FLUX ***", width), colors.purple)
  print_r("", colors.white)

  local change_text = ""
  local change_color = colors.gray
  if matrix_info.change_amount_per_second > 0 then
    change_text = "+" .. energy_string(matrix_info.change_amount_per_second) .. "/s"
    change_color = colors.green
  elseif matrix_info.change_amount_per_second < 0 then
    change_text = "-" .. energy_string(math.abs(matrix_info.change_amount_per_second)) .. "/s"
    change_color = colors.red
  else
    change_text = "~"
    change_color = colors.gray
  end
  print_r(center_text(change_text, width), change_color)
  print_r("", colors.white)
  print_r(center_text("*** STATUT ***", width), colors.orange)
  print_r("", colors.white)

  local status_text = ""
  local status_color = colors.white
  if matrix_info.is_charging then
    status_text = "Charge - " .. eta_string((matrix_info.energy_capacity - matrix_info.energy_stored) / matrix_info.change_amount_per_second)
    status_color = colors.lime
  elseif matrix_info.is_discharging then
    status_text = "Décharge - " .. eta_string(matrix_info.energy_stored / math.abs(matrix_info.change_amount_per_second))
    status_color = colors.red
  else
    status_text = "~"
    status_color = colors.gray
  end
  print_r(center_text(status_text, width), status_color)
end

--------------------------------------------------
--- Program initialization
--------------------------------------------------

args = {...}

if options.auto_update then
  print('Checking for updates...')
  local current_version = file_read('startup.lua')
  local response = http.get(INSTALLER_URL)
  if response then
    local latest = response.readAll()
    response.close()
    print('Current length: ' .. #current_version)
    print('Latest length: ' .. #latest)
    if latest ~= current_version then
      print('Downloading latest version...')
      local temp = 'temp_startup.lua'
      file_write(temp, latest)
      if fs.exists('startup.lua') then
        fs.delete('startup.lua')
      end
      fs.move(temp, 'startup.lua')
      print('Updated to latest version, rebooting...')
      os.reboot()
    else
      print('Already up to date.')
    end
  else
    print('Failed to check for updates.')
  end
end

if 'install' == args[1] then
  print('Installing Matrix Monitor...')

  local response = http.get(INSTALLER_URL)
  if response then
    local content = response.readAll()
    response.close()
    file_write('startup.lua', content)
  else
    error('Failed to download from GitHub')
  end

  print('Install complete! Restarting computer...')
  os.reboot()
end

monitor = peripheral.find('monitor')

if monitor then
  debug('Monitor detected, enabling output!')
  monitor.setTextScale(options.text_scale)
else
  error('No monitor detected!')
end

--------------------------------------------------
--- Main runtime
--------------------------------------------------

debug('Entering main loop...')

local energy_stored_previous = nil

while true do
  local status, err = pcall(function ()
    if not induction_matrix then
      induction_matrix = peripheral.find('inductionPort')

      if not induction_matrix then
        error('Induction Port not connected!')
      end
    end

    local matrix_info = {
      energy_stored = induction_matrix.getEnergy(),
      energy_capacity = induction_matrix.getMaxEnergy(),
      energy_percentage = induction_matrix.getEnergyFilledPercentage(),
      io_input = induction_matrix.getLastInput(),
      io_output = induction_matrix.getLastOutput(),
      io_capacity = induction_matrix.getTransferCap(),
    }

    matrix_info.change_amount_per_second = matrix_info.io_input - matrix_info.io_output

    matrix_info.is_charging = matrix_info.change_amount_per_second > 0
    matrix_info.is_discharging = matrix_info.change_amount_per_second < 0

    print_matrix_info(matrix_info)
  end)

  if not status then
    print_buffer = {}

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

  print_flush()

  os.sleep(options.update_frequency)
end
