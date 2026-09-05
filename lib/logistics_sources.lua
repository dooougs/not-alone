-- Functional area extracted from not-alone.lua.

function find_logistics_return_source(record, item_name)
  -- Use the closest network, not just one that exactly covers this position:
  -- a full Miner/Builder may have wandered just outside coverage while
  -- gathering and must still be able to find its way back to deliver.
  local network = record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  if not network then
    return nil
  end

  local nearest_source
  local nearest_distance
  for _, source in pairs(network.storages) do
    local inventory = get_logistics_source_inventory(source)
    if inventory and inventory.get_insertable_count(item_name) > 0 then
      local current_distance = distance_squared(record.entity.position, source.position)
      if not nearest_distance or current_distance < nearest_distance then
        nearest_source = source
        nearest_distance = current_distance
      end
    end
  end
  return nearest_source
end

function find_logistics_item_source(record, item_name)
  local network = record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  if not network then
    return nil
  end
  local pickup_point = network.select_pickup_point({
    name = item_name,
    position = position_table(record.entity.position),
    include_buffers = true
  })
  local source = pickup_point and pickup_point.owner
  local inventory = get_logistics_source_inventory(source)
  if inventory and inventory.get_item_count(item_name) > 0 then
    return source
  end
  local nearest_source
  local nearest_distance
  for _, furnace in pairs(get_network_furnaces(network)) do
    local furnace_inventory = get_logistics_source_inventory(furnace)
    if furnace_inventory and furnace_inventory.get_item_count(item_name) > 0 then
      local distance = distance_squared(record.entity.position, furnace.position)
      if not nearest_distance or distance < nearest_distance then
        nearest_source = furnace
        nearest_distance = distance
      end
    end
  end
  local function consider_source(candidate)
    candidate = candidate and candidate.owner or candidate
    local candidate_inventory = get_logistics_source_inventory(candidate)
    if candidate_inventory and candidate_inventory.get_item_count(item_name) > 0 then
      local distance = distance_squared(record.entity.position, candidate.position)
      if not nearest_distance or distance < nearest_distance then
        nearest_source = candidate
        nearest_distance = distance
      end
    end
  end
  for _, provider in pairs(network.providers or {}) do
    consider_source(provider)
  end
  for _, storage_entity in pairs(network.storages or {}) do
    consider_source(storage_entity)
  end
  return nearest_source
end

