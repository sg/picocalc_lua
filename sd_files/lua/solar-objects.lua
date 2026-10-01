-- Solar System Object Finder
-- V1.0 11.02.2026
-- Peter Doerwald
-- Converted from MMBasic to Lua
-- Adapted for PicoCalc Lua

-- ANSI escape codes
local ESC = "\27["
local RESET = ESC .. "0m"
local BOLD = ESC .. "1m"
local DIM = ESC .. "2m"
local CYAN = ESC .. "96m"
local GREEN = ESC .. "92m"
local YELLOW = ESC .. "93m"
local RED = ESC .. "91m"
local WHITE = ESC .. "97m"
local MAGENTA = ESC .. "95m"

-- GPS Coordinates (degrees)
local lat = 32.295230     -- negative if south
local long = -97.886451   -- negative if west
local zone = -5           -- Timezone, here UTC-5

local utc_str = ""
local alt, az = 0, 0
local stunde, minute, sekunde = 0, 0, 0
local tag, monat, jahr = 0, 0, 0
local days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local solar = {"SUN", "MOON", "MERCURY", "VENUS", "MARS", "JUPITER", "SATURN", "URANUS", "NEPTUNE"}

----------------------------------------------------------------------
-- Math helpers
----------------------------------------------------------------------
local pi = math.pi
local rad = math.rad
local deg = math.deg
local sin = math.sin
local cos = math.cos
local tan = math.tan
local asin = math.asin
local acos = math.acos
local atan2 = math.atan2 or math.atan  -- Lua 5.3+

local function normalize(angle)
    angle = angle % 360
    if angle < 0 then angle = angle + 360 end
    return angle
end

----------------------------------------------------------------------
-- Days since J2000.0 from calendar date + UTC time
-- Returns (JD - 2451545.0) computed in a way that preserves
-- precision on 32-bit float platforms (avoids adding small
-- fractional hours to large Julian Date numbers).
----------------------------------------------------------------------
local function djd(y, m, d, h, mn, s)
    local ut = h + mn / 60 + s / 3600
    if m <= 2 then
        y = y - 1
        m = m + 12
    end
    local A = math.floor(y / 100)
    local B = 2 - A + math.floor(A / 4)
    -- Split into integer day number and fractional day.
    -- The constant -1525 is -(1524.5 + 0.5); the 0.5 is added
    -- back into the fractional part so jd_int stays integer.
    local jd_int = math.floor(365.25 * (y + 4716)) +
                   math.floor(30.6001 * (m + 1)) +
                   d + B - 1525
    local jd_frac = ut / 24 + 0.5
    -- Subtract J2000 epoch from the integer part (keeps numbers small)
    return (jd_int - 2451545) + jd_frac
end

----------------------------------------------------------------------
-- Greenwich Mean Sidereal Time (degrees) from days since J2000
----------------------------------------------------------------------
local function gmst(d)
    local T = d / 36525.0
    local theta = 280.46061837 + 360.98564736629 * d +
                  0.000387933 * T * T - T * T * T / 38710000.0
    return normalize(theta)
end

----------------------------------------------------------------------
-- Equatorial (RA, Dec) -> Horizontal (Alt, Az)
-- ra, dec in degrees; lst = local sidereal time in degrees
----------------------------------------------------------------------
local function equatorialToHorizontal(ra_deg, dec_deg, lst_deg, lat_deg)
    local ha = rad(lst_deg - ra_deg)
    local dec = rad(dec_deg)
    local la = rad(lat_deg)

    local sin_alt = sin(dec) * sin(la) + cos(dec) * cos(la) * cos(ha)
    local altitude = deg(asin(sin_alt))

    local cos_az = (sin(dec) - sin(la) * sin_alt) / (cos(la) * cos(rad(altitude)))
    -- clamp for numerical safety
    if cos_az > 1 then cos_az = 1 end
    if cos_az < -1 then cos_az = -1 end
    local azimuth = deg(acos(cos_az))

    if sin(ha) > 0 then azimuth = 360 - azimuth end

    return altitude, azimuth
end

----------------------------------------------------------------------
-- Solve Kepler's equation M = E - e*sin(E) by iteration
-- M in radians, returns E in radians
----------------------------------------------------------------------
local function solveKepler(M_rad, e)
    local E = M_rad
    for _ = 1, 30 do
        local dE = (M_rad - (E - e * sin(E))) / (1 - e * cos(E))
        E = E + dE
        if math.abs(dE) < 1e-12 then break end
    end
    return E
end

----------------------------------------------------------------------
-- Planetary orbital elements at J2000.0 and rates per Julian century
-- Source: Standish (1992) / JPL
----------------------------------------------------------------------
local planet_elements = {
    MERCURY = {
        0.38709927, 0.20563593,  7.00497902, 252.25032350,  77.45779628,  48.33076593,
        0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081
    },
    VENUS = {
        0.72333566, 0.00677672,  3.39467605, 181.97909950, 131.60246718,  76.67984255,
        0.00000390,-0.00004107, -0.00078890, 58517.81538729,  0.00268329, -0.27769418
    },
    EARTH = {
        1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193,   0.0,
        0.00000562,-0.00004392, -0.01294668, 35999.37244981, 0.32327364,   0.0
    },
    MARS = {
        1.52371034, 0.09339410,  1.84969142,  -4.55343205, -23.94362959,  49.55953891,
        0.00001847, 0.00007882, -0.00813131, 19140.30268499,  0.44441088, -0.29257343
    },
    JUPITER = {
        5.20288700, 0.04838624,  1.30439695,  34.39644051,  14.72847983, 100.47390909,
       -0.00011607,-0.00013253, -0.00183714, 3034.74612775,  0.21252668,  0.20469106
    },
    SATURN = {
        9.53667594, 0.05386179,  2.48599187,  49.95424423,  92.59887831, 113.66242448,
       -0.00125060,-0.00050991,  0.00193609, 1222.49362201, -0.41897216, -0.28867794
    },
    URANUS = {
       19.18916464, 0.04725744,  0.77263783, 313.23810451, 170.95427630,  74.01692503,
       -0.00196176,-0.00004397, -0.00242939, 428.48202785,   0.40805281,  0.04240589
    },
    NEPTUNE = {
       30.06992276, 0.00859048,  1.77004347, -55.12002969,  44.96476227, 131.78422574,
        0.00026291, 0.00005105,  0.00035372, 218.45945325,  -0.32241464, -0.00508664
    },
}

----------------------------------------------------------------------
-- Compute heliocentric ecliptic coordinates (x,y,z) in AU
----------------------------------------------------------------------
local function heliocentricXYZ(elem, T)
    local a    = elem[1]  + elem[7]  * T
    local e    = elem[2]  + elem[8]  * T
    local I    = elem[3]  + elem[9]  * T
    local L    = elem[4]  + elem[10] * T
    local wbar = elem[5]  + elem[11] * T
    local node = elem[6]  + elem[12] * T

    local w = wbar - node            -- argument of perihelion
    local M = normalize(L - wbar)    -- mean anomaly

    local E = solveKepler(rad(M), e)

    -- heliocentric coords in orbital plane
    local xp = a * (cos(E) - e)
    local yp = a * math.sqrt(1 - e * e) * sin(E)

    -- rotate to ecliptic
    local w_r = rad(w)
    local node_r = rad(node)
    local I_r = rad(I)

    local cos_w = cos(w_r)
    local sin_w = sin(w_r)
    local cos_n = cos(node_r)
    local sin_n = sin(node_r)
    local cos_I = cos(I_r)
    local sin_I = sin(I_r)

    local x = (cos_w * cos_n - sin_w * sin_n * cos_I) * xp +
              (-sin_w * cos_n - cos_w * sin_n * cos_I) * yp
    local y = (cos_w * sin_n + sin_w * cos_n * cos_I) * xp +
              (-sin_w * sin_n + cos_w * cos_n * cos_I) * yp
    local z = (sin_w * sin_I) * xp + (cos_w * sin_I) * yp

    return x, y, z
end

----------------------------------------------------------------------
-- Compute geocentric ecliptic longitude and latitude (degrees)
----------------------------------------------------------------------
local function planetGeoEcliptic(planet_name, T)
    local ex, ey, ez = heliocentricXYZ(planet_elements.EARTH, T)
    local px, py, pz = heliocentricXYZ(planet_elements[planet_name], T)

    local dx = px - ex
    local dy = py - ey
    local dz = pz - ez

    local ecl_lon = deg(atan2(dy, dx))
    local ecl_lat = deg(atan2(dz, math.sqrt(dx * dx + dy * dy)))

    return normalize(ecl_lon), ecl_lat
end

----------------------------------------------------------------------
-- Ecliptic (lon, lat) -> Equatorial (RA, Dec), all in degrees
----------------------------------------------------------------------
local function eclipticToEquatorial(ecl_lon, ecl_lat, obliquity)
    local lon = rad(ecl_lon)
    local la = rad(ecl_lat)
    local eps = rad(obliquity)

    local sin_dec = sin(la) * cos(eps) + cos(la) * sin(eps) * sin(lon)
    local dec_deg = deg(asin(sin_dec))

    local y_val = sin(lon) * cos(eps) - tan(la) * sin(eps)
    local x_val = cos(lon)
    local ra_deg = normalize(deg(atan2(y_val, x_val)))

    return ra_deg, dec_deg
end

----------------------------------------------------------------------
-- Sun position (geocentric ecliptic longitude)
----------------------------------------------------------------------
local function sunPosition(T)
    local M = normalize(357.5291092 + 35999.0502909 * T)
    local M_r = rad(M)
    local C = 1.9146 * sin(M_r) + 0.0200 * sin(2 * M_r) + 0.0003 * sin(3 * M_r)
    local lon = normalize(M + C + 180.0 + 102.9372)
    return lon, 0.0
end

----------------------------------------------------------------------
-- Moon position (simplified, main terms)
----------------------------------------------------------------------
local function moonPosition(T)
    local Lp = normalize(218.3165 + 481267.8813 * T)
    local D  = normalize(297.8502 + 445267.1115 * T)
    local M  = normalize(357.5291 + 35999.0503 * T)
    local Mp = normalize(134.9634 + 477198.8676 * T)
    local F  = normalize(93.2720  + 483202.0175 * T)

    local Lp_r = rad(Lp)
    local D_r = rad(D)
    local M_r = rad(M)
    local Mp_r = rad(Mp)
    local F_r = rad(F)

    local lon = Lp
        + 6.289 * sin(Mp_r)
        - 1.274 * sin(2 * D_r - Mp_r)
        + 0.658 * sin(2 * D_r)
        + 0.214 * sin(2 * Mp_r)
        - 0.186 * sin(M_r)
        - 0.114 * sin(2 * F_r)
        + 0.059 * sin(2 * D_r - 2 * Mp_r)
        + 0.057 * sin(2 * D_r - M_r - Mp_r)
        + 0.053 * sin(2 * D_r + Mp_r)
        + 0.046 * sin(2 * D_r - M_r)
        - 0.041 * sin(Mp_r - M_r)
        - 0.035 * sin(D_r)
        - 0.030 * sin(M_r + Mp_r)

    local lat = 5.128 * sin(F_r)
        + 0.281 * sin(Mp_r + F_r)
        + 0.278 * sin(Mp_r - F_r)
        + 0.173 * sin(2 * D_r - F_r)
        + 0.055 * sin(2 * D_r - Mp_r + F_r)
        + 0.046 * sin(2 * D_r - Mp_r - F_r)
        + 0.033 * sin(2 * D_r + F_r)
        + 0.017 * sin(2 * Mp_r + F_r)

    return normalize(lon), lat
end

----------------------------------------------------------------------
-- Main astro function: returns altitude and azimuth
-- d = days since J2000.0 (from djd())
----------------------------------------------------------------------
local function astro(object_name, d, lst_deg)
    local T = d / 36525.0
    local obliquity = 23.4393 - 0.0000004 * d

    local ecl_lon, ecl_lat

    if object_name == "SUN" then
        ecl_lon, ecl_lat = sunPosition(T)
    elseif object_name == "MOON" then
        ecl_lon, ecl_lat = moonPosition(T)
    else
        ecl_lon, ecl_lat = planetGeoEcliptic(object_name, T)
    end

    local ra, dec = eclipticToEquatorial(ecl_lon, ecl_lat, obliquity)
    return equatorialToHorizontal(ra, dec, lst_deg, lat)
end

----------------------------------------------------------------------
-- UTC calculation from local time (pure function, no side effects)
-- Returns utc_hour, utc_day, utc_month, utc_year, utc_string
----------------------------------------------------------------------
local function calcUTC()
    local h = stunde - zone
    local d, m, y = tag, monat, jahr

    -- Correction for negative hour (previous day)
    if h < 0 then
        h = 24 + h
        d = d - 1
        if d < 1 then
            m = m - 1
            if m < 1 then
                m = 12
                y = y - 1
            end
            d = days[m]
        end
    end

    -- Correction for hour overflow (next day)
    if h > 23 then
        h = h - 24
        d = d + 1
        if d > days[m] then
            d = 1
            m = m + 1
            if m > 12 then
                m = 1
                y = y + 1
            end
        end
    end

    local s = string.format("%02d-%02d-%04d %02d:%02d:%02d",
        d, m, y, h, minute, sekunde)
    return h, d, m, y, s
end

----------------------------------------------------------------------
-- Prompt user for date, time, and location
----------------------------------------------------------------------
local function prompt_settings()
    term.write(GREEN .. "Solar System Object Finder" .. WHITE .. "\n")
    term.write(DIM .. "Peter Doerwald - Adapted for PicoCalc" .. RESET .. "\n\n")

    term.write(CYAN .. "Enter date and time (local)" .. WHITE .. "\n")

    local input

    input = term.read("  Year [2026]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    jahr = tonumber(input) or 2026

    input = term.read("  Month [3]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    monat = tonumber(input) or 3

    input = term.read("  Day [14]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    tag = tonumber(input) or 14

    input = term.read("  Hour (24h) [12]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    stunde = tonumber(input) or 12

    input = term.read("  Minute [0]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    minute = tonumber(input) or 0

    sekunde = 0

    term.write("\n" .. CYAN .. "Location" .. WHITE .. "\n")

    input = term.read("  Latitude [" .. lat .. "]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    if input ~= "" then lat = tonumber(input) or lat end

    input = term.read("  Longitude [" .. long .. "]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    if input ~= "" then long = tonumber(input) or long end

    input = term.read("  UTC offset [" .. zone .. "]: ")
    input = input and input:match("^%s*(.-)%s*$") or ""
    if input ~= "" then zone = tonumber(input) or zone end
end

----------------------------------------------------------------------
-- Display results
----------------------------------------------------------------------
local function display_results()
    local utc_h, utc_d, utc_m, utc_y, utc_s = calcUTC()

    local d = djd(utc_y, utc_m, utc_d, utc_h, minute, sekunde)
    local lst_deg = gmst(d) + long

    term.clear()
    term.setCursorPos(1, 1)
    term.setCursorBlink(false)

    term.write(GREEN .. "** Solar System Object Finder **" .. WHITE .. "\n")
    term.write(CYAN .. "Local: " .. WHITE
        .. string.format("%02d-%02d-%04d %02d:%02d:%02d", tag, monat, jahr, stunde, minute, sekunde) .. "\n")
    term.write(CYAN .. "UTC:   " .. WHITE .. utc_s .. "\n")
    term.write(CYAN .. "Lat: " .. WHITE .. string.format("%.4f", lat)
        .. CYAN .. "  Lon: " .. WHITE .. string.format("%.4f", long)
        .. CYAN .. "  TZ: " .. WHITE .. string.format("%+d", zone) .. "\n")
    term.write("\n")

    -- header
    term.write(YELLOW .. string.format("%-10s %10s %10s", "Object", "Altitude", "Azimuth")
        .. WHITE .. "\n")
    term.write(DIM .. string.rep("-", 34) .. RESET .. "\n")

    for i = 1, #solar do
        alt, az = astro(solar[i], d, lst_deg)

        local name_color = WHITE
        local marker = ""

        if alt < 0 then
            -- below horizon: dim
            name_color = DIM
            marker = " *"
        elseif solar[i] == "SUN" then
            name_color = YELLOW
        elseif solar[i] == "MOON" then
            name_color = CYAN
        else
            name_color = GREEN
        end

        term.write(name_color
            .. string.format("%-10s", solar[i])
            .. WHITE
            .. string.format(" %9.4f %9.4f", alt, az)
            .. RED .. marker .. WHITE .. "\n")
    end

    term.write("\n")
    term.write(DIM .. "(* = below horizon)" .. RESET .. "\n")
    term.write("\n")
    term.write(CYAN .. "[+/-] " .. WHITE .. "adjust hour  "
        .. CYAN .. "[</>] " .. WHITE .. "adjust day  "
        .. CYAN .. "[r] " .. WHITE .. "re-enter  "
        .. CYAN .. "[q] " .. WHITE .. "quit\n")
end

----------------------------------------------------------------------
-- Main loop with keyboard controls
----------------------------------------------------------------------
local function main()
    term.setCursorBlink(false)
    prompt_settings()

    -- save original local-time values for adjustments
    local orig_stunde = stunde
    local orig_tag = tag
    local orig_monat = monat
    local orig_jahr = jahr

    display_results()

    while true do
        local state, _, code = keys.wait(true, true)

        if code == "q" or code == "Q" or code == keys.esc then
            break

        elseif code == "+" or code == "=" or code == keys.up then
            -- advance one hour
            orig_stunde = orig_stunde + 1
            if orig_stunde > 23 then
                orig_stunde = 0
                orig_tag = orig_tag + 1
                if orig_tag > days[orig_monat] then
                    orig_tag = 1
                    orig_monat = orig_monat + 1
                    if orig_monat > 12 then
                        orig_monat = 1
                        orig_jahr = orig_jahr + 1
                    end
                end
            end
            stunde = orig_stunde
            tag = orig_tag
            monat = orig_monat
            jahr = orig_jahr
            display_results()

        elseif code == "-" or code == "_" or code == keys.down then
            -- go back one hour
            orig_stunde = orig_stunde - 1
            if orig_stunde < 0 then
                orig_stunde = 23
                orig_tag = orig_tag - 1
                if orig_tag < 1 then
                    orig_monat = orig_monat - 1
                    if orig_monat < 1 then
                        orig_monat = 12
                        orig_jahr = orig_jahr - 1
                    end
                    orig_tag = days[orig_monat]
                end
            end
            stunde = orig_stunde
            tag = orig_tag
            monat = orig_monat
            jahr = orig_jahr
            display_results()

        elseif code == ">" or code == "." or code == keys.right then
            -- advance one day
            orig_tag = orig_tag + 1
            if orig_tag > days[orig_monat] then
                orig_tag = 1
                orig_monat = orig_monat + 1
                if orig_monat > 12 then
                    orig_monat = 1
                    orig_jahr = orig_jahr + 1
                end
            end
            stunde = orig_stunde
            tag = orig_tag
            monat = orig_monat
            jahr = orig_jahr
            display_results()

        elseif code == "<" or code == "," or code == keys.left then
            -- go back one day
            orig_tag = orig_tag - 1
            if orig_tag < 1 then
                orig_monat = orig_monat - 1
                if orig_monat < 1 then
                    orig_monat = 12
                    orig_jahr = orig_jahr - 1
                end
                orig_tag = days[orig_monat]
            end
            stunde = orig_stunde
            tag = orig_tag
            monat = orig_monat
            jahr = orig_jahr
            display_results()

        elseif code == "r" or code == "R" then
            -- re-enter settings
            term.clear()
            term.setCursorPos(1, 1)
            term.setCursorBlink(true)
            prompt_settings()
            orig_stunde = stunde
            orig_tag = tag
            orig_monat = monat
            orig_jahr = jahr
            display_results()
        end
    end

    -- restore terminal
    term.write("\n")
    term.setCursorBlink(true)
end

main()
