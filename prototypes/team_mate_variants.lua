local context = require("prototypes/team_mate_base")

-- Teammate role, weapon, armor, and command prototypes.

-- Soldier weapon tiers: each variant borrows the vanilla gun's range and
-- cadence plus the ammo's effect, keeping the ammo_category aligned so the
-- force's weapon-damage and shooting-speed research applies automatically.
-- The armor sheet grows with the tier so loadouts are tellable at a glance.
local SOLDIER_WEAPONS = {
	{suffix = "smg", kind = "soldier-smg", gun = "submachine-gun", ammo = "firearm-magazine", order = "e[soldier-smg]", sheet = "level1"},
	{suffix = "shotgun", kind = "soldier-shotgun", gun = "shotgun", ammo = "shotgun-shell", order = "f[soldier-shotgun]", sheet = "level2armor1and2"},
	{suffix = "combat-shotgun", kind = "soldier-combat-shotgun", gun = "combat-shotgun", ammo = "piercing-shotgun-shell", order = "g[soldier-combat-shotgun]", sheet = "level2armor1and2"},
	{suffix = "flamethrower", kind = "soldier-flamethrower", gun = "flamethrower", ammo = "flamethrower-ammo", order = "h[soldier-flamethrower]", sheet = "level3armor3and4"},
	{suffix = "rocket", kind = "soldier-rocket", gun = "rocket-launcher", ammo = "rocket", order = "i[soldier-rocket]", sheet = "level3armor3and4"}
}

local soldier_prototypes = {}
local soldier_units = {}
for _, weapon in pairs(SOLDIER_WEAPONS) do
	local unit = table.deepcopy(context.team_mate)
	unit.name = "not-alone-team-mate-" .. weapon.suffix
	unit.localised_name = {"entity-name.not-alone-team-mate-soldier"}
	local sheet = character_animations[weapon.sheet] or character_animations.level1
	context.set_team_mate_pedia_visuals(unit, context.KIND_TINT.soldier, sheet)
	local gun = data.raw.gun[weapon.gun]
	local ammo = data.raw.ammo[weapon.ammo]
	if gun and ammo then
		-- Adopt the gun's complete attack parameters so the attack type, cadence,
		-- and audio all match the real weapon - the flamethrower's sound lives in
		-- cyclic_sound and its delivery is a stream, which field-by-field copying
		-- onto a projectile attack silently loses. Keep the character animation
		-- and the ammo's effect.
		local params = table.deepcopy(gun.attack_parameters)
		params.animation = unit.attack_parameters.animation
		params.ammo_category = ammo.ammo_category
		local ammo_type = table.deepcopy(ammo.ammo_type)
		if ammo_type and not ammo_type.action and ammo_type[1] then
			ammo_type = ammo_type[1]
		end
		params.ammo_type = ammo_type
		unit.attack_parameters = params
	end
	soldier_prototypes[#soldier_prototypes + 1] = unit
	soldier_units[#soldier_units + 1] = unit
end

-- The base Soldier is unarmed and punches at melee range, like a recruit.
local fists_unit = table.deepcopy(context.team_mate)
fists_unit.name = "not-alone-team-mate-fists"
fists_unit.localised_name = {"entity-name.not-alone-team-mate-soldier"}
fists_unit.hidden_in_factoriopedia = nil
fists_unit.factoriopedia_description = {"factoriopedia-description.not-alone-team-mate-soldier"}
context.set_team_mate_pedia_visuals(fists_unit, context.KIND_TINT.soldier, character_animations.level1)
local fist_params = fists_unit.attack_parameters
fist_params.range = 1.5
fist_params.cooldown = 35
fist_params.min_range = nil
fist_params.ammo_category = "melee"
-- Center-to-center range can never reach a large structure's center, so
-- punches on spawners and turrets would whiff forever without this.
fist_params.range_mode = "bounding-box-to-bounding-box"
local biter_attack = data.raw.unit["small-biter"]
	and data.raw.unit["small-biter"].attack_parameters
fist_params.sound = biter_attack and table.deepcopy(biter_attack.sound) or nil
-- Swing on each punch instead of freezing in the gun-idle pose.
local punch_tool = table.deepcopy(character_animations.level1.mining_tool)
local punch_mask = table.deepcopy(character_animations.level1.mining_tool_mask)
local punch_shadow = table.deepcopy(character_animations.level1.mining_tool_shadow)
punch_mask.apply_runtime_tint = nil
punch_mask.tint = context.KIND_TINT.soldier
fist_params.animation = {
	layers = {
		punch_tool,
		punch_mask,
		punch_shadow
	}
}
fist_params.ammo_type = {
	category = "melee",
	target_type = "entity",
	action = {
		type = "direct",
		action_delivery = {
			type = "instant",
			target_effects = {
				{type = "damage", damage = {amount = 8, type = "physical"}}
			}
		}
	}
}
soldier_prototypes[#soldier_prototypes + 1] = fists_unit
soldier_units[#soldier_units + 1] = fists_unit

local armor_animation_sets = {}
for _, entry in pairs(data.raw.character.character.animations or {}) do
	for _, armor_name in pairs(entry.armors or {}) do
		if armor_name == "heavy-armor" or armor_name == "modular-armor" then
			armor_animation_sets.heavy = entry
		elseif armor_name == "power-armor" or armor_name == "power-armor-mk2" then
			armor_animation_sets.power = entry
		end
	end
end

local armor_visuals = {
	{suffix = "armor-heavy", set = armor_animation_sets.heavy},
	{suffix = "armor-power", set = armor_animation_sets.power}
}
for _, base_unit in pairs(soldier_units) do
	for _, visual in pairs(armor_visuals) do
		if visual.set then
			local armored_unit = table.deepcopy(base_unit)
			armored_unit.name = base_unit.name .. "-" .. visual.suffix
			armored_unit.hidden_in_factoriopedia = true
			armored_unit.factoriopedia_description = nil
			armored_unit.run_animation = table.deepcopy(visual.set.running)
			armored_unit.attack_parameters.animation = table.deepcopy(
				visual.set.idle_with_gun
			)
				armored_unit.icon = context.TEAM_MATE_ICON
				armored_unit.icon_size = context.TEAM_MATE_ICON_SIZE
				armored_unit.icons = {
					{icon = context.TEAM_MATE_ICON, icon_size = context.TEAM_MATE_ICON_SIZE,
						tint = context.KIND_TINT.soldier}
				}
				context.tint_unit_masks(armored_unit, context.KIND_TINT.soldier)
			soldier_prototypes[#soldier_prototypes + 1] = armored_unit
		end
	end
end

-- Space Age mech armor lets a Soldier hover: each combat variant gains a
-- "-mech" twin using the mech suit's flying animation that ignores ground
-- collision entirely.
local mech_animations
for _, entry in pairs(data.raw.character.character.animations or {}) do
	for _, armor_name in pairs(entry.armors or {}) do
		if armor_name == "mech-armor" then
			mech_animations = entry
		end
	end
end
local mech_unit_names = {}
if mech_animations and mech_animations.flying then
	for _, unit in pairs(soldier_units) do
		local mech = table.deepcopy(unit)
		mech.name = unit.name .. "-mech"
		mech.hidden_in_factoriopedia = true
		mech.factoriopedia_description = nil
		mech.run_animation = table.deepcopy(mech_animations.flying)
		if mech_animations.idle_with_gun then
			mech.attack_parameters.animation = table.deepcopy(mech_animations.idle_with_gun)
		end
		context.tint_unit_masks(mech, context.KIND_TINT.soldier)
		mech.collision_mask = {layers = {}}
		mech.movement_speed = mech.movement_speed * 1.3
		soldier_prototypes[#soldier_prototypes + 1] = mech
		mech_unit_names[#mech_unit_names + 1] = mech.name
	end
end

soldier_prototypes[#soldier_prototypes + 1] = {
	type = "recipe",
	name = "not-alone-soldier",
	enabled = true,
	hidden = true,
	ingredients = {
		{type = "item", name = "iron-plate", amount = 5}
	},
	results = {{type = "item", name = "not-alone-soldier", amount = 1}}
}

for _, kind in pairs({"miner", "builder", "carrier"}) do
	local unit = table.deepcopy(context.team_mate)
	unit.name = "not-alone-team-mate-" .. kind
	unit.localised_name = {"entity-name.not-alone-team-mate-" .. kind}
	unit.hidden_in_factoriopedia = nil
	unit.factoriopedia_description = {"factoriopedia-description.not-alone-team-mate-" .. kind}
	context.set_team_mate_pedia_visuals(unit, context.KIND_TINT[kind], character_animations.level1)
	soldier_prototypes[#soldier_prototypes + 1] = unit
end
data:extend(soldier_prototypes)

local team_mate_filter_names = {
	"not-alone-team-mate",
	"not-alone-team-mate-hidden",
	"not-alone-team-mate-fists",
	"not-alone-team-mate-miner",
	"not-alone-team-mate-builder",
	"not-alone-team-mate-carrier"
}
for _, weapon in pairs(SOLDIER_WEAPONS) do
	table.insert(team_mate_filter_names, "not-alone-team-mate-" .. weapon.suffix)
end
for _, suffix in pairs({"armor-heavy", "armor-power"}) do
	for _, weapon in pairs(SOLDIER_WEAPONS) do
		table.insert(team_mate_filter_names,
			"not-alone-team-mate-" .. weapon.suffix .. "-" .. suffix)
	end
	table.insert(team_mate_filter_names, "not-alone-team-mate-fists-" .. suffix)
end
for _, name in pairs(mech_unit_names) do
	table.insert(team_mate_filter_names, name)
end

local command_tool = {
	type = "selection-tool",
	name = "not-alone-command-tool",
	icon = "__base__/graphics/icons/spidertron-remote.png",
	factoriopedia_description = {"factoriopedia-description.not-alone-command-tool"},
	flags = {"not-stackable", "spawnable"},
	subgroup = "tool",
	order = "c[automated-construction]-z[not-alone-command-tool]",
	stack_size = 1,
	select = {
		border_color = {0.2, 1, 0.2},
		mode = {"any-entity"},
		entity_filters = team_mate_filter_names,
		cursor_box_type = "entity"
	},
	alt_select = {
		border_color = {0.2, 1, 0.2},
		mode = {"any-entity"},
		entity_filters = team_mate_filter_names,
		cursor_box_type = "entity"
	},
	reverse_select = {
		border_color = {1, 0.8, 0.1},
		mode = {"any-tile"},
		cursor_box_type = "pair"
	},
	alt_reverse_select = {
		border_color = {0.2, 0.7, 1},
		mode = {"any-tile"},
		cursor_box_type = "pair"
	}
}


data:extend({
	context.miner_item,
	context.builder_item,
	context.soldier_item,
	context.carrier_item,
  context.team_mate,
  context.hidden_team_mate,
  context.vehicle_driver,
  context.mining_sound,
  command_tool
})
