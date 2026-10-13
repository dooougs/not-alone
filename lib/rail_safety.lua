-- Rail safety: team mates are units and moving trains kill them, but the
-- engine pathfinder knows nothing about trains. Every update each moving train
-- near a team mate marks the rails it will cover within the lookahead, plus the
-- carriages it already spans, and team mates step off or hold clear of them.

-- Rebuilt from live trains at the start of every update, so it is never saved.
local rail_dangers = {}

local function danger_chunk_key(chunk_x, chunk_y)
  return chunk_x .. "," .. chunk_y
end

local function unit_vector(delta_x, delta_y)
  local length = math.sqrt(delta_x * delta_x + delta_y * delta_y)
  if length < 0.01 then
    return 0, 0, length
  end
  return delta_x / length, delta_y / length, length
end

-- Registered in every chunk the widest query could reach it from, so a query
-- only ever reads its own chunk.
local function add_danger(surface_dangers, position, radius, direction_x, direction_y)
  local danger = {
    x = position.x,
    y = position.y,
    radius = radius,
    direction_x = direction_x,
    direction_y = direction_y
  }
  local reach = radius + RAIL_DANGER_TRACK_PADDING
    + math.max(RAIL_DANGER_APPROACH_DISTANCE, RAIL_DANGER_VEHICLE_APPROACH_DISTANCE)
  for chunk_x = math.floor((position.x - reach) / CHUNK_SIZE),
    math.floor((position.x + reach) / CHUNK_SIZE) do
    for chunk_y = math.floor((position.y - reach) / CHUNK_SIZE),
      math.floor((position.y + reach) / CHUNK_SIZE) do
      local key = danger_chunk_key(chunk_x, chunk_y)
      local list = surface_dangers[key] or {}
      list[#list + 1] = danger
      surface_dangers[key] = list
    end
  end
end

local function box_radius(box)
  local width = box.right_bottom.x - box.left_top.x
  local height = box.right_bottom.y - box.left_top.y
  return math.sqrt(width * width + height * height) / 2
end

-- Returns the distance from the previous rail so the caller can stop once the
-- lookahead is covered.
local function add_rail_danger(surface_dangers, rail, previous)
  local position = rail.position
  local direction_x, direction_y, length = unit_vector(
    position.x - previous.x, position.y - previous.y
  )
  add_danger(surface_dangers, position, box_radius(rail.bounding_box), direction_x, direction_y)
  return length
end

local function add_train_dangers(surface_dangers, train)
  local forward = train.speed > 0
  local lead = forward and train.front_stock or train.back_stock
  if not lead or not lead.valid then
    return
  end

  -- The body counts too: a team mate released once the front has passed must
  -- not walk into the wagons behind it.
  for _, carriage in pairs(train.carriages) do
    local angle = carriage.orientation * 2 * math.pi
    add_danger(
      surface_dangers, carriage.position, box_radius(carriage.bounding_box),
      math.sin(angle), -math.cos(angle)
    )
  end

  local lookahead = math.min(
    math.max(math.abs(train.speed) * RAIL_DANGER_LOOKAHEAD_TICKS, RAIL_DANGER_MIN_DISTANCE),
    RAIL_DANGER_MAX_DISTANCE
  )
  local covered = 0
  local previous = lead.position

  -- Automatic trains follow their path through switches; manual ones go the
  -- natural way from the leading rail end.
  local path = train.path
  if not train.manual_mode and path and path.valid and path.is_front == forward then
    local rails = path.rails
    local last = math.min(path.size, path.current + RAIL_DANGER_MAX_RAILS)
    for index = path.current, last do
      local rail = rails[index]
      if rail and rail.valid then
        covered = covered + add_rail_danger(surface_dangers, rail, previous)
        previous = rail.position
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
    covered = covered + add_rail_danger(surface_dangers, rail, previous)
    previous = rail.position
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

local function any_position_within(positions, center, distance)
  local limit = distance * distance
  for _, position in pairs(positions) do
    if distance_squared(position, center) <= limit then
      return true
    end
  end
  return false
end

function update_rail_dangers()
  rail_dangers = {}

  -- Only trains near team mates matter, so a big rail network costs little
  -- while crew are away from it.
  local positions_by_surface = {}
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      local entity = rail_safety_entity(record)
      if entity then
        local positions = positions_by_surface[entity.surface_index] or {}
        positions[#positions + 1] = entity.position
        positions_by_surface[entity.surface_index] = positions
      end
    end
  end

  for surface_index, positions in pairs(positions_by_surface) do
    local trains = game.train_manager.get_trains({surface = surface_index, is_moving = true})
    for _, train in pairs(trains) do
      local lead = train.speed > 0 and train.front_stock or train.back_stock
      local reach = math.min(
        math.max(math.abs(train.speed) * RAIL_DANGER_LOOKAHEAD_TICKS, RAIL_DANGER_MIN_DISTANCE),
        RAIL_DANGER_MAX_DISTANCE
      ) + #train.carriages * 8 + RAIL_DANGER_VEHICLE_APPROACH_DISTANCE + 8
      if lead and lead.valid and any_position_within(positions, lead.position, reach) then
        local surface_dangers = rail_dangers[surface_index] or {}
        rail_dangers[surface_index] = surface_dangers
        add_train_dangers(surface_dangers, train)
      end
    end
  end
end

-- Nearest danger within margin of its footprint, and the gap to that footprint.
local function find_rail_danger(surface_index, position, margin)
  local surface_dangers = rail_dangers[surface_index]
  local list = surface_dangers and surface_dangers[danger_chunk_key(
    math.floor(position.x / CHUNK_SIZE), math.floor(position.y / CHUNK_SIZE)
  )]
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
    local _, gap = find_rail_danger(
      entity.surface_index, entity.position,
      RAIL_DANGER_TRACK_PADDING + RAIL_DANGER_VEHICLE_APPROACH_DISTANCE
    )
    -- A car already on the track keeps driving: braking there is what gets it hit.
    if gap and gap > RAIL_DANGER_TRACK_PADDING then
      behavior.stop(record, entity)
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
