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
        restore_docked_team_mate(base, record)
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

