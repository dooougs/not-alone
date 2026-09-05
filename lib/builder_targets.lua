-- Functional area extracted from poc.lua.

function builder_target_is_claimed(target, current_record)
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record ~= current_record and record.builder_target == target then
        return true
      end
    end
  end
  return false
end

BUILDER_UNREACHABLE_RETRY_TICKS = 7200

function builder_target_is_unreachable(record, target)
  local unreachable = record.builder_unreachable
  if not unreachable then
    return false
  end
  local kept = {}
  local found = false
  for _, entry in pairs(unreachable) do
    if entry.entity.valid and game.tick - entry.tick < BUILDER_UNREACHABLE_RETRY_TICKS then
      kept[#kept + 1] = entry
      if entry.entity == target then
        found = true
      end
    end
  end
  record.builder_unreachable = kept[1] and kept or nil
  return found
end

function find_builder_job(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_logistic_network_by_position(
    position_table(position),
    force
  )
  if not network then
    return nil, nil, nil
  end

  local contents = get_logistics_contents(network)
  local ghosts = {}
  local seen_ghosts = {}
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      for _, ghost in pairs(surface.find_entities_filtered({
        type = "entity-ghost",
        force = force,
        position = cell.owner.position,
        radius = math.max(cell.logistic_radius, cell.construction_radius) * 1.5
      })) do
        -- A ghost can be buildable inside the network's construction footprint
        -- even when it sits just outside the logistic coverage window; some
        -- underground-belt and power-pole ghosts land exactly on that edge.
        local in_network = cell.is_in_logistic_range(ghost.position)
          or cell.is_in_construction_range(ghost.position)
        if in_network
          and not seen_ghosts[ghost.unit_number]
          and not builder_target_is_unreachable(record, ghost)
          and not builder_target_is_claimed(ghost, record) then
          seen_ghosts[ghost.unit_number] = true
          ghosts[#ghosts + 1] = ghost
        end
      end
    end
  end
  table.sort(ghosts, function(left, right)
    return distance_squared(position, left.position)
      < distance_squared(position, right.position)
  end)

  for _, ghost in ipairs(ghosts) do
    local item = get_ghost_item(ghost)
    local plan = item and find_builder_plan(network, item, force, contents)
    if plan and builder_plan_has_valid_sources(network, plan) then
      return ghost, plan, item
    end
    storage.not_alone_pending_builder_ghosts = storage.not_alone_pending_builder_ghosts or {}
    storage.not_alone_pending_builder_ghosts[ghost.unit_number] = ghost
  end
  return nil, nil, nil
end

function find_builder_deconstruction_target(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_logistic_network_by_position(position, force)
  if not network then
    return nil
  end

  local function network_can_store(stack)
    local item = {name = stack.name, quality = stack.quality.name}
    for _, storage_entity in pairs(network.storages) do
      local inventory = get_logistics_source_inventory(storage_entity)
      if inventory and inventory.get_insertable_count(item) > 0 then
        return true
      end
    end
    return false
  end

  local nearest_target
  local nearest_distance
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      local habitat_cell = cell.owner.name == LOGISTICS_HUB_NAME
      local search_radius = habitat_cell and cell.logistic_radius or cell.construction_radius
      local targets = surface.find_entities_filtered({
        position = cell.owner.position,
        radius = search_radius * 1.5,
        to_be_deconstructed = true
      })
      for _, item_entity in pairs(surface.find_entities_filtered({
        position = cell.owner.position,
        radius = search_radius * 1.5,
        type = "item-entity"
      })) do
        targets[#targets + 1] = item_entity
      end
      for _, target in pairs(targets) do
        local distance = distance_squared(position, target.position)
        local can_collect = target.type == "item-entity"
          and target.stack.valid_for_read
        if (target.minable or can_collect)
          and (not can_collect or network_can_store(target.stack))
          and target.is_registered_for_deconstruction(force)
          and not builder_target_is_unreachable(record, target)
          and (habitat_cell and cell.is_in_logistic_range(target.position)
            or not habitat_cell and cell.is_in_construction_range(target.position))
          and not builder_target_is_claimed(target, record)
          and (not nearest_distance or distance < nearest_distance) then
          nearest_target = target
          nearest_distance = distance
        end
      end
    end
  end
  return nearest_target
end

-- Damaged buildings take priority over new construction: find the nearest
-- one, whether stock has a spare repair pack or one needs crafting first.
function find_builder_repair_target(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_logistic_network_by_position(position, force)
  if not network then
    return nil
  end

  local nearest_target
  local nearest_distance
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      local habitat_cell = cell.owner.name == LOGISTICS_HUB_NAME
      local search_radius = habitat_cell and cell.logistic_radius or cell.construction_radius
      for _, target in pairs(surface.find_entities_filtered({
        position = cell.owner.position,
        radius = search_radius * 1.5,
        force = force
      })) do
        local distance = distance_squared(position, target.position)
        if target.health and target.type ~= "unit" and target.type ~= "entity-ghost"
          and target.get_health_ratio and target.get_health_ratio() < 1
          and not target.to_be_deconstructed()
          and not builder_target_is_unreachable(record, target)
          and (habitat_cell and cell.is_in_logistic_range(target.position)
            or not habitat_cell and cell.is_in_construction_range(target.position))
          and not builder_target_is_claimed(target, record)
          and (not nearest_distance or distance < nearest_distance) then
          nearest_target = target
          nearest_distance = distance
        end
      end
    end
  end
  return nearest_target
end

function find_builder_repair_job(record, surface, force, position)
  if not prototypes.item[REPAIR_PACK_ITEM_NAME] then
    return nil, nil, nil
  end
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local target = find_builder_repair_target(record, surface, force, position)
  if not target then
    return nil, nil, nil
  end
  local network = surface.find_logistic_network_by_position(position, force)
  if not network then
    return nil, nil, nil
  end
  -- find_builder_plan already fetches directly from stock when a repair
  -- pack is available, and otherwise chains in the crafting actions needed
  -- to make one, so a builder without a spare pack crafts it on the spot.
  local item = {name = REPAIR_PACK_ITEM_NAME, quality = "normal"}
  local contents = get_logistics_contents(network)
  local plan = find_builder_plan(network, item, force, contents)
  if plan and builder_plan_has_valid_sources(network, plan) then
    return target, plan, item
  end
  return nil, nil, nil
end

function assign_builder_job(record, surface, force, position)
  local repair_target, repair_plan, repair_item = find_builder_repair_job(record, surface, force, position)
  if repair_target then
    record.builder_target = repair_target
    record.builder_plan = repair_plan
    record.builder_plan_index = 1
    record.builder_item = repair_item
    record.builder_carried_count = 0
    record.builder_source = nil
    record.builder_state = "execute-plan"
    return true
  end

  local target, plan, item = find_builder_job(record, surface, force, position)
  if target then
    record.builder_target = target
    record.builder_plan = plan
    record.builder_plan_index = 1
    record.builder_item = item
    record.builder_carried_count = 0
    record.builder_source = nil
    record.builder_state = "execute-plan"
    return true
  end

  target = find_builder_deconstruction_target(record, surface, force, position)
  if target then
    record.builder_plan = nil
    record.builder_plan_index = nil
    record.builder_craft_ready_tick = nil
    record.builder_target = target
    record.builder_source = nil
    record.builder_item = nil
    record.builder_carried_count = 0
    record.builder_state = "move-to-deconstruction"
    return true
  end
  return false
end

