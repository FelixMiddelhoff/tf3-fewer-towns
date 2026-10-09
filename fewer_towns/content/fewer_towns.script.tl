local StartDelaySeconds <const> = 15.0
local VerifyDelaySeconds <const> = 45.0
-- the towns are only deleted at the very start of a new game, never in a running game
local MaxStartUpdateCount <const> = 2000

local countTowns = function() : integer
	local count = 0
	api.engine.forEachEntityWithComponent(function(_entity : Engine.Entity)
		count = count + 1
	end, api.type.ComponentType.TOWN)
	return count
end

-- center of the bounding volume of an entity, nil when it has none
local centerOf = function(entity : Engine.Entity) : {number}
	local bb = api.engine.getComponent(entity, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if not bb then
		return nil
	end
	return { (bb.bbox.min.x + bb.bbox.max.x) * 0.5, (bb.bbox.min.y + bb.bbox.max.y) * 0.5 }
end

-- index of the town closest to the middle of all towns (the middle of the map, roughly), nil if unknown
local findCentralIndex = function(centers : {{number}}) : integer
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs(centers) do
		minX = math.min(minX, c[1])
		maxX = math.max(maxX, c[1])
		minY = math.min(minY, c[2])
		maxY = math.max(maxY, c[2])
	end
	local midX = (minX + maxX) * 0.5
	local midY = (minY + maxY) * 0.5
	local best = nil
	local bestDist = math.huge
	for i, c in ipairs(centers) do
		local dx = c[1] - midX
		local dy = c[2] - midY
		local dist = dx * dx + dy * dy
		if dist < bestDist then
			bestDist = dist
			best = i
		end
	end
	return best
end

-- indices of the towns to delete, so that the kept towns cover the whole map: the central town (if kept),
-- then one town per grid cell over the map, the one closest to the cell's middle
local spreadDeleteOrder = function(centers : {{number}}, centralIndex : integer, keepCount : integer) : {integer}
	local kept : {integer : boolean} = {}
	local keptCount = 0
	if centralIndex then
		kept[centralIndex] = true
		keptCount = 1
	end

	local want = keepCount - keptCount
	if want > 0 then
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, c in ipairs(centers) do
			minX = math.min(minX, c[1])
			maxX = math.max(maxX, c[1])
			minY = math.min(minY, c[2])
			maxY = math.max(maxY, c[2])
		end
		local width = math.max(maxX - minX, 1.0)
		local height = math.max(maxY - minY, 1.0)
		local cols = math.max(1, math.floor(math.sqrt(want * width / height) + 0.5))
		local rows = math.ceil(want / cols)

		local picked = 0
		for row = 0, rows - 1 do
			for col = 0, cols - 1 do
				if picked < want then
					local cx = minX + (col + 0.5) * width / cols
					local cy = minY + (row + 0.5) * height / rows
					local best = nil
					local bestDist = math.huge
					for i, c in ipairs(centers) do
						if not kept[i] then
							local dx = c[1] - cx
							local dy = c[2] - cy
							local dist = dx * dx + dy * dy
							if dist < bestDist then
								bestDist = dist
								best = i
							end
						end
					end
					kept[best] = true
					picked = picked + 1
				end
			end
		end
	end

	local order : {integer} = {}
	for i = 1, #centers do
		if not kept[i] then
			order[#order + 1] = i
		end
	end
	return order
end

-- state: elapsed = seconds since the script started, phase 0 = waiting, 1 = deleted, 2 = verified
local ret : GameScript<{string : number}> = {
	update = function(_userParams : table, state : GameScriptState<{string : number}>, dt : number) : any
		if dt == 0.0 then
			return
		end

		local state2 = state:get() or { elapsed = 0.0, phase = 0 }
		local phase = state2.phase or 0
		if phase >= 2 then
			return
		end
		state2.elapsed = (state2.elapsed or 0.0) + dt

		if phase == 0 and state2.elapsed >= StartDelaySeconds then
			-- handed over by the mod script through two base config fields (see mod.script.tl)
			local baseConfig = api.res.getBaseConfig()
			local keepPercent = math.floor(baseConfig.locations.town.townFrequency * 100 + 0.5)
			local encoded = math.floor(baseConfig.locations.town.maxNumberPerArea + 0.5)
			local mode = ((encoded - 1) % 4) + 1
			local keepCentral = encoded > 4

			local gameTime : Engine.Component.GameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
			log.message("FewerTowns: start, keepPercent=" .. tostring(keepPercent) .. " mode=" .. tostring(mode) .. " updateCount=" .. tostring(gameTime and gameTime.updateCount or -1))

			local updateCount = gameTime and gameTime.updateCount or 0
			if updateCount > MaxStartUpdateCount then
				log.message("FewerTowns: the game is already running, no towns are deleted")
				state2.phase = 2
				state:set(state2)
				return
			end

			local entities : {Engine.Entity} = {}
			local sizes : {number} = {}
			local centers : {{number}} = {}
			api.engine.forEachEntityWithComponent(function(entity : Engine.Entity)
				local town = api.engine.getComponent(entity, api.type.ComponentType.TOWN) as Engine.Component.Town
				local center = centerOf(entity)
				if town and town.initialLandUseCapacities and center then
					entities[#entities + 1] = entity
					sizes[#sizes + 1] = (town.initialLandUseCapacities[1] or 0) + (town.initialLandUseCapacities[2] or 0) + (town.initialLandUseCapacities[3] or 0)
					centers[#centers + 1] = center
				end
			end, api.type.ComponentType.TOWN)

			local total = #entities
			local target = math.floor(total * keepPercent / 100 + 0.5)
			if target < 1 then
				target = 1
			end
			local toDelete = total - target

			-- the central town is not a candidate for deletion, it counts towards the target
			local centralIndex : integer = nil
			if keepCentral and total > 0 then
				centralIndex = findCentralIndex(centers)
				if centralIndex then
					log.message("FewerTowns: central town " .. tostring(entities[centralIndex]) .. " '" .. tostring(api.engine.util.getEntityName(entities[centralIndex])) .. "' is kept")
				end
			end
			local candidates = total
			if centralIndex then
				candidates = total - 1
			end
			if toDelete > candidates then
				toDelete = candidates
			end
			log.message("FewerTowns: towns=" .. tostring(total) .. " target=" .. tostring(target) .. " toDelete=" .. tostring(toDelete))

			if keepPercent < 100 and toDelete > 0 then
				local order : {integer} = {}
				if mode == 4 then
					order = spreadDeleteOrder(centers, centralIndex, total - toDelete)
				else
					for i = 1, total do
						if i ~= centralIndex then
							order[#order + 1] = i
						end
					end
					total = #order
					if mode == 2 then
						table.sort(order, function(a : integer, b : integer) : boolean
							return sizes[a] < sizes[b]
						end)
					elseif mode == 3 then
						table.sort(order, function(a : integer, b : integer) : boolean
							return sizes[a] > sizes[b]
						end)
					else
						math.randomseed(total * 7919 + 17)
						for i = total, 2, -1 do
							local j = math.random(1, i)
							order[i], order[j] = order[j], order[i]
						end
					end
				end

				for k = 1, toDelete do
					local index = order[k]
					local entity = entities[index]
					log.message("FewerTowns: deleting town " .. tostring(entity) .. " '" .. tostring(api.engine.util.getEntityName(entity)) .. "' size=" .. tostring(sizes[index]))
					api.cmd.sendCommand(api.cmd.makeTownDestroyCmd(entity))
				end
			end
			state2.phase = 1
		elseif phase == 1 and state2.elapsed >= VerifyDelaySeconds then
			log.message("FewerTowns: towns left on the map: " .. tostring(countTowns()))
			state2.phase = 2
		end

		state:set(state2)
	end,
}

return ret
