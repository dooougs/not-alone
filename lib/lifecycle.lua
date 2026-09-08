-- Functional area extracted from not-alone.lua.

function assign_job(record, surface, force, position)
  if record.kind == "miner" then
    return assign_miner_job(record, surface, force, position)
  elseif record.kind == "builder" then
    return assign_builder_job(record, surface, force, position)
  elseif record.kind == "carrier" then
    return assign_carrier_job(record, surface, force, position)
  elseif record.kind == "soldier" then
    local base = record.entity
    local policy = get_base_policy(base)
    if policy and base_allows_kind(base, "soldier")
      and not policy.uses_network_jobs then
      return true
    end
    local lockers = storage.not_alone_soldier_lockers
      and base.unit_number
      and storage.not_alone_soldier_lockers[base.unit_number]
    if not lockers or #lockers == 0 then
      return true
    end
    return assign_soldier_job(record, surface, force, position)
  end
  return false
end

function auto_deploy_from_base(base)
  local player = find_any_player_for_force(base.force)
  local policy = get_base_policy(base)
  if not player or not player.valid or not base.unit_number or not policy
    or not policy.deploys_team_mates then
    return
  end
  local inventory = get_base_inventory(base)
  if not inventory then
    return
  end

  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local deployed = false
  for _, kind in ipairs(policy.allowed_kinds) do
    local item_name = ITEM_NAME_BY_KIND[kind]
    local job = {entity = base, kind = kind}
    if inventory.get_item_count(item_name) > 0
      and assign_job(job, base.surface, base.force, position_table(base.position)) then
      local team_mates = storage.not_alone_team_mates[player.index] or {}
      local record = create_team_mate(player, kind, #team_mates + 1, base.position)
      if record and inventory.remove({name = item_name, count = 1}) == 1 then
        job.entity = nil
        job.kind = nil
        for key, value in pairs(job) do
          record[key] = value
        end
        record.home_base = base
        record.home_base_type = get_base_type(base)
        if inventory.get_item_count(CAR_ITEM_NAME) > 0 then
          local vehicle_inventory = get_vehicle_inventory(record)
          if inventory.remove({name = CAR_ITEM_NAME, count = 1}) == 1
            and vehicle_inventory.insert({name = CAR_ITEM_NAME, count = 1}) ~= 1 then
            inventory.insert({name = CAR_ITEM_NAME, count = 1})
          end
        end
        -- Restore a docked Soldier's stashed weapons and ammo.
        if kind == "soldier" then
          local lockers = storage.not_alone_soldier_lockers
            and storage.not_alone_soldier_lockers[base.unit_number]
          if lockers and #lockers > 0 then
            local locker = table.remove(lockers)
            record.soldier_weapons = locker.weapons
            record.soldier_ammo = locker.ammo
            record.soldier_armor = locker.armor
          end
        end
        team_mates[#team_mates + 1] = record
        storage.not_alone_team_mates[player.index] = team_mates
        deployed = true
      elseif record then
        record.entity.destroy()
      end
    end
  end
  return deployed
end

auto_deploy_from_habitat = auto_deploy_from_base

function configure_freeplay_starter_inventory()
  local freeplay = remote.interfaces.freeplay
  if not freeplay or not freeplay.get_created_items or not freeplay.set_created_items then
    return
  end

  local created_items = remote.call("freeplay", "get_created_items")
  if not created_items then
    return
  end
  -- Saves made before the per-kind items may still list the removed item.
  created_items["not-alone-team-mate"] = nil
  for kind, item_name in pairs(ITEM_NAME_BY_KIND) do
    -- freeplay's insert_safe rejects a count of zero.
    if INITIAL_COUNT_BY_KIND[kind] > 0 then
      created_items[item_name] = INITIAL_COUNT_BY_KIND[kind]
    else
      created_items[item_name] = nil
    end
  end
  created_items[LOGISTICS_HUB_NAME] = INITIAL_HABITAT_COUNT
  remote.call("freeplay", "set_created_items", created_items)
end

