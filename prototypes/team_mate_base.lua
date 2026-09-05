-- Shared teammate prototype definitions.

-- Colors must match KIND_COLOR in not-alone.lua. The light-armor torso icon,
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
-- Belts dragging team mates off their walking paths caused endless stall
-- rescues; all variants deep-copy this base, so immunity covers every role.
team_mate.has_belt_immunity = true
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
hidden_team_mate.collision_mask = {layers = {}}
local hidden_animation_layer = {
	filename = "__core__/graphics/empty.png",
	width = 1,
	height = 1,
	frame_count = 1,
	direction_count = 1
}
hidden_team_mate.run_animation = {layers = {hidden_animation_layer}}
hidden_team_mate.attack_parameters.animation = {layers = {hidden_animation_layer}}

local vehicle_driver = table.deepcopy(data.raw.character.character)
vehicle_driver.name = "not-alone-vehicle-driver"
vehicle_driver.localised_name = {"entity-name.not-alone-team-mate"}
vehicle_driver.hidden_in_factoriopedia = true
vehicle_driver.collision_mask = {layers = {}}
vehicle_driver.selection_box = {{0, 0}, {0, 0}}
vehicle_driver.collision_box = {{0, 0}, {0, 0}}
vehicle_driver.inventory_size = 1

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


return {
	miner_item = miner_item,
	builder_item = builder_item,
	soldier_item = soldier_item,
	carrier_item = carrier_item,
  team_mate = team_mate,
  hidden_team_mate = hidden_team_mate,
  vehicle_driver = vehicle_driver,
  mining_sound = mining_sound,
  TEAM_MATE_ICON = TEAM_MATE_ICON,
  TEAM_MATE_ICON_SIZE = TEAM_MATE_ICON_SIZE,
  KIND_TINT = KIND_TINT,
  set_team_mate_pedia_visuals = set_team_mate_pedia_visuals,
  tint_unit_masks = tint_unit_masks
}
