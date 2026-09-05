-- Functional area extracted from not-alone.lua.

function get_manual_destinations(record)
  record.manual_destinations = record.manual_destinations or {}
  return record.manual_destinations
end

function get_vehicle_inventory(record)
  if not record.vehicle_inventory or not record.vehicle_inventory.valid then
    record.vehicle_inventory = game.create_inventory(1)
  end
  return record.vehicle_inventory
end

function get_vehicle_fuel_inventory(record)
  if not record.vehicle_fuel_inventory or not record.vehicle_fuel_inventory.valid then
    record.vehicle_fuel_inventory = game.create_inventory(1)
  end
  return record.vehicle_fuel_inventory
end

-- Best network fuel the car's burner accepts, judged by fuel value.
function find_car_fuel_item(record)
  local burner = prototypes.entity[CAR_ENTITY_NAME].burner_prototype
  if not burner then
    return nil
  end
  local network = record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  if not network then
    return nil
  end
  local best_name
  local best_priority
  for _, item_name in ipairs(get_network_fuel_candidates(network, record.entity.force)) do
    local prototype = prototypes.item[item_name]
    if prototype and prototype.fuel_category
      and burner.fuel_categories[prototype.fuel_category] then
      local priority = fuel_priority(item_name)
      if not best_priority or priority > best_priority then
        best_name = item_name
        best_priority = priority
      end
    end
  end
  return best_name
end

function vehicle_minimum_distance()
  local setting = settings.global["not-alone-car-minimum-distance"]
  return setting and setting.value or CAR_MINIMUM_DISTANCE
end

function find_vehicle_record(unit_number)
  if not unit_number then
    return nil
  end
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.vehicle_entity_unit_number == unit_number
        or record.vehicle_driver_unit_number == unit_number then
        return record
      end
    end
  end
  return nil
end

-- The car footprint alone is not enough clearance: boarding beside other
-- cars or team mates causes instant collisions on departure.
function deployment_position_is_clear(record, surface, position)
  for _, nearby in pairs(surface.find_entities_filtered({
    position = position,
    radius = CAR_DEPLOYMENT_CLEARANCE,
    type = "car"
  })) do
    if nearby ~= record.vehicle_entity then
      return false
    end
  end
  for _, nearby in pairs(surface.find_entities_filtered({
    position = position,
    radius = CAR_DEPLOYMENT_CLEARANCE * 0.5,
    type = "unit"
  })) do
    if nearby ~= record.entity and nearby.force == record.entity.force then
      return false
    end
  end
  return true
end

function reserve_vehicle_pickup(record, source, item_name)
  if not source or not source.valid or not source.unit_number then
    return false
  end
  local key = tostring(source.unit_number) .. ":" .. (item_name or CAR_ITEM_NAME)
  storage.not_alone_vehicle_pickups = storage.not_alone_vehicle_pickups or {}
  local existing = storage.not_alone_vehicle_pickups[key]
  if existing and existing.record ~= record and game.tick - existing.tick < 300 then
    return false
  end
  storage.not_alone_vehicle_pickups[key] = {record = record, tick = game.tick}
  record.vehicle_pickup_reservation_key = key
  return true
end

function clear_vehicle_pickup(record)
  local key = record and record.vehicle_pickup_reservation_key
  if not key then
    return
  end
  local reservations = storage.not_alone_vehicle_pickups or {}
  local existing = reservations[key]
  if existing and existing.record == record then
    reservations[key] = nil
  end
  record.vehicle_pickup_reservation_key = nil
end

function restore_vehicle_team_mate(record)
  local driver = record.vehicle_driver
  if driver and driver.valid then
    driver.destroy()
  end
  record.vehicle_driver = nil
  record.vehicle_driver_unit_number = nil
  if record.entity and record.entity.valid then
    if record.entity.name == HIDDEN_TEAM_MATE_NAME then
      replace_team_mate_entity(
        record,
        record.vehicle_visible_name or TEAM_MATE_ENTITY_BY_KIND[record.kind] or TEAM_MATE_NAME
      )
    end
  end
  record.vehicle_visible_name = nil
end

function recover_vehicle(record)
  local vehicle = record.vehicle_entity
  if not vehicle or not vehicle.valid then
    record.vehicle_entity = nil
    record.vehicle_entity_unit_number = nil
    return true
  end
  if vehicle.get_driver() then
    vehicle.set_driver(nil)
    return false
  end
  local inventory = get_vehicle_inventory(record)
  if inventory.insert({name = CAR_ITEM_NAME, count = 1}) ~= 1 then
    return false
  end
  -- Reclaim unburned fuel (including player-added fuel) before the car is
  -- destroyed, so it survives recovery and the next deployment.
  local car_fuel = vehicle.get_fuel_inventory()
  if car_fuel then
    local fuel_store = get_vehicle_fuel_inventory(record)
    for slot = 1, #car_fuel do
      local stack = car_fuel[slot]
      if stack.valid_for_read then
        local moved = fuel_store.insert({name = stack.name, count = stack.count})
        stack.count = stack.count - moved
      end
    end
  end
  vehicle.destroy()
  record.vehicle_entity = nil
  record.vehicle_entity_unit_number = nil
  return true
end

function sync_team_mate_with_vehicle(record)
  local vehicle = record.vehicle_entity
  if vehicle and vehicle.valid and record.entity and record.entity.valid then
    record.entity.teleport(vehicle.position)
  end
end

function finish_vehicle_travel(record)
  sync_team_mate_with_vehicle(record)
  recover_vehicle(record)
  if record.vehicle_entity then
    record.vehicle_state = "recovering-car"
    return true
  end
  restore_vehicle_team_mate(record)
  record.vehicle_state = nil
  record.vehicle_destination = nil
  record.vehicle_path = nil
  record.vehicle_path_request_id = nil
  record.vehicle_deployment_position = nil
  record.vehicle_failed_destination = nil
  return false
end

function abandon_vehicle_travel(record)
  local failed_destination = record.vehicle_destination
  local vehicle = record.vehicle_entity
  if vehicle and vehicle.valid then
    if vehicle.get_driver() then
      vehicle.set_driver(nil)
    end
    -- The car remains in the world if it cannot be recovered; no new item is
    -- created, preserving the ownership invariant without deleting equipment.
    record.vehicle_state = "recovering-car"
    return finish_vehicle_travel(record)
  end
  restore_vehicle_team_mate(record)
  record.vehicle_state = nil
  record.vehicle_destination = nil
  record.vehicle_path = nil
  record.vehicle_path_request_id = nil
  record.vehicle_failed_destination = failed_destination
  return false
end

function request_vehicle_path(record)
  local vehicle = record.vehicle_entity
  local destination = record.vehicle_destination
  if not vehicle or not vehicle.valid or not destination then
    return abandon_vehicle_travel(record)
  end
  local ok, request_id = pcall(function()
    return vehicle.surface.request_path({
      bounding_box = vehicle.prototype.collision_box,
      collision_mask = vehicle.prototype.collision_mask,
      start = position_table(vehicle.position),
      goal = destination,
      force = vehicle.force,
      radius = CAR_ARRIVAL_RADIUS,
      can_open_gates = false,
      pathfind_flags = {cache = false},
      entity_to_ignore = vehicle
    })
  end)
  if not ok or not request_id then
    return abandon_vehicle_travel(record)
  end
  record.vehicle_path_request_id = request_id
  record.vehicle_path_wait_ticks = 0
  record.vehicle_state = "waiting-for-car-path"
  return true
end

function deploy_vehicle(record)
  local position = record.vehicle_deployment_position
  local surface = record.entity.surface
  local inventory = get_vehicle_inventory(record)
  if not position or inventory.get_item_count(CAR_ITEM_NAME) < 1
    or get_vehicle_fuel_inventory(record).is_empty() then
    return abandon_vehicle_travel(record)
  end
  -- Remove first and roll back if either entity creation or driver creation
  -- fails, so a deployed car and an inventory car cannot coexist.
  if inventory.remove({name = CAR_ITEM_NAME, count = 1}) ~= 1 then
    return abandon_vehicle_travel(record)
  end
  record.vehicle_visible_name = record.entity.name
  if not replace_team_mate_entity(record, HIDDEN_TEAM_MATE_NAME) then
    inventory.insert({name = CAR_ITEM_NAME, count = 1})
    record.vehicle_visible_name = nil
    return abandon_vehicle_travel(record)
  end
  if not surface.can_place_entity({
    name = CAR_ENTITY_NAME,
    position = position,
    force = record.entity.force
  }) or not deployment_position_is_clear(record, surface, position) then
    inventory.insert({name = CAR_ITEM_NAME, count = 1})
    restore_vehicle_team_mate(record)
    return abandon_vehicle_travel(record)
  end
  local vehicle = surface.create_entity({
    name = CAR_ENTITY_NAME,
    position = position,
    force = record.entity.force,
    create_build_effect_smoke = false
  })
  if not vehicle then
    inventory.insert({name = CAR_ITEM_NAME, count = 1})
    restore_vehicle_team_mate(record)
    return abandon_vehicle_travel(record)
  end
  local driver = surface.create_entity({
    name = CAR_DRIVER_NAME,
    position = position,
    force = record.entity.force,
    create_build_effect_smoke = false
  })
  if not driver then
    vehicle.destroy()
    inventory.insert({name = CAR_ITEM_NAME, count = 1})
    restore_vehicle_team_mate(record)
    return abandon_vehicle_travel(record)
  end
  driver.color = {r = 1, g = 1, b = 1, a = 0}
  vehicle.set_driver(driver)
  if vehicle.get_driver() ~= driver then
    driver.destroy()
    vehicle.destroy()
    inventory.insert({name = CAR_ITEM_NAME, count = 1})
    restore_vehicle_team_mate(record)
    return abandon_vehicle_travel(record)
  end
  local car_fuel = vehicle.get_fuel_inventory()
  if car_fuel then
    local fuel_store = get_vehicle_fuel_inventory(record)
    for slot = 1, #fuel_store do
      local stack = fuel_store[slot]
      if stack.valid_for_read then
        local moved = car_fuel.insert({name = stack.name, count = stack.count})
        stack.count = stack.count - moved
      end
    end
  end
  record.vehicle_entity = vehicle
  record.vehicle_entity_unit_number = vehicle.unit_number
  record.vehicle_driver = driver
  record.vehicle_driver_unit_number = driver.unit_number
  record.vehicle_state = "requesting-car-path"
  return request_vehicle_path(record)
end

function begin_vehicle_travel(record, destination)
  if record.vehicle_state then
    return false
  end
  if record.vehicle_failed_destination
    and distance_squared(record.vehicle_failed_destination, destination) <= 4 then
    return false
  end
  local inventory = get_vehicle_inventory(record)
  if distance_squared(record.entity.position, destination)
      < vehicle_minimum_distance() * vehicle_minimum_distance() then
    return false
  end
  if inventory.get_item_count(CAR_ITEM_NAME) < 1 then
    local source = find_logistics_item_source(record, CAR_ITEM_NAME)
    if not source or not reserve_vehicle_pickup(record, source, CAR_ITEM_NAME) then
      return false
    end
    record.vehicle_pending_destination = position_table(destination)
    record.vehicle_pickup_source = source
    record.vehicle_state = "pickup-car"
    move_team_mate(record, source.position, 2)
    return true
  end
  if get_vehicle_fuel_inventory(record).is_empty() then
    local fuel_name = find_car_fuel_item(record)
    local source = fuel_name and find_logistics_item_source(record, fuel_name)
    if not source or not reserve_vehicle_pickup(record, source, fuel_name) then
      return false
    end
    record.vehicle_pending_destination = position_table(destination)
    record.vehicle_pickup_source = source
    record.vehicle_fuel_item = fuel_name
    record.vehicle_state = "pickup-car-fuel"
    move_team_mate(record, source.position, 2)
    return true
  end
  local position = record.entity.surface.find_non_colliding_position(
    CAR_ENTITY_NAME,
    record.entity.position,
    CAR_DEPLOYMENT_SEARCH_RADIUS,
    1
  )
  if not position
    or not deployment_position_is_clear(record, record.entity.surface, position) then
    return false
  end
  record.vehicle_destination = position_table(destination)
  record.vehicle_deployment_position = position_table(position)
  record.vehicle_state = "walking-to-car"
  move_team_mate(record, position, 1)
  return true
end

-- Path plans only avoid static obstacles; moving cars and team mates need a
-- steering-level dodge.
function vehicle_probe_is_clear(record, vehicle, heading, angle_offset)
  local angle = heading + angle_offset
  local probe = {
    x = vehicle.position.x + math.sin(angle) * CAR_AVOIDANCE_DISTANCE * 0.5,
    y = vehicle.position.y - math.cos(angle) * CAR_AVOIDANCE_DISTANCE * 0.5
  }
  for _, obstacle in pairs(vehicle.surface.find_entities_filtered({
    position = probe,
    radius = CAR_AVOIDANCE_DISTANCE * 0.35,
    type = {"car", "unit"}
  })) do
    if obstacle ~= vehicle and obstacle ~= record.entity then
      return false
    end
  end
  return true
end

function steer_vehicle(record)
  local vehicle = record.vehicle_entity
  local path = record.vehicle_path
  if not vehicle or not vehicle.valid or not path or #path == 0 then
    return abandon_vehicle_travel(record)
  end
  sync_team_mate_with_vehicle(record)
  if distance_squared(vehicle.position, record.vehicle_destination)
    <= CAR_ARRIVAL_RADIUS * CAR_ARRIVAL_RADIUS then
    record.vehicle_state = "stopping-car"
    vehicle.riding_state = {
      acceleration = defines.riding.acceleration.braking,
      direction = defines.riding.direction.straight
    }
    return true
  end

  record.vehicle_path_index = record.vehicle_path_index or 1
  while record.vehicle_path_index < #path
    and distance_squared(
      vehicle.position,
      path[record.vehicle_path_index].position or path[record.vehicle_path_index]
    ) < 9 do
    record.vehicle_path_index = record.vehicle_path_index + 1
  end
  local target_index = math.min(
    record.vehicle_path_index + CAR_PATH_LOOKAHEAD,
    #path
  )
  local waypoint = path[target_index]
  local target = waypoint.position or waypoint
  local delta_x = target.x - vehicle.position.x
  local delta_y = target.y - vehicle.position.y
  local desired = math.atan2(delta_x, -delta_y)
  local current = (vehicle.orientation or 0) * math.pi * 2
  local difference = (desired - current + math.pi) % (math.pi * 2) - math.pi
  local direction = defines.riding.direction.straight
  if difference > 0.12 then
    direction = defines.riding.direction.right
  elseif difference < -0.12 then
    direction = defines.riding.direction.left
  end
  local acceleration = defines.riding.acceleration.accelerating
  if math.abs(difference) > 0.8 then
    acceleration = defines.riding.acceleration.braking
  end
  if vehicle_probe_is_clear(record, vehicle, current, 0) then
    record.vehicle_blocked_ticks = 0
  else
    local left_clear = vehicle_probe_is_clear(record, vehicle, current, -CAR_AVOIDANCE_PROBE_ANGLE)
    local right_clear = vehicle_probe_is_clear(record, vehicle, current, CAR_AVOIDANCE_PROBE_ANGLE)
    if left_clear or right_clear then
      if left_clear and right_clear then
        direction = difference < 0 and defines.riding.direction.left
          or defines.riding.direction.right
      elseif left_clear then
        direction = defines.riding.direction.left
      else
        direction = defines.riding.direction.right
      end
      -- Dodge at low speed so the turn happens before reaching the obstacle.
      acceleration = math.abs(vehicle.speed or 0) > CAR_AVOIDANCE_MAX_SPEED
        and defines.riding.acceleration.braking
        or defines.riding.acceleration.accelerating
      record.vehicle_blocked_ticks = 0
    else
      acceleration = defines.riding.acceleration.braking
      record.vehicle_blocked_ticks = (record.vehicle_blocked_ticks or 0) + UPDATE_INTERVAL
      if record.vehicle_blocked_ticks >= CAR_BLOCKED_TICKS then
        -- Avoidance impossible: give up the car and finish the trip on foot.
        return abandon_vehicle_travel(record)
      end
    end
  end
  vehicle.riding_state = {acceleration = acceleration, direction = direction}

  local previous = record.vehicle_last_position
  if previous and distance_squared(previous, vehicle.position) < 0.01 then
    record.vehicle_stuck_ticks = (record.vehicle_stuck_ticks or 0) + UPDATE_INTERVAL
  else
    record.vehicle_stuck_ticks = 0
  end
  record.vehicle_last_position = position_table(vehicle.position)
  if (record.vehicle_stuck_ticks or 0) >= CAR_STUCK_TICKS then
    if (record.vehicle_repath_attempts or 0) < 2 then
      record.vehicle_repath_attempts = (record.vehicle_repath_attempts or 0) + 1
      record.vehicle_stuck_ticks = 0
      record.vehicle_path = nil
      record.vehicle_state = "requesting-car-path"
      return request_vehicle_path(record)
    end
    return abandon_vehicle_travel(record)
  end
  return true
end

update_vehicle_travel = function(record)
  if record.vehicle_state == "pickup-car" then
    local source = record.vehicle_pickup_source
    local source_inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not source_inventory
      or source_inventory.get_item_count(CAR_ITEM_NAME) < 1 then
      clear_vehicle_pickup(record)
      record.vehicle_pickup_source = nil
      record.vehicle_pending_destination = nil
      record.vehicle_state = nil
      return true
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      local removed = source_inventory.remove({name = CAR_ITEM_NAME, count = 1})
      if removed == 1 then
        local inserted = get_vehicle_inventory(record).insert({
          name = CAR_ITEM_NAME,
          count = 1
        })
        if inserted ~= 1 then
          source_inventory.insert({name = CAR_ITEM_NAME, count = 1})
        end
      end
      local destination = record.vehicle_pending_destination
      clear_vehicle_pickup(record)
      record.vehicle_pickup_source = nil
      record.vehicle_pending_destination = nil
      record.vehicle_state = nil
      if removed == 1 and get_vehicle_inventory(record).get_item_count(CAR_ITEM_NAME) > 0 then
        begin_vehicle_travel(record, destination)
      end
      return true
    end
    move_team_mate(record, source.position, 2)
    return true
  elseif record.vehicle_state == "pickup-car-fuel" then
    local source = record.vehicle_pickup_source
    local fuel_name = record.vehicle_fuel_item
    local source_inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not fuel_name or not source_inventory
      or source_inventory.get_item_count(fuel_name) < 1 then
      clear_vehicle_pickup(record)
      record.vehicle_pickup_source = nil
      record.vehicle_pending_destination = nil
      record.vehicle_fuel_item = nil
      record.vehicle_state = nil
      return true
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      local removed = source_inventory.remove({name = fuel_name, count = FUEL_REQUEST_COUNT})
      if removed > 0 then
        local inserted = get_vehicle_fuel_inventory(record).insert({
          name = fuel_name,
          count = removed
        })
        if inserted < removed then
          source_inventory.insert({name = fuel_name, count = removed - inserted})
        end
      end
      local destination = record.vehicle_pending_destination
      clear_vehicle_pickup(record)
      record.vehicle_pickup_source = nil
      record.vehicle_pending_destination = nil
      record.vehicle_fuel_item = nil
      record.vehicle_state = nil
      if removed > 0 and destination then
        begin_vehicle_travel(record, destination)
      end
      return true
    end
    move_team_mate(record, source.position, 2)
    return true
  elseif record.vehicle_state == "walking-to-car" then
    if distance_squared(record.entity.position, record.vehicle_deployment_position) <= 4 then
      return deploy_vehicle(record)
    end
    move_team_mate(record, record.vehicle_deployment_position, 1)
    return true
  elseif record.vehicle_state == "requesting-car-path" then
    return request_vehicle_path(record)
  elseif record.vehicle_state == "waiting-for-car-path" then
    -- A reload discards pending pathfinder callbacks; re-request instead of
    -- waiting forever on a request id that can no longer answer.
    record.vehicle_path_wait_ticks = (record.vehicle_path_wait_ticks or 0) + UPDATE_INTERVAL
    if record.vehicle_path_wait_ticks > 600 then
      record.vehicle_path_wait_ticks = 0
      record.vehicle_state = "requesting-car-path"
      return request_vehicle_path(record)
    end
    return true
  elseif record.vehicle_state == "driving-car" then
    return steer_vehicle(record)
  elseif record.vehicle_state == "stopping-car" then
    local vehicle = record.vehicle_entity
    if not vehicle or not vehicle.valid then
      return abandon_vehicle_travel(record)
    end
    vehicle.riding_state = {
      acceleration = defines.riding.acceleration.braking,
      direction = defines.riding.direction.straight
    }
    if math.abs(vehicle.speed or 0) < 0.05 then
      return finish_vehicle_travel(record)
    end
    return true
  elseif record.vehicle_state == "recovering-car" then
    return finish_vehicle_travel(record)
  end
  return false
end

