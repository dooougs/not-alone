-- Functional area extracted from poc.lua.

function get_consumer_inventory(consumer, mining_role)
  if consumer.name == BUILDING_REQUESTER_NAME
    or consumer.name:sub(1, #BUILDING_REQUESTER_PREFIX) == BUILDING_REQUESTER_PREFIX
    or LOGISTICS_SOURCE_MODES[consumer.prototype.logistic_mode] then
    return consumer.get_inventory(defines.inventory.chest)
  end
  return consumer.get_inventory(mining_role.inventory)
end

function consumer_accepts_item(consumer, mining_role, count)
  local inventory = get_consumer_inventory(consumer, mining_role)
  return inventory and inventory.get_insertable_count(mining_role.item_name) >= count
end

function find_requesting_consumer(record, mining_role)
  -- Use the closest network, not just one that exactly covers this position:
  -- a full Miner/Builder may have wandered just outside coverage while
  -- gathering and must still be able to find its way back to deliver.
  local network = record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  local requester_point = network and network.select_drop_point({
    stack = {name = mining_role.item_name, count = 1},
    members = "requester"
  })
  local requester = requester_point and requester_point.owner
  if requester and requester.valid
    and (requester.name == BUILDING_REQUESTER_NAME
      or requester.name:sub(1, #BUILDING_REQUESTER_PREFIX) == BUILDING_REQUESTER_PREFIX) then
    return requester
  end
  return nil
end

function get_mining_interval(player)
  local mining_speed_modifier = player.character_mining_speed_modifier
  local effective_mining_speed = NORMAL_CHARACTER_MINING_SPEED * (1 + mining_speed_modifier)
  return math.max(1, math.ceil(RESOURCE_MINING_TIME * 60 / effective_mining_speed))
end

function get_logistics_source_inventory(source)
  source = source and source.owner or source
  if not source or not source.valid then
    return nil
  end
  if FURNACE_ENTITY_NAMES[source.name] then
    return source.get_inventory(defines.inventory.crafter_output)
  end
  if not LOGISTICS_SOURCE_MODES[source.prototype.logistic_mode] then
    return nil
  end
  return source.get_inventory(defines.inventory.chest)
end

function get_network_furnaces(network)
  local furnaces = {}
  local seen = {}
  for _, cell in pairs(network and network.cells or {}) do
    if cell.valid and cell.owner.valid then
      for _, furnace in pairs(cell.owner.surface.find_entities_filtered({
        name = FURNACE_ENTITY_NAME_LIST,
        position = cell.owner.position,
        radius = cell.logistic_radius
      })) do
        if furnace.valid and not seen[furnace.unit_number]
          and cell.is_in_logistic_range(furnace.position) then
          seen[furnace.unit_number] = true
          furnaces[#furnaces + 1] = furnace
        end
      end
    end
  end
  return furnaces
end

function get_logistics_contents(network)
  local contents = network.get_contents()
  for _, furnace in pairs(get_network_furnaces(network)) do
    local inventory = get_logistics_source_inventory(furnace)
    for _, item in pairs(inventory and inventory.get_contents() or {}) do
      contents[#contents + 1] = item
    end
  end
  return contents
end

function safe_recipe_value(recipe, key)
  if not recipe then
    return nil
  end
  local ok, value = pcall(function()
    return recipe[key]
  end)
  if ok then
    return value
  end
  return nil
end

function recipe_produces_item(recipe, item_name)
  if not recipe then
    return false
  end
  if recipe.name == item_name or safe_recipe_value(recipe, "result") == item_name then
    return true
  end
  local results = safe_recipe_value(recipe, "results") or {}
  for _, result in pairs(results) do
    if result then
      local result_name = result.name or result[1]
      if result_name == item_name then
        return true
      end
    end
  end
  for _, mode in pairs({"normal", "expensive"}) do
    local recipe_mode = safe_recipe_value(recipe, mode)
    if recipe_mode and recipe_produces_item(recipe_mode, item_name) then
      return true
    end
  end
  return false
end

function trigger_research_unlocks_for_item(force, item_name)
  if not force or not item_name then
    return
  end
  for _, technology in pairs(prototypes.technology) do
    if technology and technology.effects then
      for _, effect in pairs(technology.effects) do
        if effect.type == "unlock-recipe" then
          local recipe = prototypes.recipe[effect.recipe]
          if recipe and recipe_produces_item(recipe, item_name) then
            local tech_state = force.technologies[technology.name]
            if tech_state and not tech_state.researched then
              tech_state.researched = true
            end
          end
        end
      end
    end
  end
end

function get_logistics_target_inventory(target, inventory_kind)
  if not target or not target.valid then
    return nil
  end
  if inventory_kind == "fuel" then
    return target.burner and target.burner.inventory
  end
  if inventory_kind == "requester" then
    return target.get_inventory(defines.inventory.chest)
  end
  if inventory_kind == "lab" then
    return target.get_inventory(defines.inventory.lab_input)
  end
  return target.get_inventory(defines.inventory.crafter_input)
end

function item_is_fuel_for(item_name, burner)
  local item_prototype = prototypes.item[item_name]
  return item_prototype and item_prototype.fuel_category
    and burner.fuel_categories[item_prototype.fuel_category]
end

function fuel_priority(item_name)
  local item_prototype = prototypes.item[item_name]
  if not item_prototype or not item_prototype.fuel_value then
    return 0
  end
  return item_prototype.fuel_value
end

-- Scanning every storage chest and team mate repeats identically for every
-- burner in the same network on the same tick; memoize the candidate names.
fuel_candidate_cache = {}

function get_network_fuel_candidates(network, force)
  local cached = fuel_candidate_cache[network.network_id]
  if cached and cached.tick == game.tick then
    return cached.items
  end
  local items = {}
  for _, source in pairs(network.storages) do
    local inventory = get_logistics_source_inventory(source)
    if inventory then
      for _, item in pairs(inventory.get_contents()) do
        local prototype = prototypes.item[item.name]
        if prototype and prototype.fuel_category then
          items[#items + 1] = item.name
        end
      end
    end
  end
  -- Fuel carried by team mates exists in no chest yet but is en route.
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.entity.valid and record.entity.force == force then
        local resource_info = record.kind == "miner" and record.mining_resource_info
        if resource_info then
          items[#items + 1] = resource_info.item_name
        end
        if record.kind == "builder" then
          if record.builder_item and (record.builder_carried_count or 0) > 0 then
            items[#items + 1] = record.builder_item.name
          end
          if record.builder_cargo and record.builder_cargo.valid then
            for _, item in pairs(record.builder_cargo.get_contents()) do
              items[#items + 1] = item.name
            end
          end
        end
      end
    end
  end
  fuel_candidate_cache[network.network_id] = {tick = game.tick, items = items}
  return items
end

function find_available_fuel(target, network)
  local burner = target.burner
  if not burner or not burner.inventory then
    return nil
  end
  local best_name = nil
  local best_priority = -1
  for _, item_name in ipairs(get_network_fuel_candidates(network, target.force)) do
    if item_is_fuel_for(item_name, burner) then
      local priority = fuel_priority(item_name)
      if priority > best_priority then
        best_name = item_name
        best_priority = priority
      end
    end
  end
  return best_name
end

function inventory_kind_for_item(target, item_name)
  local burner = target.burner
  if burner and burner.inventory and item_is_fuel_for(item_name, burner) then
    return "fuel"
  end
  if RECIPE_ENTITY_TYPES[target.type] then
    local recipe = target.get_recipe()
    if recipe then
      for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" and ingredient.name == item_name then
          return "input"
        end
      end
    end
  end
  if target.type == "lab" then
    for _, input_name in pairs(target.prototype.lab_inputs or {}) do
      if input_name == item_name then
        return "lab"
      end
    end
  end
  return nil
end

function get_building_requests(target, network)
  local requests = {}
  if RECIPE_ENTITY_TYPES[target.type] then
    local recipe = target.get_recipe()
    local inventory = target.get_inventory(defines.inventory.crafter_input)
    if recipe and inventory then
      for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" then
          -- Batch requests so carriers deliver loads, not single items.
          local desired_count = math.max(math.ceil(ingredient.amount), INGREDIENT_REQUEST_COUNT)
          local missing_count = desired_count - inventory.get_item_count(ingredient.name)
          if missing_count > 0 and inventory.get_insertable_count(ingredient.name) > 0 then
            requests[#requests + 1] = {
              item_name = ingredient.name,
              count = missing_count,
              inventory_kind = "input"
            }
          end
        end
      end
    end
  end

  local fuel_name = find_available_fuel(target, network)
  local fuel_inventory = target.burner and target.burner.inventory
  if fuel_name and fuel_inventory then
    local missing_count = FUEL_REQUEST_COUNT - fuel_inventory.get_item_count(fuel_name)
    if missing_count > 0 and fuel_inventory.get_insertable_count(fuel_name) > 0 then
      requests[#requests + 1] = {
        item_name = fuel_name,
        count = missing_count,
        inventory_kind = "fuel"
      }
    end
  end

  if target.type == "lab" then
    local inventory = target.get_inventory(defines.inventory.lab_input)
    if inventory then
      for _, input_name in pairs(target.prototype.lab_inputs or {}) do
        local missing_count = INGREDIENT_REQUEST_COUNT - inventory.get_item_count(input_name)
        if missing_count > 0 and inventory.get_insertable_count(input_name) > 0 then
          requests[#requests + 1] = {
            item_name = input_name,
            count = missing_count,
            inventory_kind = "lab"
          }
        end
      end
    end
  end
  return requests
end

function update_building_requester(requester_record, network)
  local target = requester_record.target
  local requester = requester_record.requester
  if not target.valid or not requester.valid then
    if requester.valid then
      requester.destroy()
    end
    return false
  end

  local requester_inventory = requester.get_inventory(defines.inventory.chest)
  for _, item in pairs(requester_inventory.get_contents()) do
    -- Move whatever the target can currently accept, even if the fresh
    -- request that originally justified delivering it has since expired.
    local inventory_kind = inventory_kind_for_item(target, item.name)
    local target_inventory = inventory_kind
      and get_logistics_target_inventory(target, inventory_kind)
    if target_inventory then
      local inserted = target_inventory.insert({name = item.name, count = item.count})
      if inserted > 0 then
        requester_inventory.remove({name = item.name, count = inserted})
      end
    end
  end

  local requests = get_building_requests(target, network)

  local requester_point = requester.get_requester_point()
  local section = requester_point and requester_point.get_section(1)
  if requester_point and not section then
    section = requester_point.add_section()
  end
  if section then
    for slot = 1, BUILDING_REQUEST_SLOT_COUNT do
      section.clear_slot(slot)
    end
    for slot, request in ipairs(requests) do
      if slot > BUILDING_REQUEST_SLOT_COUNT then
        break
      end
      section.set_slot(slot, {
        value = {type = "item", name = request.item_name, quality = "normal"},
        min = request.count
      })
    end
  end
  return true
end

function update_building_requesters_for_network(surface, force, position, network)
  network = network or surface.find_logistic_network_by_position(
    position_table(position),
    force
  )
  if not network then
    return
  end

  storage.not_alone_building_requesters = storage.not_alone_building_requesters or {}
  storage.not_alone_building_requester_ticks = storage.not_alone_building_requester_ticks or {}
  local network_key = surface.index .. ":" .. force.index
    .. ":" .. network.network_id
  local last_update_tick = storage.not_alone_building_requester_ticks[network_key]
  if last_update_tick
    and game.tick - last_update_tick < BUILDING_REQUESTER_UPDATE_INTERVAL then
    return
  end
  storage.not_alone_building_requester_ticks[network_key] = game.tick

  local requesters = storage.not_alone_building_requesters
  local destinations = surface.find_entities_filtered({
    type = LOGISTICS_DESTINATION_TYPES,
    force = force,
    position = position,
    radius = LOGISTICS_SEARCH_RADIUS
  })
  for _, target in pairs(destinations) do
    local target_network = surface.find_logistic_network_by_position(
      position_table(target.position),
      force
    )
    if target_network == network and target.unit_number then
      local requester_record = requesters[target.unit_number]
      if not requester_record or not requester_record.requester.valid then
        local requester_name = BUILDING_REQUESTER_NAME .. "-" .. target.name
        if not prototypes.entity[requester_name] then
          requester_name = BUILDING_REQUESTER_NAME
        end
        local requester = surface.create_entity({
          name = requester_name,
          position = target.position,
          force = force,
          create_build_effect_smoke = false
        })
        if requester then
          requester.destructible = false
          requester.operable = false
          requester_record = {target = target, requester = requester}
          requesters[target.unit_number] = requester_record
        end
      end
      if requester_record and not update_building_requester(requester_record, network) then
        requesters[target.unit_number] = nil
      end
    end
  end

  for unit_number, requester_record in pairs(requesters) do
    if not requester_record.target.valid or not requester_record.requester.valid then
      if requester_record.requester.valid then
        requester_record.requester.destroy()
      end
      requesters[unit_number] = nil
    end
  end
end

