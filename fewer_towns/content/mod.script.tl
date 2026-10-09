
local mod = {}

local ModName <const> = "felix_fewer_towns_1"
local KeepPercents : {number} = { 100, 75, 50, 40, 30, 20, 10 }

-- The chosen values are handed to the game script through two fields of the base config that
-- do not matter after the map was generated:
--   locations.town.townFrequency    = share of the towns that stays (1.0 = all)
--   locations.town.maxNumberPerArea = mode + 4 * keepCentral
--                                     mode: 1 random, 2 smallest first, 3 largest first, 4 evenly spread
--                                     keepCentral: 0 no, 1 yes (central town is never deleted)
-- The game counts the choices of a parameter from 1 (first value = 1).
mod.preRunFn = function(captureParams, _configDict : {{string, string}}, allModParams : {string : {string : integer}}, baseConfig : BaseConfig)
	local params = allModParams[ModName]
	local rawKeep = 1
	local rawMode = 1
	local rawCentral = 1
	if params then
		rawKeep = params["keep"] or 1
		rawMode = params["mode"] or 1
		rawCentral = params["central"] or 1
	end
	if rawKeep < 1 then
		rawKeep = 1
	end
	if rawKeep > #KeepPercents then
		rawKeep = #KeepPercents
	end
	if rawMode < 1 or rawMode > 4 then
		rawMode = 1
	end
	local keepCentral = 0
	if rawCentral == 1 then
		keepCentral = 1
	end

	-- The tutorial needs specific towns by name, and the mod cannot read which ones. A missing town
	-- crashes the tutorial, so with the tutorial on no town is deleted. The flag is 2 when it is active.
	local tutorialActive = false
	local globalParams = allModParams[""]
	if globalParams and globalParams["guideSystemConfig.tutorial"] == 2 then
		tutorialActive = true
	end
	if tutorialActive then
		log.message("FewerTowns WARNING: the tutorial is on, no towns are deleted. The tutorial needs specific towns, and the mod cannot read which ones.")
		rawKeep = 1
	end

	baseConfig.locations.town.townFrequency = KeepPercents[rawKeep] / 100
	baseConfig.locations.town.maxNumberPerArea = rawMode + 4 * keepCentral

	log.message("FewerTowns: raw keep=" .. tostring(rawKeep) .. " raw mode=" .. tostring(rawMode) .. " raw central=" .. tostring(rawCentral) .. " tutorial=" .. tostring(tutorialActive) .. " keep=" .. tostring(baseConfig.locations.town.townFrequency))
end

return mod
