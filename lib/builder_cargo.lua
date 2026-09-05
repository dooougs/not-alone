-- Functional area extracted from not-alone.lua.

function get_builder_cargo(record)
  if not record.builder_cargo or not record.builder_cargo.valid then
    record.builder_cargo = game.create_inventory(BUILDER_CARGO_SLOTS)
  end
  return record.builder_cargo
end

function size_builder_cargo_for_plan(record, plan)
  local item_names = {}
  for _, action in pairs(plan) do
    if action.type == "fetch" then
      item_names[action.item.name] = true
    elseif action.type == "craft" then
      item_names[action.product.name] = true
    end
  end
  local required_slots = 0
  for _ in pairs(item_names) do
    required_slots = required_slots + 1
  end
  required_slots = math.max(1, required_slots)
  local cargo = get_builder_cargo(record)
  if cargo.is_empty() and #cargo < required_slots then
    cargo.destroy()
    record.builder_cargo = game.create_inventory(
      math.min(required_slots, MAX_BUILDER_CARGO_SLOTS)
    )
  end
  return record.builder_cargo
end

function grow_builder_cargo(record)
  local cargo = record.builder_cargo
  if not cargo or not cargo.valid or not cargo.is_empty()
    or #cargo >= MAX_BUILDER_CARGO_SLOTS then
    return cargo
  end
  local new_size = math.min(#cargo * 2, MAX_BUILDER_CARGO_SLOTS)
  cargo.destroy()
  record.builder_cargo = game.create_inventory(new_size)
  return record.builder_cargo
end

function size_builder_cargo_for_target(record, target)
  local required_slots = #(target.prototype.mineable_properties.products or {})
  for inventory_index = 1, target.get_max_inventory_index() do
    local inventory = target.get_inventory(inventory_index)
    if inventory then
      required_slots = required_slots + #inventory
    end
  end
  required_slots = math.max(required_slots, BUILDER_CARGO_SLOTS)
  local cargo = get_builder_cargo(record)
  if cargo.is_empty() and #cargo < required_slots then
    cargo.destroy()
    record.builder_cargo = game.create_inventory(
      math.min(required_slots, MAX_BUILDER_CARGO_SLOTS)
    )
  end
  return record.builder_cargo
end

function find_builder_cargo_action(record, cargo)
  for slot = 1, #cargo do
    local stack = cargo[slot]
    if stack.valid_for_read then
      local item = {name = stack.name, quality = stack.quality.name}
      local delivery_info = {item_name = item.name, inventory = defines.inventory.chest}
      local consumer = find_requesting_consumer(record, delivery_info)
      if consumer and consumer.valid
        and consumer_accepts_item(consumer, delivery_info, 1) then
        return item, consumer, consumer.get_inventory(defines.inventory.chest)
      end
    end
  end

  for slot = 1, #cargo do
    local stack = cargo[slot]
    if stack.valid_for_read then
      local item = {name = stack.name, quality = stack.quality.name}
      local source = find_logistics_return_source(record, item)
      local inventory = get_logistics_source_inventory(source)
      if inventory then
        return item, source, inventory
      end
    end
  end
  return nil, nil, nil
end

function return_builder_cargo(record)
  local cargo = record.builder_cargo
  if not cargo or not cargo.valid or cargo.is_empty() then
    record.builder_delivery_item = nil
    record.builder_delivery_target = nil
    record.builder_delivery_inventory = nil
    if record.kind == "builder" and record.builder_deconstruction_started
      and record.builder_target and record.builder_target.valid
      and record.builder_target.to_be_deconstructed() then
      record.builder_state = "move-to-deconstruction"
    else
      record.builder_deconstruction_started = nil
      if record.kind == "builder" then
        record.builder_state = nil
      end
    end
    return false
  end

  -- Keep walking toward an already-chosen destination instead of re-running
  -- the network search every tick, which can transiently fail (returning no
  -- destination) while the team mate is between logistic cells en route.
  local item = record.builder_delivery_item
  local destination = record.builder_delivery_target
  local inventory = destination and destination.valid and record.builder_delivery_inventory
  if not item or not destination or not destination.valid or not inventory
    or cargo.get_item_count(item.name) == 0
    or inventory.get_insertable_count(item.name) == 0 then
    item, destination, inventory = find_builder_cargo_action(record, cargo)
    record.builder_delivery_item = item
    record.builder_delivery_target = destination
    record.builder_delivery_inventory = inventory
  end
  if not destination then
    stop_team_mate(record)
    return true
  end

  if distance_squared(record.entity.position, destination.position) <= 4 then
    local count = math.min(
      cargo.get_item_count(item),
      inventory.get_insertable_count(item)
    )
    if count > 0 then
      local inserted = inventory.insert({
        name = item.name,
        quality = item.quality,
        count = count
      })
      if inserted > 0 then
        cargo.remove({name = item.name, quality = item.quality, count = inserted})
      end
    end
    -- Force a fresh search next tick: this slot may be empty, or the
    -- destination may now be full, or another cargo item needs a turn.
    record.builder_delivery_item = nil
    record.builder_delivery_target = nil
    record.builder_delivery_inventory = nil
  else
    move_team_mate(record, destination.position, 2)
  end
  return true
end

function return_builder_material(record)
  if not record.builder_item or (record.builder_carried_count or 0) == 0 then
    record.builder_item = nil
    record.builder_source = nil
    record.builder_target = nil
    record.builder_carried_count = 0
    record.builder_state = nil
    return false
  end
  local inventory = get_logistics_source_inventory(record.builder_source)
  if not inventory or inventory.get_insertable_count(record.builder_item) == 0 then
    record.builder_source = find_logistics_return_source(record, record.builder_item)
    inventory = get_logistics_source_inventory(record.builder_source)
  end
  if not inventory then
    record.builder_source = nil
    stop_team_mate(record)
    return true
  end
  if distance_squared(record.entity.position, record.builder_source.position) <= 4 then
    local inserted = inventory.insert({
      name = record.builder_item.name,
      quality = record.builder_item.quality,
      count = 1
    })
    if inserted == 1 then
      record.builder_item = nil
      record.builder_source = nil
      record.builder_target = nil
      record.builder_carried_count = 0
      record.builder_state = nil
      return false
    end
  end
  move_team_mate(record, record.builder_source.position, 2)
  return true
end

dock_at_habitat = function(record)
  local habitat = find_nearest_habitat(record)
  if not habitat then
    stop_team_mate(record)
    return true
  end
  if distance_squared(record.entity.position, habitat.position) > 9 then
    move_team_mate(record, habitat.position, 3)
    return true
  end

  stop_team_mate(record)
  update_mining_animation(record, false)
  local inventory = get_habitat_inventory(habitat)
  if not habitat.unit_number or not inventory
    or inventory.insert({name = ITEM_NAME_BY_KIND[record.kind], count = 1}) ~= 1 then
    -- No room: stay deployed and wait by the habitat.
    return true
  end
  -- Docked Soldiers keep their weapons and ammo; the arsenal waits in the
  -- Habitat's locker and is restored to the next Soldier deployed from it.
  if record.kind == "soldier"
    and ((record.soldier_weapons and next(record.soldier_weapons))
      or (record.soldier_ammo and next(record.soldier_ammo))
      or record.soldier_armor) then
    storage.not_alone_soldier_lockers = storage.not_alone_soldier_lockers or {}
    local lockers = storage.not_alone_soldier_lockers[habitat.unit_number] or {}
    lockers[#lockers + 1] = {
      weapons = record.soldier_weapons,
      ammo = record.soldier_ammo,
      armor = record.soldier_armor
    }
    storage.not_alone_soldier_lockers[habitat.unit_number] = lockers
  end
  destroy_route_renderings(record)
  destroy_inventory_renderings(record)
  destroy_color_marker(record)
  if record.builder_cargo and record.builder_cargo.valid then
    -- Should be empty already (see update_builder's cargo-priority guard);
    -- spill anything left at the habitat rather than deleting it.
    if not record.builder_cargo.is_empty() then
      record.entity.surface.spill_inventory({
        position = position_table(habitat.position),
        inventory = record.builder_cargo
      })
    end
    record.builder_cargo.destroy()
  end
  if record.vehicle_inventory and record.vehicle_inventory.valid then
    local car_count = record.vehicle_inventory.get_item_count(CAR_ITEM_NAME)
    if car_count > 0 then
      local inserted = inventory.insert({name = CAR_ITEM_NAME, count = car_count})
      if inserted < car_count then
        record.entity.surface.spill_item_stack({
          position = position_table(habitat.position),
          stack = {name = CAR_ITEM_NAME, count = car_count - inserted}
        })
      end
    end
    record.vehicle_inventory.destroy()
    record.vehicle_inventory = nil
  end
  record.entity.destroy()
  return false
end

