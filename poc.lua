local poc = {}

local TEAM_MATE_COUNT = 10
local UPDATE_INTERVAL = 10
local ENGAGEMENT_RADIUS = 16
local WANDER_RADIUS = 10
local COMMAND_REFRESH_DISTANCE = 2
local CHUNK_SIZE = 32
local SCOUT_WAYPOINT_DISTANCE = 64
local SCOUT_GENERATION_RADIUS = 2
local IRON_MINER_ROLE = "iron-miner"
local IRON_MINER_TECHNOLOGY_NAME = "not-alone-iron-miner"
local IRON_ORE_SEARCH_RADIUS = 128
local IRON_CONSUMER_SEARCH_RADIUS = 128
local IRON_MINER_CAPACITY = 50
local IRON_ORE_MINING_TIME = 1
local NORMAL_CHARACTER_MINING_SPEED = 0.5
local MINING_ANIMATION_FRAMES = 52
local MINING_ANIMATION_SPEED = 52 / 30
local HIDDEN_TEAM_MATE_NAME = "not-alone-team-mate-hidden"
local ROUTE_COLOR = {r = 0.2, g = 0.7, b = 1, a = 0.9}
local TEAM_MATE_NAME = "not-alone-team-mate"
local COMMAND_TOOL_NAME = "not-alone-command-tool"
local wander_with_team_mate
local stop_team_mate
local move_team_mate
local update_mining_animation

local function distance_squared(first, second)
  local delta_x = first.x - second.x
  local delta_y = first.y - second.y
  return delta_x * delta_x + delta_y * delta_y
end

local function destroy_route_renderings(record)
  for _, render_id in pairs(record.route_render_ids or {}) do
    local render_object = rendering.get_object_by_id(render_id)
    if render_object then
      render_object.destroy()
    end
  end
  record.route_render_ids = {}
end

local function get_manual_destinations(record)
  if not record.manual_destinations then
    record.manual_destinations = {}
    if record.manual_destination then
      record.manual_destinations[1] = {
        x = record.manual_destination.x,
        y = record.manual_destination.y
      }
    end
    record.manual_destination = nil
  end
  return record.manual_destinations
end

local function find_nearest_entity(entities, position, accepts)
  local nearest_entity
  local nearest_distance
  for _, entity in pairs(entities) do
    if entity.valid and (not accepts or accepts(entity)) then
      local current_distance = distance_squared(entity.position, position)
      if not nearest_distance or current_distance < nearest_distance then
        nearest_entity = entity
        nearest_distance = current_distance
      end
    end
  end
  return nearest_entity
end

local function find_nearest_iron_ore(record)
  return find_nearest_entity(
    record.entity.surface.find_entities_filtered({
      type = "resource",
      name = "iron-ore",
      position = record.entity.position,
      radius = IRON_ORE_SEARCH_RADIUS
    }),
    record.entity.position,
    function(resource)
      return resource.amount > 0
    end
  )
end

local function furnace_accepts_iron_ore(furnace)
  local inventory = furnace.get_inventory(defines.inventory.crafter_input)
  return inventory and inventory.can_insert({name = "iron-ore", count = 1})
end

local function find_nearest_iron_consumer(record)
  return find_nearest_entity(
    record.entity.surface.find_entities_filtered({
      type = "furnace",
      position = record.entity.position,
      radius = IRON_CONSUMER_SEARCH_RADIUS
    }),
    record.entity.position,
    furnace_accepts_iron_ore
  )
end

local function get_iron_mining_interval(player)
  local mining_speed_modifier = player.character_mining_speed_modifier
  local effective_mining_speed = NORMAL_CHARACTER_MINING_SPEED * (1 + mining_speed_modifier)
  return math.max(1, math.ceil(IRON_ORE_MINING_TIME * 60 / effective_mining_speed))
end

local function update_iron_miner(record, player)
  update_mining_animation(record, record.role_state == "mine")

  if record.role_state == "find-ore" then
    local resource = find_nearest_iron_ore(record)
    if resource then
      record.role_target = resource
      record.role_state = "move-to-ore"
    else
      wander_with_team_mate(record)
    end
  elseif record.role_state == "move-to-ore" then
    if not record.role_target or not record.role_target.valid then
      record.role_state = "find-ore"
    elseif distance_squared(record.entity.position, record.role_target.position) <= 4 then
      record.role_state = "mine"
      record.next_mining_tick = game.tick + math.random(get_iron_mining_interval(player))
      stop_team_mate(record)
    else
      move_team_mate(record, record.role_target.position, 2)
    end
  elseif record.role_state == "mine" then
    stop_team_mate(record)
    if game.tick >= (record.next_mining_tick or 0) then
      local resource = record.role_target
      if not resource or not resource.valid or resource.amount <= 0 then
        record.role_state = "find-ore"
        record.role_target = nil
      else
        local mined = 1
        local mining_position = resource.position
        local remaining_amount = resource.amount - mined
        if remaining_amount > 0 then
          resource.amount = remaining_amount
        else
          resource.deplete()
        end
        record.carried_ore = (record.carried_ore or 0) + mined
        record.entity.surface.play_sound({
          path = "not-alone-team-mate-mining-sound",
          position = mining_position,
          volume_modifier = 0.8
        })
        record.next_mining_tick = record.next_mining_tick + get_iron_mining_interval(player)
        if record.carried_ore >= IRON_MINER_CAPACITY or remaining_amount <= 0 then
          record.role_state = "find-consumer"
          record.role_target = nil
        end
      end
    end
  elseif record.role_state == "find-consumer" then
    local furnace = find_nearest_iron_consumer(record)
    if furnace then
      record.role_target = furnace
      record.role_state = "move-to-consumer"
    else
      wander_with_team_mate(record)
    end
  elseif record.role_state == "move-to-consumer" then
    if not record.role_target or not record.role_target.valid then
      record.role_state = "find-consumer"
    elseif distance_squared(record.entity.position, record.role_target.position) <= 4 then
      record.role_state = "deliver"
      stop_team_mate(record)
    else
      move_team_mate(record, record.role_target.position, 2)
    end
  elseif record.role_state == "deliver" then
    local furnace = record.role_target
    if not furnace or not furnace.valid then
      record.role_state = "find-consumer"
    else
      local inventory = furnace.get_inventory(defines.inventory.crafter_input)
      local inserted = inventory and inventory.insert({
        name = "iron-ore",
        count = record.carried_ore or 0
      }) or 0
      record.carried_ore = (record.carried_ore or 0) - inserted
      if record.carried_ore <= 0 then
        record.carried_ore = 0
        record.role_state = "find-ore"
        record.role_target = nil
      end
    end
  else
    record.role_state = "find-ore"
  end

  return true
end

update_mining_animation = function(record, should_show)
  local render_object = record.mining_animation_id
    and rendering.get_object_by_id(record.mining_animation_id)
  local mask_object = record.mining_mask_animation_id
    and rendering.get_object_by_id(record.mining_mask_animation_id)
  if should_show then
    if not record.mining_hidden then
      record.mining_color = record.team_mate_color or record.entity.color
        or {r = 1, g = 1, b = 1, a = 1}
      local visible_entity = record.entity
      local hidden_entity = visible_entity.surface.create_entity({
        name = HIDDEN_TEAM_MATE_NAME,
        position = visible_entity.position,
        force = visible_entity.force,
        orientation = visible_entity.orientation,
        create_build_effect_smoke = false
      })
      if not hidden_entity then
        return
      end
      hidden_entity.color = record.mining_color
      if visible_entity.name_tag then
        hidden_entity.name_tag = visible_entity.name_tag
      end
      hidden_entity.health = visible_entity.health
      visible_entity.destroy()
      record.entity = hidden_entity
      hidden_entity.commandable.set_command({type = defines.command.stop})
      record.command_kind = "stop"
      record.command_destination = nil
      record.command_target = nil
      record.mining_hidden = true
    end
    if render_object then
      return
    end

    -- Script animations run on the global tick clock; anchor frame zero to this
    -- miner's own strike schedule so miners desync and redraws never jump frames.
    local anchor_tick = record.next_mining_tick or game.tick
    local animation_offset = (MINING_ANIMATION_FRAMES
      - ((anchor_tick * MINING_ANIMATION_SPEED) % MINING_ANIMATION_FRAMES)) % MINING_ANIMATION_FRAMES
    record.mining_animation_id = rendering.draw_animation({
      animation = "not-alone-team-mate-mining",
      target = record.entity,
      surface = record.entity.surface,
      orientation = record.entity.orientation,
      animation_offset = animation_offset,
      render_layer = "object"
    }).id
    local mask_color = record.mining_color
    record.mining_mask_animation_id = rendering.draw_animation({
      animation = "not-alone-team-mate-mining-mask",
      target = record.entity,
      surface = record.entity.surface,
      orientation = record.entity.orientation,
      animation_offset = animation_offset,
      tint = {r = mask_color.r, g = mask_color.g, b = mask_color.b, a = 1},
      render_layer = "object"
    }).id
  elseif render_object then
    render_object.destroy()
    record.mining_animation_id = nil
  end
  if not should_show and mask_object then
    mask_object.destroy()
    record.mining_mask_animation_id = nil
  end
  if not should_show and record.mining_hidden then
    local hidden_entity = record.entity
    local visible_entity = hidden_entity.surface.create_entity({
      name = TEAM_MATE_NAME,
      position = hidden_entity.position,
      force = hidden_entity.force,
      orientation = hidden_entity.orientation,
      create_build_effect_smoke = false
    })
    if visible_entity then
      visible_entity.color = record.mining_color
      if hidden_entity.name_tag then
        visible_entity.name_tag = hidden_entity.name_tag
      end
      visible_entity.health = hidden_entity.health
      hidden_entity.destroy()
      record.entity = visible_entity
      record.command_kind = nil
      record.command_destination = nil
      record.command_target = nil
      record.mining_hidden = nil
      record.mining_color = nil
    end
  end
end

local function refresh_route_renderings(record, player_index)
  destroy_route_renderings(record)

  local destinations = get_manual_destinations(record)
  if #destinations == 0 or not record.entity.valid then
    return
  end

  local surface = record.entity.surface
  local previous_target = record.entity
  for _, destination in ipairs(destinations) do
    local line = rendering.draw_line({
      color = ROUTE_COLOR,
      width = 3,
      from = previous_target,
      to = destination,
      surface = surface,
      players = {player_index},
      draw_on_ground = true
    })
    local marker = rendering.draw_circle({
      color = ROUTE_COLOR,
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

local function ensure_role_gui(player)
  if not player.valid then
    return
  end

  if player.gui.left.not_alone_role_frame then
    return
  end

  local frame = player.gui.left.add({
    type = "frame",
    name = "not_alone_role_frame",
    direction = "vertical",
    caption = {"not-alone.role-frame-title"}
  })
  frame.add({
    type = "label",
    name = "not_alone_role_selection_status",
    caption = {"not-alone.role-selection-status", 0}
  })
  frame.add({
    type = "button",
    name = "not_alone_add_team_mate",
    caption = {"not-alone.add-team-mate"},
    tooltip = {"not-alone.add-team-mate-tooltip"}
  })
  frame.add({
    type = "button",
    name = "not_alone_assign_iron_miner",
    caption = {"not-alone.assign-iron-miner"},
    tooltip = {"not-alone.assign-iron-miner-tooltip"}
  })
end

local function ensure_iron_miner_technology(force)
  local technology = force.technologies[IRON_MINER_TECHNOLOGY_NAME]
  if technology then
    technology.researched = true
  end
end

local function update_role_selection_status(player)
  local frame = player.gui.left.not_alone_role_frame
  if not frame or not frame.valid then
    return
  end

  local status = frame.not_alone_role_selection_status
  if not status or not status.valid then
    return
  end

  local selected = storage.not_alone_selected_team_mates
    and storage.not_alone_selected_team_mates[player.index]
  local selected_count = 0
  for _ in pairs(selected or {}) do
    selected_count = selected_count + 1
  end
  status.caption = {"not-alone.role-selection-status", selected_count}
end

stop_team_mate = function(record)
  if record.command_kind ~= "stop" then
    record.entity.commandable.set_command({type = defines.command.stop})
    record.command_kind = "stop"
    record.command_destination = nil
    record.command_target = nil
  end
end

wander_with_team_mate = function(record)
  if record.command_kind == "wander" and record.entity.commandable.has_command then
    return
  end

  record.entity.commandable.set_command({
    type = defines.command.wander,
    radius = WANDER_RADIUS,
    distraction = defines.distraction.by_enemy
  })
  record.command_kind = "wander"
  record.command_destination = nil
  record.command_target = nil
end

move_team_mate = function(record, destination, stopping_distance)
  if distance_squared(record.entity.position, destination) <= stopping_distance * stopping_distance then
    stop_team_mate(record)
    return
  end

  if record.command_kind == "move"
    and record.command_destination
    and record.entity.commandable.has_command
    and record.entity.commandable.command
    and record.entity.commandable.command.type == defines.command.go_to_location
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

local function move_team_mate_toward_destination(record, destination)
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

local function create_team_mate(player, index)
  local spawn_position = player.surface.find_non_colliding_position(
    TEAM_MATE_NAME,
    player.position,
    8,
    0.5
  )
  if not spawn_position then
    return nil
  end

  local character = player.surface.create_entity({
    name = TEAM_MATE_NAME,
    position = spawn_position,
    force = player.force,
    create_build_effect_smoke = false
  })
  if not character then
    return nil
  end

  character.color = player.color
  character.name_tag = "Team mate " .. index
  return {entity = character, team_mate_color = player.color}
end

local function add_team_mate(player)
  if not player.valid or not player.character or not player.character.valid then
    return nil
  end

  if player.get_item_count(COMMAND_TOOL_NAME) == 0 then
    player.insert({name = COMMAND_TOOL_NAME, count = 1})
  end

  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local team_mates = storage.not_alone_team_mates[player.index] or {}
  local record = create_team_mate(player, #team_mates + 1)
  if not record then
    return nil
  end

  team_mates[#team_mates + 1] = record
  storage.not_alone_team_mates[player.index] = team_mates
  return record
end

local function spawn_team_mates(player)
  if not player.valid or not player.character or not player.character.valid then
    return false
  end

  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local existing = storage.not_alone_team_mates[player.index]
  if existing and #existing > 0 then
    return true
  end

  local spawned_count = 0
  for _ = 1, TEAM_MATE_COUNT do
    if add_team_mate(player) then
      spawned_count = spawned_count + 1
    end
  end
  player.print({"not-alone.team-mates-arrived", spawned_count})
  return spawned_count > 0
end

local function update_team_mate(record, player)
  local character = record.entity
  if not character.valid or character.type ~= "unit" then
    destroy_route_renderings(record)
    return false
  end

  local manual_destinations = get_manual_destinations(record)
  if record.route_render_ids == nil and #manual_destinations > 0 then
    refresh_route_renderings(record, player.index)
  end

  if #manual_destinations > 0 then
    if character.surface_index == record.manual_surface_index then
      local route_changed = false
      while #manual_destinations > 0
        and distance_squared(character.position, manual_destinations[1]) <= 1 do
        table.remove(manual_destinations, 1)
        route_changed = true
      end

      if route_changed then
        record.command_kind = nil
        record.command_destination = nil
        refresh_route_renderings(record, player.index)
      end

      if #manual_destinations == 0 then
        record.manual_surface_index = nil
        stop_team_mate(record)
      else
        move_team_mate_toward_destination(record, manual_destinations[1])
      end
    else
      record.manual_destinations = {}
      record.manual_surface_index = nil
      stop_team_mate(record)
      refresh_route_renderings(record, player.index)
    end
    return true
  end

  if record.role == IRON_MINER_ROLE then
    return update_iron_miner(record, player)
  end

  local enemy = character.surface.find_nearest_enemy({
    position = character.position,
    max_distance = ENGAGEMENT_RADIUS,
    force = character.force
  })

  if enemy and enemy.valid then
    attack_with_team_mate(record, enemy)
  else
    wander_with_team_mate(record)
  end

  return true
end

function poc.on_init()
  storage.not_alone_team_mates = {}
  storage.not_alone_pending_spawns = {}
  storage.not_alone_selected_team_mates = {}
  for _, player in pairs(game.players) do
    ensure_iron_miner_technology(player.force)
    storage.not_alone_pending_spawns[player.index] = game.tick + 1
    ensure_role_gui(player)
  end
end

function poc.on_configuration_changed()
  rendering.clear("not-alone")
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
    ensure_iron_miner_technology(player.force)
    storage.not_alone_pending_spawns[player.index] = game.tick + 1
    ensure_role_gui(player)
  end
end

function poc.on_player_created(event)
  local player = game.get_player(event.player_index)
  ensure_iron_miner_technology(player.force)
  storage.not_alone_pending_spawns = storage.not_alone_pending_spawns or {}
  storage.not_alone_pending_spawns[event.player_index] = game.tick + 1
  ensure_role_gui(player)
end

function poc.on_gui_click(event)
  if not event.element or not event.element.valid
    or (event.element.name ~= "not_alone_add_team_mate"
      and event.element.name ~= "not_alone_assign_iron_miner") then
    return
  end

  local player = game.get_player(event.player_index)
  if not player or not player.valid then
    return
  end

  if event.element.name == "not_alone_add_team_mate" then
    if add_team_mate(player) then
      player.print({"not-alone.team-mate-added"})
    else
      player.print({"not-alone.team-mate-could-not-be-added"})
    end
    return
  end

  local technology = player.force.technologies[IRON_MINER_TECHNOLOGY_NAME]
  if not technology or not technology.researched then
    player.print({"not-alone.iron-miner-technology-required"})
    return
  end

  local selected = storage.not_alone_selected_team_mates
    and storage.not_alone_selected_team_mates[event.player_index]
  local assigned_count = 0
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    local entity = record.entity
    if entity.valid and selected and selected[entity.unit_number] then
      record.role = IRON_MINER_ROLE
      record.role_state = "find-ore"
      record.role_target = nil
      record.carried_ore = 0
      record.next_mining_tick = nil
      record.manual_destinations = {}
      record.manual_surface_index = nil
      record.command_kind = nil
      record.command_destination = nil
      record.command_target = nil
      refresh_route_renderings(record, event.player_index)
      assigned_count = assigned_count + 1
    end
  end

  player.print({"not-alone.iron-miners-assigned", assigned_count})
  update_role_selection_status(player)
end

function poc.on_player_removed(event)
  local team_mates = storage.not_alone_team_mates
    and storage.not_alone_team_mates[event.player_index]
  if team_mates then
    for _, record in pairs(team_mates) do
      destroy_route_renderings(record)
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
  local player = game.get_player(event.player_index)
  player.print({"not-alone.team-mates-selected", selected_count})
  update_role_selection_status(player)
end

local function order_selected_team_mates(event, append)
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
      local manual_destinations = get_manual_destinations(record)
      if not append then
        manual_destinations = {}
        record.manual_destinations = manual_destinations
      end
      manual_destinations[#manual_destinations + 1] = {
        x = destination.x,
        y = destination.y
      }
      record.manual_surface_index = event.surface.index
      if #manual_destinations == 1 then
        move_team_mate_toward_destination(record, destination)
      end
      refresh_route_renderings(record, event.player_index)
      ordered_count = ordered_count + 1
    end
  end

  if append then
    player.print({"not-alone.team-mates-waypoint-added", ordered_count})
  else
    player.print({"not-alone.team-mates-ordered", ordered_count})
  end
end

function poc.on_reverse_selected_area(event)
  order_selected_team_mates(event, false)
end

function poc.on_alt_reverse_selected_area(event)
  order_selected_team_mates(event, true)
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
    if player then
      ensure_role_gui(player)
    end
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
  script.on_event(defines.events.on_gui_click, poc.on_gui_click)
  script.on_event(defines.events.on_player_removed, poc.on_player_removed)
  script.on_event(defines.events.on_player_selected_area, poc.on_selected_area)
  script.on_event(defines.events.on_player_reverse_selected_area, poc.on_reverse_selected_area)
  script.on_event(
    defines.events.on_player_alt_reverse_selected_area,
    poc.on_alt_reverse_selected_area
  )
  script.on_nth_tick(UPDATE_INTERVAL, poc.on_update)
end

return poc