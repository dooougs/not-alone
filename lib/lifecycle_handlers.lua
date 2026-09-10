-- Functional area extracted from not-alone.lua.

function notalone.on_reverse_selected_area(event)
  if collect_reverse_clicked_team_mate(event) then
    return
  end
  order_selected_team_mates(event, false)
end

function notalone.on_alt_reverse_selected_area(event)
  if collect_reverse_clicked_team_mate(event) then
    return
  end
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
  if entity.unit_number and is_base(entity) then
    register_base(entity)
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
        if record.vehicle_state ~= "waiting-for-car-path" then
          abandon_vehicle_travel(record)
        elseif not event.path or #event.path < 2 then
          -- A one-node path has no forward waypoint. Keep the vehicle parked
          -- and retry after moving obstacles have had time to clear.
          record.vehicle_path_wait_ticks = 0
        else
          record.vehicle_path = event.path
          record.vehicle_path_index = nearest_vehicle_path_index(event.path, record.vehicle_entity)
          record.vehicle_stuck_ticks = 0
          record.vehicle_blocked_ticks = 0
          record.vehicle_last_position = nil
          record.vehicle_patrol_rolling = nil
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
    record.vehicle_path = nil
    record.vehicle_path_request_id = nil
    -- Clearing state here abandoned the driverless car on the ground; let the
    -- recovery state reclaim it into the team mate's inventory instead.
    record.vehicle_state = "recovering-car"
  end
  if is_base(entity) then
    notalone.on_base_removed(event)
  end
end

function notalone.on_update(event)
  for _, player in pairs(game.connected_players) do
    update_team_mate_panel(player)
    update_team_mate_request_gui(player)
  end

  for _, surface in pairs(game.surfaces) do
    cleanup_marked_resources(surface.index)
  end
  for base in each_base() do
    if base.valid then
      if get_base_type(base) == "habitat" then
        flush_habitat_crew_records(base)
        update_habitat_crew_display(base)
        update_building_requesters_for_network(
          base.surface, base.force, base.position, base.logistic_network
        )
      end
      -- Deploy scans re-run every role's full job search; back off when a base
      -- had nothing to deploy.
      storage.not_alone_habitat_deploy_ticks = storage.not_alone_habitat_deploy_ticks or {}
      local deploy_ticks = storage.not_alone_habitat_deploy_ticks
      if base.valid and base.unit_number
        and game.tick >= (deploy_ticks[base.unit_number] or 0) then
        fulfill_base_requests(base)
        if base.valid and auto_deploy_from_base(base) then
          deploy_ticks[base.unit_number] = nil
        elseif base.valid then
          deploy_ticks[base.unit_number] = game.tick + HABITAT_DEPLOY_RETRY_INTERVAL
        end
      end
    end
  end

  -- Orphans only appear after saves/migrations; a full multi-surface entity
  -- scan every update is wasted work.
  if game.tick >= (storage.not_alone_next_reconcile_tick or 0) then
    storage.not_alone_next_reconcile_tick = game.tick + ORPHAN_RECONCILE_INTERVAL
    reconcile_orphaned_team_mates()
  end
  -- Config-change does not fire for code-only updates; repair lazily too.
  repair_manual_loops()


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
  -- A collision means the current plan is wrong: reroute the car, and after
  -- repeated impacts get out and let default travel planning start over.
  -- Collisions accumulate per trip so path resets cannot mask a crash loop.
  local vehicle_profile = vehicle_profile_for_entity(entity.name)
  if vehicle_profile and get_vehicle_behavior(entity.name).ground_collision
    and event.damage_type.name == "impact" then
    local record = find_vehicle_record(entity.unit_number)
    if record and record.vehicle_entity_unit_number == entity.unit_number
      and record.vehicle_state == "driving-car" then
      entity.riding_state = {
        acceleration = defines.riding.acceleration.braking,
        direction = defines.riding.direction.straight
      }
      record.vehicle_collision_count = (record.vehicle_collision_count or 0) + 1
      if record.vehicle_collision_count >= CAR_MAX_COLLISIONS then
        abandon_vehicle_travel(record)
      else
        record.vehicle_stuck_ticks = 0
        record.vehicle_path = nil
        record.vehicle_state = "requesting-car-path"
      end
    end
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

function spawn_crash_ship(surface, area, rng, ship_target)
  ship_target = ship_target or {
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

function get_crash_ship_spawn_positions(surface)
  local positions = {}
  local seen = {}
  for _, force in pairs(game.forces) do
    if force.name ~= "enemy" and force.name ~= "neutral" then
      local position = force.get_spawn_position(surface)
      local key = position.x .. "," .. position.y
      if not seen[key] then
        seen[key] = true
        positions[#positions + 1] = position
      end
    end
  end
  return positions
end

function spawn_initial_crash_ships(surface)
  if surface.platform or not prototypes.entity[CRASH_SHIP_NAME] then
    return
  end
  storage.not_alone_crash_ship_starts = storage.not_alone_crash_ship_starts or {}
  local spawned_starts = storage.not_alone_crash_ship_starts[surface.index] or {}
  storage.not_alone_crash_ship_starts[surface.index] = spawned_starts
  local starting_radius = surface.get_starting_area_radius()
  if not starting_radius or starting_radius <= 0 then
    return
  end
  for _, spawn in pairs(get_crash_ship_spawn_positions(surface)) do
    local key = spawn.x .. "," .. spawn.y
    if not spawned_starts[key] then
      local rng = create_seeded_random(
        surface.map_gen_settings.seed,
        math.floor(spawn.x),
        math.floor(spawn.y)
      )
      local placed = 0
      for _ = 1, 64 do
        if placed >= CRASH_SHIP_LOCAL_TARGET then
          break
        end
        local angle = rng() * math.pi * 2
        local distance = starting_radius + 8 + rng() * starting_radius * 2
        local target = {
          x = spawn.x + math.cos(angle) * distance,
          y = spawn.y + math.sin(angle) * distance
        }
        if spawn_crash_ship(surface, nil, rng, target) then
          placed = placed + 1
        end
      end
      if placed == CRASH_SHIP_LOCAL_TARGET then
        spawned_starts[key] = true
      end
    end
  end
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
  local chunk_center = {
    x = event.area.left_top.x + CHUNK_SIZE / 2,
    y = event.area.left_top.y + CHUNK_SIZE / 2
  }
  local distance_tiles
  for _, spawn in pairs(get_crash_ship_spawn_positions(surface)) do
    local distance = math.sqrt(distance_squared(chunk_center, spawn))
    if not distance_tiles or distance < distance_tiles then
      distance_tiles = distance
    end
  end
  if not distance_tiles then
    return
  end
  local chance = get_crash_ship_rate(surface, distance_tiles)
  if rng() >= chance then
    return
  end
  spawn_crash_ship(surface, event.area, rng)
end

-- A removed Habitat drops its docked crew and lockers as real items so
-- nothing is silently lost with the building.
function notalone.on_base_removed(event)
  local entity = event.entity
  if not entity or not entity.valid or not is_base(entity)
    or not entity.unit_number then
    return
  end
  unregister_base(entity)
  local surface = entity.surface
  local position = position_table(entity.position)
  local function spill(item_name, count, quality)
    if count and count > 0 and prototypes.item[item_name] then
      local stack = {
        name = item_name,
        count = count
      }
      if quality then
        stack.quality = quality
      end
      surface.spill_item_stack({
        position = position,
        stack = stack
      })
    end
  end

  local inventory = get_base_inventory(entity)
  if inventory then
    for _, item in pairs(inventory.get_contents()) do
      spill(item.name, item.count, item.quality)
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

  local lockers = get_base_type(entity) == "habitat"
    and storage.not_alone_soldier_lockers
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

  local docked = storage.not_alone_docked_team_mates
    and storage.not_alone_docked_team_mates[entity.unit_number]
  if docked then
    local function spill_inventory(script_inventory)
      if script_inventory and script_inventory.valid then
        for _, item in pairs(script_inventory.get_contents()) do
          spill(item.name, item.count, item.quality)
        end
        script_inventory.destroy()
      end
    end
    for _, stored in pairs(docked) do
      spill_inventory(stored.builder_cargo)
      spill_inventory(stored.vehicle_inventory)
      spill_inventory(stored.vehicle_fuel_inventory)
      for weapon_kind in pairs(stored.soldier_weapons or {}) do
        local weapon = SOLDIER_WEAPON_BY_KIND[weapon_kind]
        if weapon then
          spill(weapon.gun, 1)
        end
      end
      for ammo_name, count in pairs(stored.soldier_ammo or {}) do
        spill(ammo_name, count)
      end
      if stored.soldier_armor and SOLDIER_ARMORS[stored.soldier_armor] then
        spill(SOLDIER_ARMORS[stored.soldier_armor].item, 1)
      end
    end
    storage.not_alone_docked_team_mates[entity.unit_number] = nil
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
  script.on_event(defines.events.on_player_alt_selected_area, notalone.on_selected_area)
  script.on_event(defines.events.on_player_deconstructed_area, notalone.on_deconstructed_area)
  script.on_event(defines.events.on_player_reverse_selected_area, notalone.on_reverse_selected_area)
  script.on_event(
    defines.events.on_player_alt_reverse_selected_area,
    notalone.on_alt_reverse_selected_area
  )
  script.on_event(defines.events.on_gui_opened, notalone.on_gui_opened)
  script.on_event(defines.events.on_gui_closed, notalone.on_gui_closed)
  script.on_event(defines.events.on_gui_click, notalone.on_gui_click)
  script.on_event(defines.events.on_gui_text_changed, notalone.on_gui_text_changed)
  script.on_event(defines.events.on_built_entity, notalone.on_roboport_built)
  script.on_event(defines.events.on_robot_built_entity, notalone.on_roboport_built)
  script.on_event(defines.events.script_raised_built, notalone.on_roboport_built)
  script.on_event(defines.events.script_raised_revive, notalone.on_roboport_built)
  script.on_event(defines.events.on_chunk_generated, notalone.on_chunk_generated)
  script.on_event(defines.events.on_entity_died, notalone.on_entity_died)
  local base_filters = {
    {filter = "name", name = LOGISTICS_HUB_NAME},
    {filter = "name", name = OUTPOST_NAME}
  }
  script.on_event(defines.events.on_player_mined_entity, notalone.on_base_removed, base_filters)
  script.on_event(defines.events.on_robot_mined_entity, notalone.on_base_removed, base_filters)
  local damage_filters = {}
  for _, name in pairs(TEAM_MATE_NAMES) do
    damage_filters[#damage_filters + 1] = {filter = "name", name = name}
  end
  for _, profile in ipairs(VEHICLE_PROFILES) do
    damage_filters[#damage_filters + 1] = {filter = "name", name = profile.entity_name}
  end
  script.on_event(defines.events.on_entity_damaged, notalone.on_entity_damaged, damage_filters)
  script.on_event(defines.events.on_script_path_request_finished, notalone.on_script_path_request_finished)
  script.on_nth_tick(UPDATE_INTERVAL, notalone.on_update)
end
