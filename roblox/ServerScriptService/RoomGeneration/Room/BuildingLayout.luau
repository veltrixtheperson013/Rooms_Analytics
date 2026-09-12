-- Selection weights only: never edits or transforms a room template.
local BuildingLayout = {}
BuildingLayout.__index = BuildingLayout

function BuildingLayout.new(seed, scale, strength)
	local random = Random.new(seed)
	return setmetatable({
		Seed = seed,
		Scale = math.clamp(tonumber(scale) or 18, 6, 80),
		Strength = math.clamp(tonumber(strength) or 0.8, 0, 1),
		Offset = Vector3.new(random:NextNumber(0, 1000), random:NextNumber(0, 1000), random:NextNumber(0, 1000)),
	}, BuildingLayout)
end

function BuildingLayout:Sample(step)
	local x = math.max(0, tonumber(step) or 0) / self.Scale
	local o = self.Offset
	-- Broad zones last several rooms. A small second octave prevents repetition.
	return math.clamp(0.5 + math.noise(x + o.X, o.Y, o.Z) * 0.85
		+ math.noise(x * 2 + o.Z, o.X, o.Y) * 0.15, 0, 1)
end

function BuildingLayout:Weight(name, info, step, previousInfo)
	info = info or {}
	local zone = self:Sample(step)
	local desired = 1
	if info.Stairs then
		-- Floor changes are rare, with modest preference at the end of a wing.
		local floorZone = self:Sample((step or 0) * 0.45 + 73)
		desired = 0.12 + 0.45 * math.max(0, (floorZone - 0.55) / 0.45)
		if previousInfo and previousInfo.Stairs then desired = 0.02 end
	elseif info.Direction then
		desired = 0.25 + 1.65 * math.max(0, (zone - 0.48) / 0.52)
		if previousInfo and previousInfo.Direction then desired *= 0.2 end
	else
		desired = 1.6 + 1.8 * (1 - zone)
		local lower = string.lower(name)
		if lower:find("corridor", 1, true) or lower:find("long", 1, true) then
			desired *= 1.15 + 0.5 * (1 - zone)
		end
	end
	-- Positive weights keep every safe existing template reachable.
	return 1 + (desired - 1) * self.Strength
end

return BuildingLayout

