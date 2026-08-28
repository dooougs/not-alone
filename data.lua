require("__base__.prototypes.entity.character-animations")

local team_mate = table.deepcopy(data.raw["unit"]["small-biter"])
team_mate.name = "not-alone-team-mate"
team_mate.localised_name = {"entity-name.not-alone-team-mate"}
team_mate.icon = "__core__/graphics/icons/entity/character.png"
team_mate.flags = {"placeable-player", "placeable-off-grid", "not-repairable", "breaths-air"}
team_mate.max_health = 250
team_mate.healing_per_tick = 0.15
team_mate.collision_box = {{-0.2, -0.2}, {0.2, 0.2}}
team_mate.selection_box = {{-0.4, -1.4}, {0.4, 0.2}}
team_mate.subgroup = "creatures"
team_mate.order = "a[character]-b[team-mate]"
team_mate.movement_speed = 0.15
team_mate.distance_per_frame = 0.13
team_mate.vision_distance = 30
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
		entity_filters = {"not-alone-team-mate"},
		cursor_box_type = "entity"
	},
	alt_select = {
		border_color = {0.2, 1, 0.2},
		mode = {"any-entity"},
		entity_filters = {"not-alone-team-mate"},
		cursor_box_type = "entity"
	},
	reverse_select = {
		border_color = {1, 0.8, 0.1},
		mode = {"any-tile"},
		cursor_box_type = "pair"
	}
}

data:extend({team_mate, command_tool})