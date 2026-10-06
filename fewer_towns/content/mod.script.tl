
local mod = {}

local ModName <const> = "felix_fewer_towns_1"
local KeepPercents : {number} = { 100, 75, 50, 40, 30, 20, 10 }

-- The chosen values are handed to the game script through two fields of the base config that
-- do not matter after the map was generated:
--   locations.town.townFrequency    = share of the towns that stays (1.0 = all)
--   locations.town.maxNumberPerArea = mode (1 random, 2 smallest first, 3 largest first)
-- The game counts the choices of a parameter from 1 (first value = 1).
mod.preRunFn = function(captureParams, _configDict : {{string, string}}, allModParams : {string : {string : integer}}, baseConfig : BaseConfig)
	local params = allModParams[ModName]
	local rawKeep = 1
	local rawMode = 1
	if params then
		rawKeep = params["keep"] or 1
		rawMode = params["mode"] or 1
	end
	if rawKeep < 1 then
		rawKeep = 1
	end
	if rawKeep > #KeepPercents then
		rawKeep = #KeepPercents
	end
	if rawMode < 1 or rawMode > 3 then
		rawMode = 1
	end

	baseConfig.locations.town.townFrequency = KeepPercents[rawKeep] / 100
	baseConfig.locations.town.maxNumberPerArea = rawMode

	log.message("FewerTowns: raw keep=" .. tostring(rawKeep) .. " raw mode=" .. tostring(rawMode) .. " keep=" .. tostring(baseConfig.locations.town.townFrequency))
end

return mod
