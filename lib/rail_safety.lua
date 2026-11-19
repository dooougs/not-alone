-- Rail safety: team mates are units and moving trains kill them, but the
-- engine pathfinder knows nothing about trains. Every update each moving train
-- near a team mate marks the rails it will cover within the lookahead, plus the
-- carriages it already spans, and team mates step off or hold clear of them.

-- Rebuilt from live trains at the start of every update, so it is never saved.
local rail_dangers = {}
-- Rail geometry along each automatic train's path, reused until the train
-- repaths instead of reading every rail's position and box each update. Pure
-- memo of live data, so a client joining with it empty gets the same dangers.
local path_cache = {}

local floor = math.floor

local function danger_chunk_key(chunk_x, chunk_y)
  return (chunk_x + 65536) * 131072 + chunk_y + 65536
end

local function position_chunk_key(x, y)
  return danger_chunk_key(floor(x / CHUNK_SIZE), floor(y / CHUNK_SIZE))
end

local function unit_vector(delta_x, delta_y)
  local length = math.sqrt(delta_x * delta_x + delta_y * delta_y)
  if length < 0.01 then
    return 0, 0, length
  end
  return delta_x / length, delta_y / length, length
end

-- Marks every chunk within reach of a position as one a query may read.
local function mark_chunks(watched, x, y, reach)
  for chunk_x = floor((x - reach) / CHUNK_SIZE), floor((x + reach) / CHUNK_SIZE) do
    for chunk_y = floor((y - reach) / CHUNK_SIZE), floor((y + reach) / CHUNK_SIZE) do
      watched[danger_chunk_key(chunk_x, chunk_y)] = true
    end
  end
end

-- Registered in every watched chunk the widest query could reach it from, so
-- a query only ever reads the chunk it stands in.
local function add_danger(surface_dangers, watched, x, y, radius, direction_x, direction_y, carriage)
  local reach = radius + RAIL_DANGER_TRACK_PADDING + RAIL_DANGER_APPROACH_DISTANCE
  local danger
  for chunk_x = floor((x - reach) / CHUNK_SIZE), floor((x + reach) / CHUNK_SIZE) do
    for chunk_y = floor((y - reach) / CHUNK_SIZE), floor((y + reach) / CHUNK_SIZE) do
      local key = danger_chunk_key(chunk_x, chunk_y)
      if watched[key] then
        danger = danger or {
          x = x,
          y = y,
          radius = radius,
          direction_x = direction_x,
          direction_y = direction_y,
          carriage = carriage
        }
        local list = surface_dangers[key]
        if list then
          list[#list + 1] = danger
        else
          surface_dangers[key] = {danger}
        end
      end
    end
  end
end

local function box_radius(box)
  local width = box.right_bottom.x - box.left_top.x
  local height = box.right_bottom.y - box.left_top.y
  return math.sqrt(width * width + height * height) / 2
end

local function train_lookahead(train)
  return math.min(
    math.max(math.abs(train.speed) * RAIL_DANGER_LOOKAHEAD_TICKS, RAIL_DANGER_MIN_DISTANCE),
    RAIL_DANGER_MAX_DISTANCE
  )
end

local function cached_path(train, path, next_cache)
  local key = path.size .. ":" .. path.total_distance
  local cached = path_cache[train.id]
  if not cached or cached.key ~= key or not cached.path.valid then
    cached = {key = key, path = path, source = path.rails, rails = {}}
  end
  next_cache[train.id] = cached
  return cached
end

-- Filled on first use: only the stretch just ahead of the train is ever read.
local function cached_path_rail(cached, index)
  local rail = cached.rails[index]
  if rail == nil then
    local entity = cached.source[index]
    if entity and entity.valid then
      local position = entity.position
      rail = {x = position.x, y = position.y, radius = box_radius(entity.bounding_box)}
    else
      rail = false
    end
    cached.rails[index] = rail
  end
  return rail
end

local function add_train_dangers(surface_dangers, watched, train, next_cache)
  local forward = train.speed > 0
  local lead = forward and train.front_stock or train.back_stock
  if not lead or not lead.valid then
    return
  end

  -- The body counts too: a team mate released once the front has passed must
  -- not walk into the wagons behind it.
  for _, carriage in pairs(train.carriages) do
    local angle = carriage.orientation * 2 * math.pi
    local position = carriage.position
    add_danger(
      surface_dangers, watched, position.x, position.y, box_radius(carriage.bounding_box),
      math.sin(angle), -math.cos(angle), true
    )
  end

  local lookahead = train_lookahead(train)
  local covered = 0
  local lead_position = lead.position
  local previous_x, previous_y = lead_position.x, lead_position.y

  -- Automatic trains follow their path through switches; manual ones go the
  -- natural way from the leading rail end.
  local path = train.path
  if not train.manual_mode and path and path.valid and path.is_front == forward then
    local cached = cached_path(train, path, next_cache)
    local last = math.min(path.size, path.current + RAIL_DANGER_MAX_RAILS)
    for index = path.current, last do
      local rail = cached_path_rail(cached, index)
      if rail then
        local direction_x, direction_y, length = unit_vector(
        rail.x - previous_x, rail.y - previous_y
      )
        add_danger(surface_dangers, watched, rail.x, rail.y, rail.radius, direction_x, direction_y)
        covered = covered + length
        previous_x, previous_y = rail.x, rail.y
        if covered >= lookahead then
          return
        end
      end
    end
    return
  end

  local rail_end = forward and train.front_end or train.back_end
  if not rail_end or not rail_end.valid then
    return
  end
  rail_end = rail_end.make_copy()
  for _ = 1, RAIL_DANGER_MAX_RAILS do
    local rail = rail_end.rail
    if not rail or not rail.valid then
      return
    end
    local position = rail.position
    local direction_x, direction_y, length = unit_vector(
      position.x - previous_x, position.y - previous_y
    )
    add_danger(
      surface_dangers, watched, position.x, position.y, box_radius(rail.bounding_box),
      direction_x, direction_y
    )
    covered = covered + length
    previous_x, previous_y = position.x, position.y
    if covered >= lookahead or not rail_end.move_natural() then
      return
    end
  end
end

-- The entity a train could hit: the car a team mate drives, or the team mate.
-- Hidden proxies (mining, riding) have no collision and are skipped.
local function rail_safety_entity(record)
  local vehicle = record.vehicle_entity
  if record.vehicle_state and vehicle and vehicle.valid
    and record.vehicle_driver and record.vehicle_driver.valid then
    return vehicle
  end
  local entity = record.entity
  if entity and entity.valid and entity.type == "unit"
    and entity.name ~= HIDDEN_TEAM_MATE_NAME then
    return entity
  end
  return nil
end

-- How far a ground vehicle travels before it can stop: one update of reaction
-- plus braking, which grows with the cube of speed (measured in 2.1: a car
-- needs 16 tiles from 0.45 tiles/tick, a tank 26 from 0.3).
local function vehicle_stopping_distance(vehicle)
  local speed = math.abs(vehicle.speed or 0)
  local prototype = vehicle.prototype
  local braking = prototype.braking_force
  local weight = prototype.weight
  local braking_distance = 0
  if braking and braking > 0 and weight then
    braking_distance = RAIL_DANGER_BRAKING_FACTOR * weight / braking * speed * speed * speed
  end
  return math.min(
    speed * UPDATE_INTERVAL + braking_distance,
    RAIL_DANGER_MAX_VEHICLE_STOPPING_DISTANCE
  )
end

-- How far from a team mate a danger can matter: escape spots for walkers, the
-- braking run ahead of a vehicle.
local function rail_safety_reach(record, entity)
  if entity == record.entity then
    return RAIL_DANGER_WALKER_REACH
  end
  if not get_vehicle_behavior(entity.name).ground_collision then
    return nil
  end
  return RAIL_DANGER_VEHICLE_APPROACH_DISTANCE + vehicle_stopping_distance(entity)
    + RAIL_DANGER_VEHICLE_PROBE_STEP
end

local function any_watcher_within(watchers, center, distance)
  for _, watcher in pairs(watchers) do
    local limit = distance + watcher.reach
    if distance_squared(watcher.position, center) <= limit * limit then
      return true
    end
  end
  return false
end

function update_rail_dangers()
  rail_dangers = {}
  local next_cache = {}

  -- Only trains near team mates matter, and only chunks a team mate can query
  -- get dangers, so a big rail network costs little while crew are away.
  local watchers_by_surface = {}
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      local entity = rail_safety_entity(record)
      local reach = entity and rail_safety_reach(record, entity)
      if reach then
        local surface_index = entity.surface_index
        local watchers = watchers_by_surface[surface_index]
        if not watchers then
          watchers = {chunks = {}, list = {}}
          watchers_by_surface[surface_index] = watchers
        end
        local position = entity.position
        watchers.list[#watchers.list + 1] = {position = position, reach = reach}
        mark_chunks(watchers.chunks, position.x, position.y, reach)
      end
    end
  end

  for surface_index, watchers in pairs(watchers_by_surface) do
    local trains = game.train_manager.get_trains({surface = surface_index, is_moving = true})
    for _, train in pairs(trains) do
      local lead = train.speed > 0 and train.front_stock or train.back_stock
      local reach = train_lookahead(train) + #train.carriages * 8
        + RAIL_DANGER_TRACK_PADDING + RAIL_DANGER_APPROACH_DISTANCE + 8
      if lead and lead.valid and any_watcher_within(watchers.list, lead.position, reach) then
        local surface_dangers = rail_dangers[surface_index] or {}
        rail_dangers[surface_index] = surface_dangers
        add_train_dangers(surface_dangers, watchers.chunks, train, next_cache)
      end
    end
  end
  path_cache = next_cache
end

-- Nearest danger within margin of its footprint, and the gap to that footprint.
local function find_rail_danger(surface_index, position, margin)
  local surface_dangers = rail_dangers[surface_index]
  local list = surface_dangers and surface_dangers[position_chunk_key(position.x, position.y)]
  if not list then
    return nil
  end
  local nearest, nearest_gap
  for _, danger in pairs(list) do
    local gap = math.sqrt(distance_squared(position, danger)) - danger.radius
    if gap <= margin and (not nearest or gap < nearest_gap) then
      nearest = danger
      nearest_gap = gap
    end
  end
  return nearest, nearest_gap
end

local function vehicle_heading(vehicle)
  local angle = vehicle.orientation * 2 * math.pi
  local sign = (vehicle.speed or 0) < 0 and -1 or 1
  return math.sin(angle) * sign, -math.cos(angle) * sign
end

-- First danger along the vehicle's heading within its braking run plus the
-- approach margin, and the distance to it. Probes are closer together than a
-- track strip is wide.
local function vehicle_danger_distance(vehicle)
  local position = vehicle.position
  local heading_x, heading_y = vehicle_heading(vehicle)
  local reach = RAIL_DANGER_VEHICLE_APPROACH_DISTANCE + vehicle_stopping_distance(vehicle)
  local margin = RAIL_DANGER_TRACK_PADDING + RAIL_DANGER_VEHICLE_CLEARANCE
  local step = RAIL_DANGER_VEHICLE_PROBE_STEP
  for distance = step, reach + step, step do
    local danger = find_rail_danger(vehicle.surface_index, {
      x = position.x + heading_x * distance,
      y = position.y + heading_y * distance
    }, margin)
    if danger then
      return danger, distance
    end
  end
  return nil
end

-- Drives straight on across the track it stands on. Running along the rails
-- straight would stay on them, so the route steers there instead.
local function drive_off_track(vehicle, danger)
  local heading_x, heading_y = vehicle_heading(vehicle)
  local across = math.abs(heading_x * danger.direction_y - heading_y * danger.direction_x)
  if across < RAIL_DANGER_VEHICLE_MIN_CROSSING then
    return false
  end
  vehicle.riding_state = {
    acceleration = (vehicle.speed or 0) < 0 and defines.riding.acceleration.reversing
      or defines.riding.acceleration.accelerating,
    direction = defines.riding.direction.straight
  }
  return true
end

-- Step sideways off the track, to the side the team mate already stands on,
-- else the other side, else further out.
local function rail_escape_position(entity, danger)
  local position = entity.position
  local side_x, side_y = -danger.direction_y, danger.direction_x
  if side_x == 0 and side_y == 0 then
    side_x, side_y = unit_vector(position.x - danger.x, position.y - danger.y)
    if side_x == 0 and side_y == 0 then
      side_x = 1
    end
  end
  local offset = (position.x - danger.x) * side_x + (position.y - danger.y) * side_y
  local sign = offset < 0 and -1 or 1
  offset = math.abs(offset)
  local clear = danger.radius + RAIL_DANGER_TRACK_PADDING + RAIL_ESCAPE_CLEARANCE
  local attempts = {
    {sign, clear - offset},
    {-sign, clear + offset},
    {sign, clear - offset + 6}
  }
  for _, attempt in ipairs(attempts) do
    local step = math.max(attempt[2], 0.5) * attempt[1]
    local candidate = {x = position.x + side_x * step, y = position.y + side_y * step}
    if not find_rail_danger(entity.surface_index, candidate, RAIL_DANGER_TRACK_PADDING) then
      return candidate
    end
  end
  return nil
end

local function release_rail_hold(record)
  if record.rail_hold then
    record.rail_hold = nil
    -- The interrupted job or route issues a fresh command next.
    record.command_kind = nil
    record.command_destination = nil
    record.command_target = nil
  end
end

-- Returns true while a train has taken control of this team mate this update.
function update_rail_safety(record)
  local entity = rail_safety_entity(record)
  if not entity then
    return false
  end

  if entity ~= record.entity then
    local behavior = get_vehicle_behavior(entity.name)
    if not behavior.ground_collision then
      return false
    end
    -- Braking on the track is what gets a car hit: clear it instead.
    local on_track = find_rail_danger(
      entity.surface_index, entity.position,
      RAIL_DANGER_TRACK_PADDING + RAIL_DANGER_VEHICLE_CLEARANCE
    )
    if on_track then
      record.rail_hold = drive_off_track(entity, on_track) or nil
      if record.rail_hold then
        sync_team_mate_with_vehicle(record)
      end
      return record.rail_hold == true
    end
    -- Brake while it can still stop short of the track. Once it cannot, carry
    -- on across: rails are marked a whole lookahead before the train arrives.
    -- A passing wagon is never driven at.
    local danger, distance = vehicle_danger_distance(entity)
    if danger and (danger.carriage or distance > vehicle_stopping_distance(entity)) then
      behavior.stop(record, entity)
      -- Travel is skipped while held; keep the hidden rider with the car.
      sync_team_mate_with_vehicle(record)
      record.rail_hold = true
      return true
    end
    record.rail_hold = nil
    return false
  end

  local danger, gap = find_rail_danger(
    entity.surface_index, entity.position,
    RAIL_DANGER_TRACK_PADDING + RAIL_DANGER_APPROACH_DISTANCE
  )
  if not danger then
    release_rail_hold(record)
    return false
  end

  record.rail_hold = true
  local escape = gap <= RAIL_DANGER_TRACK_PADDING and rail_escape_position(entity, danger)
  if not escape then
    stop_team_mate(record)
    return true
  end
  if record.command_kind ~= "rail-escape"
    or not entity.commandable.has_command
    or not record.command_destination
    or distance_squared(record.command_destination, escape) > 1 then
    entity.commandable.set_command({
      type = defines.command.go_to_location,
      destination = escape,
      radius = 0.5,
      distraction = defines.distraction.none,
      pathfind_flags = {cache = false, allow_paths_through_own_entities = true}
    })
    record.command_kind = "rail-escape"
    record.command_destination = escape
    record.command_target = nil
  end
  return true
end
