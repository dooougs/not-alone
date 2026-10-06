-- Soldiers pull back to heal and rearm instead of fighting to the death.
-- A badly hurt Soldier, or one whose guns are all dry while the network
-- still has ammo, walks (or drives) to the nearest Habitat or Outpost,
-- heals faster there, restocks, and then picks its route or post back up.
-- Anything attacking the base itself is fought off whatever the health.

local function find_retreat_base(record)
  local entity = record.entity
  local nearest_base
  local nearest_distance
  for base in each_base() do
    if base.surface == entity.surface
      and base.force == entity.force
      and base_allows_kind(base, "soldier") then
      local distance = distance_squared(entity.position, base.position)
      if not nearest_distance or distance < nearest_distance then
        nearest_base = base
        nearest_distance = distance
      end
    end
  end
  return nearest_base
end

local function at_base(record, base)
  return base_contains_position(base, record.entity.position, SOLDIER_RETREAT_ARRIVAL_DISTANCE)
end

local function owns_a_gun(record)
  for weapon_kind in pairs(record.soldier_weapons or {}) do
    if SOLDIER_WEAPON_BY_KIND[weapon_kind] then
      return true
    end
  end
  return false
end

local function out_of_ammo(record)
  return owns_a_gun(record) and not select_soldier_weapon(record)
end

local function soldier_should_retreat(record)
  if record.entity.get_health_ratio() < SOLDIER_RETREAT_HEALTH then
    return true
  end
  -- Only walk back for ammo the network can actually supply; with none
  -- anywhere, staying put and punching is all a Soldier can do.
  return not record.soldier_state and out_of_ammo(record)
    and find_soldier_ammo_source(record) ~= nil
end

function end_soldier_retreat(record)
  record.soldier_retreat = nil
  record.soldier_retreat_base = nil
  -- A finished move must not count as reaching the next manual waypoint.
  record.command_kind = nil
  record.command_destination = nil
  record.command_target = nil
end

-- Returns true while the retreat owns the Soldier this update.
function update_soldier_retreat(record)
  local entity = record.entity
  if not record.soldier_retreat then
    if game.tick < (record.soldier_retreat_check_tick or 0) then
      return false
    end
    record.soldier_retreat_check_tick = game.tick + SOLDIER_RETREAT_CHECK_INTERVAL
    if not soldier_should_retreat(record) then
      return false
    end
    local base = find_retreat_base(record)
    if not base then
      return false
    end
    record.soldier_retreat_base = base
    record.soldier_retreat = at_base(record, base) and "recovering" or "moving"
  end

  local base = record.soldier_retreat_base
  if not base or not base.valid then
    base = find_retreat_base(record)
    if not base then
      end_soldier_retreat(record)
      return false
    end
    record.soldier_retreat_base = base
  end

  if record.soldier_retreat == "moving" then
    if not at_base(record, base) then
      move_team_mate(record, position_table(base.position), SOLDIER_RETREAT_ARRIVAL_DISTANCE)
      return true
    end
    record.soldier_retreat = "recovering"
    stop_team_mate(record)
  end

  -- Recovering at the base: defend it if anything comes close.
  if find_soldier_immediate_target(record) then
    end_soldier_retreat(record)
    return false
  end
  if entity.health < entity.max_health then
    entity.health = entity.health + SOLDIER_RETREAT_HEAL_PER_TICK * UPDATE_INTERVAL
  end
  if out_of_ammo(record) and not record.soldier_state then
    start_soldier_restock(record)
  end
  -- Restock trips to the base's chests run as usual; other errands wait.
  if record.soldier_state == "restock" then
    update_soldier(record)
    return true
  end
  if entity.get_health_ratio() >= SOLDIER_RETREAT_RESUME_HEALTH then
    end_soldier_retreat(record)
    return false
  end
  stop_team_mate(record)
  return true
end
