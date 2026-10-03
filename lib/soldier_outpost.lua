-- Outpost duty: Soldiers stationed at an Outpost build the defenses
-- ghosted around it (turrets, walls, gates) and keep its ammo turrets fed,
-- using items from the Outpost's logistic network.

local function outpost_claims()
  storage.not_alone_outpost_claims = storage.not_alone_outpost_claims or {}
  return storage.not_alone_outpost_claims
end

local function claim_is_live(record, claim, target)
  return claim and claim.record ~= record
    and claim.record.entity and claim.record.entity.valid
    and claim.record.soldier_outpost_target == target
    and game.tick - claim.tick < OUTPOST_CLAIM_TICKS
end

local function target_is_claimed(record, target)
  return claim_is_live(record, outpost_claims()[target.unit_number], target)
end

local function claim_target(record, target)
  if target_is_claimed(record, target) then
    return false
  end
  outpost_claims()[target.unit_number] = {record = record, tick = game.tick}
  record.soldier_outpost_target = target
  record.soldier_outpost_target_id = target.unit_number
  return true
end

local function release_target(record)
  local claims = outpost_claims()
  local id = record.soldier_outpost_target_id
  if id and claims[id] and claims[id].record == record then
    claims[id] = nil
  end
  record.soldier_outpost_target = nil
  record.soldier_outpost_target_id = nil
end

function soldier_outpost_cargo_stacks(record)
  local cargo = record.soldier_outpost_cargo
  if cargo and cargo.count and cargo.count > 0 and prototypes.item[cargo.name] then
    return {{name = cargo.name, quality = cargo.quality, count = cargo.count}}
  end
  return {}
end

function clear_soldier_outpost_duty(record)
  release_target(record)
  record.soldier_outpost_cargo = nil
  record.soldier_outpost_source = nil
  record.soldier_outpost_attempts = nil
  if record.soldier_state == "outpost-fetch"
    or record.soldier_state == "outpost-deliver"
    or record.soldier_state == "outpost-return" then
    record.soldier_state = nil
  end
end

-- Ammo names in the order Soldiers rank them, best first, then any other
-- ammo the game knows about.
local ranked_ammo_cache
local function ranked_ammo_names()
  if ranked_ammo_cache then
    return ranked_ammo_cache
  end
  local names = {}
  local seen = {}
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    for _, ammo_name in ipairs(SOLDIER_WEAPONS[rank].ammo) do
      if not seen[ammo_name] then
        seen[ammo_name] = true
        names[#names + 1] = ammo_name
      end
    end
  end
  local others = {}
  for name in pairs(prototypes.get_item_filtered({{filter = "type", type = "ammo"}})) do
    if not seen[name] then
      others[#others + 1] = name
    end
  end
  table.sort(others)
  for _, name in ipairs(others) do
    names[#names + 1] = name
  end
  ranked_ammo_cache = names
  return names
end

local function turret_ammo_inventory(turret)
  return turret.valid and turret.get_inventory(defines.inventory.turret_ammo) or nil
end

local function turret_accepts(turret, inventory, ammo_name)
  local prototype = prototypes.item[ammo_name]
  local params = turret.prototype.attack_parameters
  if not prototype or not prototype.ammo_category or not params then
    return false
  end
  local category = prototype.ammo_category.name
  local accepted = false
  for _, name in pairs(params.ammo_categories or {}) do
    if name == category then
      accepted = true
    end
  end
  return accepted and inventory.can_insert({name = ammo_name, count = 1})
end

local function start_fetch(record, source, item, count, target, purpose)
  if not claim_target(record, target) then
    return false
  end
  record.soldier_state = "outpost-fetch"
  record.soldier_outpost_source = source
  record.soldier_outpost_cargo = {
    name = item.name,
    quality = item.quality,
    count = 0,
    wanted = count,
    purpose = purpose
  }
  return true
end

local function try_outpost_build(record, outpost)
  local entity = record.entity
  local ghosts = entity.surface.find_entities_filtered({
    type = "entity-ghost",
    ghost_type = OUTPOST_DEFENSE_TYPES,
    force = entity.force,
    position = outpost.position,
    radius = OUTPOST_DEFENSE_RADIUS
  })
  table.sort(ghosts, function(a, b)
    return distance_squared(entity.position, a.position)
      < distance_squared(entity.position, b.position)
  end)
  for _, ghost in ipairs(ghosts) do
    if ghost.valid and not target_is_claimed(record, ghost)
      and not builder_target_is_claimed(ghost, record) then
      local item = get_ghost_item(ghost)
      local source = item and find_logistics_item_source(record, item.name)
      local inventory = source and get_logistics_source_inventory(source)
      if inventory and inventory.get_item_count({name = item.name, quality = item.quality}) > 0
        and start_fetch(record, source, item, 1, ghost, "build") then
        return true
      end
    end
  end
  return false
end

local function try_outpost_supply(record, outpost)
  local entity = record.entity
  for _, turret in pairs(entity.surface.find_entities_filtered({
    type = "ammo-turret",
    force = entity.force,
    position = outpost.position,
    radius = OUTPOST_DEFENSE_RADIUS
  })) do
    local inventory = turret_ammo_inventory(turret)
    if inventory and inventory.get_item_count() < OUTPOST_TURRET_AMMO_LOW
      and not target_is_claimed(record, turret) then
      -- Stay with the ammo already loaded; otherwise the best ammo stocked.
      local loaded = not inventory.is_empty() and inventory[1].valid_for_read
        and inventory[1].name
      local candidates = loaded and {loaded} or ranked_ammo_names()
      for _, ammo_name in ipairs(candidates) do
        if turret_accepts(turret, inventory, ammo_name) then
          local source = find_logistics_item_source(record, ammo_name)
          if source and start_fetch(record, source, {name = ammo_name, quality = "normal"},
            OUTPOST_TURRET_AMMO_FILL, turret, "supply") then
            return true
          end
        end
      end
    end
  end
  return false
end

-- Called for idle Outpost Soldiers; true when a duty was started.
function try_soldier_outpost_duty(record)
  local outpost = record.home_base
  if record.home_base_type ~= "outpost" or not outpost or not outpost.valid then
    return false
  end
  if game.tick < (record.next_outpost_duty_tick or 0) then
    return false
  end
  record.next_outpost_duty_tick = game.tick + IDLE_JOB_SEARCH_INTERVAL
  return try_outpost_build(record, outpost) or try_outpost_supply(record, outpost)
end

local function start_return(record)
  release_target(record)
  local cargo = record.soldier_outpost_cargo
  if not cargo or (cargo.count or 0) <= 0 then
    clear_soldier_outpost_duty(record)
    return
  end
  record.soldier_state = "outpost-return"
  record.soldier_outpost_source = find_logistics_return_source(record, cargo.name)
  if not record.soldier_outpost_source then
    -- Nowhere to put it: leave it on the ground for the network to collect.
    record.entity.surface.spill_item_stack({
      position = record.entity.position,
      stack = {name = cargo.name, quality = cargo.quality, count = cargo.count},
      enable_looted = true,
      force = record.entity.force,
      allow_belts = false
    })
    clear_soldier_outpost_duty(record)
  end
end

local function update_fetch(record)
  local source = record.soldier_outpost_source
  local cargo = record.soldier_outpost_cargo
  local target = record.soldier_outpost_target
  local inventory = source and source.valid and get_logistics_source_inventory(source)
  if not cargo or not target or not target.valid or not inventory then
    clear_soldier_outpost_duty(record)
    return
  end
  if distance_squared(record.entity.position, source.position) > 4 then
    move_team_mate(record, position_table(source.position), 2)
    return
  end
  local removed = inventory.remove({
    name = cargo.name,
    quality = cargo.quality,
    count = cargo.wanted
  })
  stop_team_mate(record)
  if removed <= 0 then
    clear_soldier_outpost_duty(record)
    return
  end
  cargo.count = removed
  record.soldier_outpost_source = nil
  record.soldier_state = "outpost-deliver"
end

local function update_deliver(record)
  local cargo = record.soldier_outpost_cargo
  local target = record.soldier_outpost_target
  if not cargo or not target or not target.valid then
    start_return(record)
    return
  end
  local reach = OUTPOST_DUTY_REACH
  if distance_squared_to_box(record.entity.position, target.bounding_box) > reach * reach then
    move_team_mate(record, position_table(target.position), reach)
    return
  end
  if cargo.purpose == "build" then
    local _, revived = target.revive({raise_revive = true})
    if revived then
      progress_trigger_research(record.entity.force, "build-entity", revived.name, 1)
      cargo.count = cargo.count - 1
      release_target(record)
      stop_team_mate(record)
      start_return(record)
      return
    end
    -- Blocked, usually by this Soldier standing in the footprint.
    record.soldier_outpost_attempts = (record.soldier_outpost_attempts or 0) + 1
    if record.soldier_outpost_attempts > OUTPOST_BUILD_ATTEMPTS then
      start_return(record)
    else
      move_team_mate(record, builder_ghost_standing_position(record, target), 0.2)
    end
    return
  end
  local inventory = turret_ammo_inventory(target)
  local inserted = inventory and inventory.insert({
    name = cargo.name,
    quality = cargo.quality,
    count = cargo.count
  }) or 0
  cargo.count = cargo.count - inserted
  stop_team_mate(record)
  start_return(record)
end

local function update_return(record)
  local cargo = record.soldier_outpost_cargo
  local source = record.soldier_outpost_source
  local inventory = source and source.valid and get_logistics_source_inventory(source)
  if not cargo or cargo.count <= 0 then
    clear_soldier_outpost_duty(record)
    return
  end
  if not inventory then
    start_return(record)
    return
  end
  if distance_squared(record.entity.position, source.position) > 4 then
    move_team_mate(record, position_table(source.position), 2)
    return
  end
  local inserted = inventory.insert({name = cargo.name, quality = cargo.quality, count = cargo.count})
  cargo.count = cargo.count - inserted
  stop_team_mate(record)
  if cargo.count > 0 then
    start_return(record)
  else
    clear_soldier_outpost_duty(record)
  end
end

-- Returns true when the Soldier is busy with an Outpost duty state.
function update_soldier_outpost_duty(record)
  local state = record.soldier_state
  if state == "outpost-fetch" then
    update_fetch(record)
  elseif state == "outpost-deliver" then
    update_deliver(record)
  elseif state == "outpost-return" then
    update_return(record)
  else
    return false
  end
  return true
end
