-- Assembler-style furnaces expose a chosen recipe, letting building requesters
-- derive ingredient and fuel demand before any ore has ever been inserted.
-- Runs at final fixes so every other mod still sees the original furnaces.
local smelting_furnace_names = {"stone-furnace", "steel-furnace", "electric-furnace"}
for _, furnace_name in pairs(smelting_furnace_names) do
	local furnace = data.raw.furnace[furnace_name]
	if furnace then
		local converted = table.deepcopy(furnace)
		converted.type = "assembling-machine"
		converted.result_inventory_size = nil
		converted.source_inventory_size = nil
		converted.cant_insert_at_source_message_key = nil
		converted.custom_input_slot_tooltip_key = nil
		data.raw.furnace[furnace_name] = nil
		data:extend({converted})
	end
end
