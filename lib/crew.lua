-- Functional area extracted from not-alone.lua.

function store_docked_team_mate(base, record)
  if not base or not base.valid or not base.unit_number then
    return false
  end
  storage.not_alone_docked_team_mates = storage.not_alone_docked_team_mates or {}
  local docked = storage.not_alone_docked_team_mates[base.unit_number] or {}
  docked[#docked + 1] = {
    kind = record.kind,
    builder_cargo = record.builder_cargo,
    vehicle_inventory = record.vehicle_inventory,
    vehicle_fuel_inventory = record.vehicle_fuel_inventory,
    vehicle_ammo_inventory = record.vehicle_ammo_inventory,
    soldier_weapons = record.soldier_weapons,
    soldier_ammo = record.soldier_ammo,
    soldier_armor = record.soldier_armor,
    carried_count = record.carried_count,
    mining_resource_info = record.mining_resource_info
  }
  storage.not_alone_docked_team_mates[base.unit_number] = docked
  return true
end

function restore_docked_team_mate(base, record)
  local docked = base and base.unit_number
    and storage.not_alone_docked_team_mates
    and storage.not_alone_docked_team_mates[base.unit_number]
  if docked then
    for index, stored in ipairs(docked) do
      if stored.kind == record.kind then
        record.builder_cargo = stored.builder_cargo
        record.vehicle_inventory = stored.vehicle_inventory
        record.vehicle_fuel_inventory = stored.vehicle_fuel_inventory
        record.vehicle_ammo_inventory = stored.vehicle_ammo_inventory
        record.soldier_weapons = stored.soldier_weapons
        record.soldier_ammo = stored.soldier_ammo
        record.soldier_armor = stored.soldier_armor
        record.carried_count = stored.carried_count
        record.mining_resource_info = stored.mining_resource_info
        table.remove(docked, index)
        if #docked == 0 then
          storage.not_alone_docked_team_mates[base.unit_number] = nil
        end
        return true
      end
    end
  end
  -- Compatibility with Soldiers docked before per-team-mate records.
  local lockers = base and base.unit_number and storage.not_alone_soldier_lockers
    and storage.not_alone_soldier_lockers[base.unit_number]
  if record.kind == "soldier" and lockers and #lockers > 0 then
    local locker = table.remove(lockers)
    record.soldier_weapons = locker.weapons
    record.soldier_ammo = locker.ammo
    record.soldier_armor = locker.armor
    return true
  end
  return false
end

function create_team_mate(player, kind, index, spawn_center)
  -- Units do not collide with each other, so find_non_colliding_position
  -- returns the same spot for every spawn; ring offsets keep them apart
  -- because perfectly co-located units cannot be separated by the engine.
  local center = spawn_center or player.position
  local angle = index * 2.39996
  local ring_center = {
    x = center.x + math.cos(angle) * 3,
    y = center.y + math.sin(angle) * 3
  }
  local spawn_position = player.surface.find_non_colliding_position(
    TEAM_MATE_NAME,
    ring_center,
    8,
    0.5
  )
  if not spawn_position then
    return nil
  end

  local entity_name = TEAM_MATE_ENTITY_BY_KIND[kind]
  if kind == "soldier" then
    entity_name = "not-alone-team-mate-handgun"
  end
  local character = player.surface.create_entity({
    name = entity_name or TEAM_MATE_NAME,
    position = spawn_position,
    force = player.force,
    create_build_effect_smoke = false
  })
  if not character then
    return nil
  end

  character.name_tag = (KIND_LABEL[kind] or "Team mate") .. " " .. index
  local record = {entity = character, kind = kind}
  if kind == "soldier" then
    record.soldier_weapons = {handgun = true}
    record.soldier_ammo = {['firearm-magazine'] = 10}
  end
  find_nearest_habitat(record)
  return record
end

function find_any_player_for_force(force)
  if force.connected_players and force.connected_players[1] then
    return force.connected_players[1]
  end
  return force.players and force.players[1]
end

-- A save/load or migration desync can leave a real team mate entity in the
-- world with no matching record in storage; since update_team_mate only ever
-- runs for tracked records, an orphan would otherwise sit frozen forever
-- (e.g. a Miner stuck holding a full load it can never deliver). Re-adopt any
-- such entity so it resumes normal behavior instead of staying stranded.
-- Death drops everything where the team mate fell so squad mates can
-- reclaim the gear, cargo, and vehicle from the ground.
function spill_team_mate_loot(record, surface, position)
  local function spill(item_name, count)
    if item_name and count and count > 0 and prototypes.item[item_name] then
      surface.spill_item_stack({
        position = position,
        stack = {name = item_name, count = count}
      })
    end
  end
  for _, inventory_name in ipairs({"builder_cargo", "vehicle_inventory",
    "vehicle_fuel_inventory", "vehicle_ammo_inventory"}) do
    local inventory = record[inventory_name]
    if inventory and inventory.valid then
      if not inventory.is_empty() then
        surface.spill_inventory({position = position, inventory = inventory})
      end
      inventory.destroy()
    end
    record[inventory_name] = nil
  end
  for weapon_kind in pairs(record.soldier_weapons or {}) do
    local weapon = SOLDIER_WEAPON_BY_KIND[weapon_kind]
    if weapon then
      spill(weapon.gun, 1)
    end
  end
  for ammo_name, count in pairs(record.soldier_ammo or {}) do
    spill(ammo_name, count)
  end
  if record.soldier_armor and SOLDIER_ARMORS[record.soldier_armor] then
    spill(SOLDIER_ARMORS[record.soldier_armor].item, 1)
  end
  record.soldier_weapons = nil
  record.soldier_ammo = nil
  record.soldier_armor = nil
  local vehicle = record.vehicle_entity
  if vehicle and vehicle.valid then
    spill(record.vehicle_item_name or vehicle.name, 1)
    for _, inventory in pairs({
      vehicle.get_fuel_inventory(),
      get_vehicle_entity_ammo_inventory(vehicle)
    }) do
      if inventory and not inventory.is_empty() then
        surface.spill_inventory({position = position, inventory = inventory})
      end
    end
    vehicle.destroy()
  end
  record.vehicle_entity = nil
  record.vehicle_entity_unit_number = nil
end

function reconcile_orphaned_team_mates()
  local tracked = {}
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.entity and record.entity.valid then
        tracked[record.entity.unit_number] = true
      end
    end
  end

  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({name = TEAM_MATE_NAMES})) do
      if entity.valid and not tracked[entity.unit_number] then
        local player = find_any_player_for_force(entity.force)
        if player and player.valid then
          local kind = KIND_BY_ENTITY_NAME[entity.name]
          if not kind then
            local label = entity.name_tag and entity.name_tag:match("^(%a+)")
            kind = (label and KIND_BY_LABEL[label]) or "soldier"
          end
          local record = {entity = entity, kind = kind}
          find_nearest_habitat(record)
          storage.not_alone_team_mates = storage.not_alone_team_mates or {}
          local team_mates = storage.not_alone_team_mates[player.index] or {}
          team_mates[#team_mates + 1] = record
          storage.not_alone_team_mates[player.index] = team_mates
          tracked[entity.unit_number] = true
        end
      end
    end
  end
end

-- Mirrors how logistic robots resolve a delivery: find any network item with
-- an unmet requester demand, then find the nearest chest currently holding it.
