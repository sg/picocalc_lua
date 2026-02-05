--
-- simple http example
--
local http = require("lua/modules/http")
local url = "https://ipinfo.io"

print("Fetching URL: " ..url)
local response = http.get(url)

print("Status: " .. response.status)
print("Reason: " .. response.reason)
print("Headers:")
for k, v in pairs(response.headers) do
  print(k .. ":" .. v)
end
print("-------------------")
print("Body:")
print(response.body)
