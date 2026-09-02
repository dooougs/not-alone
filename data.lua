require("__base__.prototypes.entity.character-animations")

local logistic_chest_recipe_names = {
	"passive-provider-chest",
	"active-provider-chest",
	"storage-chest",
	"buffer-chest",
	"requester-chest"
}
for _, recipe_name in pairs(logistic_chest_recipe_names) do
	local recipe = data.raw.recipe[recipe_name]
	recipe.enabled = false
	recipe.ingredients = {
		{type = "item", name = "iron-chest", amount = 1}
	}
end

for _, recipe_name in pairs(logistic_chest_recipe_names) do
	table.insert(data.raw.technology.electronics.effects, {
		type = "unlock-recipe",
		recipe = recipe_name
	})
end

local logistics_hub = table.deepcopy(data.raw.roboport.roboport)
logistics_hub.name = "not-alone-logistics-hub"
logistics_hub.localised_name = {"entity-name.not-alone-logistics-hub"}
logistics_hub.icon = "__not-alone__/graphics/icons/habitat.png"
logistics_hub.icon_size = 64
logistics_hub.minable = {mining_time = 0.1, result = "not-alone-logistics-hub"}
logistics_hub.fast_replaceable_group = nil
logistics_hub.next_upgrade = nil
logistics_hub.energy_source = {type = "void"}
logistics_hub.energy_usage = "0W"
logistics_hub.recharge_minimum = "0J"
logistics_hub.charging_energy = "0W"
logistics_hub.charging_offsets = {}
logistics_hub.robot_slots_count = 0
logistics_hub.material_slots_count = 3
logistics_hub.construction_radius = 0

local habitat_picture = {
	filename = "__not-alone__/graphics/entity/habitat.png",
	width = 256,
	height = 256,
	scale = 0.5,
	shift = {0, -0.3}
}
logistics_hub.base = habitat_picture
logistics_hub.base_animation = nil
logistics_hub.base_patch = nil
logistics_hub.door_animation_up = nil
logistics_hub.door_animation_down = nil

-- Rides along with a deployed team mate so it is a real member of the
-- network. Zero radius with a connection distance so it joins a Habitat's
-- logistic area without contributing any coverage of its own.
local team_mate_member = table.deepcopy(logistics_hub)
team_mate_member.name = "not-alone-team-mate-member"
team_mate_member.localised_name = {"entity-name.not-alone-team-mate"}
team_mate_member.minable = nil
team_mate_member.material_slots_count = 0
team_mate_member.logistics_radius = 0
team_mate_member.logistics_connection_distance = 1
team_mate_member.radar_range = 0
team_mate_member.selectable_in_game = false
team_mate_member.draw_logistic_radius_visualization = false
team_mate_member.draw_construction_radius_visualization = false
team_mate_member.collision_box = nil
team_mate_member.collision_mask = {layers = {}}
team_mate_member.selection_box = nil
team_mate_member.flags = {
	"placeable-off-grid",
	"not-on-map",
	"not-blueprintable",
	"not-deconstructable",
	"not-flammable",
	"hide-alt-info",
	"not-selectable-in-game",
	"not-upgradable",
	"not-in-kill-statistics",
	"not-in-made-in"
}
team_mate_member.hidden = nil
team_mate_member.hidden_in_factoriopedia = true
for _, key in pairs({"base", "base_patch", "frozen_patch", "base_animation",
	"door_animation_up", "door_animation_down", "recharging_animation",
	"water_reflection", "integration_patch"}) do
	team_mate_member[key] = nil
end

local logistics_hub_item = table.deepcopy(data.raw.item.roboport)
logistics_hub_item.name = "not-alone-logistics-hub"
logistics_hub_item.localised_name = {"item-name.not-alone-logistics-hub"}
logistics_hub_item.icon = "__not-alone__/graphics/icons/habitat.png"
logistics_hub_item.icon_size = 64
logistics_hub_item.place_result = "not-alone-logistics-hub"
logistics_hub_item.order = "c[signal]-a[not-alone-logistics-hub]"

local logistics_hub_recipe = {
	type = "recipe",
	name = "not-alone-logistics-hub",
	enabled = true,
	ingredients = {
		{type = "item", name = "wood", amount = 5}
	},
	results = {
		{type = "item", name = "not-alone-logistics-hub", amount = 1}
	}
}

local building_logistics_requester = table.deepcopy(data.raw["logistic-container"]["requester-chest"])
building_logistics_requester.name = "not-alone-building-logistics-requester"
building_logistics_requester.localised_name = {"entity-name.not-alone-building-logistics-requester"}
building_logistics_requester.flags = {
	"not-on-map",
	"not-blueprintable",
	"not-deconstructable",
	"not-selectable-in-game"
}
building_logistics_requester.collision_box = {{0, 0}, {0, 0}}
building_logistics_requester.selection_box = {{0, 0}, {0, 0}}
building_logistics_requester.selectable_in_game = false
building_logistics_requester.allow_copy_paste = false
building_logistics_requester.inventory_size = 20
building_logistics_requester.trash_inventory_size = 0
building_logistics_requester.max_logistic_slots = 20
building_logistics_requester.minable = nil
building_logistics_requester.corpse = nil
building_logistics_requester.dying_explosion = nil
building_logistics_requester.picture = {
	filename = "__core__/graphics/empty.png",
	width = 1,
	height = 1
}
building_logistics_requester.robot_door = nil
building_logistics_requester.circuit_connector = nil
building_logistics_requester.circuit_wire_max_distance = 0
building_logistics_requester.render_not_in_network_icon = false

-- Colors must match KIND_COLOR in poc.lua.
local TEAM_MATE_ICON = "__core__/graphics/player-force-icon.png"
local TEAM_MATE_ICON_SIZE = 32

local function make_team_mate_item(kind, tint, order_suffix)
	local item = table.deepcopy(data.raw["repair-tool"]["repair-pack"])
	item.name = "not-alone-" .. kind
	item.localised_name = {"item-name.not-alone-" .. kind}
	item.localised_description = {"item-description.not-alone-" .. kind}
	item.icon = nil
	item.icon_size = nil
	item.icons = {
		{
			icon = TEAM_MATE_ICON,
			icon_size = TEAM_MATE_ICON_SIZE,
			tint = tint
		}
	}
	item.subgroup = "tool"
	item.order = "z[not-alone]-" .. order_suffix
	item.stack_size = 20
	return item
end

local miner_item = make_team_mate_item("miner", {r = 0.92, g = 0.42, b = 0.04, a = 1}, "a[miner]")
local builder_item = make_team_mate_item("builder", {r = 0.87, g = 0.72, b = 0.2, a = 1}, "b[builder]")
local soldier_item = make_team_mate_item("soldier", {r = 0.72, g = 0.08, b = 0.08, a = 1}, "c[soldier]")
local carrier_item = make_team_mate_item("carrier", {r = 0.2, g = 0.55, b = 0.85, a = 1}, "d[carrier]")

local team_mate = table.deepcopy(data.raw["unit"]["small-biter"])
team_mate.name = "not-alone-team-mate"
team_mate.localised_name = {"entity-name.not-alone-team-mate"}
team_mate.icon = "__base__/graphics/icons/light-armor.png"
team_mate.flags = {"placeable-player", "placeable-off-grid", "not-repairable", "breaths-air"}
team_mate.max_health = 250
team_mate.healing_per_tick = 0.15
team_mate.collision_box = {{-0.2, -0.2}, {0.2, 0.2}}
team_mate.selection_box = {{-0.4, -1.4}, {0.4, 0.2}}
team_mate.subgroup = "creatures"
team_mate.order = "a[character]-b[team-mate]"
team_mate.movement_speed = data.raw.character.character.running_speed
team_mate.distance_per_frame = 0.13
team_mate.vision_distance = 30
team_mate.radar_range = 2
team_mate.friendly_map_color = {r = 0.2, g = 1, b = 0.2, a = 1}
team_mate.corpse = nil
team_mate.dying_explosion = nil
team_mate.dying_sound = nil
team_mate.working_sound = nil
team_mate.walking_sound = nil
team_mate.run_animation = {
	layers = {
		character_animations.level1.running,
		character_animations.level1.running_mask,
		character_animations.level1.running_shadow
	}
}
team_mate.attack_parameters = {
	type = "projectile",
	ammo_category = "bullet",
	cooldown = 15,
	range = 15,
	sound = {
		variations = {
			{filename = "__base__/sound/fight/light-gunshot-1.ogg", volume = 0.6},
			{filename = "__base__/sound/fight/light-gunshot-2.ogg", volume = 0.6},
			{filename = "__base__/sound/fight/light-gunshot-3.ogg", volume = 0.6},
			{filename = "__base__/sound/fight/light-gunshot-4.ogg", volume = 0.6},
			{filename = "__base__/sound/fight/light-gunshot-5.ogg", volume = 0.6},
			{filename = "__base__/sound/fight/light-gunshot-6.ogg", volume = 0.6},
			{filename = "__base__/sound/fight/light-gunshot-7.ogg", volume = 0.6}
		}
	},
	ammo_type = {
		category = "bullet",
		target_type = "entity",
		action = {
			type = "direct",
			action_delivery = {
				type = "instant",
				target_effects = {
					{
						type = "damage",
						damage = {amount = 5, type = "physical"}
					}
				}
			}
		}
	},
	animation = {
		layers = {
			character_animations.level1.idle_gun,
			character_animations.level1.idle_gun_mask,
			character_animations.level1.idle_gun_shadow
		}
	}
}
team_mate.ai_settings = {
	destroy_when_commands_fail = false,
	allow_try_return_to_spawner = false
}

local hidden_team_mate = table.deepcopy(team_mate)
hidden_team_mate.name = "not-alone-team-mate-hidden"
local hidden_animation_layer = {
	filename = "__core__/graphics/empty.png",
	width = 1,
	height = 1,
	frame_count = 1,
	direction_count = 1
}
hidden_team_mate.run_animation = {layers = {hidden_animation_layer}}
hidden_team_mate.attack_parameters.animation = {layers = {hidden_animation_layer}}

-- Bounce (forward then backward) with a 1-frame hold at the top of the swing
-- before it comes back down, approximating the native player's brief pause.
local mining_bounce_sequence = {}
for frame = 1, 26 do
	mining_bounce_sequence[#mining_bounce_sequence + 1] = frame
end
mining_bounce_sequence[#mining_bounce_sequence + 1] = 26
for frame = 25, 2, -1 do
	mining_bounce_sequence[#mining_bounce_sequence + 1] = frame
end

-- AnimationPrototype has no direction support, so the character sheets' 8
-- direction rows each become their own body/mask prototype pair; the runtime
-- picks the pair matching the unit's facing. Sampling the sheets as flat
-- grids mixed rows between the striped body and single-file mask, which is
-- what made the overlay desync from the body.
local mining_prototypes = {}
for direction = 0, 7 do
	local mining_tool = table.deepcopy(character_animations.level1.mining_tool)
	local mining_tool_mask = table.deepcopy(character_animations.level1.mining_tool_mask)
	local mining_tool_shadow = table.deepcopy(character_animations.level1.mining_tool_shadow)
	for _, layer in pairs({mining_tool, mining_tool_mask, mining_tool_shadow}) do
		layer.direction_count = nil
		layer.frame_sequence = mining_bounce_sequence
	end
	-- Under 1 frame per tick so no sequence steps are skipped and the apex hold
	-- always renders; the 60-tick cycle still divides the 120-tick strike interval.
	mining_tool.animation_speed = 51 / 60
	mining_tool_mask.animation_speed = 51 / 60
	mining_tool_mask.apply_runtime_tint = nil
	for _, stripe in pairs(mining_tool.stripes) do
		stripe.height_in_frames = 1
		stripe.y = direction * 194
	end
	for _, stripe in pairs(mining_tool_shadow.stripes) do
		stripe.height_in_frames = 1
		stripe.y = direction * 142
	end
	mining_tool_mask.y = direction * 138
	mining_prototypes[#mining_prototypes + 1] = {
		type = "animation",
		name = "not-alone-team-mate-mining-" .. direction,
		layers = {
			mining_tool,
			mining_tool_shadow
		}
	}
	mining_prototypes[#mining_prototypes + 1] = {
		type = "animation",
		name = "not-alone-team-mate-mining-mask-" .. direction,
		layers = {
			mining_tool_mask
		}
	}
end
data:extend(mining_prototypes)

local mining_sound = {
	type = "sound",
	name = "not-alone-team-mate-mining-sound",
	variations = {
		{filename = "__core__/sound/axe-mining-ore-1.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-2.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-3.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-4.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-5.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-6.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-7.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-8.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-9.ogg", volume = 0.4},
		{filename = "__core__/sound/axe-mining-ore-10.ogg", volume = 0.4}
	}
}

local command_tool = {
	type = "selection-tool",
	name = "not-alone-command-tool",
	icon = "__base__/graphics/icons/spidertron-remote.png",
	flags = {"not-stackable", "spawnable"},
	subgroup = "tool",
	order = "c[automated-construction]-z[not-alone-command-tool]",
	stack_size = 1,
	select = {
		border_color = {0.2, 1, 0.2},
		mode = {"any-entity"},
		entity_filters = {"not-alone-team-mate", "not-alone-team-mate-hidden"},
		cursor_box_type = "entity"
	},
	alt_select = {
		border_color = {0.2, 1, 0.2},
		mode = {"any-entity"},
		entity_filters = {"not-alone-team-mate", "not-alone-team-mate-hidden"},
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
	logistics_hub,
	logistics_hub_item,
	logistics_hub_recipe,
	team_mate_member,
	miner_item,
	builder_item,
	soldier_item,
	carrier_item,
	building_logistics_requester,
	team_mate,
	hidden_team_mate,
	mining_sound,
	command_tool
})