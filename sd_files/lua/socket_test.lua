--
-- socket test
--
local tsock, msg = socket.tcp()
if tsock:connect("192.168.44.75", 8888, 30000) then
  print("connectin successful")
  local sent, smsg = tsock:send("Hello!")
  print("sent: " .. sent)
else
  print("connect failed")
end
