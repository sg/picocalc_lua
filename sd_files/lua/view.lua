draw.clear()
draw.enableBuffer(1) -- psram
local bmp = draw.loadBMPSprites("screen001.bmp", 320, 320)
bmp:blit(1,1)

