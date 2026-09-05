-- Functional area extracted from not-alone.lua.

function notalone.on_reverse_selected_area(event)
  order_selected_team_mates(event, false)
end

function notalone.on_alt_reverse_selected_area(event)
  order_selected_team_mates(event, true)
end

function notalone.on_roboport_built(event)
  local entity = event.entity
  if not entity or not entity.valid then
    return
  end
  if entity.type ~= "roboport" then
    return
  end
  if entity.name == LOGISTICS_HUB_NAME and entity.unit_number then
    get_habitat_registry()[entity.unit_number] = entity
  end
  -- New coverage may reveal marked resources to miners still looking for ore.
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.kind == "miner" and not record.miner_state
        and record.entity.valid and record.entity.surface == entity.surface then
        assign_miner_job(record)
      end
    end
  end
end

function notalone.on_script_path_request_finished(event)
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.vehicle_path_request_id == event.id then
        record.vehicle_path_request_id = nil
        if record.vehicle_state ~= "waiting-for-car-path"
          or not event.path or #event.path == 0 then
          abandon_vehicle_travel(record)
        else
          record.vehicle_path = event.path
          record.vehicle_path_index = 1
          record.vehicle_stuck_ticks = 0
          record.vehicle_last_position = nil
          record.vehicle_repath_attempts = 0
          record.vehicle_state = "driving-car"
        end
        return
      end
    end
  end
end

function notalone.on_entity_died(event)
  local entity = event.entity
  if not entity then
    return
  end
  local record = find_vehicle_record(entity.unit_number)
  if record and record.vehicle_entity_unit_number == entity.unit_number then
    -- A destroyed deployed car is lost equipment, not an opportunity to
    -- recreate the item in the teammate's inventory.
    record.vehicle_entity = nil
    record.vehicle_entity_unit_number = nil
    record.vehicle_path = nil
    record.vehicle_path_request_id = nil
    record.vehicle_state = nil
    restore_vehicle_team_mate(record)
  elseif record and record.vehicle_driver_unit_number == entity.unit_number then
    record.vehicle_driver = nil
    record.vehicle_driver_unit_number = nil
    record.vehicle_state = nil
    restore_vehicle_team_mate(record)
  end
  if entity.name == LOGISTICS_HUB_NAME then
    notalone.on_habitat_removed(event)
  end
end

function notalone.on_update(event)
  queue_starter_inventory_migration()
  for player_index in pairs(storage.not_alone_starter_inventory_pending or {}) do
    if ensure_starter_inventory(game.get_player(player_index)) then
      storage.not_alone_starter_inventory_pending[player_index] = nil
    end
  end

  for _, player in pairs(game.connected_players) do
    update_team_mate_panel(player)
  end

  for _, surface in pairs(game.surfaces) do
    cleanup_marked_resources(surface.index)
  end
  for habitat in each_habitat() do
    flush_habitat_crew_records(habitat)
    update_habitat_crew_display(habitat)
    update_building_requesters_for_network(
      habitat.surface,
      habitat.force,
      habitat.position,
      habitat.logistic_network
    )
    -- Deploy scans re-run every role's full job search; back off when a
    -- habitat had nothing to deploy.
    storage.not_alone_habitat_deploy_ticks = storage.not_alone_habitat_deploy_ticks or {}
    local deploy_ticks = storage.not_alone_habitat_deploy_ticks
    if habitat.unit_number and game.tick >= (deploy_ticks[habitat.unit_number] or 0) then
      if auto_deploy_from_habitat(habitat) then
        deploy_ticks[habitat.unit_number] = nil
      else
        deploy_ticks[habitat.unit_number] = game.tick + HABITAT_DEPLOY_RETRY_INTERVAL
      end
    end
  end

  -- Orphans only appear after saves/migrations; a full multi-surface entity
  -- scan every update is wasted work.
  if game.tick >= (storage.not_alone_next_reconcile_tick or 0) then
    storage.not_alone_next_reconcile_tick = game.tick + ORPHAN_RECONCILE_INTERVAL
    reconcile_orphaned_team_mates()
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
      local selected = storage.not_alone_selected_team_mates
        and storage.not_alone_selected_team_mates[player_index]
      if selected and next(selected) then
        local active_ids = {}
        for _, record in pairs(active_team_mates) do
          active_ids[record.entity.unit_number] = true
        end
        for team_mate_id in pairs(selected) do
          if not active_ids[team_mate_id] then
            selected[team_mate_id] = nil
          end
        end
      end
    end
  end
end

-- A Soldier's armor absorbs part of every hit; units cannot wear real armor,
-- so the mitigated fraction is healed straight back.
function notalone.on_entity_damaged(event)
  local entity = event.entity
  if not entity.valid or entity.health <= 0 then
    return
  end
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.entity == entity then
        local armor = record.kind == "soldier" and record.soldier_armor
          and SOLDIER_ARMORS[record.soldier_armor]
        if armor then
          entity.health = entity.health + event.final_damage_amount * armor.mitigation
        end
        return
      end
    end
  end
end

function spawn_crash_ship(surface, area, rng)
  local ship_target = {
    x = area.left_top.x + rng(4, 28),
    y = area.left_top.y + rng(4, 28)
  }
  local position = surface.find_non_colliding_position(CRASH_SHIP_NAME, ship_target, 12, 1)
  if not position then
    return false
  end
  local ship = surface.create_entity({
    name = CRASH_SHIP_NAME,
    position = position,
    force = "neutral"
  })
  if not ship then
    return false
  end
  local inventory = ship.get_inventory(defines.inventory.chest)
  if inventory then
    local crew_counts = {}
    for _ = 1, rng(1, CRASH_SHIP_MAX_CREW) do
      local kind = TEAM_MATE_KINDS[rng(1, #TEAM_MATE_KINDS)]
      crew_counts[kind] = (crew_counts[kind] or 0) + 1
    end
    for kind, count in pairs(crew_counts) do
      inventory.insert({name = ITEM_NAME_BY_KIND[kind], count = count})
    end
  end
  return true
end

-- Other crews crash-landed here too. Seeded purely from the map seed and
-- chunk position so the same map always yields the same wreck field.
function create_seeded_random(seed, chunk_x, chunk_y)
  local modulus = 2147483647
  local state = (seed % modulus
    + (chunk_x + 1048576) * 40093
    + (chunk_y + 1048576) * 92821) % modulus
  if state <= 0 then
    state = 1
  end
  return function(first, last)
    state = (state * 48271) % modulus
    local value = state / modulus
    if first == nil then
      return value
    end
    return math.floor(first + value * (last - first + 1))
  end
end

function get_crash_ship_rate(surface, distance_tiles)
  local starting_radius = surface.get_starting_area_radius()
  if not starting_radius or starting_radius <= 0 then
    return 0
  end
  local visible_radius = starting_radius
  local cutoff_radius = visible_radius * CRASH_SHIP_VISIBLE_RADIUS_MULTIPLIER
  if distance_tiles >= cutoff_radius then
    return 0
  end

  -- Normalize the local rate from the map's starting-area size rather than
  -- using a fixed per-chunk chance.
  local local_area = math.pi * (visible_radius / CHUNK_SIZE) ^ 2
  local local_rate = CRASH_SHIP_LOCAL_TARGET / local_area
  return local_rate * (1 - distance_tiles / cutoff_radius)
end

function notalone.on_chunk_generated(event)
  local surface = event.surface
  if not surface.valid or surface.platform then
    return
  end
  local chunk = event.position
  if (chunk.x == 0 and chunk.y == 0) or not prototypes.entity[CRASH_SHIP_NAME] then
    return
  end
  local seed = surface.map_gen_settings.seed
  local rng = create_seeded_random(seed, chunk.x, chunk.y)
  local spawn = game.forces.player.get_spawn_position(surface)
  local chunk_center = {
    x = event.area.left_top.x + CHUNK_SIZE / 2,
    y = event.area.left_top.y + CHUNK_SIZE / 2
  }
  local distance_tiles = math.sqrt(distance_squared(chunk_center, spawn))
  local chance = get_crash_ship_rate(surface, distance_tiles)
  if rng() >= chance then
    return
  end
  spawn_crash_ship(surface, event.area, rng)
end

-- A removed Habitat drops its docked crew and lockers as real items so
-- nothing is silently lost with the building.
function notalone.on_habitat_removed(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.name ~= LOGISTICS_HUB_NAME
    or not entity.unit_number then
    return
  end
  if storage.not_alone_habitats then
    storage.not_alone_habitats[entity.unit_number] = nil
  end
  local surface = entity.surface
  local position = position_table(entity.position)
  local function spill(item_name, count)
    if count and count > 0 and prototypes.item[item_name] then
      surface.spill_item_stack({
        position = position,
        stack = {name = item_name, count = count}
      })
    end
  end

  local crews = storage.not_alone_habitat_crews
  local crew = crews and crews[entity.unit_number]
  if crew then
    for kind, count in pairs(crew) do
      spill(ITEM_NAME_BY_KIND[kind], count)
    end
    crews[entity.unit_number] = nil
  end

  local lockers = storage.not_alone_soldier_lockers
    and storage.not_alone_soldier_lockers[entity.unit_number]
  if lockers then
    for _, locker in pairs(lockers) do
      for weapon_kind in pairs(locker.weapons or {}) do
        local weapon = SOLDIER_WEAPON_BY_KIND[weapon_kind]
        if weapon then
          spill(weapon.gun, 1)
        end
      end
      for ammo_name, count in pairs(locker.ammo or {}) do
        spill(ammo_name, count)
      end
      if locker.armor and SOLDIER_ARMORS[locker.armor] then
        spill(SOLDIER_ARMORS[locker.armor].item, 1)
      end
    end
    storage.not_alone_soldier_lockers[entity.unit_number] = nil
  end

  local renders = storage.not_alone_habitat_crew_renders
  if renders then
    renders[entity.unit_number] = nil
  end
end

function notalone.register()
  script.on_init(notalone.on_init)
  script.on_configuration_changed(notalone.on_configuration_changed)
  script.on_event(defines.events.on_player_created, notalone.on_player_created)
  script.on_event(defines.events.on_player_removed, notalone.on_player_removed)
  script.on_event(defines.events.on_player_selected_area, notalone.on_selected_area)
  script.on_event(defines.events.on_player_deconstructed_area, notalone.on_deconstructed_area)
  script.on_event(defines.events.on_player_reverse_selected_area, notalone.on_reverse_selected_area)
  script.on_event(
    defines.events.on_player_alt_reverse_selected_area,
    notalone.on_alt_reverse_selected_area
  )
  script.on_event(defines.events.on_gui_opened, notalone.on_gui_opened)
  script.on_event(defines.events.on_gui_closed, notalone.on_gui_closed)
  script.on_event(defines.events.on_built_entity, notalone.on_roboport_built)
  script.on_event(defines.events.on_robot_built_entity, notalone.on_roboport_built)
  script.on_event(defines.events.script_raised_built, notalone.on_roboport_built)
  script.on_event(defines.events.script_raised_revive, notalone.on_roboport_built)
  script.on_event(defines.events.on_chunk_generated, notalone.on_chunk_generated)
  script.on_event(defines.events.on_entity_died, notalone.on_entity_died)
  local habitat_filters = {{filter = "name", name = LOGISTICS_HUB_NAME}}
  script.on_event(defines.events.on_player_mined_entity, notalone.on_habitat_removed, habitat_filters)
  script.on_event(defines.events.on_robot_mined_entity, notalone.on_habitat_removed, habitat_filters)
  local damage_filters = {}
  for _, name in pairs(TEAM_MATE_NAMES) do
    damage_filters[#damage_filters + 1] = {filter = "name", name = name}
  end
  script.on_event(defines.events.on_entity_damaged, notalone.on_entity_damaged, damage_filters)
  script.on_event(defines.events.on_script_path_request_finished, notalone.on_script_path_request_finished)
  script.on_nth_tick(UPDATE_INTERVAL, notalone.on_update)
end
