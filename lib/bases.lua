BASE_TYPE_BY_ENTITY_NAME = {
  [LOGISTICS_HUB_NAME] = "habitat",
  [OUTPOST_NAME] = "outpost"
}

BASE_POLICY = {
  habitat = {
    allowed_kinds = TEAM_MATE_KINDS,
    stores_team_mates = true,
    deploys_team_mates = true,
    returns_team_mates = true,
    uses_network_jobs = true,
    uses_soldier_lockers = true
  },
  outpost = {
    allowed_kinds = {"soldier"},
    stores_team_mates = true,
    deploys_team_mates = true,
    returns_team_mates = false,
    uses_network_jobs = false,
    uses_soldier_lockers = false
  }
}

function get_base_type(base)
  return base and BASE_TYPE_BY_ENTITY_NAME[base.name]
end

function get_base_policy(base)
  local base_type = get_base_type(base)
  return base_type and BASE_POLICY[base_type]
end

function is_base(base)
  return base and base.valid and get_base_type(base) ~= nil
end

function get_base_inventory(base)
  return is_base(base)
    and base.get_inventory(defines.inventory.roboport_material)
    or nil
end

function base_allows_kind(base, kind)
  local policy = get_base_policy(base)
  if not policy then
    return false
  end
  for _, allowed_kind in ipairs(policy.allowed_kinds) do
    if allowed_kind == kind then
      return true
    end
  end
  return false
end

function get_base_registry()
  local registry = storage.not_alone_bases
  if not registry then
    registry = {}
    for _, surface in pairs(game.surfaces) do
      for entity_name in pairs(BASE_TYPE_BY_ENTITY_NAME) do
        for _, base in pairs(surface.find_entities_filtered({name = entity_name})) do
          if base.unit_number then
            registry[base.unit_number] = base
          end
        end
      end
    end
    storage.not_alone_bases = registry
  end
  return registry
end

function register_base(base)
  if is_base(base) and base.unit_number then
    get_base_registry()[base.unit_number] = base
  end
end

function unregister_base(base)
  if base and base.unit_number and storage.not_alone_bases then
    storage.not_alone_bases[base.unit_number] = nil
  end
end

function each_base()
  local registry = get_base_registry()
  local key, base
  return function()
    repeat
      key, base = next(registry, key)
      if base and not base.valid then
        registry[key] = nil
        base = nil
      end
    until key == nil or base
    return base
  end
end

function find_nearest_base(record, kind)
  local nearest_base
  local nearest_distance
  for base in each_base() do
    if base.surface == record.entity.surface
      and base.force == record.entity.force
      and (not kind or base_allows_kind(base, kind)) then
      local distance = distance_squared(record.entity.position, base.position)
      if not nearest_distance or distance < nearest_distance then
        nearest_base = base
        nearest_distance = distance
      end
    end
  end
  record.home_base = nearest_base
  record.home_base_type = get_base_type(nearest_base)
  return nearest_base
end

function fulfill_base_requests(base)
  if get_base_type(base) ~= "outpost" then
    return false
  end
  local requests = storage.not_alone_team_mate_requests
    and storage.not_alone_team_mate_requests[base.unit_number]
  local inventory = get_base_inventory(base)
  local network = base.logistic_network
  if not requests or not inventory or not network then
    return false
  end

  local moved = false
  for _, kind in ipairs(get_base_policy(base).allowed_kinds) do
    local item_name = ITEM_NAME_BY_KIND[kind]
    local needed = math.max((requests[kind] or 0) - inventory.get_item_count(item_name), 0)
    if needed > 0 then
      for habitat in each_base() do
        if needed == 0 then
          break
        end
        if get_base_type(habitat) == "habitat"
          and habitat.surface == base.surface
          and habitat.force == base.force
          and habitat.logistic_network == network then
          local source_inventory = get_base_inventory(habitat)
          if source_inventory then
            local removed = source_inventory.remove({name = item_name, count = needed})
            if removed > 0 then
              local inserted = inventory.insert({name = item_name, count = removed})
              if inserted < removed then
                source_inventory.insert({name = item_name, count = removed - inserted})
              end
              needed = needed - inserted
              moved = moved or inserted > 0
            end
          end
        end
      end
    end
  end
  return moved
end

function each_habitat()
  local function habitats()
    for base in each_base() do
      if get_base_type(base) == "habitat" then
        coroutine.yield(base)
      end
    end
  end
  return coroutine.wrap(habitats)
end
