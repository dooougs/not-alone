-- Functional area extracted from poc.lua.

function get_requested_count(logistic_point, item_name, quality)
  for _, filter in pairs(logistic_point.filters or {}) do
    if filter.name == item_name and (not filter.quality or filter.quality == quality) then
      return filter.count
    end
  end
  return nil
end

function requester_chest_accepts_item(chest, item_id)
  if not chest or not chest.valid then
    return false
  end
  local inventory = chest.get_inventory(defines.inventory.chest)
  if not inventory or inventory.get_insertable_count(item_id) <= 0 then
    return false
  end
  -- Only deliver items the chest is actively requesting; anything else would
  -- turn requesters (including the hidden per-building ones) into dumping grounds.
  local requester_point = chest.get_requester_point()
  if not requester_point then
    return false
  end
  for _, filter in pairs(requester_point.filters or {}) do
    if filter.name == item_id.name and (not filter.quality or filter.quality == item_id.quality) then
      local requested = filter.count or 0
      return inventory.get_item_count(item_id) < requested
    end
  end
  return false
end

function find_nearest_requester_for_item(surface, force, position, item_id)
  local nearest = nil
  local nearest_distance = nil
  for _, chest in pairs(surface.find_entities_filtered({
    type = "logistic-container",
    force = force,
    position = position,
    radius = LOGISTICS_SEARCH_RADIUS
  })) do
    if chest.valid and chest.prototype.logistic_mode == "requester"
      and requester_chest_accepts_item(chest, item_id) then
      local distance = distance_squared(position, chest.position)
      if not nearest_distance or distance < nearest_distance then
        nearest = chest
        nearest_distance = distance
      end
    end
  end
  return nearest
end

function get_producer_output_inventory(source)
  if not source or not source.valid then
    return nil
  end
  if source.type == "furnace" or source.type == "assembling-machine"
    or source.type == "rocket-silo" then
    return source.get_inventory(defines.inventory.crafter_output)
  end
  return nil
end

function find_producer_with_item(surface, force, position, item_id)
  local nearest
  local nearest_distance
  for _, producer in pairs(surface.find_entities_filtered({
    type = {"furnace", "assembling-machine", "rocket-silo"},
    force = force,
    position = position,
    radius = LOGISTICS_SEARCH_RADIUS
  })) do
    local inventory = get_producer_output_inventory(producer)
    if inventory and inventory.get_item_count(item_id) > 0 then
      local distance = distance_squared(position, producer.position)
      if not nearest_distance or distance < nearest_distance then
        nearest = producer
        nearest_distance = distance
      end
    end
  end
  return nearest
end

function carrier_request_key(target, item)
  if not target or not target.valid or not item then
    return nil
  end
  return tostring(target.unit_number) .. ":" .. item.name .. ":" .. (item.quality or "normal")
end

function reserve_carrier_request(record, target, item, count)
  local key = carrier_request_key(target, item)
  if not key then
    return false
  end
  storage.not_alone_carrier_requests = storage.not_alone_carrier_requests or {}
  local existing = storage.not_alone_carrier_requests[key]
  if existing and existing.record ~= record and existing.count > 0 and game.tick - existing.tick < 300 then
    return false
  end
  storage.not_alone_carrier_requests[key] = {
    record = record,
    count = count,
    tick = game.tick
  }
  record.carrier_request_key = key
  return true
end

function clear_carrier_request(record)
  if not record or not record.carrier_request_key then
    return
  end
  storage.not_alone_carrier_requests = storage.not_alone_carrier_requests or {}
  local existing = storage.not_alone_carrier_requests[record.carrier_request_key]
  if existing and existing.record == record then
    storage.not_alone_carrier_requests[record.carrier_request_key] = nil
  end
  record.carrier_request_key = nil
end

function find_carrier_job(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_logistic_network_by_position(position, force)
  if not network then
    return nil, nil, nil, nil
  end

  for _, item in pairs(get_logistics_contents(network)) do
    local quality = item.quality or "normal"
    local item_id = {name = item.name, quality = quality}
    local consumer = find_nearest_requester_for_item(surface, force, position, item_id)
    if consumer then
      local consumer_inventory = consumer.get_inventory(defines.inventory.chest)
      local requester_point = consumer.get_requester_point()
      local requested = requester_point and get_requested_count(requester_point, item.name, quality)
      local missing = requested
        and math.max(requested - consumer_inventory.get_item_count(item_id), 0)
        or consumer_inventory.get_insertable_count(item_id)
      missing = math.min(missing, consumer_inventory.get_insertable_count(item_id))
      if missing > 0 then
        local pickup_point = network.select_pickup_point({
          name = item_id,
          position = position,
          include_buffers = true
        })
        local source = pickup_point and pickup_point.owner
        local source_inventory = get_logistics_source_inventory(source)
        local available = source_inventory and source_inventory.get_item_count(item_id) or 0
        if available > 0 then
          local claimed_count = math.min(missing, available)
          if reserve_carrier_request(record, consumer, item_id, claimed_count) then
            return source, consumer, item_id, claimed_count
          end
        end
      end
    end
  end

  -- Fulfil unmet requester demands from producer machine outputs; only items
  -- the chest actively requests are considered, so producers never become
  -- generic storage sources.
  local requesters = surface.find_entities_filtered({
    type = "logistic-container",
    force = force,
    position = position,
    radius = LOGISTICS_SEARCH_RADIUS
  })
  table.sort(requesters, function(left, right)
    return distance_squared(position, left.position) < distance_squared(position, right.position)
  end)
  for _, chest in ipairs(requesters) do
    if chest.valid and chest.prototype.logistic_mode == "requester" then
      local inventory = chest.get_inventory(defines.inventory.chest)
      local requester_point = chest.get_requester_point()
      if inventory and inventory.valid and requester_point then
        for _, filter in pairs(requester_point.filters or {}) do
          if filter.name then
            local item_id = {name = filter.name, quality = filter.quality or "normal"}
            local missing = math.max((filter.count or 0) - inventory.get_item_count(item_id), 0)
            missing = math.min(missing, inventory.get_insertable_count(item_id))
            if missing > 0 then
              local producer = find_producer_with_item(surface, force, position, item_id)
              local producer_inventory = get_producer_output_inventory(producer)
              if producer_inventory then
                local claimed_count = math.min(
                  missing,
                  producer_inventory.get_item_count(item_id),
                  CARRIER_CAPACITY
                )
                if claimed_count > 0
                  and reserve_carrier_request(record, chest, item_id, claimed_count) then
                  return producer, chest, item_id, claimed_count
                end
              end
            end
          end
        end
      end
    end
  end

  return nil, nil, nil, nil
end

function assign_carrier_job(record, surface, force, position)
  local source, target, item, needed = find_carrier_job(record, surface, force, position)
  if not source then
    return false
  end
  record.carrier_source = source
  record.carrier_target = target
  record.carrier_item = item
  record.carrier_needed_count = needed
  record.carrier_carried_count = 0
  record.carrier_state = "move-to-source"
  return true
end

function update_carrier(record)
  if record.carrier_state == "move-to-source" then
    local source = record.carrier_source
    local inventory = get_logistics_source_inventory(source)
      or get_producer_output_inventory(source)
    if not source or not source.valid or not inventory
      or inventory.get_item_count(record.carrier_item) == 0 then
      clear_carrier_request(record)
      record.carrier_state = nil
      record.carrier_source = nil
      record.carrier_target = nil
      record.carrier_item = nil
      record.carrier_needed_count = nil
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      local removed = inventory.remove({
        name = record.carrier_item.name,
        quality = record.carrier_item.quality,
        count = math.min(CARRIER_CAPACITY, record.carrier_needed_count or CARRIER_CAPACITY)
      })
      if removed > 0 then
        record.carrier_carried_count = removed
        record.carrier_state = "move-to-target"
      else
        clear_carrier_request(record)
        record.carrier_state = nil
        record.carrier_source = nil
        record.carrier_target = nil
        record.carrier_item = nil
        record.carrier_needed_count = nil
      end
    else
      move_team_mate(record, source.position, 2)
    end
    return true
  end

  if record.carrier_state == "move-to-target" then
    local target = record.carrier_target
    local target_inventory = target and target.valid
      and target.get_inventory(defines.inventory.chest)
    if not target_inventory
      or target_inventory.get_insertable_count(record.carrier_item) == 0 then
      -- No longer wanted: return it to network storage instead of stranding it.
      target = find_logistics_return_source(record, record.carrier_item)
      record.carrier_target = target
      target_inventory = target and get_logistics_source_inventory(target)
    end
    if not target then
      clear_carrier_request(record)
      record.carrier_state = nil
      record.carrier_source = nil
      record.carrier_item = nil
      record.carrier_carried_count = 0
      record.carrier_needed_count = nil
    elseif distance_squared(record.entity.position, target.position) <= 4 then
      local inserted = target_inventory.insert({
        name = record.carrier_item.name,
        quality = record.carrier_item.quality,
        count = record.carrier_carried_count
      })
      record.carrier_carried_count = record.carrier_carried_count - inserted
      stop_team_mate(record)
      if record.carrier_carried_count <= 0 then
        clear_carrier_request(record)
        record.carrier_state = nil
        record.carrier_source = nil
        record.carrier_target = nil
        record.carrier_item = nil
        record.carrier_needed_count = nil
      end
    else
      move_team_mate(record, target.position, 2)
    end
    return true
  end

  if game.tick >= (record.next_job_search_tick or 0) then
    if assign_carrier_job(record) then
      record.next_job_search_tick = nil
      record.idle_search_failures = nil
      return true
    end
    record.next_job_search_tick = game.tick + IDLE_JOB_SEARCH_INTERVAL
    record.idle_search_failures = (record.idle_search_failures or 0) + 1
  end
  if (record.idle_search_failures or 0) < IDLE_DOCK_AFTER_FAILURES then
    stop_team_mate(record)
    return true
  end
  return dock_at_habitat(record)
end

