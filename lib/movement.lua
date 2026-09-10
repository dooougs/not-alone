-- Functional area extracted from not-alone.lua.

function refresh_route_renderings(record, player_index)
  destroy_route_renderings(record)

  local destinations = record.manual_loop and record.manual_loop_destinations
    or get_manual_destinations(record)
  if #destinations == 0 or not record.entity.valid then
    return
  end

  local surface = record.entity.surface
  local previous_target = record.entity
  local route_color = record.manual_loop and PATROL_ROUTE_COLOR or ROUTE_COLOR
  for _, destination in ipairs(destinations) do
    local line = rendering.draw_line({
      color = route_color,
      width = 3,
      from = previous_target,
      to = destination,
      surface = surface,
      players = {player_index},
      draw_on_ground = true
    })
    local marker = rendering.draw_circle({
      color = route_color,
      radius = 0.45,
      width = 3,
      filled = false,
      target = destination,
      surface = surface,
      players = {player_index},
      draw_on_ground = true
    })
    record.route_render_ids[#record.route_render_ids + 1] = line.id
    record.route_render_ids[#record.route_render_ids + 1] = marker.id
    previous_target = destination
  end
end

function enable_logistics_network_gui(force)
  force.unlock_logistic_network = true
  force.character_logistic_requests = true
end

stop_team_mate = function(record)
  if record.command_kind ~= "stop" then
    record.entity.commandable.set_command({type = defines.command.stop})
    record.command_kind = "stop"
    record.command_destination = nil
    record.command_target = nil
  end
end

wander_team_mate = function(record)
  if record.command_kind ~= "wander" then
    record.entity.commandable.set_command({
      type = defines.command.wander,
      distraction = defines.distraction.by_enemy
    })
    record.command_kind = "wander"
    record.command_destination = nil
    record.command_target = nil
  end
end

move_team_mate = function(record, destination, stopping_distance)
  if not record.vehicle_state
    and distance_squared(record.entity.position, destination)
      >= vehicle_minimum_distance(record) * vehicle_minimum_distance(record)
    and begin_vehicle_travel(record, destination) then
    return
  end
  if distance_squared(record.entity.position, destination) <= stopping_distance * stopping_distance then
    record.move_failures = nil
    stop_team_mate(record)
    return
  end

  if record.command_kind == "move"
    and record.command_destination
    and distance_squared(record.command_destination, destination)
      <= COMMAND_REFRESH_DISTANCE * COMMAND_REFRESH_DISTANCE then
    if record.entity.commandable.has_command
      and record.entity.commandable.command
      and record.entity.commandable.command.type == defines.command.go_to_location then
      return
    end
    -- The same move ended without arrival: retry with a fresh path while
    -- staying focused on the requested destination.
    record.move_failures = (record.move_failures or 0) + 1
    if record.move_failures >= 2 then
      record.move_failures = 0
      record.entity.commandable.set_command({type = defines.command.stop})
      record.command_kind = "stop"
      record.command_destination = nil
      record.command_target = nil
      return
    end
  end

  record.entity.commandable.set_command({
    type = defines.command.go_to_location,
    destination = destination,
    radius = stopping_distance,
    distraction = defines.distraction.none,
    -- Cached path failures otherwise repeat forever, and crowded spawns need
    -- paths that may pass through fellow team mates.
    pathfind_flags = {cache = false, allow_paths_through_own_entities = true}
  })
  record.command_kind = "move"
  record.command_destination = {x = destination.x, y = destination.y}
  record.command_target = nil
end

function find_nearest_habitat(record)
  local base = find_nearest_base(record, record.kind)
  record.habitat = base
  return base
end

function move_team_mate_toward_destination(record, destination)
  if begin_vehicle_travel(record, destination) then
    return
  end
  local position = record.entity.position
  local delta_x = destination.x - position.x
  local delta_y = destination.y - position.y
  local distance = math.sqrt(delta_x * delta_x + delta_y * delta_y)
  local waypoint = destination

  if distance > SCOUT_WAYPOINT_DISTANCE then
    local scale = SCOUT_WAYPOINT_DISTANCE / distance
    waypoint = {
      x = position.x + delta_x * scale,
      y = position.y + delta_y * scale
    }
  end

  local surface = record.entity.surface
  local waypoint_chunk = {
    x = math.floor(waypoint.x / CHUNK_SIZE),
    y = math.floor(waypoint.y / CHUNK_SIZE)
  }
  surface.request_to_generate_chunks(waypoint, SCOUT_GENERATION_RADIUS)
  if not surface.is_chunk_generated(waypoint_chunk) then
    stop_team_mate(record)
    return
  end

  move_team_mate(record, waypoint, 1)
end

