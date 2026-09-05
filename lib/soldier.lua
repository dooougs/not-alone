-- Functional area extracted from poc.lua.

function find_soldier_ammo_source(record, only_empty)
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if record.soldier_weapons and record.soldier_weapons[weapon.kind]
      and (not only_empty or get_soldier_ammo_count(record, weapon) == 0) then
      for _, ammo_name in ipairs(weapon.ammo) do
        if prototypes.item[ammo_name] then
          local source = find_logistics_item_source(record, ammo_name)
          if source then
            return source, ammo_name
          end
        end
      end
    end
  end
  return nil
end

function find_soldier_weapon_source(record, weapon)
  if not prototypes.item[weapon.gun] then
    return nil
  end
  local source = find_logistics_item_source(record, weapon.gun)
  if source then
    return source, weapon.gun
  end
  return nil
end

function assign_soldier_job(record, surface, force, position)
  -- Even an unarmed Soldier will deploy and punch.
  if find_soldier_target(record, surface, force, position) then
    return true
  end
  -- No enemies in range: still deploy when there is gear worth collecting.
  -- Pre-deploy records own nothing yet, so peek at the Habitat locker the
  -- deployed Soldier would inherit.
  local locker
  local habitat = record.entity
  if habitat and habitat.unit_number and storage.not_alone_soldier_lockers then
    local lockers = storage.not_alone_soldier_lockers[habitat.unit_number]
    locker = lockers and lockers[#lockers]
  end
  local owned_weapons = record.soldier_weapons or (locker and locker.weapons)
  local owned_armor = record.soldier_armor or (locker and locker.armor)
  local owned_ammo = record.soldier_ammo or (locker and locker.ammo)
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if not (owned_weapons and owned_weapons[weapon.kind])
      and find_soldier_weapon_source(record, weapon) then
      return true
    end
  end
  for tier = #SOLDIER_ARMORS, (owned_armor or 0) + 1, -1 do
    local armor = SOLDIER_ARMORS[tier]
    if prototypes.item[armor.item] and find_logistics_item_source(record, armor.item) then
      return true
    end
  end
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if owned_weapons and owned_weapons[weapon.kind] then
      local total = 0
      for _, ammo_name in pairs(weapon.ammo) do
        total = total + ((owned_ammo and owned_ammo[ammo_name]) or 0)
      end
      if total == 0 then
        for _, ammo_name in ipairs(weapon.ammo) do
          if prototypes.item[ammo_name] and find_logistics_item_source(record, ammo_name) then
            return true
          end
        end
      end
    end
  end
  return false
end

-- Prevents multiple Soldiers from all committing to the same scarce weapon,
-- armor, or ammo stack; mirrors the carrier request reservation pattern.
-- Attached to the existing `poc` table (rather than a new local) since the
-- main chunk is already at Lua's 200 local variable limit.
function poc._reserve_soldier_pickup(record, source, item_name)
  if not source or not source.valid or not item_name then
    return false
  end
  local key = tostring(source.unit_number) .. ":" .. item_name
  storage.not_alone_soldier_pickups = storage.not_alone_soldier_pickups or {}
  local existing = storage.not_alone_soldier_pickups[key]
  if existing and existing.record ~= record and game.tick - existing.tick < 300 then
    return false
  end
  storage.not_alone_soldier_pickups[key] = {record = record, tick = game.tick}
  record.soldier_reservation_key = key
  return true
end

function poc._clear_soldier_pickup(record)
  if not record or not record.soldier_reservation_key then
    return
  end
  storage.not_alone_soldier_pickups = storage.not_alone_soldier_pickups or {}
  local existing = storage.not_alone_soldier_pickups[record.soldier_reservation_key]
  if existing and existing.record == record then
    storage.not_alone_soldier_pickups[record.soldier_reservation_key] = nil
  end
  record.soldier_reservation_key = nil
end

function try_soldier_weapon_pickup(record)
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if not (record.soldier_weapons and record.soldier_weapons[weapon.kind]) then
      local source, item_name = find_soldier_weapon_source(record, weapon)
      if source and poc._reserve_soldier_pickup(record, source, item_name) then
        record.soldier_state = "pickup-weapon"
        record.soldier_pickup_kind = weapon.kind
        record.soldier_pickup_item = item_name
        record.soldier_pickup_source = source
        return true
      end
    end
  end
  return false
end

function try_soldier_armor_pickup(record)
  for tier = #SOLDIER_ARMORS, (record.soldier_armor or 0) + 1, -1 do
    local armor = SOLDIER_ARMORS[tier]
    if prototypes.item[armor.item] then
      local source = find_logistics_item_source(record, armor.item)
      if source and poc._reserve_soldier_pickup(record, source, armor.item) then
        record.soldier_state = "pickup-armor"
        record.soldier_pickup_armor = tier
        record.soldier_pickup_source = source
        return true
      end
    end
  end
  return false
end

function start_soldier_restock(record, only_empty)
  local source, ammo_name = find_soldier_ammo_source(record, only_empty)
  if not source or not poc._reserve_soldier_pickup(record, source, ammo_name) then
    return false
  end
  record.soldier_state = "restock"
  record.soldier_ammo_source = source
  record.soldier_restock_name = ammo_name
  return true
end

function soldier_needs_ammo(record)
  for _, weapon in ipairs(SOLDIER_WEAPONS) do
    if record.soldier_weapons and record.soldier_weapons[weapon.kind]
      and get_soldier_ammo_count(record, weapon) == 0 then
      return true
    end
  end
  return false
end

function update_soldier(record)
  if record.soldier_state == "restock" then
    local source = record.soldier_ammo_source
    local inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not inventory
      or inventory.get_item_count(record.soldier_restock_name) == 0 then
      record.soldier_state = nil
      record.soldier_ammo_source = nil
      record.soldier_restock_name = nil
      poc._clear_soldier_pickup(record)
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      local removed = inventory.remove({
        name = record.soldier_restock_name,
        count = SOLDIER_AMMO_RESTOCK_COUNT
      })
      if removed > 0 then
        record.soldier_ammo = record.soldier_ammo or {}
        record.soldier_ammo[record.soldier_restock_name] =
          (record.soldier_ammo[record.soldier_restock_name] or 0) + removed
      end
      record.soldier_state = nil
      record.soldier_ammo_source = nil
      record.soldier_restock_name = nil
      poc._clear_soldier_pickup(record)
      stop_team_mate(record)
    else
      move_team_mate(record, source.position, 2)
    end
    return true
  end

  if record.soldier_state == "pickup-weapon" then
    local source = record.soldier_pickup_source
    local weapon = SOLDIER_WEAPON_BY_KIND[record.soldier_pickup_kind]
    local pickup_item = record.soldier_pickup_item or (weapon and weapon.gun)
    local inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not inventory or not weapon
      or inventory.get_item_count(pickup_item) == 0 then
      record.soldier_state = nil
      record.soldier_pickup_source = nil
      record.soldier_pickup_kind = nil
      record.soldier_pickup_item = nil
      poc._clear_soldier_pickup(record)
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      if inventory.remove({name = pickup_item, count = 1}) == 1 then
        record.soldier_weapons = record.soldier_weapons or {}
        record.soldier_weapons[weapon.kind] = true
      end
      record.soldier_state = nil
      record.soldier_pickup_source = nil
      record.soldier_pickup_kind = nil
      record.soldier_pickup_item = nil
      poc._clear_soldier_pickup(record)
      stop_team_mate(record)
    else
      move_team_mate(record, source.position, 2)
    end
    return true
  end

  if record.soldier_state == "pickup-armor" then
    local source = record.soldier_pickup_source
    local armor = SOLDIER_ARMORS[record.soldier_pickup_armor]
    local inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not inventory or not armor
      or inventory.get_item_count(armor.item) == 0 then
      record.soldier_state = nil
      record.soldier_pickup_source = nil
      record.soldier_pickup_armor = nil
      poc._clear_soldier_pickup(record)
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      if inventory.remove({name = armor.item, count = 1}) == 1 then
        -- Trade in the old suit so it goes back to the network.
        local old_armor = record.soldier_armor and SOLDIER_ARMORS[record.soldier_armor]
        if old_armor then
          inventory.insert({name = old_armor.item, count = 1})
        end
        record.soldier_armor = record.soldier_pickup_armor
      end
      record.soldier_state = nil
      record.soldier_pickup_source = nil
      record.soldier_pickup_armor = nil
      poc._clear_soldier_pickup(record)
      stop_team_mate(record)
    else
      move_team_mate(record, source.position, 2)
    end
    return true
  end

  local target
  local active_target = record.command_kind == "attack"
    and record.command_target and record.command_target.valid
  if active_target then
    -- Keep pursuing a target found inside the network while closing on it.
    target = record.command_target
  else
    -- Prepare before choosing a target: weapons first, then ammunition. This
    -- prevents a newly deployed Soldier from fighting with fists while gear
    -- is waiting in logistics storage. The full gear and network scan is
    -- expensive, so idle Soldiers repeat it on a cooldown.
    if game.tick >= (record.next_job_search_tick or 0) then
      if try_soldier_weapon_pickup(record) then
        record.next_job_search_tick = nil
        record.idle_search_failures = nil
        return true
      end
      if soldier_needs_ammo(record) and start_soldier_restock(record, true) then
        record.next_job_search_tick = nil
        record.idle_search_failures = nil
        return true
      end
      if try_soldier_armor_pickup(record) then
        record.next_job_search_tick = nil
        record.idle_search_failures = nil
        return true
      end
      target = find_soldier_target(record)
      if not target then
        record.next_job_search_tick = game.tick + IDLE_JOB_SEARCH_INTERVAL
        record.idle_search_failures = (record.idle_search_failures or 0) + 1
      else
        record.idle_search_failures = nil
      end
    end
    -- Point-blank threats are engine-indexed and cheap: always check.
    if not target then
      local nearby = record.entity.surface.find_nearest_enemy({
        position = record.entity.position,
        max_distance = ENGAGEMENT_RADIUS,
        force = record.entity.force
      })
      if nearby and nearby.valid then
        target = nearby
      end
    end
  end

  -- Keep the body in sync with the gear so a mech-armored Soldier hovers
  -- even while idle.
  if not ensure_soldier_entity(record, select_soldier_weapon(record)) then
    return true
  end

  if target then
    local weapon = select_soldier_weapon(record)
    -- Out of ammo for every owned weapon: rearm if the network has any;
    -- only fight bare-handed when no ammo can be had anywhere.
    if not weapon and start_soldier_restock(record) then
      return true
    end
    if not ensure_soldier_entity(record, weapon) then
      return true
    end
    attack_with_team_mate(record, target)
    -- Fighting burns ammo over time; the engine cannot report each shot.
    -- Only count rounds while actually in firing range - the march to a
    -- distant battle must not drain the magazine before arrival.
    if weapon and game.tick >= (record.soldier_next_ammo_tick or 0) then
      local params = record.entity.prototype.attack_parameters
      local firing_range = ((params and params.range) or ENGAGEMENT_RADIUS) + 2
      if target.valid
        and distance_squared(record.entity.position, target.position)
          <= firing_range * firing_range then
        consume_soldier_ammo(record, weapon)
        record.soldier_next_ammo_tick = game.tick + SOLDIER_AMMO_TICKS_PER_ROUND
      end
    end
    return true
  end

  -- No target and no preparation work: return to the Habitat, but only
  -- once a sustained drought confirms there is nothing left to do nearby.
  if not select_soldier_weapon(record)
    and game.tick >= (record.next_job_search_tick or 0)
    and start_soldier_restock(record) then
    return true
  end
  if (record.idle_search_failures or 0) < IDLE_DOCK_AFTER_FAILURES then
    stop_team_mate(record)
    return true
  end
  return dock_at_habitat(record)
end

