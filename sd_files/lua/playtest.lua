-- drawing / play test

local function randomCircle()
	local x = math.random(0,319)
	local y = math.random(0,319)
	local r = math.random(20,50)
	local c = colors.fromHSV(math.random(0,255),255,255)
	draw.circleFill(x,y,r,c)
end

local sprites = draw.loadBMPSprites("lua/boxworld.bmp", 20, 20)

local function drawSprite(p)
	--local x = math.random(-29, 319)
	--local y = math.random(-29, 319)
	--local id = math.random(0,13)
	
  sprites:blit(p.x,p.y,p.sprite_id)
  
end

local player1 = {
  sprite_id = 2,
  x = 20,
  y = 20,
  speed = 5,
  move = function(self, dx, dy)
    self.x = self.x + dx
    self.y = self.y + dy
  end,
  print_position = function(self)
    term.setCursorPos(0,39)
    term.write("p1: " .. self.x .. "," .. self.y)
  end
}

--local start, dur0, dur1, dur2
--local testDraw = randomCircle
--local testDraw = randomSprite

--draw.clear()
--start = os.clock()
--for i=1,1000 do
--	testDraw()
--end
--dur0 = os.clock()-start

--draw.enableBuffer(true)
--draw.clear()
--start = os.clock()
--for i=1,1000 do
--	testDraw()
--end
--draw.blitBuffer()
--dur1 = os.clock()-start
--draw.enableBuffer(false)

draw.enableBuffer(2)
draw.clear()
--for i=1,1000 do
--	testDraw()
--end
local done = false

while not done do

  local i, j, k = keys.wait()
  if k:lower() == 'q' then
    done = true
  elseif k == keys.up then
    player1.y = player1.y - 1
  elseif k == keys.down then
    player1.y = player1.y + 1
  elseif k == keys.right then
    player1.x = player1.x + 1
  elseif k == keys.left then
    player1.x = player1.x - 1
  end

  draw.clear()
  drawSprite(player1)
  draw.blitBuffer()

end
draw.enableBuffer(false)
