# Wi-Fi Module for PicoCalc <!-- omit in toc -->

The `wifi` module provides Wi-Fi networking capabilities for the PicoCalc running on a Pico 2W (RP2350 with CYW43 wireless chip). This module enables scanning for networks, connecting to access points, and retrieving network information.

- [Getting Started](#getting-started)
- [Basic Usage](#basic-usage)
  - [Initializing Wi-Fi](#initializing-wi-fi)
  - [Scanning for Networks](#scanning-for-networks)
  - [Connecting to a Network](#connecting-to-a-network)
  - [Checking Connection Status](#checking-connection-status)
  - [Getting Network Information](#getting-network-information)
  - [Disconnecting](#disconnecting)
- [Complete Example](#complete-example)
- [API Reference](#api-reference)
  - [Functions](#functions)
  - [Constants](#constants)
- [Error Handling](#error-handling)
- [Tips and Best Practices](#tips-and-best-practices)

---

## Getting Started

The Wi-Fi module must be initialized before use. Initialization powers on the CYW43 wireless chip and configures it for station (client) mode.

```lua
-- Initialize Wi-Fi with default settings
if wifi.init() then
    print("Wi-Fi ready!")
else
    print("Failed to initialize Wi-Fi")
end
```

For best results, specify your country code during initialization. This ensures the correct regulatory settings for your region:

```lua
-- Initialize with country code (recommended)
wifi.init("US")  -- United States
wifi.init("GB")  -- United Kingdom
wifi.init("DE")  -- Germany
wifi.init("JP")  -- Japan
```

---

## Basic Usage

### Initializing Wi-Fi

```lua
-- Simple initialization
local ok = wifi.init()

-- With country code (recommended)
local ok = wifi.init("US")

-- Check if already initialized
if wifi.isInitialized() then
    print("Wi-Fi is ready")
end
```

### Scanning for Networks

The `wifi.scan()` function performs a blocking scan for nearby Wi-Fi networks and returns a table of results:

```lua
local networks = wifi.scan()

if networks then
    print("Found " .. #networks .. " networks:")
    for i, net in ipairs(networks) do
        local security = net.secure and "Secured" or "Open"
        print(string.format("%d. %-20s  Ch:%2d  RSSI:%4d  %s",
            i, net.ssid, net.channel, net.rssi, security))
    end
else
    print("Scan failed")
end
```

Each network entry contains:
- `ssid` - Network name (string)
- `rssi` - Signal strength in dBm (number, typically -30 to -90)
- `channel` - Wi-Fi channel 1-14 (number)
- `secure` - Whether authentication is required (boolean)
- `authMode` - Raw authentication mode value (number)
- `bssid` - MAC address as "XX:XX:XX:XX:XX:XX" (string)

### Connecting to a Network

```lua
-- Connect to an open network
local ok, err = wifi.connect("OpenNetwork", "")

-- Connect to a WPA2 network (most common)
local ok, err = wifi.connect("MyNetwork", "mypassword123")

-- Explicit authentication type
local ok, err = wifi.connect("MyNetwork", "mypassword123", wifi.AUTH_WPA2)

-- With custom timeout (in milliseconds)
local ok, err = wifi.connect("MyNetwork", "mypassword123", wifi.AUTH_WPA2, 60000)

if ok then
    print("Connected successfully!")
else
    print("Connection failed: " .. (err or "unknown error"))
end
```

### Checking Connection Status

```lua
-- Simple connected check
if wifi.isConnected() then
    print("Connected to Wi-Fi with IP address")
end

-- Detailed status check
local status = wifi.status()

if status == wifi.STATUS_UP then
    print("Fully connected with IP")
elseif status == wifi.STATUS_JOIN then
    print("Associated with AP, waiting for IP...")
elseif status == wifi.STATUS_NOIP then
    print("Connected but no IP yet (DHCP in progress)")
elseif status == wifi.STATUS_DOWN then
    print("Not connected")
elseif status == wifi.STATUS_FAIL then
    print("Connection failed")
elseif status == wifi.STATUS_BADAUTH then
    print("Authentication failed - check password")
elseif status == wifi.STATUS_NONET then
    print("Network not found")
end
```

### Getting Network Information

```lua
-- Individual queries
local ip = wifi.getIP()
local gateway = wifi.getGateway()
local netmask = wifi.getNetmask()

if ip then
    print("IP Address: " .. ip)
    print("Gateway:    " .. gateway)
    print("Netmask:    " .. netmask)
end

-- All info at once
local info = wifi.getInfo()
if info then
    print("IP:      " .. info.ip)
    print("Gateway: " .. info.gateway)
    print("Netmask: " .. info.netmask)
end
```

### Disconnecting

```lua
-- Disconnect from current network
wifi.disconnect()

-- Completely shut down Wi-Fi (frees resources)
wifi.deinit()
```

---

## Complete Example

Here's a complete example that demonstrates typical Wi-Fi usage:

```lua
-- Wi-Fi connection utility for PicoCalc

-- Initialize Wi-Fi
print("Initializing Wi-Fi...")
if not wifi.init("US") then
    print("ERROR: Failed to initialize Wi-Fi")
    return
end
print("Wi-Fi initialized!")

-- Scan for networks
print("\nScanning for networks...")
local networks = wifi.scan()

if not networks or #networks == 0 then
    print("No networks found")
    wifi.deinit()
    return
end

-- Display available networks
print(string.format("\nFound %d networks:\n", #networks))
print("    SSID                  CH   RSSI   Security")
print("    " .. string.rep("-", 45))

for i, net in ipairs(networks) do
    local security = net.secure and "Yes" or "No"
    print(string.format("%2d. %-20s  %2d   %4d   %s",
        i, net.ssid, net.channel, net.rssi, security))
end

-- Connect to a network
local ssid = "MyNetwork"
local password = "mypassword123"

print(string.format("\nConnecting to '%s'...", ssid))
local ok, err = wifi.connect(ssid, password, wifi.AUTH_WPA2, 30000)

if not ok then
    print("Connection failed: " .. (err or "unknown error"))
    wifi.deinit()
    return
end

print("Connected!")

-- Display network information
local info = wifi.getInfo()
if info then
    print("\nNetwork Information:")
    print("  IP Address: " .. info.ip)
    print("  Gateway:    " .. info.gateway)
    print("  Netmask:    " .. info.netmask)
end

-- Keep connection active (in a real application)
print("\nPress any key to disconnect...")
keys.wait()

-- Clean up
wifi.disconnect()
wifi.deinit()
print("Disconnected and Wi-Fi shut down")
```

---

## API Reference

### Functions

| Function | Description |
|----------|-------------|
| `wifi.init([country])` | Initialize Wi-Fi hardware |
| `wifi.deinit()` | Shut down Wi-Fi and free resources |
| `wifi.isInitialized()` | Check if Wi-Fi is initialized |
| `wifi.scan()` | Scan for available networks |
| `wifi.connect(ssid, password, [auth], [timeout])` | Connect to a network |
| `wifi.disconnect()` | Disconnect from current network |
| `wifi.status()` | Get connection status code |
| `wifi.isConnected()` | Check if connected with IP |
| `wifi.getIP()` | Get assigned IP address |
| `wifi.getGateway()` | Get gateway address |
| `wifi.getNetmask()` | Get subnet mask |
| `wifi.getInfo()` | Get all network info as table |

### Constants

**Authentication Modes:**
| Constant | Value | Description |
|----------|-------|-------------|
| `wifi.AUTH_OPEN` | 0 | Open network (no password) |
| `wifi.AUTH_WPA2` | 1 | WPA2-PSK (most common) |
| `wifi.AUTH_WPA3` | 2 | WPA3-SAE (newer, more secure) |

**Status Codes:**
| Constant | Value | Description |
|----------|-------|-------------|
| `wifi.STATUS_DOWN` | 0 | Link down, not connected |
| `wifi.STATUS_JOIN` | 1 | Associated with access point |
| `wifi.STATUS_NOIP` | 2 | Connected, waiting for DHCP |
| `wifi.STATUS_UP` | 3 | Fully connected with IP address |
| `wifi.STATUS_FAIL` | -1 | Connection failed |
| `wifi.STATUS_NONET` | -2 | Network not found |
| `wifi.STATUS_BADAUTH` | -3 | Authentication failed |

---

## Error Handling

Most Wi-Fi functions that can fail return two values: a success indicator and an error message.

```lua
-- Pattern for error handling
local ok, err = wifi.connect("MyNetwork", "password")
if not ok then
    if err == "authentication failed" then
        print("Wrong password!")
    elseif err == "network not found" then
        print("Can't find that network")
    elseif err == "Wi-Fi not initialized" then
        print("Call wifi.init() first")
    else
        print("Error: " .. err)
    end
end
```

For `wifi.scan()`, check for `nil` return:

```lua
local networks, err = wifi.scan()
if not networks then
    print("Scan error: " .. (err or "unknown"))
end
```

---

## Tips and Best Practices

1. **Always initialize with a country code** - This ensures compliance with local regulations and optimal channel selection.

2. **Check initialization status** - Before performing any Wi-Fi operations, verify that `wifi.isInitialized()` returns true.

3. **Use appropriate timeouts** - The default 30-second timeout works for most networks, but increase it for networks with slow DHCP servers.

4. **Handle connection failures gracefully** - Networks can be unreliable; always check return values and provide user feedback.

5. **Clean up when done** - Call `wifi.deinit()` when Wi-Fi is no longer needed to free resources.

6. **Signal strength interpretation**:
   - `-30 to -50 dBm`: Excellent signal
   - `-50 to -60 dBm`: Good signal
   - `-60 to -70 dBm`: Fair signal
   - `-70 to -80 dBm`: Weak signal
   - `-80 to -90 dBm`: Very weak, may have issues

7. **Blocking operations** - All Wi-Fi operations (scan, connect) are blocking. The device will be unresponsive during these operations. Plan your UI accordingly.

---

## Future Enhancements

The following features are planned for future releases:

- **Phase 2**: TCP/UDP socket support for raw network communication
- **Phase 3**: HTTP/HTTPS client for web requests with TLS encryption
