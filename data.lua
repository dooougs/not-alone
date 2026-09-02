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
-- Room for a stack of every team mate kind plus spillover, so docking
-- never stalls with a "full" habitat.
logistics_hub.material_slots_count = 8
logistics_hub.construction_radius = 0

local habitat_picture = {
	filename = "__not-alone__/graphics/entity/habitat.png",
	width = 256,
	height = 256,
	scale = 0.5,
	shift = {0, -0.3}
}
logistics_hub.factoriopedia_description = {"factoriopedia-description.not-alone-logistics-hub"}
logistics_hub.base = habitat_picture
logistics_hub.base_animation = nil
logistics_hub.base_patch = nil
logistics_hub.door_animation_up = nil
logistics_hub.door_animation_down = nil

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
building_logistics_requester.hidden_in_factoriopedia = true

local building_requester_variants = {}
local requester_target_types = {
	"stone-furnace", "steel-furnace", "electric-furnace",
	"assembling-machine-1", "assembling-machine-2", "assembling-machine-3",
	"lab", "boiler", "burner-generator", "rocket-silo"
}
for _, target_name in pairs(requester_target_types) do
	local target = data.raw.furnace[target_name]
		or data.raw["assembling-machine"][target_name]
		or data.raw.lab[target_name]
		or data.raw.boiler[target_name]
		or data.raw["burner-generator"][target_name]
		or data.raw["rocket-silo"][target_name]
	if target then
		local variant = table.deepcopy(building_logistics_requester)
		variant.name = "not-alone-building-logistics-requester-" .. target_name
		variant.localised_name = {"entity-name." .. target_name}
		variant.icon = target.icon
		variant.icon_size = target.icon_size
		variant.icons = target.icons
		variant.hidden_in_factoriopedia = true
		building_requester_variants[#building_requester_variants + 1] = variant
	end
end

-- Colors must match KIND_COLOR in poc.lua. The light-armor torso icon,
-- tinted per role, echoes the look of basic armour.
local TEAM_MATE_ICON = "__base__/graphics/icons/light-armor.png"
local TEAM_MATE_ICON_SIZE = 64

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
	item.factoriopedia_description = {"factoriopedia-description.not-alone-" .. kind}
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
-- Legacy generic unit; per-role variants below are the pedia-facing pages.
team_mate.hidden_in_factoriopedia = true

-- Units ignore LuaEntity.color at runtime, so each role gets its own
-- prototype with the runtime-tint mask layers baked to the role color.
local KIND_TINT = {
	miner = {r = 0.92, g = 0.42, b = 0.04, a = 1},
	builder = {r = 0.87, g = 0.72, b = 0.2, a = 1},
	soldier = {r = 0.72, g = 0.08, b = 0.08, a = 1},
	carrier = {r = 0.2, g = 0.55, b = 0.85, a = 1}
}

local function tint_unit_masks(unit, tint)
	for _, animation in pairs({unit.run_animation, unit.attack_parameters.animation}) do
		for _, layer in pairs(animation.layers or {}) do
			if layer.apply_runtime_tint then
				layer.apply_runtime_tint = nil
				layer.tint = tint
			end
		end
	end
end

local function set_team_mate_pedia_visuals(unit, tint, sheet)
	unit.icon = TEAM_MATE_ICON
	unit.icon_size = TEAM_MATE_ICON_SIZE
	unit.icons = {
		{icon = TEAM_MATE_ICON, icon_size = TEAM_MATE_ICON_SIZE, tint = tint}
	}
	unit.run_animation = {
		layers = {
			table.deepcopy(sheet.running),
			table.deepcopy(sheet.running_mask),
			table.deepcopy(sheet.running_shadow)
		}
	}
	unit.attack_parameters.animation = {
		layers = {
			table.deepcopy(sheet.idle_gun),
			table.deepcopy(sheet.idle_gun_mask),
			table.deepcopy(sheet.idle_gun_shadow)
		}
	}
	tint_unit_masks(unit, tint)
	unit.factoriopedia_simulation = {
		init = "game.simulation.camera_zoom = 2.8\n"
			.. "game.simulation.camera_position = {0, 0}\n"
			.. "tiles = {}\n"
			.. "for x = -12, 12 do for y = -12, 12 do "
			.. "tiles[#tiles + 1] = {position = {x, y}, name = \"grass-1\"} "
			.. "end end\n"
			.. "game.surfaces[1].set_tiles(tiles)\n"
			.. "preview = game.surfaces[1].create_entity{name = \""
			.. unit.name .. "\", position = {0, 0}}"
			.. "\npreview.commandable.set_command{type = defines.command.stop}"
	}
end

local hidden_team_mate = table.deepcopy(team_mate)
hidden_team_mate.name = "not-alone-team-mate-hidden"
hidden_team_mate.hidden_in_factoriopedia = true
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

local function find_unlocking_technology(recipe_name)
	for _, technology in pairs(data.raw.technology) do
		for _, effect in pairs(technology.effects or {}) do
			if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
				return technology
			end
		end
	end
	return nil
end

local soldier_prototypes = {}
local soldier_units = {}
for _, weapon in pairs(SOLDIER_WEAPONS) do
	local unit = table.deepcopy(team_mate)
	unit.name = "not-alone-team-mate-" .. weapon.suffix
	unit.localised_name = {"entity-name.not-alone-team-mate-soldier"}
	local sheet = character_animations[weapon.sheet] or character_animations.level1
	set_team_mate_pedia_visuals(unit, KIND_TINT.soldier, sheet)
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

	local kit_item = make_team_mate_item(weapon.kind, KIND_TINT.soldier, weapon.order)
	-- The kit shows the actual gun so the tiers are tellable apart at a glance.
	if gun and gun.icon then
		kit_item.icons = nil
		kit_item.icon = gun.icon
		kit_item.icon_size = gun.icon_size
	end
	soldier_prototypes[#soldier_prototypes + 1] = kit_item

	local recipe = {
		type = "recipe",
		name = "not-alone-" .. weapon.kind,
		enabled = true,
		ingredients = {
			{type = "item", name = weapon.gun, amount = 1},
			{type = "item", name = weapon.ammo, amount = 5}
		},
		results = {{type = "item", name = "not-alone-" .. weapon.kind, amount = 1}}
	}
	local technology = find_unlocking_technology(weapon.gun)
	if technology then
		recipe.enabled = false
		table.insert(technology.effects, {type = "unlock-recipe", recipe = recipe.name})
	end
	soldier_prototypes[#soldier_prototypes + 1] = recipe
end

-- The base Soldier is unarmed and punches at melee range, like a recruit.
local fists_unit = table.deepcopy(team_mate)
fists_unit.name = "not-alone-team-mate-fists"
fists_unit.localised_name = {"entity-name.not-alone-team-mate-soldier"}
fists_unit.hidden_in_factoriopedia = nil
fists_unit.factoriopedia_description = {"factoriopedia-description.not-alone-team-mate-soldier"}
set_team_mate_pedia_visuals(fists_unit, KIND_TINT.soldier, character_animations.level1)
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
punch_mask.tint = KIND_TINT.soldier
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
				armored_unit.icon = TEAM_MATE_ICON
				armored_unit.icon_size = TEAM_MATE_ICON_SIZE
				armored_unit.icons = {
					{icon = TEAM_MATE_ICON, icon_size = TEAM_MATE_ICON_SIZE,
						tint = KIND_TINT.soldier}
				}
				tint_unit_masks(armored_unit, KIND_TINT.soldier)
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
		tint_unit_masks(mech, KIND_TINT.soldier)
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
	local unit = table.deepcopy(team_mate)
	unit.name = "not-alone-team-mate-" .. kind
	unit.localised_name = {"entity-name.not-alone-team-mate-" .. kind}
	unit.hidden_in_factoriopedia = nil
	unit.factoriopedia_description = {"factoriopedia-description.not-alone-team-mate-" .. kind}
	set_team_mate_pedia_visuals(unit, KIND_TINT[kind], character_animations.level1)
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
	logistics_hub,
	logistics_hub_item,
	logistics_hub_recipe,
	miner_item,
	builder_item,
	soldier_item,
	carrier_item,
	building_logistics_requester,
	table.unpack(building_requester_variants),
	team_mate,
	hidden_team_mate,
	mining_sound,
	command_tool
})