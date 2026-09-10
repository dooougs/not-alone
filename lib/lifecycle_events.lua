-- Functional area extracted from not-alone.lua.

function ensure_command_tool(player)
  if not player or not player.valid then
    return
  end
  local inventory = player.get_main_inventory()
  if not inventory then
    return
  end
  local command_tool_stack = inventory.find_item_stack(COMMAND_TOOL_NAME)
  if not command_tool_stack then
    if player.insert({name = COMMAND_TOOL_NAME, count = 1}) ~= 1 then
      return
    end
    command_tool_stack = inventory.find_item_stack(COMMAND_TOOL_NAME)
  end
  local width = player.quick_bar_width or 10
  for page = 1, 10 do
    for slot = 1, width do
      local quick_bar_slot = player.get_quick_bar_slot(page, slot)
      if quick_bar_slot and quick_bar_slot.filter == COMMAND_TOOL_NAME then
        return
      end
    end
  end
  for page = 1, 10 do
    for slot = 1, width do
      if not player.get_quick_bar_slot(page, slot) then
        player.set_quick_bar_slot(page, slot, command_tool_stack)
        return
      end
    end
  end
end

function migrate_car_minimum_distance()
  if storage.not_alone_car_minimum_distance_migration == 2 then
    return
  end
  local setting = settings.global["not-alone-car-minimum-distance"]
  -- Raise stale old defaults (80, then 20) without overriding custom values.
  if setting and (setting.value == 80 or setting.value == 20) then
    settings.global["not-alone-car-minimum-distance"] = {value = CAR_MINIMUM_DISTANCE}
  end
  storage.not_alone_car_minimum_distance_migrated = true
  storage.not_alone_car_minimum_distance_migration = 2
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

local find_base_at

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
  -- Never while driving: the swap would un-hide the vehicle proxy.
  if not record.mining_hidden and not record.vehicle_state and record.kind ~= "soldier" then
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

  -- Soldiers interrupt wandering and manual travel to engage any hostile
  -- unit, including characters and team mates from non-friendly forces.
  if record.kind == "soldier" then
    local soldier_target = find_soldier_target(record)
      or find_soldier_immediate_target(record)
    if soldier_target then
      attack_with_team_mate(record, soldier_target)
      update_soldier(record)
      return true
    end
  end

  local manual_destinations = get_manual_destinations(record)
  if not record.route_rendering_suppressed
    and record.route_render_ids == nil and #manual_destinations > 0 then
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
      local joined_base
      -- The engine parks units near, not on, a waypoint; a finished move
      -- command also counts as arrival so crowded routes cannot loop forever.
      while #manual_destinations > 0 do
        local waypoint = manual_destinations[1]
        local waypoint_base = record.kind == "soldier"
          and find_base_at(character.surface, waypoint)
        local reached = waypoint_base and waypoint_base.force == character.force
          and base_contains_position(waypoint_base, character.position, 0.5)
          or distance_squared(character.position, waypoint)
            <= WAYPOINT_ARRIVAL_RADIUS * WAYPOINT_ARRIVAL_RADIUS
          or (record.command_kind == "move"
            and not character.commandable.has_command)
        if not reached then
          break
        end
        local arrived_at = manual_destinations[1]
        table.remove(manual_destinations, 1)
        route_changed = true
        if record.kind == "soldier" then
          local base = waypoint_base or find_base_at(character.surface, arrived_at)
          if base and base.force == character.force then
            record.home_base = base
            record.home_base_type = get_base_type(base)
            record.pending_home_base = nil
            manual_destinations = {}
            record.manual_destinations = manual_destinations
            joined_base = base
          end
        end
      end

      if #manual_destinations == 0
        and not joined_base
        and record.manual_loop
        and record.manual_loop_destinations then
        manual_destinations = {}
        for _, waypoint in ipairs(record.manual_loop_destinations) do
          manual_destinations[#manual_destinations + 1] = {
            x = waypoint.x,
            y = waypoint.y
          }
        end
        record.manual_destinations = manual_destinations
        record.manual_hold = nil
      end

      if route_changed then
        record.command_kind = nil
        record.command_destination = nil
        destroy_route_renderings(record)
        if not record.route_rendering_suppressed then
          refresh_route_renderings(record, player.index)
        end
      end

      if #manual_destinations == 0 then
        record.manual_surface_index = nil
        if joined_base then
          record.manual_hold = nil
          if get_base_type(joined_base) == "outpost" then
            wander_team_mate(record)
          else
            dock_at_habitat(record)
          end
        else
          if record.kind == "soldier" then
            record.manual_hold = nil
            record.manual_wander = true
            wander_team_mate(record)
          else
            record.manual_hold = true
            stop_team_mate(record)
          end
        end
      else
        move_team_mate_toward_destination(record, manual_destinations[1])
      end
    else
      record.manual_destinations = {}
      record.manual_surface_index = nil
      record.manual_loop = nil
      record.manual_loop_destinations = nil
      stop_team_mate(record)
      destroy_route_renderings(record)
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

function notalone.on_init()
  storage.not_alone_team_mates = {}
  storage.not_alone_selected_team_mates = {}
  storage.not_alone_marked_resources = {}
  storage.not_alone_carrier_requests = {}
  for base in each_base() do
    if get_base_type(base) == "habitat"
      and storage.not_alone_team_mate_requests then
      storage.not_alone_team_mate_requests[base.unit_number] = nil
    end
  end
  migrate_car_minimum_distance()
  for _, surface in pairs(game.surfaces) do
    spawn_initial_crash_ships(surface)
  end
  for _, player in pairs(game.players) do
    enable_logistics_network_gui(player.force)
    ensure_command_tool(player)
  end
end

function reset_stale_vehicle_travel()
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.vehicle_state then
        abandon_vehicle_travel(record)
        record.vehicle_failed_destination = nil
      end
      clear_vehicle_pickup(record)
      record.vehicle_pickup_source = nil
      record.vehicle_pending_destination = nil
      record.vehicle_fuel_item = nil
    end
  end
  storage.not_alone_vehicle_pickups = {}
end

function notalone.on_configuration_changed()
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
  migrate_car_minimum_distance()
  reset_stale_vehicle_travel()
  for _, surface in pairs(game.surfaces) do
    spawn_initial_crash_ships(surface)
  end
  for _, player in pairs(game.players) do
    enable_logistics_network_gui(player.force)
    ensure_command_tool(player)
  end
end

function notalone.on_player_created(event)
  local player = game.get_player(event.player_index)
  enable_logistics_network_gui(player.force)
  ensure_command_tool(player)
end

function notalone.on_player_removed(event)
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

local function is_command_tool_event(event)
  return event.item == COMMAND_TOOL_NAME
end

local function collect_team_mate(player, team_mates, record)
  local item_name = ITEM_NAME_BY_KIND[record.kind]
  if not item_name or player.insert({name = item_name, count = 1}) ~= 1 then
    return false
  end

  local surface = record.entity.surface
  local position = position_table(record.entity.position)
  local function give_or_spill(item)
    if not item.count or item.count <= 0 then
      return
    end
    local given = player.insert(item)
    if given < item.count then
      item.count = item.count - given
      surface.spill_item_stack({position = position, stack = item})
    end
  end
  if record.kind == "soldier" then
    for weapon_kind in pairs(record.soldier_weapons or {}) do
      local weapon = SOLDIER_WEAPON_BY_KIND[weapon_kind]
      if weapon then
        give_or_spill({name = weapon.gun, count = 1})
      end
    end
    for ammo_name, count in pairs(record.soldier_ammo or {}) do
      give_or_spill({name = ammo_name, count = count})
    end
    local armor = record.soldier_armor and SOLDIER_ARMORS[record.soldier_armor]
    if armor then
      give_or_spill({name = armor.item, count = 1})
    end
  end
  for _, inventory_name in ipairs({"builder_cargo", "vehicle_inventory", "vehicle_fuel_inventory"}) do
    local inventory = record[inventory_name]
    if inventory and inventory.valid then
      for item, count in pairs(inventory.get_contents()) do
        local stack = {name = item, count = count}
        local removed = inventory.remove(stack)
        stack.count = removed
        give_or_spill(stack)
      end
      inventory.destroy()
      record[inventory_name] = nil
    end
  end
  if record.vehicle_state then
    abandon_vehicle_travel(record)
  end
  destroy_route_renderings(record)
  destroy_inventory_renderings(record)
  destroy_color_marker(record)
  local old_base = record.home_base or record.pending_home_base
  record.entity.destroy()
  for index, candidate in pairs(team_mates) do
    if candidate == record then
      table.remove(team_mates, index)
      break
    end
  end
  if old_base and old_base.valid and get_base_type(old_base) == "outpost" then
    fulfill_base_requests(old_base)
  end
  return true
end

function collect_reverse_clicked_team_mate(event)
  if not is_command_tool_event(event) then
    return false
  end
  local player = game.get_player(event.player_index)
  local team_mates = storage.not_alone_team_mates
    and storage.not_alone_team_mates[event.player_index]
  if not player or not team_mates then
    return false
  end
  local click_position = {
    x = (event.area.left_top.x + event.area.right_bottom.x) / 2,
    y = (event.area.left_top.y + event.area.right_bottom.y) / 2
  }
  local targets = player.surface.find_entities_filtered({
    type = "unit",
    position = click_position,
    radius = 1
  })
  for _, entity in pairs(targets) do
    if entity.valid then
      for _, record in pairs(team_mates) do
        if record.entity == entity then
          if not collect_team_mate(player, team_mates, record) then
            player.print({"not-alone.team-mate-inventory-full"})
          end
          return true
        end
      end
    end
  end
  return false
end

function notalone.on_selected_area(event)
  if not is_command_tool_event(event) then
    return
  end

  local owned_team_mates = {}
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    if record.kind == "soldier" and record.entity.valid then
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

  local area = event.area
  local click_position = {
    x = (area.left_top.x + area.right_bottom.x) / 2,
    y = (area.left_top.y + area.right_bottom.y) / 2
  }
  local nearest_waypoint
  local nearest_distance
  if selected_count == 0
    and area.right_bottom.x - area.left_top.x <= WAYPOINT_SELECTION_RADIUS * 2
    and area.right_bottom.y - area.left_top.y <= WAYPOINT_SELECTION_RADIUS * 2 then
    for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
      local destinations = record.kind == "soldier"
        and (record.manual_loop and record.manual_loop_destinations
        or get_manual_destinations(record)
        ) or {}
      for _, waypoint in ipairs(destinations) do
        local distance = distance_squared(click_position, waypoint)
        if distance <= WAYPOINT_SELECTION_RADIUS * WAYPOINT_SELECTION_RADIUS
          and (not nearest_distance or distance < nearest_distance) then
          nearest_waypoint = waypoint
          nearest_distance = distance
        end
      end
    end
  end
  if nearest_waypoint then
    for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
      local destinations = record.kind == "soldier"
        and (record.manual_loop and record.manual_loop_destinations
        or get_manual_destinations(record)
        ) or {}
      for _, waypoint in ipairs(destinations) do
        if distance_squared(nearest_waypoint, waypoint)
          <= WAYPOINT_SELECTION_RADIUS * WAYPOINT_SELECTION_RADIUS then
          selected[record.entity.unit_number] = true
          break
        end
      end
    end
    selected_count = 0
    for _ in pairs(selected) do
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

function notalone.on_deconstructed_area(event)
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

local function is_building_at(surface, position)
  for _, entity in pairs(surface.find_entities_filtered({position = position, radius = 1})) do
    if entity.valid and not is_base(entity)
      and entity.type ~= "unit"
      and entity.type ~= "character"
      and entity.type ~= "resource"
      and entity.type ~= "tree"
      and entity.type ~= "simple-entity"
      and entity.type ~= "simple-entity-with-force"
      and entity.type ~= "simple-entity-with-owner"
      and entity.type ~= "item-entity"
      and entity.type ~= "corpse"
      and entity.type ~= "decorative" then
      return true
    end
  end
  return false
end

find_base_at = function(surface, position)
  for base in each_base() do
    if base.surface == surface and base_contains_position(base, position, 2) then
      return base
    end
  end
  return nil
end

function order_selected_team_mates(event, append)
  if not is_command_tool_event(event) then
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
  local blocked_soldier_waypoint = false
  local departed_outposts = {}
  local ordered_count = 0
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    local entity = record.entity
    if entity.valid
      and selected[record.entity.unit_number]
      and entity.surface_index == event.surface.index then
      if record.kind == "soldier" and is_building_at(event.surface, destination) then
        blocked_soldier_waypoint = true
        goto continue
      end
      if record.kind == "soldier" and record.home_base_type == "outpost"
        and record.home_base and record.home_base.valid then
        departed_outposts[record.home_base.unit_number] = record.home_base
        record.home_base = nil
        record.home_base_type = nil
        record.pending_home_base = nil
      end
      record.route_rendering_suppressed = nil
      record.manual_hold = nil
      record.manual_wander = nil
      local manual_destinations = get_manual_destinations(record)
      if not append then
        manual_destinations = {}
        record.manual_destinations = manual_destinations
      end
      manual_destinations[#manual_destinations + 1] = {
        x = destination.x,
        y = destination.y
      }
      if #manual_destinations >= 2 then
        local first = manual_destinations[1]
        local last = manual_destinations[#manual_destinations]
        record.manual_loop = distance_squared(first, last)
          <= WAYPOINT_ARRIVAL_RADIUS * WAYPOINT_ARRIVAL_RADIUS
        if record.manual_loop then
          record.manual_loop_destinations = {}
          for _, waypoint in ipairs(manual_destinations) do
            record.manual_loop_destinations[#record.manual_loop_destinations + 1] = {
              x = waypoint.x,
              y = waypoint.y
            }
          end
        else
          record.manual_loop_destinations = nil
        end
      else
        record.manual_loop = nil
        record.manual_loop_destinations = nil
      end
      record.manual_surface_index = event.surface.index
      if #manual_destinations == 1 then
        move_team_mate_toward_destination(record, destination)
      end
      refresh_route_renderings(record, event.player_index)
      ordered_count = ordered_count + 1
    end
    ::continue::
  end

  if blocked_soldier_waypoint then
    player.print({"not-alone.soldier-building-waypoint"})
  end
  for _, outpost in pairs(departed_outposts) do
    fulfill_base_requests(outpost)
  end
  if append then
    player.print({"not-alone.team-mates-waypoint-added", ordered_count})
  else
    player.print({"not-alone.team-mates-ordered", ordered_count})
  end
end

