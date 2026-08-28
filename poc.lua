local poc = {}

local TEAM_MATE_COUNT = 10
local UPDATE_INTERVAL = 10
local ENGAGEMENT_RADIUS = 16
local COMMAND_REFRESH_DISTANCE = 2
local CHUNK_SIZE = 32
local TEAM_MATE_NAME = "not-alone-team-mate"
local COMMAND_TOOL_NAME = "not-alone-command-tool"

local function distance_squared(first, second)
  local delta_x = first.x - second.x
  local delta_y = first.y - second.y
  return delta_x * delta_x + delta_y * delta_y
end

local function stop_team_mate(record)
  if record.command_kind ~= "stop" then
    record.entity.commandable.set_command({type = defines.command.stop})
    record.command_kind = "stop"
    record.command_destination = nil
    record.command_target = nil
  end
end

local function move_team_mate(record, destination, stopping_distance)
  if distance_squared(record.entity.position, destination) <= stopping_distance * stopping_distance then
    stop_team_mate(record)
    return
  end

  if record.command_kind == "move"
    and record.command_destination
    and record.entity.commandable.has_command
    and distance_squared(record.command_destination, destination)
      <= COMMAND_REFRESH_DISTANCE * COMMAND_REFRESH_DISTANCE then
    return
  end

  record.entity.commandable.set_command({
    type = defines.command.go_to_location,
    destination = destination,
    radius = stopping_distance,
    distraction = defines.distraction.none
  })
  record.command_kind = "move"
  record.command_destination = {x = destination.x, y = destination.y}
  record.command_target = nil
end

local function attack_with_team_mate(record, enemy)
  if record.command_kind == "attack"
    and record.command_target
    and record.command_target.valid
    and record.entity.commandable.has_command
    and record.command_target == enemy then
    return
  end

  record.entity.commandable.set_command({
    type = defines.command.attack,
    target = enemy,
    distraction = defines.distraction.none
  })
  record.command_kind = "attack"
  record.command_destination = nil
  record.command_target = enemy
end

local function reveal_team_mate_chunk(record)
  local character = record.entity
  local chunk_x = math.floor(character.position.x / CHUNK_SIZE)
  local chunk_y = math.floor(character.position.y / CHUNK_SIZE)

  if record.chart_surface_index == character.surface_index
    and record.chart_chunk_x == chunk_x
    and record.chart_chunk_y == chunk_y then
    return
  end

  character.force.chart(character.surface, {
    {x = chunk_x * CHUNK_SIZE, y = chunk_y * CHUNK_SIZE},
    {x = (chunk_x + 1) * CHUNK_SIZE, y = (chunk_y + 1) * CHUNK_SIZE}
  })
  record.chart_surface_index = character.surface_index
  record.chart_chunk_x = chunk_x
  record.chart_chunk_y = chunk_y
end

local function spawn_team_mates(player)
  if not player.valid or not player.character or not player.character.valid then
    return false
  end

  if player.get_item_count(COMMAND_TOOL_NAME) == 0 then
    player.insert({name = COMMAND_TOOL_NAME, count = 1})
  end

  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local existing = storage.not_alone_team_mates[player.index]
  if existing and #existing > 0 then
    return true
  end

  local team_mates = {}
  for index = 1, TEAM_MATE_COUNT do
    local spawn_position = player.surface.find_non_colliding_position(
      TEAM_MATE_NAME,
      player.position,
      8,
      0.5
    )

    if spawn_position then
      local character = player.surface.create_entity({
        name = TEAM_MATE_NAME,
        position = spawn_position,
        force = player.force,
        create_build_effect_smoke = false
      })

      if character then
        character.color = player.color
        character.name_tag = "Team mate " .. index
        team_mates[#team_mates + 1] = {entity = character}
      end
    end
  end

  storage.not_alone_team_mates[player.index] = team_mates
  player.print({"not-alone.team-mates-arrived", #team_mates})
  return true
end

local function update_team_mate(record, player)
  local character = record.entity
  if not character.valid or character.type ~= "unit" then
    return false
  end

  reveal_team_mate_chunk(record)

  if record.manual_destination then
    if character.surface_index == record.manual_surface_index then
      if distance_squared(character.position, record.manual_destination) <= 1 then
        record.manual_destination = nil
        record.manual_surface_index = nil
        stop_team_mate(record)
      else
        move_team_mate(record, record.manual_destination, 1)
      end
    else
      record.manual_destination = nil
      record.manual_surface_index = nil
      stop_team_mate(record)
    end
    return true
  end

  local enemy = character.surface.find_nearest_enemy({
    position = character.position,
    max_distance = ENGAGEMENT_RADIUS,
    force = character.force
  })

  if enemy and enemy.valid then
    attack_with_team_mate(record, enemy)
  else
    stop_team_mate(record)
  end

  return true
end

function poc.on_init()
  storage.not_alone_team_mates = {}
  storage.not_alone_pending_spawns = {}
  storage.not_alone_selected_team_mates = {}
  for _, player in pairs(game.players) do
    storage.not_alone_pending_spawns[player.index] = game.tick + 1
  end
end

function poc.on_configuration_changed()
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.entity and record.entity.valid then
        record.entity.destroy()
      end
    end
  end

  storage.not_alone_team_mates = {}
  storage.not_alone_pending_spawns = {}
  storage.not_alone_selected_team_mates = {}
  for _, player in pairs(game.players) do
    storage.not_alone_pending_spawns[player.index] = game.tick + 1
  end
end

function poc.on_player_created(event)
  storage.not_alone_pending_spawns = storage.not_alone_pending_spawns or {}
  storage.not_alone_pending_spawns[event.player_index] = game.tick + 1
end

function poc.on_player_removed(event)
  local team_mates = storage.not_alone_team_mates
    and storage.not_alone_team_mates[event.player_index]
  if team_mates then
    for _, record in pairs(team_mates) do
      if record.entity.valid then
        record.entity.destroy()
      end
    end
    storage.not_alone_team_mates[event.player_index] = nil
  end
  if storage.not_alone_selected_team_mates then
    storage.not_alone_selected_team_mates[event.player_index] = nil
  end
end

function poc.on_selected_area(event)
  if event.item ~= COMMAND_TOOL_NAME then
    return
  end

  local owned_team_mates = {}
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    if record.entity.valid then
      owned_team_mates[record.entity.unit_number] = true
    end
  end

  local selected = {}
  local selected_count = 0
  for _, entity in pairs(event.entities) do
    if entity.valid and owned_team_mates[entity.unit_number] then
      selected[entity.unit_number] = true
      selected_count = selected_count + 1
    end
  end

  storage.not_alone_selected_team_mates = storage.not_alone_selected_team_mates or {}
  storage.not_alone_selected_team_mates[event.player_index] = selected
  game.get_player(event.player_index).print({"not-alone.team-mates-selected", selected_count})
end

function poc.on_reverse_selected_area(event)
  if event.item ~= COMMAND_TOOL_NAME then
    return
  end

  local player = game.get_player(event.player_index)
  local selected = storage.not_alone_selected_team_mates
    and storage.not_alone_selected_team_mates[event.player_index]
  if not selected or not next(selected) then
    player.print({"not-alone.no-team-mates-selected"})
    return
  end

  local destination = {
    x = (event.area.left_top.x + event.area.right_bottom.x) / 2,
    y = (event.area.left_top.y + event.area.right_bottom.y) / 2
  }
  local ordered_count = 0
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    local entity = record.entity
    if entity.valid
      and selected[entity.unit_number]
      and entity.surface_index == event.surface.index then
      record.manual_destination = destination
      record.manual_surface_index = event.surface.index
      move_team_mate(record, destination, 1)
      ordered_count = ordered_count + 1
    end
  end

  player.print({"not-alone.team-mates-ordered", ordered_count})
end

function poc.on_update(event)
  storage.not_alone_pending_spawns = storage.not_alone_pending_spawns or {}
  for player_index, spawn_tick in pairs(storage.not_alone_pending_spawns) do
    if event.tick >= spawn_tick then
      local player = game.get_player(player_index)
      if player and spawn_team_mates(player) then
        storage.not_alone_pending_spawns[player_index] = nil
      end
    end
  end

  for player_index, team_mates in pairs(storage.not_alone_team_mates or {}) do
    local player = game.get_player(player_index)
    if player and player.character and player.character.valid then
      local active_team_mates = {}
      for _, record in pairs(team_mates) do
        if update_team_mate(record, player) then
          active_team_mates[#active_team_mates + 1] = record
        end
      end
      storage.not_alone_team_mates[player_index] = active_team_mates
    end
  end
end

function poc.register()
  script.on_init(poc.on_init)
  script.on_configuration_changed(poc.on_configuration_changed)
  script.on_event(defines.events.on_player_created, poc.on_player_created)
  script.on_event(defines.events.on_player_removed, poc.on_player_removed)
  script.on_event(defines.events.on_player_selected_area, poc.on_selected_area)
  script.on_event(defines.events.on_player_reverse_selected_area, poc.on_reverse_selected_area)
  script.on_nth_tick(UPDATE_INTERVAL, poc.on_update)
end

return poc