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


data:extend({
  logistics_hub,
  logistics_hub_item,
  logistics_hub_recipe,
  table.unpack(building_requester_variants),
})
require("prototypes/team_mate_variants")
