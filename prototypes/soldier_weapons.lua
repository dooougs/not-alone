-- Soldier weapon variants, built from every gun the game knows about.
-- Runs at data-final-fixes so guns from Space Age and other mods exist.
-- Each gun gets a unit variant that borrows the gun's range, cadence and
-- audio plus one ammo's effect, keeping the ammo_category aligned so the
-- force's weapon-damage and shooting-speed research applies automatically.
-- The list of weapons, their rank and their ammo is handed to the control
-- stage through a mod-data prototype.

require("__base__.prototypes.entity.character-animations")
local context = NOT_ALONE_TEAM_MATE_CONTEXT or require("prototypes/team_mate_base")

-- Guns that existed before weapons were data-driven keep their entity names
-- and internal kinds so Soldiers in existing saves keep their weapons.
local LEGACY_WEAPONS = {
	["pistol"] = {suffix = "handgun", kind = "handgun", ammo = "firearm-magazine"},
	["submachine-gun"] = {suffix = "smg", kind = "smg", ammo = "firearm-magazine"},
	["shotgun"] = {suffix = "shotgun", kind = "shotgun", ammo = "shotgun-shell"},
	["combat-shotgun"] = {suffix = "combat-shotgun", kind = "combat-shotgun", ammo = "piercing-shotgun-shell"},
	["flamethrower"] = {suffix = "flamethrower", kind = "flamethrower", ammo = "flamethrower-ammo"},
	["rocket-launcher"] = {suffix = "rocket", kind = "rocket", ammo = "rocket"}
}

-- Hand-ranked tiers for vanilla and Space Age guns, worst to best. Other
-- guns are slotted in by estimated damage per second.
local KNOWN_RANK = {
	["pistol"] = 1,
	["submachine-gun"] = 2,
	["shotgun"] = 3,
	["combat-shotgun"] = 4,
	["flamethrower"] = 5,
	["teslagun"] = 6,
	["rocket-launcher"] = 7,
	["railgun"] = 8
}

-- Ammo a Soldier must never spend on its own: the atomic bomb levels
-- whatever it is fired near, and capture rockets are for the player to aim.
local BLOCKED_AMMO = {
	["atomic-bomb"] = true,
	["capture-robot-rocket"] = true
}

local function as_list(value)
	if value == nil then
		return {}
	end
	if value[1] ~= nil or next(value) == nil then
		return value
	end
	return {value}
end

local action_damage

local function effects_damage(effects, depth)
	local total = 0
	for _, effect in pairs(as_list(effects)) do
		if effect.type == "damage" and effect.damage then
			total = total + (effect.damage.amount or 0)
		elseif effect.type == "nested-result" then
			total = total + action_damage(effect.action, depth + 1)
		elseif effect.type == "create-fire" then
			local fire = data.raw.fire and data.raw.fire[effect.entity_name]
			local per_tick = fire and fire.damage_per_tick and fire.damage_per_tick.amount
			total = total + (per_tick or 0) * 60
		end
	end
	return total
end

-- Rough damage one shot deals; area hits count triple because they usually
-- land on a pack. Only used to order guns and ammo, never for real damage.
action_damage = function(action, depth)
	depth = depth or 0
	if not action or depth > 6 then
		return 0
	end
	if action[1] ~= nil then
		local total = 0
		for _, entry in ipairs(action) do
			total = total + action_damage(entry, depth)
		end
		return total
	end
	local per_hit = 0
	for _, delivery in pairs(as_list(action.action_delivery)) do
		per_hit = per_hit + effects_damage(delivery.target_effects, depth)
		local child
		if delivery.type == "projectile" then
			child = data.raw.projectile and data.raw.projectile[delivery.projectile]
		elseif delivery.type == "stream" then
			child = data.raw.stream and data.raw.stream[delivery.stream]
		elseif delivery.type == "beam" then
			child = data.raw.beam and data.raw.beam[delivery.beam]
		end
		if child then
			per_hit = per_hit
				+ action_damage(child.action, depth + 1)
				+ action_damage(child.final_action, depth + 1)
				+ action_damage(child.initial_action, depth + 1)
		end
	end
	local weight = action.type == "area" and 3 or 1
	return per_hit * (action.repeat_count or 1) * weight
end

local function player_ammo_type(ammo)
	local ammo_type = ammo.ammo_type
	if ammo_type and not ammo_type.action and ammo_type[1] then
		for _, entry in ipairs(ammo_type) do
			if entry.source_type == "player" or entry.source_type == "default" then
				return entry
			end
		end
		return ammo_type[1]
	end
	return ammo_type
end

local function gun_categories(params)
	local categories = {}
	if params.ammo_category then
		categories[params.ammo_category] = true
	end
	for _, category in pairs(params.ammo_categories or {}) do
		categories[category] = true
	end
	return categories
end

local function shot_score(gun, ammo)
	local ammo_type = player_ammo_type(ammo)
	if not ammo_type then
		return 0
	end
	local cooldown = (gun.attack_parameters.cooldown or 60) * (ammo_type.cooldown_modifier or 1)
	return action_damage(ammo_type.action) * 60 / math.max(cooldown, 1)
end

-- Collect usable guns: not hidden (vehicle and turret guns are hidden) and
-- with at least one ammo a Soldier may fire.
local weapons = {}
for gun_name, gun in pairs(data.raw.gun or {}) do
	local params = gun.attack_parameters
	if not gun.hidden and params then
		local categories = gun_categories(params)
		local ammo_list = {}
		for ammo_name, ammo in pairs(data.raw.ammo or {}) do
			local ammo_type = player_ammo_type(ammo)
			if not ammo.hidden and not BLOCKED_AMMO[ammo_name]
				and categories[ammo.ammo_category] and ammo_type then
				ammo_list[#ammo_list + 1] = {name = ammo_name, score = shot_score(gun, ammo)}
			end
		end
		if #ammo_list > 0 then
			table.sort(ammo_list, function(a, b)
				if a.score ~= b.score then
					return a.score > b.score
				end
				return a.name < b.name
			end)
			local legacy = LEGACY_WEAPONS[gun_name]
			local unit_ammo = legacy and data.raw.ammo[legacy.ammo] and legacy.ammo
				or ammo_list[#ammo_list].name
			local ammo_names = {}
			for _, entry in ipairs(ammo_list) do
				ammo_names[#ammo_names + 1] = entry.name
			end
			weapons[#weapons + 1] = {
				gun = gun_name,
				kind = legacy and legacy.kind or gun_name,
				entity = "not-alone-team-mate-" .. (legacy and legacy.suffix or ("gun-" .. gun_name)),
				ammo = ammo_names,
				unit_ammo = unit_ammo,
				score = ammo_list[1].score
			}
		end
	end
end

-- Known guns keep their hand-set order. Every other gun goes after the
-- strongest known gun whose estimated damage it matches or beats.
local known_by_rank = {}
for _, weapon in ipairs(weapons) do
	local rank = KNOWN_RANK[weapon.gun]
	if rank then
		known_by_rank[#known_by_rank + 1] = weapon
		weapon.sort_key = rank
	end
end
table.sort(known_by_rank, function(a, b) return a.sort_key < b.sort_key end)
for _, weapon in ipairs(weapons) do
	if not weapon.sort_key then
		weapon.sort_key = 0.5
		for _, known in ipairs(known_by_rank) do
			if known.score <= weapon.score then
				weapon.sort_key = known.sort_key + 0.5
			end
		end
	end
end
table.sort(weapons, function(a, b)
	if a.sort_key ~= b.sort_key then
		return a.sort_key < b.sort_key
	end
	if a.score ~= b.score then
		return a.score < b.score
	end
	return a.gun < b.gun
end)

-- Heavier guns get heavier-looking armor so loadouts are tellable at a
-- glance.
local function sheet_for_position(position, count)
	local fraction = count > 1 and (position - 1) / (count - 1) or 0
	if fraction < 0.3 then
		return character_animations.level1
	elseif fraction < 0.65 then
		return character_animations.level2armor1and2 or character_animations.level1
	end
	return character_animations.level3armor3and4 or character_animations.level1
end

local new_prototypes = {}
local soldier_units = {data.raw.unit["not-alone-team-mate-fists"]}
for position, weapon in ipairs(weapons) do
	local gun = data.raw.gun[weapon.gun]
	local ammo = data.raw.ammo[weapon.unit_ammo]
	local unit = table.deepcopy(context.team_mate)
	unit.name = weapon.entity
	unit.localised_name = {"entity-name.not-alone-team-mate-soldier"}
	context.set_team_mate_pedia_visuals(unit, context.KIND_TINT.soldier,
		sheet_for_position(position, #weapons))
	-- Adopt the gun's complete attack parameters so the attack type, cadence,
	-- and audio all match the real weapon - the flamethrower's sound lives in
	-- cyclic_sound and its delivery is a stream, which field-by-field copying
	-- onto a projectile attack silently loses. Keep the character animation
	-- and the ammo's effect.
	local params = table.deepcopy(gun.attack_parameters)
	params.animation = unit.attack_parameters.animation
	params.ammo_categories = nil
	params.ammo_category = ammo.ammo_category
	params.ammo_type = table.deepcopy(player_ammo_type(ammo))
	unit.attack_parameters = params
	new_prototypes[#new_prototypes + 1] = unit
	soldier_units[#soldier_units + 1] = unit
	-- The control stage only needs these fields.
	weapon.unit_ammo = nil
	weapon.score = nil
	weapon.sort_key = nil
end

local armor_animation_sets = {}
for _, entry in pairs(data.raw.character.character.animations or {}) do
	for _, armor_name in pairs(entry.armors or {}) do
		if armor_name == "heavy-armor" or armor_name == "modular-armor" then
			armor_animation_sets.heavy = entry
		elseif armor_name == "power-armor" or armor_name == "power-armor-mk2" then
			armor_animation_sets.power = entry
		elseif armor_name == "mech-armor" then
			armor_animation_sets.mech = entry
		end
	end
end

-- Armored twins only exist when the character prototype still exposes the
-- matching armor animations (other mods can replace them); record the names
-- actually created so the command tool never filters on a missing entity.
local soldier_filter_names = {}
for _, base_unit in pairs(soldier_units) do
	if base_unit.name ~= "not-alone-team-mate-fists" then
		soldier_filter_names[#soldier_filter_names + 1] = base_unit.name
	end
	for _, visual in pairs({
		{suffix = "armor-heavy", set = armor_animation_sets.heavy},
		{suffix = "armor-power", set = armor_animation_sets.power}
	}) do
		if visual.set then
			local armored_unit = table.deepcopy(base_unit)
			armored_unit.name = base_unit.name .. "-" .. visual.suffix
			armored_unit.hidden_in_factoriopedia = true
			armored_unit.factoriopedia_description = nil
			armored_unit.factoriopedia_simulation = nil
			armored_unit.run_animation = table.deepcopy(visual.set.running)
			armored_unit.attack_parameters.animation = table.deepcopy(visual.set.idle_with_gun)
			armored_unit.icons = {
				{icon = context.TEAM_MATE_ICON, icon_size = context.TEAM_MATE_ICON_SIZE,
					tint = context.KIND_TINT.soldier}
			}
			context.tint_unit_masks(armored_unit, context.KIND_TINT.soldier)
			new_prototypes[#new_prototypes + 1] = armored_unit
			soldier_filter_names[#soldier_filter_names + 1] = armored_unit.name
		end
	end
	-- Space Age mech armor lets a Soldier hover: each combat variant gains a
	-- "-mech" twin using the mech suit's flying animation that ignores ground
	-- collision entirely.
	local mech_animations = armor_animation_sets.mech
	if mech_animations and mech_animations.flying then
		local mech = table.deepcopy(base_unit)
		mech.name = base_unit.name .. "-mech"
		mech.hidden_in_factoriopedia = true
		mech.factoriopedia_description = nil
		mech.factoriopedia_simulation = nil
		mech.run_animation = table.deepcopy(mech_animations.flying)
		if mech_animations.idle_with_gun then
			mech.attack_parameters.animation = table.deepcopy(mech_animations.idle_with_gun)
		end
		context.tint_unit_masks(mech, context.KIND_TINT.soldier)
		mech.collision_mask = {layers = {}}
		mech.movement_speed = mech.movement_speed * 1.3
		new_prototypes[#new_prototypes + 1] = mech
		soldier_filter_names[#soldier_filter_names + 1] = mech.name
	end
end

new_prototypes[#new_prototypes + 1] = {
	type = "mod-data",
	name = "not-alone-soldier-weapons",
	data = {weapons = weapons}
}
data:extend(new_prototypes)

local command_tool = data.raw["selection-tool"]["not-alone-command-tool"]
for _, mode_name in pairs({"select", "alt_select"}) do
	local mode = command_tool and command_tool[mode_name]
	if mode and mode.entity_filters then
		for _, name in ipairs(soldier_filter_names) do
			table.insert(mode.entity_filters, name)
		end
	end
end
