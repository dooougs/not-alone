local context = require("prototypes/team_mate_base")

-- Teammate role, weapon, armor, and command prototypes.

-- Gun-armed Soldier variants and every armored or mech twin are built at
-- data-final-fixes (prototypes/soldier_weapons.lua) so guns from other mods
-- are included; they reuse this context.
NOT_ALONE_TEAM_MATE_CONTEXT = context

local soldier_prototypes = {}
-- The base Soldier is unarmed and punches at melee range, like a recruit.
local fists_unit = table.deepcopy(context.team_mate)
fists_unit.name = "not-alone-team-mate-fists"
fists_unit.localised_name = {"entity-name.not-alone-team-mate-soldier"}
fists_unit.flags = {"placeable-player", "placeable-off-grid", "not-repairable", "breaths-air"}
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
	unit.flags = {"placeable-player", "placeable-off-grid", "not-repairable", "breaths-air"}
	unit.hidden_in_factoriopedia = nil
	unit.factoriopedia_description = {"factoriopedia-description.not-alone-team-mate-" .. kind}
	context.set_team_mate_pedia_visuals(unit, context.KIND_TINT[kind], character_animations.level1)
	soldier_prototypes[#soldier_prototypes + 1] = unit
end
data:extend(soldier_prototypes)

-- Weapon, armored and mech variants are appended at data-final-fixes.
local soldier_filter_names = {"not-alone-team-mate-fists"}
-- Soldiers travelling by vehicle are hidden units riding these; selecting
-- the vehicle must select the Soldier inside it.
for _, vehicle_name in pairs({"car", "tank", "spidertron"}) do
	if data.raw["car"] and data.raw["car"][vehicle_name]
		or data.raw["spider-vehicle"] and data.raw["spider-vehicle"][vehicle_name] then
		table.insert(soldier_filter_names, vehicle_name)
	end
end

local command_tool = {
	type = "selection-tool",
	name = "not-alone-command-tool",
	icons = {
		{
			icon = "__base__/graphics/icons/spidertron-remote.png",
			icon_size = 64
		},
		{
			icon = "__base__/graphics/icons/light-armor.png",
			icon_size = 64,
			tint = {r = 0.72, g = 0.08, b = 0.08, a = 1},
			scale = 0.42,
			shift = {8, 8}
		}
	},
	factoriopedia_description = {"factoriopedia-description.not-alone-command-tool"},
	flags = {"not-stackable", "spawnable"},
	subgroup = "tool",
	order = "c[automated-construction]-z[not-alone-command-tool]",
	stack_size = 1,
	select = {
		border_color = {0.2, 1, 0.2},
		mode = {"any-entity"},
		entity_filters = soldier_filter_names,
		cursor_box_type = "entity"
	},
	alt_select = {
		border_color = {0.2, 1, 0.2},
		mode = {"any-entity"},
		entity_filters = soldier_filter_names,
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

local command_tool_shortcut = {
	type = "shortcut",
	name = "not-alone-command-tool-shortcut",
	order = "e[not-alone-command-tool]",
	action = "spawn-item",
	localised_name = {"shortcut.make-not-alone-command-tool"},
	item_to_spawn = "not-alone-command-tool",
	icon = "__not-alone__/graphics/icons/command-tool-shortcut-56.png",
	icon_size = 56,
	small_icon = "__not-alone__/graphics/icons/command-tool-shortcut-24.png",
	small_icon_size = 24
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
	command_tool,
	command_tool_shortcut
})
