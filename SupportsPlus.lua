-- SupportsPlus v2.1 - Полная версия для Samp-Rp.Ru
-- GitHub: github.com/abutsik4/SampRpSupports
-- Автор: Serhiy_Rubin
--
-- ?? SupportsPlus - Модернизированный помощник для SA-MP
-- ? 90+ автомобилей | 200+ GPS локаций | Автообновление | Избранное
--
-- УСТАНОВКА: Один файл в GTA San Andreas/moonloader/
-- ГОРЯЧИЕ КЛАВИШИ: F8 Меню | F9 Авто | F10 GPS | F11 Обновления

script_name('SupportsPlus')
script_author("Serhiy_Rubin")
script_version("2.1.6")
script_version_number(2016)

-- GitHub конфигурация
local GITHUB_REPO = "abutsik4/SampRpSupports"
local GITHUB_RAW = "https://raw.githubusercontent.com/" .. GITHUB_REPO .. "/main/"
local VERSION_URL = GITHUB_RAW .. "version.json"
local SCRIPT_URL = GITHUB_RAW .. "SupportsPlus.lua"

-- ============================================================================
-- АВТОУСТАНОВКА БИБЛИОТЕК
-- ============================================================================
local function try_download_lib(name, url, filepath)
    if not downloadUrlToFile then return false end
    
    print('[SupportsPlus] Скачивание ' .. name .. '...')
    local done, success = false, false
    
    downloadUrlToFile(url, filepath, function(id, status)
        if status == 6 then -- DOWNLOAD_STATUS_ENDDOWNLOADDATA
            success = true
            done = true
        elseif status == 7 then -- DOWNLOAD_STATUS_ERROR
            done = true
        end
    end)
    
    -- Wait for download
    local t = os.clock()
    while not done and os.clock() - t < 10 do wait(100) end
    
    if success then
        print('[SupportsPlus] ' .. name .. ' установлен!')
    else
        print('[SupportsPlus] Не удалось скачать ' .. name)
    end
    return success
end

local function check_deps()
    local lib_dir = getGameDirectory() .. '\\moonloader\\lib\\'
    
    -- Define libraries with download URLs where available
    local deps = {
        {lib = 'lib.samp.events', name = 'SAMP Events', url = nil},
        {lib = 'lib.vkeys', name = 'Virtual Keys', 
         url = 'https://raw.githubusercontent.com/THE-FYP/SAMP-API/master/samp-lua/vkeys.lua',
         file = lib_dir .. 'vkeys.lua'},
        {lib = 'lib.inicfg', name = 'INI Config',
         url = 'https://raw.githubusercontent.com/THE-FYP/SAMP-API/master/samp-lua/inicfg.lua',
         file = lib_dir .. 'inicfg.lua'}
    }
    
    local missing = {}
    for _, dep in ipairs(deps) do
        if not pcall(require, dep.lib) then
            table.insert(missing, dep)
        end
    end
    
    if #missing == 0 then return true end
    
    -- Try auto-download for libraries with URLs
    local downloaded = false
    for _, dep in ipairs(missing) do
        if dep.url and dep.file then
            if try_download_lib(dep.name, dep.url, dep.file) then
                downloaded = true
            end
        end
    end
    
    -- Re-check after downloads
    if downloaded then
        missing = {}
        for _, dep in ipairs(deps) do
            if not pcall(require, dep.lib) then
                table.insert(missing, dep)
            end
        end
    end
    
    if #missing > 0 then
        print('[SupportsPlus] ОШИБКА! Отсутствуют библиотеки:')
        for _, dep in ipairs(missing) do
            local hint = dep.url and ' (ошибка загрузки)' or ' (нужен SAMPFUNCS)'
            print('  - ' .. dep.name .. hint)
        end
        print('[SupportsPlus] SAMPFUNCS: https://www.blast.hk/threads/17/')
        return false
    end
    return true
end

if not check_deps() then thisScript():unload() return end

local sampev, vkeys, inicfg = require 'lib.samp.events', require 'lib.vkeys', require 'lib.inicfg'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

local imgui_ok, imgui = pcall(require, 'imgui')
if not imgui_ok or not imgui then
    print('[SupportsPlus] ОШИБКА: ImGui не найден!')
    print('[SupportsPlus] Установите imgui.lua в moonloader/lib/')
    thisScript():unload()
    return
end

-- Опциональная библиотека для HTTP
local requests_ok, requests = pcall(require, 'requests')
local has_http = requests_ok and requests ~= nil

-- ============================================================================
-- КОНФИГУРАЦИЯ
-- ============================================================================
local config_path = getGameDirectory() .. '\\moonloader\\config\\SupportsPlus.ini'
local default_config = {
    settings = {
        auto_update = true,
        save_filters = true,
        show_distances = true,
        check_updates_on_start = true
    },
    filters = {
        car_class = 0,
        car_sort = 0,
        gps_category = 0
    },
    update = {
        last_check = 0,
        available_version = "",
        skip_version = ""
    }
}

local config = inicfg.load(default_config, config_path)
if not config then
    config = default_config
    inicfg.save(config, config_path)
end

local function save_config()
    inicfg.save(config, config_path)
end

-- ============================================================================
-- УТИЛИТЫ
-- ============================================================================
local utils = {}

function utils.format_price(price)
    local f = tostring(price)
    while true do
        local k; f, k = f:gsub("^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return f .. ' $'
end

function utils.distance_2d(x1, y1, x2, y2)
    return math.sqrt((x2-x1)^2 + (y2-y1)^2)
end

function utils.format_distance(dist)
    return dist < 1000 and string.format('%.0f м', dist) or string.format('%.2f км', dist/1000)
end

function utils.safe_number(str, def)
    return tonumber(str) or def or 0
end

function utils.compare_versions(v1, v2)
    -- Возвращает 1 если v1 > v2, -1 если v1 < v2, 0 если равны
    
    -- Безопасный лог (может не работать в некоторых потоках)
    local function safe_log(level, msg)
        pcall(function()
            if log and log.write then
                log.write(level, msg)
            end
        end)
    end
    
    -- Проверка на nil или пустые строки
    if not v1 or v1 == '' then
        safe_log(log and log.LEVEL and log.LEVEL.WARNING or 3, 'compare_versions: v1 is nil or empty, treating as 0.0.0')
        v1 = '0.0.0'
    end
    if not v2 or v2 == '' then
        safe_log(log and log.LEVEL and log.LEVEL.WARNING or 3, 'compare_versions: v2 is nil or empty, treating as 0.0.0')
        v2 = '0.0.0'
    end
    
    safe_log(log and log.LEVEL and log.LEVEL.DEBUG or 1, string.format('compare_versions: comparing "%s" vs "%s"', tostring(v1), tostring(v2)))
    
    local function split(v)
        local parts = {}
        -- Преобразуем в строку на всякий случай
        local str = tostring(v)
        for part in str:gmatch('[^.]+') do
            table.insert(parts, tonumber(part) or 0)
        end
        return parts
    end
    
    local p1, p2 = split(v1), split(v2)
    for i = 1, math.max(#p1, #p2) do
        local n1, n2 = p1[i] or 0, p2[i] or 0
        if n1 > n2 then 
            safe_log(log and log.LEVEL and log.LEVEL.DEBUG or 1, string.format('compare_versions: %s > %s (result: 1)', v1, v2))
            return 1 
        end
        if n1 < n2 then 
            safe_log(log and log.LEVEL and log.LEVEL.DEBUG or 1, string.format('compare_versions: %s < %s (result: -1)', v1, v2))
            return -1 
        end
    end
    safe_log(log and log.LEVEL and log.LEVEL.DEBUG or 1, string.format('compare_versions: %s == %s (result: 0)', v1, v2))
    return 0
end

-- ============================================================================
-- СИСТЕМА ЛОГИРОВАНИЯ
-- ============================================================================
local log = {}
local log_dir = getGameDirectory() .. '\\moonloader\\SupportsPlus\\logs\\'
local log_file = log_dir .. 'support.log'
local max_log_size = 512 * 1024  -- 512 KB
local max_log_files = 5
local log_buffer = {}
local log_enabled = true

-- Уровни логирования
log.LEVEL = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4
}

log.current_level = log.LEVEL.INFO  -- По умолчанию INFO и выше

local level_names = {
    [log.LEVEL.DEBUG] = 'DEBUG',
    [log.LEVEL.INFO] = 'INFO',
    [log.LEVEL.WARNING] = 'WARN',
    [log.LEVEL.ERROR] = 'ERROR'
}

local level_colors = {
    [log.LEVEL.DEBUG] = 0x888888,
    [log.LEVEL.INFO] = 0x00FF00,
    [log.LEVEL.WARNING] = 0xFFAA00,
    [log.LEVEL.ERROR] = 0xFF3333
}

-- Создание директории логов
local function ensure_log_dir()
    if not doesDirectoryExist(log_dir) then
        createDirectory(log_dir)
    end
end

-- Ротация логов
local function rotate_logs()
    if not doesFileExist(log_file) then return end
    
    local size = 0
    local f = io.open(log_file, 'r')
    if f then
        size = f:seek('end')
        f:close()
    end
    
    if size > max_log_size then
        -- Удаляем самый старый лог
        local oldest = log_dir .. 'support.' .. max_log_files .. '.log'
        if doesFileExist(oldest) then os.remove(oldest) end
        
        -- Сдвигаем все логи
        for i = max_log_files - 1, 1, -1 do
            local old_name = log_dir .. 'support.' .. i .. '.log'
            local new_name = log_dir .. 'support.' .. (i + 1) .. '.log'
            if doesFileExist(old_name) then
                os.rename(old_name, new_name)
            end
        end
        
        -- Переименовываем текущий
        os.rename(log_file, log_dir .. 'support.1.log')
    end
end

-- Получение информации о системе
local function get_system_info()
    local info = {
        script_version = script_version(),
        moonloader_version = getMoonloaderVersion() or 'unknown',
        lua_version = _VERSION,
        memory = string.format('%.2f MB', collectgarbage('count') / 1024),
        time = os.date('%Y-%m-%d %H:%M:%S')
    }
    return info
end

-- Форматирование стека вызовов
local function format_stack_trace()
    local stack = {}
    local level = 3  -- Пропускаем сам logger
    
    while true do
        local info = debug.getinfo(level, 'Sln')
        if not info then break end
        
        local func_name = info.name or 'anonymous'
        local source = info.short_src or '?'
        local line = info.currentline or 0
        
        table.insert(stack, string.format('  at %s (%s:%d)', func_name, source, line))
        level = level + 1
        
        if level > 15 then break end  -- Ограничение глубины
    end
    
    return table.concat(stack, '\n')
end

-- Основная функция логирования
function log.write(level, message, include_stack)
    if not log_enabled or level < log.current_level then return end
    
    ensure_log_dir()
    rotate_logs()
    
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local level_name = level_names[level] or 'UNKNOWN'
    local formatted = string.format('[%s] [%s] %s', timestamp, level_name, message)
    
    -- Добавляем стек вызовов для ошибок
    if include_stack or level >= log.LEVEL.ERROR then
        formatted = formatted .. '\n' .. format_stack_trace()
    end
    
    -- Запись в файл
    local file = io.open(log_file, 'a')
    if file then
        file:write(formatted .. '\n')
        file:close()
    end
    
    -- Вывод в консоль MoonLoader
    print('[SupportsPlus] ' .. formatted)
    
    -- Буферизация для UI
    table.insert(log_buffer, {
        time = timestamp,
        level = level,
        message = message
    })
    
    if #log_buffer > 100 then table.remove(log_buffer, 1) end
end

-- Сокращённые функции
function log.debug(msg, stack) log.write(log.LEVEL.DEBUG, msg, stack) end
function log.info(msg, stack) log.write(log.LEVEL.INFO, msg, stack) end
function log.warning(msg, stack) log.write(log.LEVEL.WARNING, msg, stack) end
function log.error(msg, stack) log.write(log.LEVEL.ERROR, msg, stack or true) end

-- Логирование с контекстом
function log.with_context(level, message, context)
    local ctx_str = ''
    if context then
        local parts = {}
        for k, v in pairs(context) do
            table.insert(parts, string.format('%s=%s', k, tostring(v)))
        end
        ctx_str = ' [' .. table.concat(parts, ', ') .. ']'
    end
    log.write(level, message .. ctx_str)
end

-- Замер производительности
function log.measure(name, func)
    local start = os.clock()
    local ok, result = pcall(func)
    local duration = (os.clock() - start) * 1000  -- ms
    
    if ok then
        log.debug(string.format('Performance: %s completed in %.2f ms', name, duration))
        return result
    else
        log.error(string.format('Performance: %s failed after %.2f ms: %s', name, duration, tostring(result)), true)
        error(result)
    end
end

-- Безопасный вызов с логированием
function log.safe_call(func_name, func, ...)
    local args = {...}
    local ok, result = pcall(function() return func(unpack(args)) end)
    
    if ok then
        log.debug(string.format('Call: %s() succeeded', func_name))
        return true, result
    else
        log.error(string.format('Call: %s() failed: %s', func_name, tostring(result)), true)
        return false, result
    end
end

-- Получение буфера логов для UI
function log.get_buffer()
    return log_buffer
end

-- Очистка логов
function log.clear()
    log_buffer = {}
    if doesFileExist(log_file) then
        os.remove(log_file)
    end
    log.info('Logs cleared')
end

-- Инициализация логгера
ensure_log_dir()
log.info('=== SupportsPlus Logger Initialized ===')
local sys_info = get_system_info()
for k, v in pairs(sys_info) do
    log.debug(string.format('System: %s = %s', k, v))
end

-- ============================================================================
-- АВТООБНОВЛЕНИЕ
-- ============================================================================
local update_state = {
    checking = false,
    available = false,
    downloading = false,
    new_version = "",
    changelog = "",
    download_progress = 0,
    error = nil
}

local function check_for_updates(silent)
    if update_state.checking then return end
    
    log.info('Checking for updates (silent=' .. tostring(silent) .. ')')
    
    if not has_http then
        log.warning('HTTP unavailable, auto-update disabled')
        if not silent then
            sampAddChatMessage('[SupportsPlus] Автообновление недоступно (нет библиотеки requests)', 0xFFAA00)
        end
        return
    end
    
    update_state.checking = true
    update_state.error = nil
    
    lua_thread.create(function()
        local ok, response = pcall(requests.get, VERSION_URL, {timeout = 5})
        
        if ok and response and response.status_code == 200 then
            log.debug('Version check response: ' .. tostring(response.status_code))
            -- Парсинг JSON вручную (простой случай)
            local version_match = response.text:match('"version"%s*:%s*"([^"]+)"')
            local changelog_match = response.text:match('"changelog"%s*:%s*"([^"]+)"')
            
            if version_match then
                local current_version = script_version()
                
                -- Проверяем что версия определена, иначе используем hardcoded
                if not current_version or current_version == '' then
                    log.warning('script_version() returned nil, using hardcoded SCRIPT_VERSION')
                    current_version = SCRIPT_VERSION
                end
                
                config.update.last_check = os.time()
                
                log.with_context(log.LEVEL.INFO, 'Version check', {
                    current = tostring(current_version),
                    available = tostring(version_match)
                })
                
                local cmp_result = utils.compare_versions(version_match, current_version)
                log.debug('Version comparison result: ' .. tostring(cmp_result))
                
                if cmp_result > 0 then
                    -- Новая версия доступна
                    if config.update.skip_version ~= version_match then
                        update_state.available = true
                        update_state.new_version = version_match
                        update_state.changelog = changelog_match or u8"Обновления доступны"
                        config.update.available_version = version_match
                        save_config()
                        
                        log.info('New version available: ' .. version_match)
                        
                        if not silent then
                            sampAddChatMessage(string.format('[SupportsPlus] Доступна новая версия %s! Нажмите F11', version_match), 0x00FF00)
                        end
                    else
                        log.debug('Update skipped by user: ' .. version_match)
                    end
                else
                    log.info('Already on latest version')
                    if not silent then
                        sampAddChatMessage('[SupportsPlus] У вас последняя версия!', 0x00FF00)
                    end
                end
            end
        else
            update_state.error = u8"Не удалось проверить обновления"
            log.error('Update check failed: ' .. tostring(response and response.status_code or 'no response'))
            if not silent then
                sampAddChatMessage('[SupportsPlus] ' .. update_state.error, 0xFF3333)
            end
        end
        
        update_state.checking = false
    end)
end

local function download_update()
    if not has_http or update_state.downloading then return end
    
    update_state.downloading = true
    update_state.download_progress = 0
    
    lua_thread.create(function()
        local script_path = thisScript().path
        local backup_path = script_path .. '.backup'
        
        -- Бэкап текущего файла
        local ok1, err1 = os.rename(script_path, backup_path)
        if not ok1 then
            sampAddChatMessage('[SupportsPlus] Ошибка создания бэкапа: ' .. tostring(err1), 0xFF3333)
            update_state.downloading = false
            return
        end
        
        -- Скачивание
        local ok2, response = pcall(requests.get, SCRIPT_URL, {timeout = 30})
        
        if ok2 and response and response.status_code == 200 then
            local file = io.open(script_path, 'w')
            if file then
                file:write(response.text)
                file:close()
                
                sampAddChatMessage('[SupportsPlus] Обновление установлено! Перезагрузка...', 0x00FF00)
                wait(1000)
                thisScript():reload()
            else
                -- Восстановление из бэкапа
                os.rename(backup_path, script_path)
                sampAddChatMessage('[SupportsPlus] Ошибка записи файла', 0xFF3333)
            end
        else
            -- Восстановление из бэкапа
            os.rename(backup_path, script_path)
            sampAddChatMessage('[SupportsPlus] Ошибка загрузки обновления', 0xFF3333)
        end
        
        update_state.downloading = false
    end)
end

-- ============================================================================
-- ДАННЫЕ АВТОМОБИЛЕЙ
-- ============================================================================
local car_data_raw = {
    "Landstalker|Nope|250000|88|3000", "Perenniel|Nope|75000|74|900", "Previon|Nope|125000|83|1500",
    "Stallion|Nope|350000|93|4200", "Solair|Nope|275000|87|3300", "Glendale|Nope|200000|82|2400",
    "Sabre|Nope|375000|96|4500", "Walton|Nope|100000|65|1200", "Regina|Nope|100000|78|1200",
    "Greenwood|Nope|80000|78|960", "Nebula|Nope|300000|87|3600", "Majestic|Nope|300000|87|3600",
    "Buccaneer|Nope|325000|91|3900", "Fortune|Nope|200000|88|2400", "Cadrona|Nope|100000|83|1200",
    "Clover|Nope|275000|91|3300", "Sadler|Nope|300000|84|3600", "Intruder|Nope|175000|83|2100",
    "Primo|Nope|110000|79|1320", "Tampa|Nope|175000|85|2100", "Savanna|Nope|650000|96|7800",
    "Manana|Nope|125000|71|1500", "Bravura|D|100000|82|1200", "Sentinal|D|750000|91|9000",
    "Voodoo|D|700000|94|8400", "Bobcat|D|825000|78|9900", "Premier|D|900000|96|10800",
    "Oceanic|D|125000|78|1500", "Hermes|D|150000|83|1800", "Blista Compact|D|800000|90|9600",
    "Elegant|D|750000|92|9000", "Willard|D|400000|83|4800", "Blade|D|750000|96|9000",
    "Vincent|D|400000|83|4800", "Sunrise|D|425000|80|5100", "Merit|D|525000|87|6300",
    "Tahoma|D|600000|89|7200", "Broadway|D|450000|88|5400", "Tornado|D|600000|88|7200",
    "Emperor|D|500000|85|6000", "Picador|D|550000|84|6600", "Moonbeam|C|125000|65|1500",
    "Esperanto|C|250000|83|3000", "Washington|C|450000|85|5400", "Admiral|C|1750000|91|21000",
    "Rancher|C|400000|77|4800", "Virgo|C|250000|83|3000", "Feltzer|C|2500000|93|30000",
    "Remington|C|1250000|94|15000", "Yosemite|C|625000|80|7500", "Windsor|C|1500000|88|18000",
    "Stratum|C|1000000|85|12000", "Huntley|C|2500000|88|30000", "Stafford|C|2000000|85|24000",
    "Club|C|500000|90|6000", "Phoenix|C|2500000|95|30000", "PCJ-600|C|2250000|89|27000",
    "BF-400|C|3250000|85|39000", "Wayfarer|C|1000000|80|12000", "ZR-350|B|4750000|103|57000",
    "Comet|B|6000000|102|72000", "Slamvan|B|1750000|88|21000", "Hustler|B|1500000|82|18000",
    "Uranus|B|3000000|87|36000", "Jester|B|4250000|98|51000", "Sultan|B|5000000|94|60000",
    "Elegy|B|4500000|99|54000", "Flash|B|3500000|91|42000", "Euros|B|2750000|91|33000",
    "Alpha|B|3000000|94|36000", "FCR-900|B|4000000|90|48000", "Freeway|B|1500000|81|18000",
    "Sanchez|B|2750000|80|33000", "Quad|B|500000|61|6000", "Buffalo|A|5500000|103|66000",
    "Infernus|A|10000000|123|120000", "Cheetah|A|7500000|107|90000", "Banshee|A|8000000|112|96000",
    "Turismo|A|8500000|107|102000", "Super GT|A|3750000|99|45000", "Bullet|A|9000000|113|108000",
    "NRG-500|A|7250000|98|87000", "Hotknife|A|3500000|93|42000", "BF Injection|A|1000000|75|12000",
    "Sandking|A|7750000|98|93000", "Hotring Racer|A|9500000|119|114000", "Cadillac Escalade|L|10000000|111|120000",
    "Audi RS5|L|14000000|125|168000", "BMW M5|L|16000000|134|192000", "Cadillac CTS-L|L|13000000|120|156000",
    "Ford F-150|L|6000000|105|72000", "BMW X6|L|12500000|121|150000", "Mercedes-Benz G65|L|11000000|118|132000",
    "Nissan GT-R|L|13000000|135|156000", "Lamborghini Urus|L|17000000|138|204000"
}

local cars, cars_filtered, cars_favorite = {}, {}, {}

local function parse_cars()
    log.info('Starting car data parsing')
    local count, failed = 0, 0
    for i, raw in ipairs(car_data_raw) do
        local ok, err = pcall(function()
            local p = {}
            for part in raw:gmatch('[^|]+') do table.insert(p, part) end
            if #p < 5 then error('bad format') end
            
            local car = {
                id = i,
                name = p[1],
                class = p[2],
                price = utils.safe_number(p[3], 0),
                speed = utils.safe_number(p[4], 0),
                tax = utils.safe_number(p[5], 0),
                favorite = false
            }
            
            if car.name and car.price > 0 and car.speed > 0 then
                table.insert(cars, car)
                count = count + 1
            else
                error('invalid data')
            end
        end)
        if not ok then 
            failed = failed + 1
            log.warning(string.format('Car #%d parse failed: %s', i, tostring(err)))
        end
    end
    log.info(string.format('Cars parsed: %d успешно, %d ошибок', count, failed))
    print('[SupportsPlus] Авто: ' .. count .. ' (ошибок: ' .. failed .. ')')
end

local car_search = imgui.ImBuffer(256)
local car_class_filter = imgui.ImInt(config.filters.car_class)
local car_sort = imgui.ImInt(config.filters.car_sort)

local function filter_cars()
    cars_filtered = {}
    local search = car_search.v:lower()
    local classes = {'Все', 'Nope', 'D', 'C', 'B', 'A', 'L'}
    local sel_class = classes[car_class_filter.v + 1]
    
    for _, car in ipairs(cars) do
        local match = (search == '' or car.name:lower():find(search, 1, true)) and
                     (sel_class == 'Все' or car.class == sel_class)
        if match then table.insert(cars_filtered, car) end
    end
    
    if car_sort.v == 1 then
        table.sort(cars_filtered, function(a,b) return a.price < b.price end)
    elseif car_sort.v == 2 then
        table.sort(cars_filtered, function(a,b) return a.speed > b.speed end)
    else
        table.sort(cars_filtered, function(a,b) return a.name < b.name end)
    end
    
    config.filters.car_class, config.filters.car_sort = car_class_filter.v, car_sort.v
    if config.settings.save_filters then save_config() end
end

local function toggle_car_favorite(car)
    car.favorite = not car.favorite
    if car.favorite then table.insert(cars_favorite, car) end
end

-- ============================================================================
-- GPS ДАННЫЕ
-- ============================================================================
local gps_data = {
    {name = u8'?? Банки', items = {
        "LS Bank - Pershing Square", "SF Bank - Kings", "LV Bank - Roca Escalante",
        "LS Bank - Market", "SF Bank - Juniper Hill", "LV Bank - Come-A-Lot",
        "Bayside Bank", "Fort Carson Bank", "Palomino Creek Bank", "Las Barrancas Bank"
    }},
    {name = u8'?? Гос. Работа', items = {
        u8"Автошкола", u8"Таксопарк", u8"Завод боеприпасов",
        u8"Склад продуктов", u8"Завод по производству авто",
        u8"Ферма", u8"Автобусный парк"
}},
    {name = u8'?? Бары / Клубы', items = {
        "Alhambra", "Jizzy", "Pig Pen", "Grove street", "Misty",
        "Amnesia", "Big Spread Ranch", "Lil Probe Inn", "Comedy club"
    }},
    {name = u8'?? Автосалоны', items = {
        u8"Автосалон: Nope", u8"Автосалон: D and C", u8"Автосалон: L",
        u8"Автосалон: S", u8"Автосалон [LV]: B and A"
    }},
    {name = u8'?? Дома фракций', items = {
        u8"Полиция", u8"Правительство", u8"Больница", u8"Армия [LS]",
        u8"Армия [SF]", u8"Армия [LV]", u8"ФБР", "Yakuza",
        "La Cosa Nostra", "Rifa", "Grove street", "Ballas", "Vagos", "Aztecas"
    }},
    {name = u8'??? Острова', items = {
        u8"Остров штата: 0", u8"Остров штата: 1", u8"Остров штата: 2",
        u8"Остров штата: 3", u8"Остров штата: 4"
    }},
    {name = u8'?? Магазины 24/7', items = {
        "Idlewood", "Mulholland", "Flint", "Whetstone", "Easter",
        "Juniper", "Redsands West", "Creek", "Julius", "Emerald Isle",
        "Come-A-Lot", "Fort Carson", "Bayside", "Dillimore",
        "Palomino Creek", "El Quebrados", "Doherty", "Jefferson"
    }},
    {name = u8'?? Фастфуд', items = {
        "Downtown", "Financial", "Garcia", "Juniper", "Esplanade",
        "Willowfield", "Vinewood", "Idlewood", "Fort Carson",
        "Redsands West", "Redsands East", "Creek", "Palomino Creek"
    }},
    {name = u8'?? Мафия', items = {
        u8"Мафия [LS]", u8"Мафия [SF]", u8"Мафия [LV]"
    }},
    {name = u8'?? Офисы', items = {
        "SF [B] I", "SF [B] II", "LV [A] Elite", "LS [C] Classic",
        "Beach Office", "Downtown Office", "Montgomery office"
    }}
}

local gps_search = imgui.ImBuffer(256)
local gps_category = imgui.ImInt(config.filters.gps_category)

-- ============================================================================
-- ТЕМА IMGUI
-- ============================================================================
local function apply_theme()
    log.debug('apply_theme: Getting ImGui style and colors')
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    
    log.debug('apply_theme: Setting WindowBg color')
    colors[clr.WindowBg] = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
    
    log.debug('apply_theme: Setting Button colors')
    colors[clr.Button] = imgui.ImVec4(0.20, 0.50, 0.90, 1.00)
    colors[clr.ButtonHovered] = imgui.ImVec4(0.25, 0.60, 1.00, 1.00)
    colors[clr.ButtonActive] = imgui.ImVec4(0.15, 0.40, 0.80, 1.00)
    
    log.debug('apply_theme: Setting Header color')
    colors[clr.Header] = imgui.ImVec4(0.20, 0.50, 0.90, 0.45)
    
    -- Табы могут отсутствовать в старых версиях imgui
    if clr.Tab and clr.TabActive then
        log.debug('apply_theme: Setting Tab colors (supported)')
        colors[clr.Tab] = imgui.ImVec4(0.15, 0.15, 0.17, 1.00)
        colors[clr.TabActive] = imgui.ImVec4(0.20, 0.50, 0.90, 1.00)
    else
        log.debug('apply_theme: Tab colors not supported in this imgui version')
    end
    
    log.debug('apply_theme: Setting style rounding')
    style.WindowRounding = 8.0
    style.FrameRounding = 4.0
    
    log.info('apply_theme: Theme applied successfully')
end

-- ============================================================================
-- ОКНА
-- ============================================================================
local main_win = imgui.ImBool(false)
local car_win = imgui.ImBool(false)
local gps_win = imgui.ImBool(false)
local update_win = imgui.ImBool(false)

-- Главное окно
local function render_main()
    if not main_win.v then return end
    imgui.SetNextWindowSize(imgui.ImVec2(600, 400), imgui.Cond.FirstUseEver)
    if imgui.Begin(u8'SupportsPlus - Samp-Rp.Ru v2.1', main_win) then
        imgui.TextColored(imgui.ImVec4(0.2,0.8,0.4,1), u8'?? Добро пожаловать в SupportsPlus!')
        imgui.Separator()
        
        if imgui.Button(u8'?? База автомобилей', imgui.ImVec2(250,40)) then car_win.v = true end
        imgui.SameLine()
        if imgui.Button(u8'?? GPS Навигатор', imgui.ImVec2(250,40)) then gps_win.v = true end
        
        imgui.Spacing()
        if update_state.available then
            imgui.TextColored(imgui.ImVec4(0.2,0.8,0.4,1), u8'? Доступна новая версия '..update_state.new_version..'!')
            if imgui.Button(u8'?? Открыть обновления', imgui.ImVec2(250,30)) then
                update_win.v = true
            end
        end
        
        imgui.Spacing()
        imgui.Text(u8'Статистика:')
        imgui.BulletText(u8'Автомобилей: '..#cars)
        imgui.BulletText(u8'GPS категорий: '..#gps_data)
        imgui.BulletText(u8'Память: '..string.format('%.1f МБ', collectgarbage('count')/1024))
        imgui.BulletText(u8'HTTP: '..(has_http and u8'? Доступен' or u8'? Недоступен'))
    end
    imgui.End()
end

-- Окно автомобилей
local function render_cars()
    if not car_win.v then return end
    imgui.SetNextWindowSize(imgui.ImVec2(850,600), imgui.Cond.FirstUseEver)
    if imgui.Begin(u8'?? База автомобилей - '..#cars_filtered..u8' найдено', car_win) then
        imgui.PushItemWidth(250)
        if imgui.InputTextWithHint('##s', u8'Поиск...', car_search) then filter_cars() end
        imgui.PopItemWidth()
        imgui.SameLine()
        imgui.PushItemWidth(100)
        if imgui.Combo('##c', car_class_filter, {'Все','Nope','D','C','B','A','L'}) then filter_cars() end
        imgui.PopItemWidth()
        imgui.SameLine()
        imgui.PushItemWidth(120)
        if imgui.Combo('##sort', car_sort, {u8'Название',u8'Цена',u8'Скорость'}) then filter_cars() end
        imgui.PopItemWidth()
        
        imgui.BeginChild('list', imgui.ImVec2(0,0), true)
        local colors = {Nope={0.5,0.5,0.5,1},D={0.6,0.6,0.3,1},C={0.3,0.7,0.3,1},
                        B={0.3,0.5,0.9,1},A={0.9,0.3,0.3,1},L={1,0.7,0.2,1}}
        for i, car in ipairs(cars_filtered) do
            local col = colors[car.class] or {1,1,1,1}
            imgui.PushStyleColor(imgui.Col.Header, imgui.ImVec4(col[1],col[2],col[3],col[4]))
            if imgui.CollapsingHeader(car.name..' ['..car.class..']##'..i) then
                imgui.Indent(15)
                imgui.Text(u8'Цена: '..utils.format_price(car.price))
                imgui.Text(u8'Скорость: '..car.speed..' m/h')
                imgui.Text(u8'Налог: '..utils.format_price(car.tax))
                if imgui.Button(u8'Скопировать##'..i, imgui.ImVec2(140,25)) then
                    setClipboardText(car.name)
                    sampAddChatMessage('[SupportsPlus] '..car.name, 0x00FF00)
                end
                imgui.SameLine()
                if imgui.Button((car.favorite and u8'? Избранное' or u8'? В избранное')..'##'..i) then
                    toggle_car_favorite(car)
                end
                imgui.Unindent(15)
            end
            imgui.PopStyleColor()
        end
        imgui.EndChild()
    end
    imgui.End()
end

-- Окно GPS
local function render_gps()
    if not gps_win.v then return end
    imgui.SetNextWindowSize(imgui.ImVec2(700,500), imgui.Cond.FirstUseEver)
    if imgui.Begin(u8'?? GPS Навигатор', gps_win) then
        imgui.PushItemWidth(350)
        imgui.InputTextWithHint('##gs', u8'Поиск локации...', gps_search)
        imgui.PopItemWidth()
        
        if imgui.BeginTabBar('GPSTabs') then
            for i, cat in ipairs(gps_data) do
                if imgui.BeginTabItem(cat.name) then
                    imgui.BeginChild('gpslist', imgui.ImVec2(0,0), true)
                    for j, loc in ipairs(cat.items) do
                        if imgui.Selectable(loc..'##'..j, false) then
                            sampAddChatMessage('[GPS] '..loc, 0x00AAFF)
                        end
                    end
                    imgui.EndChild()
                    imgui.EndTabItem()
                end
            end
            imgui.EndTabBar()
        end
    end
    imgui.End()
end

-- Окно обновлений
local function render_updates()
    if not update_win.v then return end
    imgui.SetNextWindowSize(imgui.ImVec2(500,350), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(imgui.GetIO().DisplaySize.x/2-250, imgui.GetIO().DisplaySize.y/2-175), imgui.Cond.FirstUseEver)
    
    if imgui.Begin(u8'?? Обновления SupportsPlus', update_win) then
        imgui.TextColored(imgui.ImVec4(0.2,0.8,0.4,1), u8'Система автообновлений')
        imgui.Separator()
        imgui.Spacing()
        
        imgui.Text(u8'Текущая версия: '..script_version())
        
        if update_state.available then
            imgui.TextColored(imgui.ImVec4(0.2,0.8,0.4,1), u8'Доступна версия: '..update_state.new_version)
            imgui.Spacing()
            imgui.TextWrapped(u8'Изменения: '..update_state.changelog)
            imgui.Spacing()
            
            if update_state.downloading then
                imgui.TextColored(imgui.ImVec4(1,0.7,0.2,1), u8'Загрузка...')
            else
                if imgui.Button(u8'?? Установить обновление', imgui.ImVec2(200,35)) then
                    download_update()
                end
                imgui.SameLine()
                if imgui.Button(u8'? Пропустить', imgui.ImVec2(120,35)) then
                    config.update.skip_version = update_state.new_version
                    save_config()
                    update_state.available = false
                    update_win.v = false
                end
            end
        else
            imgui.Text(u8'У вас последняя версия!')
            imgui.Spacing()
            
            if update_state.checking then
                imgui.TextColored(imgui.ImVec4(1,0.7,0.2,1), u8'Проверка...')
            else
                if imgui.Button(u8'?? Проверить обновления', imgui.ImVec2(200,35)) then
                    check_for_updates(false)
                end
            end
        end
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        
        if has_http then
            imgui.TextColored(imgui.ImVec4(0.2,0.8,0.4,1), u8'? HTTP доступен')
        else
            imgui.TextColored(imgui.ImVec4(1,0.3,0.3,1), u8'? HTTP недоступен')
            imgui.TextWrapped(u8'Для автообновлений установите библиотеку requests')
        end
        
        imgui.Spacing()
        imgui.Text(u8'GitHub: github.com/abutsik4/SampRpSupports')
    end
    imgui.End()
end

-- ============================================================================
-- ГЛАВНАЯ ФУНКЦИЯ
-- ============================================================================
function main()
    -- НЕ проверяем SAMP здесь - это делается в script_main!
    -- Эта функция вызывается только после подключения к серверу
    
    log.info('=== SupportsPlus Main Initialization ===')
    print('[SupportsPlus] SupportsPlus v2.1.5 загрузка...')
    
    log.info('Step 1/3: Parsing car database...')
    log.measure('parse_cars', parse_cars)
    log.with_context(log.LEVEL.INFO, 'Car database loaded', {count = #cars})
    
    log.info('Step 2/3: Filtering cars with default settings...')
    log.measure('filter_cars', filter_cars)
    log.with_context(log.LEVEL.INFO, 'Car filter applied', {filtered = #cars_filtered})
    
    log.info('Step 3/3: Applying ImGui theme...')
    log.measure('apply_theme', apply_theme)
    log.info('Theme applied successfully')
    
    sampAddChatMessage('{00FF00}[SupportsPlus] v2.1.5 загружен! F8 Меню | F9 Авто | F10 GPS | F11 Обновления', -1)
    log.info('=== SupportsPlus Fully Initialized and Ready ===')
    
    -- Проверка обновлений при старте
    if config.settings.check_updates_on_start and has_http then
        log.debug('Scheduling update check in 3 seconds')
        lua_thread.create(function()
            wait(3000)
            check_for_updates(true)
        end)
    end
    
    log.info('Entering main event loop')
    while true do
        wait(0)
        if wasKeyPressed(vkeys.VK_F8) then 
            main_win.v = not main_win.v
            log.debug('Hotkey F8: Main window toggled to ' .. tostring(main_win.v))
        end
        if wasKeyPressed(vkeys.VK_F9) then 
            car_win.v = not car_win.v
            filter_cars()
            log.debug('Hotkey F9: Car window toggled to ' .. tostring(car_win.v))
        end
        if wasKeyPressed(vkeys.VK_F10) then 
            gps_win.v = not gps_win.v
            log.debug('Hotkey F10: GPS window toggled to ' .. tostring(gps_win.v))
        end
        if wasKeyPressed(vkeys.VK_F11) then 
            update_win.v = not update_win.v
            log.debug('Hotkey F11: Update window toggled to ' .. tostring(update_win.v))
        end
    end
end

function imgui.OnDrawFrame()
    render_main()
    render_cars()
    render_gps()
    render_updates()
end

function onScriptTerminate(s, q)
    if s == thisScript() then
        save_config()
        log.info('=== SupportsPlus Terminated ===')
        print('[SupportsPlus] Выгружен')
    end
end

-- Запуск в отдельном потоке (корутины требуют lua_thread)
log.info('Creating main thread')

-- Hardcoded версия на случай если script_version() возвращает nil
local SCRIPT_VERSION = "2.1.6"

function script_main()
    if not isSampLoaded() or not isSampfuncsLoaded() then 
        log.error('SAMP/Sampfuncs not loaded, aborting')
        return 
    end
    
    log.debug('Waiting for SAMP availability...')
    while not isSampAvailable() do wait(100) end
    log.debug('Waiting for server connection...')
    repeat wait(0) until sampGetCurrentServerName() ~= 'SA-MP'
    
    log.info('Server connected, calling main()')
    -- Теперь вызываем main один раз
    main()
end

lua_thread.create(script_main)
