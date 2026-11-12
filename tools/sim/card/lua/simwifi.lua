-- test only: join the simulator's access point without the stored, encrypted settings
if not wifi.isInitialized() then wifi.init("US") end
print(wifi.connect("PicoCalc-Sim", "simulator", wifi.AUTH_WPA2, 15000))
local t = os.clock() + 15
while not wifi.isConnected() and os.clock() < t do end
print("connected:", wifi.isConnected(), "free:", sys.freeMemory())
