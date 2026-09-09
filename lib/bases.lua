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

function base_contains_position(base, position, padding)
  if not is_base(base) then
    return false
  end
  local box = base.bounding_box
  padding = padding or 2
  return position.x >= box.left_top.x - padding
    and position.x <= box.right_bottom.x + padding
    and position.y >= box.left_top.y - padding
    and position.y <= box.right_bottom.y + padding
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

function count_base_bound_soldiers(base)
  local count = 0
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.kind == "soldier" and record.entity and record.entity.valid then
        if record.home_base == base then
          count = count + 1
        elseif record.pending_home_base == base
          and record.manual_destinations and #record.manual_destinations > 0 then
          count = count + 1
        end
      end
    end
  end
  return count
end

-- Outposts never store deployed Soldiers as items, so their wandering members
-- (and those already walking over) count as virtual inventory.
function get_base_member_count(base, kind)
  local inventory = get_base_inventory(base)
  local count = inventory and inventory.get_item_count(ITEM_NAME_BY_KIND[kind]) or 0
  if kind == "soldier" and get_base_type(base) == "outpost" then
    count = count + count_base_bound_soldiers(base)
  end
  return count
end

local function dispatch_record_to_base(record, base)
  record.home_base = nil
  record.home_base_type = nil
  record.pending_home_base = base
  record.route_rendering_suppressed = true
  destroy_route_renderings(record)
  record.manual_destinations = {{x = base.position.x, y = base.position.y}}
  record.manual_surface_index = base.surface_index
  move_team_mate_toward_destination(record, record.manual_destinations[1])
end

local function deploy_soldier_toward_base(habitat, base)
  local player = find_any_player_for_force(base.force)
  if not player or not player.valid then
    return false
  end
  local inventory = get_base_inventory(habitat)
  local item_name = ITEM_NAME_BY_KIND.soldier
  if not inventory or inventory.get_item_count(item_name) == 0 then
    return false
  end
  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local team_mates = storage.not_alone_team_mates[player.index] or {}
  local record = create_team_mate(player, "soldier", #team_mates + 1, habitat.position)
  if not record then
    return false
  end
  if inventory.remove({name = item_name, count = 1}) ~= 1 then
    record.entity.destroy()
    return false
  end
  local lockers = storage.not_alone_soldier_lockers
    and storage.not_alone_soldier_lockers[habitat.unit_number]
  if lockers and #lockers > 0 then
    local locker = table.remove(lockers)
    record.soldier_weapons = locker.weapons
    record.soldier_ammo = locker.ammo
    record.soldier_armor = locker.armor
  end
  team_mates[#team_mates + 1] = record
  storage.not_alone_team_mates[player.index] = team_mates
  dispatch_record_to_base(record, base)
  return true
end

function fulfill_base_requests(base)
  if get_base_type(base) ~= "outpost" then
    return false
  end
  local requests = storage.not_alone_team_mate_requests
    and storage.not_alone_team_mate_requests[base.unit_number]
  local network = base.logistic_network
  if not requests or not network then
    return false
  end

  local needed = (requests.soldier or 0) - get_base_member_count(base, "soldier")
  local moved = false

  -- Surplus wanderers at other Outposts on the network walk over first.
  if needed > 0 then
    for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
      if needed <= 0 then
        break
      end
      for _, record in pairs(team_mates) do
        if needed <= 0 then
          break
        end
        if record.kind == "soldier" and record.entity and record.entity.valid
          and record.entity.surface == base.surface
          and record.home_base and record.home_base.valid
          and record.home_base ~= base
          and get_base_type(record.home_base) == "outpost"
          and record.home_base.logistic_network == network then
          local source_requests = storage.not_alone_team_mate_requests
            and storage.not_alone_team_mate_requests[record.home_base.unit_number]
          local source_request = (source_requests and source_requests.soldier) or 0
          if get_base_member_count(record.home_base, "soldier") > source_request then
            dispatch_record_to_base(record, base)
            needed = needed - 1
            moved = true
          end
        end
      end
    end
  end

  -- Then stored Soldiers deploy from Habitats and walk over.
  if needed > 0 then
    for habitat in each_base() do
      if needed <= 0 then
        break
      end
      if get_base_type(habitat) == "habitat"
        and habitat.surface == base.surface
        and habitat.force == base.force
        and habitat.logistic_network == network
        and deploy_soldier_toward_base(habitat, base) then
        needed = needed - 1
        moved = true
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
