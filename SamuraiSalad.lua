-- Samurai Salad by Michiel for PineJam 2023

local Pine3D = require("Pine3D.Pine3D")
local SCREEN_WIDTH, SCREEN_HEIGHT = term.getSize()
local SCREEN_RATIO = SCREEN_HEIGHT * 3 / (SCREEN_WIDTH * 2)
local frame = Pine3D.newFrame()
frame:setCamera(0, 0, 0, 0, 0, 0)
frame:setFoV(90)
frame:setBackgroundColor(colors.cyan)
local tZ = 3 -- distance from camera for targets

local oldLightBlue = table.pack(term.getPaletteColor(colors.lightBlue))
term.setPaletteColour(colors.lightBlue, 0x4284ba)
local function resetPalette()
    term.setPaletteColour(colors.lightBlue, oldLightBlue[1], oldLightBlue[2], oldLightBlue[3])
end

local backgroundObj = frame:newObject("models/background.stab")

---@type Target[]
local targets = {}

---@type Particle[]
local particles = {}

---@type Explosion[]
local explosions = {}

if periphemu then
    -- Attach speakers
    local SIDES = { "top", "bottom", "left", "right", "front", "back" }
    for i = 1, #SIDES do
        periphemu.create(SIDES[i], "speaker")
    end
end

---@type Speaker[]
local speakers = table.pack(peripheral.find("speaker"))
local nextSpeakerToUse = 1
---@param name string The name of the sound to play
---@param volume number? The volume to play at (0.0 - 3.0, defaults to 1.0)
---@param pitch number? The speed to play at (0.5 - 2.0, defaults to 12)
local function playSound(name, volume, pitch)
    speakers[nextSpeakerToUse].playSound(name, volume, pitch)
    nextSpeakerToUse = nextSpeakerToUse % #speakers + 1
end
if #speakers <= 0 then playSound = function() return end end

-- Game state
local lives = 5
local points = 0
local combo = 0

local CONF_FILE = "samurai.conf"
local function beforeExit()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    resetPalette()

    -- Read save data
    local conf_data = {}
    if fs.exists(CONF_FILE) then
        local file = fs.open(CONF_FILE, "r")
        if not file then error("Can't read file " .. CONF_FILE .. "...") end
        local str = file.readAll()
        file.close()

        conf_data = textutils.unserialise(str or "") or {}
    end

    local newHighscore = false
    conf_data.highscore = conf_data.highscore or 0
    if points > conf_data.highscore then
        newHighscore = true
        conf_data.highscore = points
    end

    -- Write save data
    local str = textutils.serialise(conf_data)
    local file = fs.open(CONF_FILE, "w")
    if not file then error("Can't write to file " .. CONF_FILE .. "...") end
    file.write(str)
    file.close()

    print("Thanks for playing Samurai Salad!\n")
    term.setTextColor(colors.yellow)
    write("You scored ")
    term.setTextColor(colors.orange)
    write(tostring(points))
    term.setTextColor(colors.yellow)
    print(" points!\n")
    term.setTextColor(colors.white)

    if newHighscore then
        print("New highscore!")
    else
        print("Highscore: " .. conf_data.highscore)
    end
    print("")
end

local max = math.max
local min = math.min
local abs = math.abs
local sqrt = math.sqrt
local sin = math.sin
local cos = math.cos
local floor = math.floor
local rand = math.random

-- Sprites
local __ = 0
local YE = colors.yellow
local OR = colors.orange
local LI = colors.lime
local GR = colors.green
local sprPineapple = {
    { GR, __, LI },
    { __, GR },
    { OR, YE, YE },
    { __, YE }
}
local sprNumbers = {
    [0] = {
        { YE, YE, YE },
        { YE, __, YE },
        { OR, __, OR },
        { OR, __, OR },
        { OR, OR, OR }
    },
    [1] = {
        { YE },
        { YE },
        { OR },
        { OR },
        { OR }
    },
    [2] = {
        { YE, YE, YE },
        { __, __, YE },
        { OR, OR, OR },
        { OR },
        { OR, OR, OR }
    },
    [3] = {
        { YE, YE, YE },
        { __, __, YE },
        { OR, OR, OR },
        { __, __, OR },
        { OR, OR, OR }
    },
    [4] = {
        { YE, __, YE },
        { YE, __, YE },
        { OR, OR, OR },
        { __, __, OR },
        { __, __, OR }
    },
    [5] = {
        { YE, YE, YE },
        { YE },
        { OR, OR, OR },
        { __, __, OR },
        { OR, OR, OR }
    },
    [6] = {
        { YE, YE, YE },
        { YE },
        { OR, OR, OR },
        { OR, __, OR },
        { OR, OR, OR }
    },
    [7] = {
        { YE, YE, YE },
        { __, __, YE },
        { __, OR },
        { __, OR },
        { __, OR }
    },
    [8] = {
        { YE, YE, YE },
        { YE, __, YE },
        { OR, OR, OR },
        { OR, __, OR },
        { OR, OR, OR }
    },
    [9] = {
        { YE, YE, YE },
        { YE, __, YE },
        { OR, OR, OR },
        { __, __, OR },
        { OR, OR, OR }
    },
}
local sprTimes = {
    { 1, 0, 1 },
    { 0, 1 },
    { 1, 0, 1 }
}

---@param buffer Buffer
---@param sx number
---@param sy number
---@param image table
local function drawShadedChar(buffer, sx, sy, image)
    local c2 = buffer.screenBuffer.c2
    local width = buffer.width
    for y, row in pairs(image) do
        local drawY = sy + y
        local c2Y = c2[drawY]
        if c2Y then
            local color = y <= 3 - (sy % 3) and YE or OR
            for x, value in pairs(row) do
                if value and value > 0 then
                    local drawX = sx + x
                    if drawX >= 1 and drawX <= width then
                        c2Y[drawX] = color
                    end
                end
            end
        end
    end
end

---@param buffer Buffer
---@param n integer
---@param x integer
---@param y integer
---@return integer x coordinate where next character may be drawn
local function drawNumber(buffer, n, x, y)
    local str = tostring(n)
    for i = 1, #str do
        local c = tonumber(str:sub(i, i))
        drawShadedChar(buffer, x, y, sprNumbers[c])
        x = x + (c == 1 and 2 or 4)
    end
    return x
end

---Remove a given object from a given table array
---@param myTable table
---@param myObject any
local function removeFromArray(myTable, myObject)
    for i = #myTable, 1, -1 do
        if myTable[i] == myObject then
            table.remove(myTable, i)
            return
        end
    end
end

---@param x number explosion position
---@param y number
---@param z number
local function createExplosion(x, y, z)
    ---@param spikes integer number of spikes
    ---@param spikeWidth number width of spikes (radians)
    ---@param rotationOffset number rotation offset (radians)
    ---@param scale number scale of model
    ---@return Polygon[]
    local function createExplosionModel(spikes, spikeWidth, rotationOffset, scale)
        ---@type Polygon[]
        local model = {}
        local radPerSpike = 2 * math.pi / spikes
        for i = 1, spikes do
            local rad = i * radPerSpike + rotationOffset - 0.5 * spikeWidth
            model[i] = {
                x1 = 0,
                y1 = 0,
                z1 = 0,
                x2 = 0,
                y2 = scale * sin(rad),
                z2 = scale * cos(rad),
                x3 = 0,
                y3 = scale * sin(rad + spikeWidth),
                z3 = scale * cos(rad + spikeWidth),
                c = colors.white
            }
        end
        return model
    end

    -- Make other targets fly away
    for i = 1, #targets do
        local target = targets[i]
        target.vx = target.vx + 0.03 / (target.x - x)
        target.vy = target.vy + 0.03 / (target.y - y)
    end

    local SPIKES = rand(5, 7)
    local radius = 1
    local spikeWidth = math.pi * 1 / SPIKES
    local rot = rand() * 2 * math.pi

    local timeSinceLastShake = 100

    ---@class Explosion
    explosions[#explosions + 1] = {
        obj = frame:newObject(createExplosionModel(SPIKES, spikeWidth, rot, radius), z, y, x),
        ---@param self Explosion
        ---@param dt number
        gameUpdate = function(self, dt)
            radius = radius + 0.04 * dt
            rot = rot + 0.002 * dt
            spikeWidth = spikeWidth - 0.003 * dt
            if spikeWidth <= 0 then
                removeFromArray(explosions, self)
                frame:setCamera(0, 0, 0, 0, 0, 0)
            else
                -- Camera shake
                timeSinceLastShake = timeSinceLastShake + dt
                if timeSinceLastShake > 75 then
                    timeSinceLastShake = 0
                    local camX = spikeWidth * 3 * (rand() - 0.5)
                    local camY = spikeWidth * 3 * (rand() - 0.5)
                    local camRotX = spikeWidth * 3 * (rand() - 0.5)
                    frame:setCamera(0, camX, camY, camRotX, 0, 0)
                end
            end
            self.obj:setModel(createExplosionModel(SPIKES, spikeWidth, rot, radius))
        end,
    }
end


local function createParticle(x, y, size, vx, vy, color)
    local particleModel = { {
        x1 = 0,
        y1 = -0.25 * size,
        z1 = 0.25 * size,
        x2 = 0,
        y2 = -0.25 * size,
        z2 = -0.25 * size,
        x3 = 0,
        y3 = 0.25 * size,
        z3 = 0,
        forceRender = true,
        c = color
    } }

    ---@class Particle
    local particle = {
        x = x,             -- world position (x and y are swapped)
        y = y,             -- world position
        z = tZ,            -- world position
        vx = vx,           -- velocity
        vy = vy,           -- velocity
        rx = 0,            -- rotation
        ry = 0,            -- rotation
        rz = 0,            -- rotation
        vrx = rand() / 30, -- rotation velocity
        vry = rand() / 30, -- rotation velocity
        vrz = rand() / 30, -- rotation velocity
        ---@param self Particle
        ---@param x number 3d coordinate
        ---@param y number 3d coordinate
        setPosition = function(self, x, y)
            self.x = x
            self.y = y
            self.obj:setPos(self.z, y, x)
        end,
        gameUpdate = function(self, dt)
            self.vy = self.vy - 0.00001 * dt -- gravity
            self:setPosition(self.x + self.vx * dt, self.y + self.vy * dt)
            self.rx = self.rx + self.vrx * dt
            self.ry = self.ry + self.vry * dt
            self.rz = self.rz + self.vrz * dt
            self.obj:setRot(self.rx, self.ry, self.rz)
            if self.y < -tZ - 1 and self.vy < 0 then
                -- Particle fell out of frame
                removeFromArray(particles, self)
            end
        end,
        obj = frame:newObject(particleModel, tZ, y, x),
    }

    -- random X location and X velocity (but stay within screen)
    -- local x = rand() * 2 - 1
    -- particle:setPosition(x * tZ, -tZ - 1 - 0.5 * rand())
    -- particle.vx = (rand() - 0.5 - x) * 0.0025
    -- particle.vy = 0.01

    particles[#particles + 1] = particle
end

---@param modelPath string
---@param radius number
---@param pitch number
---@param isBomb boolean?
---@return Fruit
local function loadFruit(modelPath, radius, pitch, isBomb)
    local model = Pine3D.loadModel(modelPath)

    ---@param x number target coordinate when sliced
    ---@param y number
    ---@param z number
    ---@param sliceSegment SliceSegment
    local onSliced = function(x, y, z, sliceSegment)
        points = points + floor(1 + 1 * sqrt(combo))
        combo = combo + 1
        playSound("minecraft:block.wet_grass.break", 0.8, pitch)

        -- Create particles
        local dx = sliceSegment[3] - sliceSegment[1]
        local dy = sliceSegment[4] - sliceSegment[2]
        local angle = math.atan2(dy, dx)
        local velocity = 0.01
        local vx = velocity * cos(angle)
        local vy = -velocity * sin(angle)
        for i = 1, 4 do
            createParticle(x, y, 2 * radius, vx + (rand() - 0.5) * 0.01, vy + (rand() - 0.5) * 0.01,
                model[rand(1, #model)].c)
        end
    end
    if isBomb then
        ---@param x number target coordinate when sliced
        ---@param y number
        ---@param z number
        ---@param sliceSegment SliceSegment
        onSliced = function(x, y, z, sliceSegment)
            lives = lives - 1
            combo = 0
            createExplosion(x, y, z)
            playSound("minecraft:entity.generic.explode")
        end
    end

    ---@class Fruit
    return {
        model = model,
        radius = radius,
        pitch = pitch,
        onSliced = onSliced,
        isBomb = isBomb
    }
end

local bomb = loadFruit("models/bomb.stab", 0.3, 1, true)

local fruits = {
    loadFruit("models/apple.stab", 0.2, 2),
    loadFruit("models/coconut.stab", 0.3, 1),
    loadFruit("models/pineapple.stab", 0.4, 0.7),
    loadFruit("models/watermelon.stab", 0.4, 0.5)
}

---Create a new target fruit at a random location
---@param fruit Fruit
local function createTarget(fruit)
    ---@class Target
    local target = {
        x = 0,                                 -- world position (x and y are swapped)
        y = 0,                                 -- world position
        z = tZ,                                -- world position
        scrX = SCREEN_WIDTH / 2 * 2,           -- screen position (based on pixels)
        scrY = SCREEN_HEIGHT / 2 * 3,          -- screen position (based on pixels)
        r = SCREEN_WIDTH / 2.8 * fruit.radius, -- radius
        vx = 0,                                -- velocity
        vy = 0,                                -- velocity
        rx = 0,                                -- rotation
        ry = 0,                                -- rotation
        rz = 0,                                -- rotation
        vrx = rand() / 300,                    -- rotation velocity
        vry = rand() / 300,                    -- rotation velocity
        vrz = rand() / 300,                    -- rotation velocity
        entered = false,                       -- true if current slice has entered this target's hitbox
        ---@param self Target
        ---@param x number 3d coordinate
        ---@param y number 3d coordinate
        setPosition = function(self, x, y)
            self.x = x
            self.y = y
            self.obj:setPos(self.z, y, x)
            self.scrX = (x + tZ) / (2 * tZ) * SCREEN_WIDTH * 2
            self.scrY = (-y + tZ) / (2 * tZ) * SCREEN_WIDTH * 2 - (1 - SCREEN_RATIO) * SCREEN_HEIGHT * 3
        end,
        ---@param self Target
        ---@param sliceSegment SliceSegment screen coordinate
        onNewSliceSegment = function(self, sliceSegment)
            local d = sqrt((self.scrX - sliceSegment[3]) ^ 2 + (self.scrY - sliceSegment[4]) ^ 2)
            if d <= self.r then
                self.entered = true
            else
                if self.entered then
                    -- Target has been sliced!
                    fruit.onSliced(self.x, self.y, self.z, sliceSegment)
                    removeFromArray(targets, self)
                end
                self.entered = false
            end
        end,
        ---@param self Target
        onSliceEnd = function(self)
            self.entered = false
        end,
        ---@param self Target
        ---@param dt number
        gameUpdate = function(self, dt)
            self.vy = self.vy - 0.00001 * dt -- gravity
            self:setPosition(self.x + self.vx * dt, self.y + self.vy * dt)
            self.rx = self.rx + self.vrx * dt
            self.ry = self.ry + self.vry * dt
            self.rz = self.rz + self.vrz * dt
            self.obj:setRot(self.rx, self.ry, self.rz)
            if self.y > tZ + 1 or self.x < -tZ - 1 or self.x > tZ + 1 then
                -- Target out of frame, probably because of bomb!
                removeFromArray(targets, self)
            elseif self.y < -tZ - 1 and self.vy < 0 then
                -- Target was not sliced!
                if not fruit.isBomb then
                    if combo >= 10 then playSound("minecraft:entity.pig.ambient", 0.4) end
                    combo = 0
                    points = max(points - 1, 0)
                end
                removeFromArray(targets, self)
            end
        end,
        obj = frame:newObject(fruit.model, tZ, 0, 0),
    }
    -- random X location and X velocity (but stay within screen)
    local x = (rand() * 2 - 1)
    target:setPosition(x * tZ, -tZ - 1 - 0.5 * rand())
    target.vx = (rand() - 0.5 - x) * 0.0025
    target.vy = 0.01

    targets[#targets + 1] = target

    if fruit.isBomb then
        playSound("minecraft:entity.creeper.primed", 0.4)
    else
        playSound("minecraft:entity.egg.throw", 0.1, 0.5 + 0.5 * fruit.pitch)
    end
end


-- [Slice stuff]
---@type SliceSegment[]
local sliceSegments = {}   -- round-robin buffer for slice segments
local slices_length = 0    -- number of active slices in slice buffer
local slice_next_index = 1 -- index where next slice should be added
local MAX_SLICES = 10      -- maximum number of slice segments in buffer
---@type integer | nil, integer | nil
local previousX, previousY
---@type number
local lastSliceTime                -- time of last drawn slice segment
---@type SliceSegment | nil
local tempSliceSegment             -- temporary slice from last point to cursor
local sliceHasBegonDrawing = false -- true after the first part of the slice has been added to the slice buffer

local function endSlice()
    if tempSliceSegment then
        -- Add temmporary slice segment to slice buffer
        sliceSegments[slice_next_index] = tempSliceSegment
        slices_length = slices_length + 1
        slice_next_index = min(slice_next_index % MAX_SLICES + 1, MAX_SLICES)
        tempSliceSegment = nil
    end
    previousX, previousY = nil, nil
    for i = #targets, 1, -1 do
        targets[i]:onSliceEnd()
    end
end

local function startSlice(x, y, time)
    previousX, previousY = x, y
    lastSliceTime = time
    sliceHasBegonDrawing = false
end

---On mouse move add slice segments to slices
---@param x integer
---@param y integer
---@param time number
local function addToSlice(x, y, time)
    -- End if on edge of screen (because this value gets returned in emulator when going out of bounds)
    if x >= SCREEN_WIDTH or y >= SCREEN_HEIGHT then
        endSlice()
        return
    end

    -- Start slice if not started already
    if not previousX or not previousY or not lastSliceTime then
        startSlice(x, y, time)
        return
    end

    -- Restart slice if idle for too long
    if time - 200 > lastSliceTime then
        endSlice()
        startSlice(x, y, time)
        return
    end

    tempSliceSegment = nil
    ---@class SliceSegment
    local sliceSegment = {
        previousX * 2,
        previousY * 3,
        x * 2,
        y * 3,
        created = time
    }

    -- Don't add until minimum distance
    if abs(previousX - x) < 2 and abs(previousY - y) < 2 then
        if sliceHasBegonDrawing then
            -- Draw temporary slice for better responsiveness
            tempSliceSegment = sliceSegment
        end
        return
    end

    lastSliceTime = time

    -- Add slice to slice buffer
    sliceSegments[slice_next_index] = sliceSegment
    slices_length = slices_length + 1
    slice_next_index = min(slice_next_index % MAX_SLICES + 1, MAX_SLICES)
    previousX, previousY = x, y
    sliceHasBegonDrawing = true

    -- Update targets
    for i = #targets, 1, -1 do
        targets[i]:onNewSliceSegment(sliceSegment)
    end
end

local function userInput()
    while true do
        local event, which, x, y = os.pullEventRaw()
        local currentTime = os.epoch("utc")
        if event == "mouse_click" then
            startSlice(x, y, currentTime)
        elseif event == "mouse_drag" then
            addToSlice(x, y, currentTime)
        elseif event == "mouse_up" then
            endSlice()
        elseif event == "terminate" then
            beforeExit()
            return
        end
    end
end

local function gameLoop()
    local lastTime = os.epoch("utc")

    local lastFruitSpawn = lastTime - 500
    local spawnedFruitThisWave = 0
    local fruitPerWave = 0
    local timePerFruit = rand(100, 300) -- ms
    local timeBetweenWaves = 1500       -- ms

    while true do
        -- compute the time passed since last step
        local currentTime = os.epoch("utc")
        local dt = currentTime - lastTime
        lastTime = currentTime

        local speedFactor = max(1 - 0.005 * sqrt(points), 0.5) -- goes from 1 to 0.5 based on points

        for i = #targets, 1, -1 do targets[i]:gameUpdate(dt) end
        for i = #particles, 1, -1 do particles[i]:gameUpdate(dt) end
        for i = #explosions, 1, -1 do explosions[i]:gameUpdate(dt) end

        if spawnedFruitThisWave < fruitPerWave and lastFruitSpawn + timePerFruit < currentTime then
            if rand() < 0.05 + min(0.003 * sqrt(points), 0.15) then -- more points = more bombs
                -- Bomb!
                createTarget(bomb)
            else
                -- Random fruit
                createTarget(fruits[rand(#fruits)])
            end
            lastFruitSpawn = currentTime
            spawnedFruitThisWave = spawnedFruitThisWave + 1
            timePerFruit = rand(150, 300) * speedFactor -- ms
        end

        if lastFruitSpawn + timeBetweenWaves * speedFactor < currentTime then
            -- Start a new wave
            fruitPerWave = rand(1, 10)
            spawnedFruitThisWave = 0
        end

        if lives <= 0 and #explosions == 0 then
            -- No lives left, exit program
            beforeExit()
            return
        end

        -- use a fake event to yield the coroutine
        os.queueEvent("gameLoop")
        ---@diagnostic disable-next-line: param-type-mismatch
        os.pullEventRaw("gameLoop")
    end
end


local large = math.pow(10, 99)
local function linear(x1, y1, x2, y2) -- Copied from Pine3D
    local dx = x2 - x1
    if dx == 0 then
        return large, -large * x1
    end
    local a = (y2 - y1) / dx
    return a, y1 - a * x1
end
local function drawLine(buffer, x1, y1, x2, y2, color)
    local a, b = linear(x1, y1, x2, y2)
    buffer:loadLineBLittle(x1, y1, x2, y2, color, a, b)
end

local function rendering()
    while true do
        local camera = frame.camera
        local cameraAngles = {
            sin(camera[4] or 0), cos(camera[4] or 0),
            sin(-camera[5]), cos(-camera[5]),
            sin(camera[6]), cos(camera[6]),
        }

        frame:drawObject(backgroundObj, camera, cameraAngles)

        -- Draw particles
        for i = 1, #particles do
            frame:drawObject(particles[i].obj, camera, cameraAngles)
        end

        -- Manually draw targets (to make sure they are drawn in the same order
        -- -> no switching between which target is closer to the camera)
        for i = #targets, 1, -1 do
            frame:drawObject(targets[i].obj, camera, cameraAngles)
        end

        local buffer = frame.buffer

        -- Draw circle (for debugging)
        -- local hr2 = sqrt(2) * 0.5
        -- local c = colors.black
        -- for i = #targets, 1, -1 do
        --     local target = targets[i]
        --     if target then
        --         drawLine(buffer, target.scrX - target.r, target.scrY, target.scrX + target.r, target.scrY, c)
        --         drawLine(buffer, target.scrX, target.scrY - target.r, target.scrX, target.scrY + target.r, c)
        --         drawLine(buffer, target.scrX - target.r * hr2, target.scrY - target.r * hr2,
        --             target.scrX + target.r * hr2, target.scrY + target.r * hr2, c)
        --         drawLine(buffer, target.scrX - target.r * hr2, target.scrY + target.r * hr2,
        --             target.scrX + target.r * hr2, target.scrY - target.r * hr2, c)
        --     end
        -- end

        -- Draw slices
        local currentTime = os.epoch("utc")
        local onlyDrawIfCreatedAfter = currentTime - 200
        for i = 1, slices_length do
            local slice = sliceSegments[(slice_next_index - i - 1) % MAX_SLICES + 1]
            if slice.created > onlyDrawIfCreatedAfter then
                drawLine(buffer, slice[1], slice[2] - 1, slice[3], slice[4] - 1, colors.white)
            end
        end
        if tempSliceSegment and tempSliceSegment.created > onlyDrawIfCreatedAfter then
            -- Draw temporary slice at the end
            drawLine(buffer, tempSliceSegment[1], tempSliceSegment[2] - 1, tempSliceSegment[3], tempSliceSegment[4] - 1,
                colors.white)
        end

        -- Draw explosions
        for i = 1, #explosions do
            frame:drawObject(explosions[i].obj, camera, cameraAngles)
        end

        -- Draw UI
        for i = 1, lives do
            buffer:image(SCREEN_WIDTH - 2 * i, 1, sprPineapple, 1, 1)
        end
        drawNumber(buffer, points, 2, 1)

        local x = drawNumber(buffer, combo, 2, SCREEN_HEIGHT * 3 - 6)
        drawShadedChar(buffer, x, SCREEN_HEIGHT * 3 - 4, sprTimes)

        frame:drawBuffer()

        os.queueEvent("FakeEvent")
        ---@diagnostic disable-next-line: param-type-mismatch
        os.pullEvent("FakeEvent")
    end
end

parallel.waitForAny(userInput, gameLoop, rendering)
