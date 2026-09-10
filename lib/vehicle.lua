-- Functional area extracted from not-alone.lua.

function get_manual_destinations(record)
  record.manual_destinations = record.manual_destinations or {}
  return record.manual_destinations
end

-- Full ordered route as commanded; manual_destinations is the remaining queue.
function get_manual_route(record)
  -- Older saves stored the full route only for loops.
  record.manual_route = record.manual_route or record.manual_loop_destinations or {}
  record.manual_loop_destinations = nil
  return record.manual_route
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

function vehicle_profile_for_item(record, item_name)
  for _, profile in ipairs(VEHICLE_PROFILES) do
    if profile.item_name == item_name
      and (not profile.soldier_only or record.kind == "soldier") then
      return profile
    end
  end
  return nil
end

function vehicle_profile_for_entity(entity_name)
  for _, profile in ipairs(VEHICLE_PROFILES) do
    if profile.entity_name == entity_name then
      return profile
    end
  end
  return nil
end

-- Generic vehicle behaviour with per-type specialisations. Ground vehicles
-- (cars, tanks) steer via riding_state, need clear boarding space, and treat
-- collisions as routing failures. Spider vehicles walk over obstacles with
-- native autopilot and ignore ground collision entirely.
local GROUND_VEHICLE_BEHAVIOR = {
  ground_collision = true,
  needs_deployment_clearance = true,
  needs_path = true,
  stop = function(record, vehicle)
    vehicle.riding_state = {
      acceleration = defines.riding.acceleration.braking,
      direction = defines.riding.direction.straight
    }
  end,
  coast = function(record, vehicle)
    vehicle.riding_state = {
      acceleration = math.abs(vehicle.speed or 0) > PATROL_TRANSIT_MAX_SPEED
        and defines.riding.acceleration.braking
        or defines.riding.acceleration.nothing,
      direction = defines.riding.direction.straight
    }
  end,
  drive = function(record, vehicle, path)
    return steer_ground_vehicle(record, vehicle, path)
  end
}

local SPIDER_VEHICLE_BEHAVIOR = {
  ground_collision = false,
  needs_deployment_clearance = false,
  -- The engine pathfinder mostly returns useless one-node paths for the
  -- near-empty spider collision mask; native autopilot needs no path anyway.
  needs_path = false,
  stop = function(record, vehicle)
    vehicle.autopilot_destination = nil
  end,
  coast = function(record, vehicle)
    -- Spider legs stop instantly; nothing to damp while a path is pending.
  end,
  drive = function(record, vehicle, path)
    vehicle.autopilot_destination = record.vehicle_destination
    return true
  end
}

function get_vehicle_behavior(entity_name)
  local profile = vehicle_profile_for_entity(entity_name)
  if profile and profile.uses_ground_collision == false then
    return SPIDER_VEHICLE_BEHAVIOR
  end
  return GROUND_VEHICLE_BEHAVIOR
end

function get_vehicle_behavior_for_item(record)
  local item_name = record.vehicle_item_name or find_carried_vehicle_item(record)
  local profile = vehicle_profile_for_item(record, item_name)
  if profile and profile.uses_ground_collision == false then
    return SPIDER_VEHICLE_BEHAVIOR
  end
  return GROUND_VEHICLE_BEHAVIOR
end

function find_carried_vehicle_item(record)
  local inventory = get_vehicle_inventory(record)
  for _, profile in ipairs(VEHICLE_PROFILES) do
    if (not profile.soldier_only or record.kind == "soldier")
      and inventory.get_item_count(profile.item_name) > 0 then
      return profile.item_name
    end
  end
  return nil
end

function find_vehicle_pickup(record)
  for _, profile in ipairs(VEHICLE_PROFILES) do
    if not profile.soldier_only or record.kind == "soldier" then
      local source = find_logistics_item_source(record, profile.item_name)
      if source and reserve_vehicle_pickup(record, source, profile.item_name) then
        return profile.item_name, source
      end
    end
  end
  return nil, nil
end

function soldier_vehicle_available(record)
  if record.kind ~= "soldier" or find_carried_vehicle_item(record) then
    return false
  end
  for _, profile in ipairs(VEHICLE_PROFILES) do
    if profile.soldier_only
      and find_logistics_item_source(record, profile.item_name) then
      return true
    end
  end
  return false
end

function try_soldier_vehicle_pickup(record)
  if record.kind ~= "soldier" or find_carried_vehicle_item(record) then
    return false
  end
  local item_name, source = find_vehicle_pickup(record)
  if not item_name then
    return false
  end
  record.vehicle_item_name = item_name
  record.vehicle_pickup_source = source
  record.vehicle_state = "pickup-car"
  move_team_mate(record, source.position, 2)
  return true
end

-- Best network fuel the selected vehicle's burner accepts, judged by fuel value.
function find_vehicle_fuel_item(record, item_name)
  local profile = vehicle_profile_for_item(record, item_name)
  local burner = profile and prototypes.entity[profile.entity_name].burner_prototype
  if not burner or not burner.fuel_categories then
    return nil
  end
  for _, candidate in ipairs({"nuclear-fuel", "rocket-fuel", "solid-fuel", "coal", "wood"}) do
    local prototype = prototypes.item[candidate]
    if prototype and prototype.fuel_category
      and burner.fuel_categories[prototype.fuel_category]
      and find_logistics_item_source(record, candidate) then
      return candidate
    end
  end
  return nil
end

function vehicle_requires_fuel(record, item_name)
  local profile = vehicle_profile_for_item(record, item_name)
  local prototype = profile and prototypes.entity[profile.entity_name]
  return prototype and prototype.burner_prototype ~= nil
end

-- A multi-waypoint route drives waypoint to waypoint: corners need the tight
-- patrol radius and short-leg minimum, not the long-haul defaults.
function vehicle_on_route(record)
  return record ~= nil and record.kind == "soldier"
    and (record.manual_loop or #(record.manual_destinations or {}) > 1)
end

function vehicle_arrival_radius(record)
  if vehicle_on_route(record) then
    return PATROL_VEHICLE_ARRIVAL_RADIUS
  end
  return CAR_ARRIVAL_RADIUS
end

function vehicle_minimum_distance(record)
  if vehicle_on_route(record) then
    return PATROL_VEHICLE_MINIMUM_DISTANCE
  end
  local setting = settings.global["not-alone-car-minimum-distance"]
  -- Trips shorter than the arrival radius end the moment the car is boarded,
  -- looping team mates in and out of cars forever; enforce a real drive.
  return math.max(
    setting and setting.value or CAR_MINIMUM_DISTANCE,
    CAR_ARRIVAL_RADIUS + CAR_MINIMUM_TRIP_MARGIN
  )
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
  if not get_vehicle_behavior_for_item(record).needs_deployment_clearance then
    return true
  end
  for _, nearby in pairs(surface.find_entities_filtered({
    position = position,
    radius = CAR_DEPLOYMENT_CLEARANCE,
    type = {"car", "spider-vehicle"}
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
  local item_name = record.vehicle_item_name or vehicle.name
  if inventory.insert({name = item_name, count = 1}) ~= 1 then
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
  -- An abandoned trip must remember its destination through car recovery, or
  -- the same doomed trip redeploys the moment the car is picked back up.
  record.vehicle_failed_destination = record.vehicle_abandoned
    and record.vehicle_destination or nil
  record.vehicle_failed_destination_tick = record.vehicle_failed_destination
    and game.tick or nil
  record.vehicle_abandoned = nil
  record.vehicle_destination = nil
  record.vehicle_path_goal = nil
  record.vehicle_path_goal_is_segment = nil
  record.vehicle_path = nil
  record.vehicle_path_request_id = nil
  record.vehicle_deployment_position = nil
  record.vehicle_collision_count = nil
  record.vehicle_patrol_rolling = nil
  record.vehicle_item_name = nil
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
    record.vehicle_abandoned = true
    record.vehicle_state = "recovering-car"
    return finish_vehicle_travel(record)
  end
  restore_vehicle_team_mate(record)
  record.vehicle_state = nil
  record.vehicle_destination = nil
  record.vehicle_path_goal = nil
  record.vehicle_path_goal_is_segment = nil
  record.vehicle_path = nil
  record.vehicle_path_request_id = nil
  record.vehicle_collision_count = nil
  record.vehicle_patrol_rolling = nil
  record.vehicle_failed_destination = failed_destination
  record.vehicle_failed_destination_tick = failed_destination and game.tick or nil
  return false
end

function request_vehicle_path(record)
  local vehicle = record.vehicle_entity
  local destination = record.vehicle_destination
  if not vehicle or not vehicle.valid or not destination then
    return abandon_vehicle_travel(record)
  end
  if not get_vehicle_behavior(vehicle.name).needs_path then
    record.vehicle_path = {position_table(destination)}
    record.vehicle_path_index = 1
    record.vehicle_path_goal = nil
    record.vehicle_path_goal_is_segment = nil
    record.vehicle_patrol_rolling = nil
    record.vehicle_state = "driving-car"
    return true
  end
  local goal = position_table(destination)
  local delta_x = destination.x - vehicle.position.x
  local delta_y = destination.y - vehicle.position.y
  local distance = math.sqrt(delta_x * delta_x + delta_y * delta_y)
  record.vehicle_path_goal_is_segment = distance > VEHICLE_PATH_SEGMENT_DISTANCE
  if record.vehicle_path_goal_is_segment then
    local scale = VEHICLE_PATH_SEGMENT_DISTANCE / distance
    goal.x = vehicle.position.x + delta_x * scale
    goal.y = vehicle.position.y + delta_y * scale
  end
  record.vehicle_path_goal = goal
  local ok, request_id = pcall(function()
    local box = vehicle.prototype.collision_box
    local clearance = get_vehicle_behavior(vehicle.name).ground_collision
      and CAR_PATH_CLEARANCE or 0
    return vehicle.surface.request_path({
      -- Grown box keeps planned routes clear of buildings the car would
      -- clip while turning.
      bounding_box = {
        {box.left_top.x - clearance, box.left_top.y - clearance},
        {box.right_bottom.x + clearance, box.right_bottom.y + clearance}
      },
      collision_mask = vehicle.prototype.collision_mask,
      start = position_table(vehicle.position),
      goal = goal,
      force = vehicle.force,
      radius = vehicle_arrival_radius(record),
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
  local item_name = record.vehicle_item_name or find_carried_vehicle_item(record)
  local profile = vehicle_profile_for_item(record, item_name)
  if not position or not profile or inventory.get_item_count(item_name) < 1
    or (vehicle_requires_fuel(record, item_name)
      and get_vehicle_fuel_inventory(record).is_empty()) then
    return abandon_vehicle_travel(record)
  end
  -- Remove first and roll back if either entity creation or driver creation
  -- fails, so a deployed car and an inventory car cannot coexist.
  if inventory.remove({name = item_name, count = 1}) ~= 1 then
    return abandon_vehicle_travel(record)
  end
  record.vehicle_visible_name = record.entity.name
  if not replace_team_mate_entity(record, HIDDEN_TEAM_MATE_NAME) then
    inventory.insert({name = item_name, count = 1})
    record.vehicle_visible_name = nil
    return abandon_vehicle_travel(record)
  end
  if not surface.can_place_entity({
    name = profile.entity_name,
    position = position,
    force = record.entity.force
  }) or not deployment_position_is_clear(record, surface, position) then
    inventory.insert({name = item_name, count = 1})
    restore_vehicle_team_mate(record)
    return abandon_vehicle_travel(record)
  end
  local vehicle = surface.create_entity({
    name = profile.entity_name,
    position = position,
    force = record.entity.force,
    create_build_effect_smoke = false
  })
  if not vehicle then
    inventory.insert({name = item_name, count = 1})
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
    inventory.insert({name = item_name, count = 1})
    restore_vehicle_team_mate(record)
    return abandon_vehicle_travel(record)
  end
  driver.color = {r = 1, g = 1, b = 1, a = 0}
  vehicle.set_driver(driver)
  if vehicle.get_driver() ~= driver then
    driver.destroy()
    vehicle.destroy()
    inventory.insert({name = item_name, count = 1})
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
  if record.vehicle_failed_destination then
    -- Blocked routes get another chance later; the obstruction may be gone.
    if game.tick - (record.vehicle_failed_destination_tick or 0)
      > CAR_FAILED_DESTINATION_RETRY_TICKS then
      record.vehicle_failed_destination = nil
      record.vehicle_failed_destination_tick = nil
    elseif distance_squared(record.vehicle_failed_destination, destination) <= 4 then
      return false
    end
  end
  local inventory = get_vehicle_inventory(record)
  if distance_squared(record.entity.position, destination)
      < vehicle_minimum_distance(record) * vehicle_minimum_distance(record) then
    return false
  end
  local item_name = find_carried_vehicle_item(record)
  if not item_name then
    local source
    item_name, source = find_vehicle_pickup(record)
    if not item_name then
      return false
    end
    record.vehicle_item_name = item_name
    record.vehicle_pending_destination = position_table(destination)
    record.vehicle_pickup_source = source
    record.vehicle_state = "pickup-car"
    move_team_mate(record, source.position, 2)
    return true
  end
  local profile = vehicle_profile_for_item(record, item_name)
  if not profile then
    return false
  end
  if vehicle_requires_fuel(record, item_name)
    and get_vehicle_fuel_inventory(record).is_empty() then
    record.vehicle_item_name = item_name
    local fuel_name = find_vehicle_fuel_item(record, item_name)
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
  record.vehicle_item_name = item_name
  local position = record.entity.surface.find_non_colliding_position(
    profile.entity_name,
    record.entity.position,
    CAR_DEPLOYMENT_SEARCH_RADIUS,
    1
  )
  if not position
    or not deployment_position_is_clear(record, record.entity.surface, position) then
    return false
  end
  -- A boarding spot already inside the arrival radius makes the trip finish
  -- instantly; walking is the honest plan.
  if distance_squared(position, destination)
    <= vehicle_arrival_radius(record) * vehicle_arrival_radius(record) then
    return false
  end
  record.vehicle_destination = position_table(destination)
  record.vehicle_deployment_position = position_table(position)
  record.vehicle_state = "walking-to-car"
  move_team_mate(record, position, 1)
  return true
end

function continue_patrol_vehicle_travel(record)
  if not record.vehicle_destination then
    return false
  end
  local destinations = get_manual_destinations(record)
  if #destinations == 0 then
    return false
  end
  if distance_squared(record.vehicle_destination, destinations[1])
    > vehicle_arrival_radius(record) * vehicle_arrival_radius(record) then
    return false
  end
  -- The final waypoint of a one-way route is handled on foot so base joining
  -- and end-of-route behaviour stay in one place.
  if #destinations == 1 and not record.manual_loop then
    return false
  end
  table.remove(destinations, 1)
  if #destinations == 0 then
    for _, waypoint in ipairs(get_manual_route(record)) do
      destinations[#destinations + 1] = position_table(waypoint)
    end
  end
  if #destinations == 0 then
    return false
  end
  record.vehicle_destination = position_table(destinations[1])
  record.vehicle_path = nil
  record.vehicle_path_index = nil
  record.vehicle_stuck_ticks = 0
  record.vehicle_blocked_ticks = 0
  -- Keep rolling through the waypoint; the fresh path is joined at its
  -- nearest node, so leftover momentum cannot aim at nodes behind the car.
  record.vehicle_patrol_rolling = true
  return request_vehicle_path(record)
end

-- Joining a fresh path at its nearest node keeps a still-moving vehicle from
-- turning back toward nodes it already passed while the path was computed.
function nearest_vehicle_path_index(path, vehicle)
  if not vehicle or not vehicle.valid then
    return 1
  end
  local best_index = 1
  local best_distance
  for index, waypoint in ipairs(path) do
    local distance = distance_squared(vehicle.position, waypoint.position or waypoint)
    if not best_distance or distance < best_distance then
      best_distance = distance
      best_index = index
    end
  end
  return best_index
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
    type = {"car", "spider-vehicle", "unit"}
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
  local behavior = get_vehicle_behavior(vehicle.name)
  -- A segmented long route finished its current leg: plan the next one.
  if record.vehicle_path_goal_is_segment
    and record.vehicle_path_goal
    and distance_squared(vehicle.position, record.vehicle_path_goal)
      <= vehicle_arrival_radius(record) * vehicle_arrival_radius(record) then
    record.vehicle_path = nil
    record.vehicle_path_index = nil
    return request_vehicle_path(record)
  end
  if distance_squared(vehicle.position, record.vehicle_destination)
    <= vehicle_arrival_radius(record) * vehicle_arrival_radius(record) then
    if continue_patrol_vehicle_travel(record) then
      return true
    end
    record.vehicle_state = "stopping-car"
    behavior.stop(record, vehicle)
    return true
  end
  return behavior.drive(record, vehicle, path)
end

function steer_ground_vehicle(record, vehicle, path)
  record.vehicle_path_index = record.vehicle_path_index or 1
  -- Consume reached nodes, and also nearby nodes already behind the car in
  -- route progress: an overshoot during path computation otherwise leaves
  -- the car chasing start nodes behind it, looping back to reach them.
  local car_progress = distance_squared(vehicle.position, record.vehicle_destination)
  while record.vehicle_path_index < #path do
    local node = path[record.vehicle_path_index].position
      or path[record.vehicle_path_index]
    local node_distance = distance_squared(vehicle.position, node)
    if node_distance >= 9
      and not (node_distance < 256
        and distance_squared(node, record.vehicle_destination) > car_progress) then
      break
    end
    record.vehicle_path_index = record.vehicle_path_index + 1
  end
  local target_index = math.min(
    record.vehicle_path_index + CAR_PATH_LOOKAHEAD,
    #path
  )
  -- Aim past nearby nodes: chasing a close node behind or beside the car
  -- demands instant heading changes it can only satisfy by looping.
  while target_index < #path
    and distance_squared(
      vehicle.position,
      path[target_index].position or path[target_index]
    ) < CAR_STEER_TARGET_MIN_DISTANCE * CAR_STEER_TARGET_MIN_DISTANCE do
    target_index = target_index + 1
  end
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

  -- Orbit detection: accumulate rotation while the heading error stays
  -- sharp. A full turn without converging means the steering target sits
  -- inside this vehicle's turning circle; stop once and restart the arc
  -- from standstill, which has the minimum radius.
  do
    local last_orientation = record.vehicle_last_orientation
    local orientation = vehicle.orientation or 0
    if last_orientation and math.abs(difference) > 0.5 then
      local spin = orientation - last_orientation
      if spin > 0.5 then spin = spin - 1 elseif spin < -0.5 then spin = spin + 1 end
      record.vehicle_turn_accum = (record.vehicle_turn_accum or 0) + math.abs(spin)
    elseif math.abs(difference) < 0.3 then
      record.vehicle_turn_accum = 0
    end
    record.vehicle_last_orientation = orientation
    if record.vehicle_orbit_recover then
      if math.abs(vehicle.speed or 0) < 0.02 then
        record.vehicle_orbit_recover = nil
        record.vehicle_turn_accum = 0
      else
        vehicle.riding_state = {
          acceleration = defines.riding.acceleration.braking,
          direction = defines.riding.direction.straight
        }
        return true
      end
    elseif (record.vehicle_turn_accum or 0) >= CAR_ORBIT_LIMIT then
      record.vehicle_orbit_recover = true
      vehicle.riding_state = {
        acceleration = defines.riding.acceleration.braking,
        direction = defines.riding.direction.straight
      }
      return true
    end
  end

  -- Sharp turn: hold a low steady speed. Braking to a stop deadlocks (cars
  -- cannot rotate stationary) and brake/accelerate dithering crawls through
  -- a wide sloppy loop; a constant low speed gives the tightest arc.
  if math.abs(difference) > 0.8 then
    if math.abs(vehicle.speed or 0) > CAR_TURN_MAX_SPEED then
      acceleration = defines.riding.acceleration.braking
    end
  end
  -- Slow into route corners so the arrival overshoot stays inside the
  -- car's turning circle instead of forcing a loop to recover.
  if vehicle_on_route(record)
    and distance_squared(vehicle.position, record.vehicle_destination)
      <= PATROL_CORNER_APPROACH_DISTANCE * PATROL_CORNER_APPROACH_DISTANCE
    and math.abs(vehicle.speed or 0) > PATROL_TRANSIT_MAX_SPEED then
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
    -- Only real movement proves recovery; resetting on path acceptance let
    -- a stationary car alternate stuck/repath forever.
    record.vehicle_repath_attempts = 0
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
    local item_name = record.vehicle_item_name
    local source_inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not item_name or not source_inventory
      or source_inventory.get_item_count(item_name) < 1 then
      clear_vehicle_pickup(record)
      record.vehicle_pickup_source = nil
      record.vehicle_pending_destination = nil
      record.vehicle_state = nil
      return true
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      local removed = source_inventory.remove({name = item_name, count = 1})
      if removed == 1 then
        local inserted = get_vehicle_inventory(record).insert({
          name = item_name,
          count = 1
        })
        if inserted ~= 1 then
          source_inventory.insert({name = item_name, count = 1})
        end
      end
      local destination = record.vehicle_pending_destination
      clear_vehicle_pickup(record)
      record.vehicle_pickup_source = nil
      record.vehicle_pending_destination = nil
      record.vehicle_state = nil
      if removed == 1 and destination
        and get_vehicle_inventory(record).get_item_count(item_name) > 0 then
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
    -- Kill leftover momentum so a post-collision car stops ramming while the
    -- replacement route is computed. Patrol chaining instead coasts through
    -- the waypoint at a capped speed for a smooth transition.
    local vehicle = record.vehicle_entity
    if vehicle and vehicle.valid then
      local behavior = get_vehicle_behavior(vehicle.name)
      if record.vehicle_patrol_rolling then
        behavior.coast(record, vehicle)
      else
        behavior.stop(record, vehicle)
      end
    end
    -- A reload discards pending pathfinder callbacks; re-request instead of
    -- waiting forever on a request id that can no longer answer.
    record.vehicle_path_wait_ticks = (record.vehicle_path_wait_ticks or 0) + UPDATE_INTERVAL
    if record.vehicle_path_wait_ticks > VEHICLE_PATH_RETRY_TICKS then
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
    get_vehicle_behavior(vehicle.name).stop(record, vehicle)
    if math.abs(vehicle.speed or 0) < 0.05 then
      return finish_vehicle_travel(record)
    end
    return true
  elseif record.vehicle_state == "recovering-car" then
    return finish_vehicle_travel(record)
  end
  return false
end

