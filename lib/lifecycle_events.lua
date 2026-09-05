-- Functional area extracted from poc.lua.

function queue_starter_inventory(player_index)
  storage.not_alone_starter_inventory_pending =
    storage.not_alone_starter_inventory_pending or {}
  storage.not_alone_starter_inventory_pending[player_index] = true
end

function queue_starter_inventory_migration()
  if storage.not_alone_starter_inventory_version == STARTER_INVENTORY_VERSION then
    return
  end
  for _, player in pairs(game.players) do
    queue_starter_inventory(player.index)
  end
  storage.not_alone_starter_inventory_version = STARTER_INVENTORY_VERSION
end

function ensure_starter_inventory(player)
  if not player or not player.valid or not player.character or not player.character.valid then
    return false
  end

  local satisfied = true
  for kind, item_name in pairs(ITEM_NAME_BY_KIND) do
    local missing = math.max(INITIAL_COUNT_BY_KIND[kind] - player.get_item_count(item_name), 0)
    if missing > 0 then
      player.insert({name = item_name, count = missing})
    end
    if player.get_item_count(item_name) < INITIAL_COUNT_BY_KIND[kind] then
      satisfied = false
    end
  end

  local missing_habitats = math.max(
    INITIAL_HABITAT_COUNT - player.get_item_count(LOGISTICS_HUB_NAME),
    0
  )
  if missing_habitats > 0 then
    player.insert({name = LOGISTICS_HUB_NAME, count = missing_habitats})
  end

  return satisfied and player.get_item_count(LOGISTICS_HUB_NAME) >= INITIAL_HABITAT_COUNT
end

function rescue_immobile_team_mate(record)
  local entity = record.entity
  if record.command_kind ~= "move" and record.command_kind ~= "attack" then
    record.stall_position = nil
    record.stall_count = nil
    return
  end
  -- Standing still while firing at an in-range target is not a stall.
  if record.command_kind == "attack" then
    local target = record.command_target
    if target and target.valid then
      local params = entity.prototype.attack_parameters
      local range = ((params and params.range) or ENGAGEMENT_RADIUS) + 2
      if distance_squared(entity.position, target.position) <= range * range then
        record.stall_position = nil
        record.stall_count = nil
        return
      end
    end
  end
  if record.stall_position
    and distance_squared(entity.position, record.stall_position) < 0.01 then
    record.stall_count = (record.stall_count or 0) + 1
    if record.stall_count >= 30 then
      record.stall_count = 0
      record.move_failures = 2
      record.command_kind = nil
      record.command_destination = nil
      record.command_target = nil
    end
  else
    record.stall_position = position_table(entity.position)
    record.stall_count = 0
  end
end

function update_team_mate(record, player)
  local character = record.entity
  if not character.valid or character.type ~= "unit" then
    if record.vehicle_driver and record.vehicle_driver.valid then
      record.vehicle_driver.destroy()
    end
    record.vehicle_driver = nil
    record.vehicle_driver_unit_number = nil
    destroy_route_renderings(record)
    destroy_inventory_renderings(record)
    destroy_color_marker(record)
    return false
  end

  rescue_immobile_team_mate(record)
  destroy_color_marker(record)
  -- Older saves deployed the untinted generic unit; swap in the role variant.
  if not record.mining_hidden and record.kind ~= "soldier" then
    local wanted = TEAM_MATE_ENTITY_BY_KIND[record.kind]
    if wanted and character.name ~= wanted then
      if not replace_team_mate_entity(record, wanted) then
        return true
      end
      character = record.entity
    end
  end
  update_inventory_renderings(record)
  update_builder_target_renderings(record)

  local manual_destinations = get_manual_destinations(record)
  if record.route_render_ids == nil and #manual_destinations > 0 then
    refresh_route_renderings(record, player.index)
  end

  if record.vehicle_state then
    update_vehicle_travel(record)
    return true
  end

  if #manual_destinations > 0
    and character.surface_index == record.manual_surface_index
    and begin_vehicle_travel(record, manual_destinations[1]) then
    return true
  end

  if #manual_destinations > 0 then
    if character.surface_index == record.manual_surface_index then
      local route_changed = false
      -- The engine parks units near, not on, a waypoint; a finished move
      -- command also counts as arrival so crowded routes cannot loop forever.
      while #manual_destinations > 0
        and (distance_squared(character.position, manual_destinations[1]) <= 4
          or (record.command_kind == "move"
            and not character.commandable.has_command)) do
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

  local enemy = character.surface.find_nearest_enemy({
    position = character.position,
    max_distance = ENGAGEMENT_RADIUS,
    force = character.force
  })

  -- Soldiers manage their own combat (with ammo) in update_soldier.
  if enemy and enemy.valid and record.kind ~= "soldier" then
    attack_with_team_mate(record, enemy)
    return true
  end

  if record.kind == "miner" then
    return update_miner(record, player)
  elseif record.kind == "builder" then
    return update_builder(record)
  elseif record.kind == "carrier" then
    return update_carrier(record)
  elseif record.kind == "soldier" then
    return update_soldier(record)
  end
  return dock_at_habitat(record)
end

function poc.on_init()
  storage.not_alone_team_mates = {}
  storage.not_alone_selected_team_mates = {}
  storage.not_alone_starter_inventory_pending = {}
  storage.not_alone_marked_resources = {}
  storage.not_alone_carrier_requests = {}
  configure_freeplay_starter_inventory()
  for _, player in pairs(game.players) do
    enable_logistics_network_gui(player.force)
    queue_starter_inventory(player.index)
  end
  storage.not_alone_starter_inventory_version = STARTER_INVENTORY_VERSION
end

function poc.on_configuration_changed()
  rendering.clear("not-alone")
  storage.not_alone_habitats = nil
  for _, requester_record in pairs(storage.not_alone_building_requesters or {}) do
    if requester_record.requester and requester_record.requester.valid then
      requester_record.requester.destroy()
    end
  end
  storage.not_alone_building_requesters = nil
  storage.not_alone_building_requester_ticks = nil
  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  storage.not_alone_selected_team_mates = {}
  storage.not_alone_marked_resources = {}
  storage.not_alone_carrier_requests = {}
  queue_starter_inventory_migration()
  configure_freeplay_starter_inventory()
  for _, player in pairs(game.players) do
    enable_logistics_network_gui(player.force)
  end
end

function poc.on_player_created(event)
  local player = game.get_player(event.player_index)
  enable_logistics_network_gui(player.force)
  queue_starter_inventory(player.index)
end

function poc.on_player_removed(event)
  local team_mates = storage.not_alone_team_mates
    and storage.not_alone_team_mates[event.player_index]
  if team_mates then
    for _, record in pairs(team_mates) do
      destroy_route_renderings(record)
      destroy_inventory_renderings(record)
      destroy_color_marker(record)
      if record.builder_cargo and record.builder_cargo.valid then
        if not record.builder_cargo.is_empty() and record.entity.valid then
          record.entity.surface.spill_inventory({
            position = position_table(record.entity.position),
            inventory = record.builder_cargo
          })
        end
        record.builder_cargo.destroy()
      end
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
end

function deconstruction_planner_accepts(stack, resource_name)
  if not stack or not stack.valid_for_read then
    return true
  end
  if stack.trees_and_rocks_only then
    return false
  end
  local filters = stack.entity_filters
  if not filters or #filters == 0 then
    return true
  end
  local listed = false
  for _, filter in pairs(filters) do
    -- The filter entries are prototype names, or prototypes on some versions.
    if filter == resource_name or (type(filter) == "table" and filter.name == resource_name) then
      listed = true
      break
    end
  end
  if stack.entity_filter_mode == defines.deconstruction_item.entity_filter_mode.whitelist then
    return listed
  end
  return not listed
end

function poc.on_deconstructed_area(event)
  local changed_count = 0
  for _, resource in pairs(event.surface.find_entities_filtered({
    area = event.area,
    type = "resource"
  })) do
    if deconstruction_planner_accepts(event.stack, resource.name) then
      if not event.alt then
        mark_resource_for_mining(resource)
        changed_count = changed_count + 1
      elseif is_resource_marked(resource) then
        unmark_resource_for_mining(resource)
        changed_count = changed_count + 1
      end
    end
  end
  if changed_count > 0 then
    local player = game.get_player(event.player_index)
    player.print({
      event.alt and "not-alone.resources-unmarked" or "not-alone.resources-marked",
      changed_count
    })
  end
end

function order_selected_team_mates(event, append)
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
      and selected[record.entity.unit_number]
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

