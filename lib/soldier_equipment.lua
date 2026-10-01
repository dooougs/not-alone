-- Soldier armor equipment: the modular armors' equipment grids filled the way
-- a player would fill them. Soldiers are units, not characters, so the grid is
-- simulated: equipment is read from the runtime prototypes (vanilla, Space Age,
-- and any modded equipment of a supported type), packed into the worn armor's
-- real grid shape, and its effects (power, shields, legs, personal lasers,
-- discharge defense, and personal roboports with repair bots) are applied by
-- script each update.

local catalog_cache
local grid_cache = {}
local stats_cache = setmetatable({}, {__mode = "k"})

local function safe(getter)
  local ok, value = pcall(getter)
  if ok then
    return value
  end
  return nil
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

-- Each equipment type maps onto the role a player slots it for.
local EQUIPMENT_ROLE_BY_TYPE = {
  ["generator-equipment"] = "generation",
  ["solar-panel-equipment"] = "generation",
  ["battery-equipment"] = "battery",
  ["energy-shield-equipment"] = "shield",
  ["movement-bonus-equipment"] = "legs",
  ["roboport-equipment"] = "roboport",
  ["night-vision-equipment"] = "misc",
  ["belt-immunity-equipment"] = "misc",
  ["inventory-bonus-equipment"] = "misc"
}

local function equipment_cells(shape)
  local cells = {}
  if shape.points and #shape.points > 0 then
    for _, point in pairs(shape.points) do
      cells[#cells + 1] = {x = point.x or point[1], y = point.y or point[2]}
    end
  else
    for y = 0, shape.height - 1 do
      for x = 0, shape.width - 1 do
        cells[#cells + 1] = {x = x, y = y}
      end
    end
  end
  return cells
end

-- Finds the beam and area radius inside an active defense's ammo action.
local function describe_defense_action(ammo_type)
  local result = {}
  for _, trigger in pairs(ammo_type and ammo_type.action or {}) do
    if trigger.radius then
      result.radius = trigger.radius
    end
    local deliveries = trigger.action_delivery or {}
    if deliveries.type then
      deliveries = {deliveries}
    end
    for _, delivery in pairs(deliveries) do
      if delivery.type == "beam" and not result.beam then
        result.beam = delivery.beam
        result.duration = delivery.duration
        result.max_length = delivery.max_length
        result.source_offset = delivery.source_offset
      end
    end
  end
  return result
end

local function describe_equipment(prototype)
  local item = prototype.take_result
  local role = EQUIPMENT_ROLE_BY_TYPE[prototype.type]
  if prototype.type == "active-defense-equipment" then
    role = prototype.automatic and "laser" or "discharge"
  end
  if not item or not role then
    return nil
  end
  local source = safe(function() return prototype.electric_energy_source_prototype end)
  local shape = prototype.shape
  local entry = {
    name = prototype.name,
    item = item.name,
    type = prototype.type,
    role = role,
    width = shape.width,
    height = shape.height,
    cells = equipment_cells(shape),
    categories = {},
    buffer = source and source.buffer_capacity or 0,
    input_flow = source and safe(function() return source.get_input_flow_limit() end) or 0,
    production = 0,
    peak_production = 0,
    demand = 0,
    plan_buffer = 0,
    strength = 1
  }
  for _, category in pairs(prototype.equipment_categories or {}) do
    entry.categories[category] = true
  end

  if prototype.type == "generator-equipment" then
    -- Burner generators need a fuel slot a Soldier cannot keep stocked.
    if safe(function() return prototype.burner_prototype end) then
      return nil
    end
    entry.peak_production = prototype.energy_production
    entry.production = entry.peak_production
  elseif prototype.type == "solar-panel-equipment" then
    entry.solar = true
    entry.peak_production = prototype.energy_production
    entry.production = entry.peak_production * SOLDIER_SOLAR_AVERAGE
  elseif role == "battery" then
    entry.plan_buffer = entry.buffer
    entry.strength = math.sqrt(entry.buffer / SOLDIER_BATTERY_REFERENCE)
  elseif role == "shield" then
    entry.shield = safe(function() return prototype.get_shield() end) or 0
    entry.energy_per_shield = prototype.energy_per_shield
    if entry.shield <= 0 or not entry.energy_per_shield or entry.energy_per_shield <= 0 then
      return nil
    end
    entry.shield_flow = entry.input_flow / entry.energy_per_shield
    entry.demand = entry.input_flow * SOLDIER_SHIELD_DEMAND_FACTOR
    entry.strength = entry.shield / SOLDIER_SHIELD_REFERENCE
  elseif role == "legs" then
    entry.movement_bonus = safe(function() return prototype.get_movement_bonus() end) or 0
    entry.consumption = safe(function() return prototype.get_energy_consumption() end) or 0
    entry.demand = entry.consumption
    entry.strength = entry.movement_bonus / SOLDIER_LEGS_REFERENCE
  elseif role == "laser" or role == "discharge" then
    local attack = prototype.attack_parameters
    local ammo_type = attack and attack.ammo_type
    if not attack or not ammo_type then
      return nil
    end
    local action = describe_defense_action(ammo_type)
    entry.range = attack.range
    entry.cooldown = math.max(attack.cooldown or 60, 1)
    entry.shot_energy = ammo_type.energy_consumption or 0
    entry.damage_modifier = attack.damage_modifier or 1
    entry.ammo_category = attack.ammo_categories and attack.ammo_categories[1]
      or (role == "laser" and "laser" or "electric")
    entry.beam = action.beam
    entry.beam_duration = action.duration
    entry.beam_max_length = action.max_length
    entry.beam_source_offset = action.source_offset
    entry.radius = action.radius or entry.range
    entry.demand = entry.shot_energy / entry.cooldown
      * (role == "laser" and SOLDIER_LASER_DEMAND_FACTOR or SOLDIER_DISCHARGE_DEMAND_FACTOR)
    if role == "laser" then
      entry.strength = (entry.range / 15) * (40 / entry.cooldown)
    end
  elseif role == "roboport" then
    local logistics = prototype.logistic_parameters
    if not logistics or (logistics.robot_limit or 0) == 0 then
      return nil
    end
    entry.robot_limit = logistics.robot_limit
    entry.construction_radius = logistics.construction_radius or 0
    entry.charging_stations = math.max(logistics.charging_station_count or 1, 1)
    entry.demand = (logistics.charging_energy or 0) * entry.charging_stations
      * SOLDIER_ROBOPORT_DEMAND_FACTOR
    entry.strength = entry.robot_limit / SOLDIER_ROBOPORT_REFERENCE
  elseif role == "misc" then
    entry.consumption = safe(function() return prototype.get_energy_consumption() end) or 0
    entry.demand = entry.consumption
  end
  return entry
end

function get_soldier_equipment_catalog()
  if catalog_cache then
    return catalog_cache
  end
  local catalog = {by_name = {}, names = {}, robot_items = {}, repair_items = {}}
  for name, prototype in pairs(prototypes.equipment) do
    local entry = describe_equipment(prototype)
    if entry then
      catalog.by_name[name] = entry
      catalog.names[#catalog.names + 1] = name
    end
  end
  table.sort(catalog.names)
  for _, robot in pairs(prototypes.get_entity_filtered({
    {filter = "type", type = "construction-robot"}
  })) do
    for _, item in pairs(robot.items_to_place_this or {}) do
      local item_name = type(item) == "string" and item or item.name
      if type(item_name) ~= "string" then
        item_name = item_name and item_name.name
      end
      if item_name and prototypes.item[item_name] then
        catalog.robot_items[#catalog.robot_items + 1] = item_name
      end
    end
  end
  table.sort(catalog.robot_items)
  -- Team mate items are built on the repair pack prototype; a Soldier must
  -- never spend a stored Miner or Builder as repair durability.
  local team_mate_items = {}
  for _, item_name in pairs(ITEM_NAME_BY_KIND) do
    team_mate_items[item_name] = true
  end
  for name in pairs(prototypes.get_item_filtered({{filter = "type", type = "repair-tool"}})) do
    if not team_mate_items[name] then
      catalog.repair_items[#catalog.repair_items + 1] = name
    end
  end
  table.sort(catalog.repair_items)
  catalog_cache = catalog
  return catalog
end

function get_soldier_armor_grid(armor_tier)
  local armor = armor_tier and SOLDIER_ARMORS[armor_tier]
  if not armor then
    return nil
  end
  local cached = grid_cache[armor.item]
  if cached == nil then
    local item = prototypes.item[armor.item]
    local grid = item and item.equipment_grid
    cached = false
    if grid then
      cached = {width = grid.width, height = grid.height, categories = {}}
      for _, category in pairs(grid.equipment_categories or {}) do
        cached.categories[category] = true
      end
    end
    grid_cache[armor.item] = cached
  end
  return cached or nil
end

local function grid_accepts(grid, entry)
  if entry.width > grid.width or entry.height > grid.height then
    return false
  end
  for category in pairs(entry.categories) do
    if grid.categories[category] then
      return true
    end
  end
  return false
end

-- Packs largest pieces first into the first free spot, row by row; returns
-- the names that fit, in the order they were given, and whether all did.
local function pack_loadout(grid, names, catalog)
  local order = {}
  for index, name in ipairs(names) do
    order[#order + 1] = {name = name, index = index, entry = catalog.by_name[name]}
  end
  table.sort(order, function(a, b)
    if #a.entry.cells ~= #b.entry.cells then
      return #a.entry.cells > #b.entry.cells
    end
    return a.index < b.index
  end)
  local occupied = {}
  local fitted = {}
  local all_fit = true
  for _, piece in ipairs(order) do
    local entry = piece.entry
    local placed = false
    for y = 0, grid.height - entry.height do
      for x = 0, grid.width - entry.width do
        local free = true
        for _, cell in ipairs(entry.cells) do
          if occupied[(y + cell.y) * grid.width + x + cell.x] then
            free = false
            break
          end
        end
        if free then
          for _, cell in ipairs(entry.cells) do
            occupied[(y + cell.y) * grid.width + x + cell.x] = true
          end
          placed = true
          break
        end
      end
      if placed then
        break
      end
    end
    if placed then
      fitted[piece.index] = true
    else
      all_fit = false
    end
  end
  local result = {}
  for index, name in ipairs(names) do
    if fitted[index] then
      result[#result + 1] = name
    end
  end
  return result, all_fit
end

local function power_balanced(power, extra_demand, extra_production, extra_buffer)
  local demand = power.demand + extra_demand
  if demand <= 0 then
    return true
  end
  -- Batteries smooth peaks but cannot stand in for generation, so their
  -- credit is capped at what the generators provide.
  local production = power.production + extra_production
  local credit = (power.buffer + extra_buffer) / SOLDIER_POWER_BUFFER_TICKS
  return demand <= production + math.min(credit, production)
end

local function role_value(entry, role_counts, power, bots_available)
  local role = SOLDIER_EQUIPMENT_ROLES[entry.role]
  if not role then
    return 0
  end
  if entry.role == "roboport" and not bots_available then
    return 0
  end
  if entry.role == "battery" and power.demand <= 0 then
    return 0
  end
  if entry.role == "generation"
    and power.production >= power.demand * SOLDIER_GENERATION_HEADROOM then
    return 0
  end
  -- Stronger pieces are worth more, but with diminishing returns so one
  -- outstanding item does not crowd out every other role.
  local strength = math.sqrt(entry.strength)
  if role.sqrt then
    strength = math.sqrt(strength)
  end
  return role.weight * role.decay ^ (role_counts[entry.role] or 0)
    * clamp(strength, 0.25, 4)
end

-- The consumer plus the fewest generator cells of one generator kind that
-- keep the suit's power budget balanced, or nil when the pool cannot power it.
local function powered_bundles(entry, power, pool, used, generator_names, catalog)
  if entry.role == "generation"
    or power_balanced(power, entry.demand, entry.production, entry.plan_buffer) then
    return {{entry.name}}
  end
  local bundles = {}
  for _, generator_name in ipairs(generator_names) do
    local generator = catalog.by_name[generator_name]
    local remaining = (pool[generator_name] or 0) - (used[generator_name] or 0)
    local bundle = {entry.name}
    local production = entry.production
    local buffer = entry.plan_buffer
    while remaining > 0 and #bundle <= SOLDIER_LOADOUT_MAX_ITEMS do
      bundle[#bundle + 1] = generator_name
      remaining = remaining - 1
      production = production + generator.production
      buffer = buffer + generator.plan_buffer
      if power_balanced(power, entry.demand, production, buffer) then
        bundles[#bundles + 1] = bundle
        break
      end
    end
  end
  return bundles
end

local function add_to_loadout(state, name, catalog)
  local entry = catalog.by_name[name]
  state.chosen[#state.chosen + 1] = name
  state.used[name] = (state.used[name] or 0) + 1
  state.role_counts[entry.role] = (state.role_counts[entry.role] or 0) + 1
  state.power.production = state.power.production + entry.production
  state.power.demand = state.power.demand + entry.demand
  state.power.buffer = state.power.buffer + entry.plan_buffer
  state.cells_left = state.cells_left - #entry.cells
end

-- Greedy fill from a seeded start: each step adds whatever gives the most
-- value per grid cell, with diminishing returns per role, pairing consumers
-- with the generators they need so the suit never runs a power deficit.
local function fill_loadout(grid, pool, bots_available, candidates, generator_names, seed)
  local catalog = get_soldier_equipment_catalog()
  local state = {
    chosen = {}, used = {}, role_counts = {}, value = 0,
    power = {production = 0, demand = 0, buffer = 0},
    cells_left = grid.width * grid.height
  }
  for _, name in ipairs(seed) do
    add_to_loadout(state, name, catalog)
  end
  local failed = {}
  while state.cells_left > 0 and #state.chosen < SOLDIER_LOADOUT_MAX_ITEMS do
    local options = {}
    for _, name in ipairs(candidates) do
      local entry = catalog.by_name[name]
      if (state.used[name] or 0) < pool[name] then
        local value = role_value(entry, state.role_counts, state.power, bots_available)
        if value > 0 then
          for _, bundle in ipairs(powered_bundles(entry, state.power, pool, state.used,
            generator_names, catalog)) do
            local cells = 0
            for _, bundle_name in ipairs(bundle) do
              cells = cells + #catalog.by_name[bundle_name].cells
            end
            local key = table.concat(bundle, ",")
            if cells <= state.cells_left and not failed[key] then
              options[#options + 1] = {
                bundle = bundle, key = key, value = value, score = value / cells
              }
            end
          end
        end
      end
    end
    table.sort(options, function(a, b)
      if a.score ~= b.score then
        return a.score > b.score
      end
      return a.key < b.key
    end)
    local accepted
    for _, option in ipairs(options) do
      if option.score < SOLDIER_LOADOUT_MIN_SCORE then
        break
      end
      local trial = {}
      for _, name in ipairs(state.chosen) do
        trial[#trial + 1] = name
      end
      for _, name in ipairs(option.bundle) do
        trial[#trial + 1] = name
      end
      local _, all_fit = pack_loadout(grid, trial, catalog)
      if all_fit then
        accepted = option
        break
      end
      failed[option.key] = true
    end
    if not accepted then
      break
    end
    for _, name in ipairs(accepted.bundle) do
      add_to_loadout(state, name, catalog)
    end
    state.value = state.value + accepted.value
  end
  return state.chosen, state.value
end

-- Chooses a balanced loadout from the pool of equipment the Soldier owns or
-- can reach. Like a player sizing the power plant to the suit first, it tries
-- starting from zero to a few reactors of each kind and keeps whichever
-- finished suit is worth the most.
function plan_soldier_loadout(grid, pool, bots_available)
  local catalog = get_soldier_equipment_catalog()
  local candidates, generator_names = {}, {}
  for _, name in ipairs(catalog.names) do
    local entry = catalog.by_name[name]
    if (pool[name] or 0) > 0 and grid_accepts(grid, entry) then
      candidates[#candidates + 1] = name
      if entry.role == "generation" and entry.production > 0 then
        generator_names[#generator_names + 1] = name
      end
    end
  end
  local best, best_value = fill_loadout(grid, pool, bots_available, candidates,
    generator_names, {})
  for _, generator_name in ipairs(generator_names) do
    local generator = catalog.by_name[generator_name]
    if not generator.solar then
      local seed = {}
      for _ = 1, math.min(pool[generator_name], SOLDIER_LOADOUT_MAX_REACTORS) do
        seed[#seed + 1] = generator_name
        local _, all_fit = pack_loadout(grid, seed, catalog)
        if not all_fit then
          break
        end
        local plan, value = fill_loadout(grid, pool, bots_available, candidates,
          generator_names, seed)
        if value > best_value then
          best, best_value = plan, value
        end
      end
    end
  end
  return best
end

local function count_names(names)
  local counts = {}
  for _, name in ipairs(names or {}) do
    counts[name] = (counts[name] or 0) + 1
  end
  return counts
end

local function sum_counts(counts)
  local total = 0
  for _, count in pairs(counts or {}) do
    total = total + count
  end
  return total
end

-- Equipment that is actually in the suit: owned pieces that fit the worn
-- armor's grid, in pickup order.
function get_soldier_equipment_stats(record)
  local grid = get_soldier_armor_grid(record.soldier_armor)
  if not grid or not record.soldier_equipment or #record.soldier_equipment == 0 then
    return nil
  end
  local signature = tostring(record.soldier_armor) .. "|"
    .. table.concat(record.soldier_equipment, ",")
  local cached = stats_cache[record]
  if cached and cached.signature == signature then
    return cached.stats
  end
  local catalog = get_soldier_equipment_catalog()
  local accepted = {}
  for _, name in ipairs(record.soldier_equipment) do
    local entry = catalog.by_name[name]
    if entry and grid_accepts(grid, entry) then
      accepted[#accepted + 1] = name
      local _, all_fit = pack_loadout(grid, accepted, catalog)
      if not all_fit then
        accepted[#accepted] = nil
      end
    end
  end
  local stats = {
    active = accepted,
    production = 0, solar_production = 0, capacity = 0,
    shield_max = 0, shield_flow = 0, shield_energy = 0,
    movement_bonus = 0, legs_draw = 0, misc_draw = 0,
    lasers = {}, discharges = {},
    robot_limit = 0, construction_radius = 0
  }
  for _, name in ipairs(accepted) do
    local entry = catalog.by_name[name]
    stats.capacity = stats.capacity + entry.buffer
    if entry.solar then
      stats.solar_production = stats.solar_production + entry.peak_production
    else
      stats.production = stats.production + entry.peak_production
    end
    if entry.role == "shield" then
      stats.shield_max = stats.shield_max + entry.shield
      stats.shield_flow = stats.shield_flow + entry.shield_flow
      stats.shield_energy = stats.shield_energy + entry.shield * entry.energy_per_shield
    elseif entry.role == "legs" then
      stats.movement_bonus = stats.movement_bonus + entry.movement_bonus
      stats.legs_draw = stats.legs_draw + entry.consumption
    elseif entry.role == "misc" then
      stats.misc_draw = stats.misc_draw + (entry.consumption or 0)
    elseif entry.role == "laser" then
      stats.lasers[#stats.lasers + 1] = entry
    elseif entry.role == "discharge" then
      stats.discharges[#stats.discharges + 1] = entry
    elseif entry.role == "roboport" then
      stats.robot_limit = stats.robot_limit + entry.robot_limit
      stats.construction_radius = math.max(stats.construction_radius,
        entry.construction_radius)
    end
  end
  stats.movement_bonus = math.min(stats.movement_bonus, SOLDIER_MAX_MOVEMENT_BONUS)
  -- Average energy per shield point across the installed shields.
  stats.energy_per_shield = stats.shield_max > 0
    and stats.shield_energy / stats.shield_max or 0
  stats_cache[record] = {signature = signature, stats = stats}
  return stats
end

-- Planning ------------------------------------------------------------------

local function soldier_network(record)
  return record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
end

-- Replans only when the Soldier's armor, kit, or the reachable equipment
-- stock changes, since planning packs the grid many times over.
function get_soldier_loadout_plan(record)
  local grid = get_soldier_armor_grid(record.soldier_armor)
  if not grid then
    record.soldier_loadout_plan = nil
    record.soldier_loadout_signature = nil
    return nil
  end
  local catalog = get_soldier_equipment_catalog()
  local network = soldier_network(record)
  local owned = count_names(record.soldier_equipment)
  local pool = {}
  local parts = {tostring(record.soldier_armor)}
  for _, name in ipairs(catalog.names) do
    local entry = catalog.by_name[name]
    -- Stock beyond what the grid could hold cannot change the plan; capping
    -- it keeps the signature stable while the factory produces more.
    local count = math.min((owned[name] or 0)
      + (network and network.get_item_count(entry.item) or 0),
      math.floor(grid.width * grid.height / #entry.cells))
    if count > 0 then
      pool[name] = count
      parts[#parts + 1] = name .. "=" .. count
    end
  end
  local bots_available = sum_counts(record.soldier_bots) > 0
  if not bots_available and network then
    for _, item_name in ipairs(catalog.robot_items) do
      if network.get_item_count(item_name) > 0 then
        bots_available = true
        break
      end
    end
  end
  parts[#parts + 1] = bots_available and "bots" or "nobots"
  local signature = table.concat(parts, ",")
  if record.soldier_loadout_signature ~= signature then
    record.soldier_loadout_plan = plan_soldier_loadout(grid, pool, bots_available)
    record.soldier_loadout_signature = signature
  end
  return record.soldier_loadout_plan
end

local function planned_robot_limit(plan)
  local catalog = get_soldier_equipment_catalog()
  local total = 0
  for _, name in ipairs(plan or {}) do
    local entry = catalog.by_name[name]
    total = total + (entry and entry.robot_limit or 0)
  end
  return total
end

-- Hands back equipment the plan dropped, and bots beyond what the planned
-- roboports can hold, into the storage the Soldier is standing at.
function deposit_soldier_surplus(record, inventory)
  local plan = record.soldier_loadout_plan
  local catalog = get_soldier_equipment_catalog()
  if plan and record.soldier_equipment then
    local wanted = count_names(plan)
    local kept = {}
    for _, name in ipairs(record.soldier_equipment) do
      local entry = catalog.by_name[name]
      if (wanted[name] or 0) > 0 then
        wanted[name] = wanted[name] - 1
        kept[#kept + 1] = name
      elseif not entry
        or inventory.insert({name = entry.item, count = 1}) ~= 1 then
        kept[#kept + 1] = name
      end
    end
    record.soldier_equipment = kept
  end
  local excess = sum_counts(record.soldier_bots) - planned_robot_limit(plan)
  for item_name, count in pairs(record.soldier_bots or {}) do
    if excess <= 0 then
      break
    end
    local inserted = inventory.insert({name = item_name, count = math.min(count, excess)})
    excess = excess - inserted
    record.soldier_bots[item_name] = count - inserted > 0 and count - inserted or nil
  end
end

local function start_kit_pickup(record, kind, item_name, count, equipment_name)
  local source = find_logistics_item_source(record, item_name)
  if not source or not notalone._reserve_soldier_pickup(record, source, item_name) then
    return false
  end
  record.soldier_state = "pickup-kit"
  record.soldier_kit_kind = kind
  record.soldier_kit_item = item_name
  record.soldier_kit_count = count
  record.soldier_kit_equipment = equipment_name
  record.soldier_pickup_source = source
  return true
end

-- Fetches the next missing piece of the planned loadout, then bots for the
-- installed roboports, then repair packs for those bots.
local function try_suit_kit_pickup(record)
  local plan = get_soldier_loadout_plan(record)
  if not plan then
    return false
  end
  local catalog = get_soldier_equipment_catalog()
  local have = count_names(record.soldier_equipment)
  for _, name in ipairs(plan) do
    if (have[name] or 0) > 0 then
      have[name] = have[name] - 1
    elseif start_kit_pickup(record, "equipment", catalog.by_name[name].item, 1, name) then
      return true
    end
  end
  local stats = get_soldier_equipment_stats(record)
  if not stats or stats.robot_limit == 0 then
    return false
  end
  local bots = sum_counts(record.soldier_bots)
  if bots < stats.robot_limit then
    -- Keep one robot kind so a partial stack does not mix models.
    local preferred = next(record.soldier_bots or {})
    local robot_items = preferred and {preferred} or catalog.robot_items
    for _, item_name in ipairs(robot_items) do
      if start_kit_pickup(record, "bot", item_name, stats.robot_limit - bots) then
        return true
      end
    end
  end
  if bots > 0 and sum_counts(record.soldier_repair) < SOLDIER_REPAIR_RESTOCK_THRESHOLD then
    for _, item_name in ipairs(catalog.repair_items) do
      if start_kit_pickup(record, "repair", item_name,
        SOLDIER_REPAIR_PACK_TARGET - sum_counts(record.soldier_repair)) then
        return true
      end
    end
  end
  return false
end

-- Combat robot capsules (defender, distractor, destroyer, and any modded
-- capsule that deploys a combat robot), best first.
local capsule_cache

function get_soldier_capsules()
  if capsule_cache then
    return capsule_cache
  end
  local capsules = {}
  for name, item in pairs(prototypes.get_item_filtered({{filter = "type", type = "capsule"}})) do
    local action = safe(function() return item.capsule_action end)
    local attack = action and action.type == "throw" and action.attack_parameters
    local projectile
    for _, trigger in pairs(attack and attack.ammo_type and attack.ammo_type.action or {}) do
      local deliveries = trigger.action_delivery or {}
      if deliveries.type then
        deliveries = {deliveries}
      end
      for _, delivery in pairs(deliveries) do
        if delivery.type == "projectile" and delivery.projectile then
          projectile = delivery.projectile
        end
      end
    end
    -- Capsules are named after the robot they release.
    local robot = prototypes.entity[(name:gsub("%-capsule$", ""))]
    if projectile and prototypes.entity[projectile]
      and robot and robot.type == "combat-robot" then
      capsules[#capsules + 1] = {
        item = name,
        projectile = projectile,
        range = attack.range or 20,
        rank = SOLDIER_CAPSULE_RANK[robot.name] or 1
      }
    end
  end
  table.sort(capsules, function(a, b)
    if a.rank ~= b.rank then
      return a.rank > b.rank
    end
    return a.item < b.item
  end)
  capsule_cache = capsules
  return capsules
end

local function try_capsule_pickup(record)
  local held = sum_counts(record.soldier_capsules)
  if held >= SOLDIER_CAPSULE_RESTOCK_THRESHOLD then
    return false
  end
  for _, capsule in ipairs(get_soldier_capsules()) do
    if start_kit_pickup(record, "capsule", capsule.item, SOLDIER_CAPSULE_TARGET - held) then
      return true
    end
  end
  return false
end

-- Fills the armor first, then tops up combat robot capsules, which any
-- Soldier can throw whatever it wears.
function try_soldier_kit_pickup(record)
  return try_suit_kit_pickup(record) or try_capsule_pickup(record)
end

local function clear_kit_pickup(record)
  record.soldier_state = nil
  record.soldier_pickup_source = nil
  record.soldier_kit_kind = nil
  record.soldier_kit_item = nil
  record.soldier_kit_count = nil
  record.soldier_kit_equipment = nil
  notalone._clear_soldier_pickup(record)
end

function update_soldier_kit_pickup(record)
  local source = record.soldier_pickup_source
  local item_name = record.soldier_kit_item
  local inventory = get_logistics_source_inventory(source)
  if not source or not source.valid or not inventory or not item_name
    or inventory.get_item_count(item_name) == 0 then
    clear_kit_pickup(record)
  elseif distance_squared(record.entity.position, source.position) <= 4 then
    -- Swap out what the new plan no longer wants before taking the new piece.
    deposit_soldier_surplus(record, inventory)
    local kind = record.soldier_kit_kind
    local removed = inventory.remove({
      name = item_name,
      count = math.max(record.soldier_kit_count or 1, 1)
    })
    if removed > 0 then
      if kind == "equipment" then
        record.soldier_equipment = record.soldier_equipment or {}
        record.soldier_equipment[#record.soldier_equipment + 1] = record.soldier_kit_equipment
      elseif kind == "bot" then
        record.soldier_bots = record.soldier_bots or {}
        record.soldier_bots[item_name] = (record.soldier_bots[item_name] or 0) + removed
      elseif kind == "repair" then
        record.soldier_repair = record.soldier_repair or {}
        record.soldier_repair[item_name] = (record.soldier_repair[item_name] or 0) + removed
      elseif kind == "capsule" then
        record.soldier_capsules = record.soldier_capsules or {}
        record.soldier_capsules[item_name] = (record.soldier_capsules[item_name] or 0) + removed
      end
    end
    clear_kit_pickup(record)
    stop_team_mate(record)
  else
    move_team_mate(record, source.position, 2)
  end
  return true
end

-- Kit bookkeeping -------------------------------------------------------------

SOLDIER_KIT_FIELDS = {
  "soldier_equipment", "soldier_bots", "soldier_repair",
  "soldier_repair_durability", "soldier_energy", "soldier_shield",
  "soldier_capsules"
}

function copy_soldier_kit(from, to)
  for _, field in ipairs(SOLDIER_KIT_FIELDS) do
    to[field] = from[field]
  end
end

-- Every item a Soldier's kit holds, for spilling or returning it.
function soldier_kit_item_stacks(holder)
  local stacks = {}
  local catalog = get_soldier_equipment_catalog()
  for _, name in ipairs(holder.soldier_equipment or {}) do
    local entry = catalog.by_name[name]
    local item_name = entry and entry.item
      or (prototypes.equipment[name] and prototypes.equipment[name].take_result
        and prototypes.equipment[name].take_result.name)
    if item_name then
      stacks[#stacks + 1] = {name = item_name, count = 1}
    end
  end
  for _, field in ipairs({"soldier_bots", "soldier_repair", "soldier_capsules"}) do
    for item_name, count in pairs(holder[field] or {}) do
      if count > 0 and prototypes.item[item_name] then
        stacks[#stacks + 1] = {name = item_name, count = count}
      end
    end
  end
  return stacks
end

function clear_soldier_kit(holder)
  for _, field in ipairs(SOLDIER_KIT_FIELDS) do
    holder[field] = nil
  end
  holder.soldier_loadout_plan = nil
  holder.soldier_loadout_signature = nil
end

-- Runtime effects -----------------------------------------------------------

local function set_soldier_speed(entity, bonus)
  local base = entity.prototype.speed
  if not base then
    return
  end
  local wanted = base * (1 + bonus)
  if math.abs((entity.speed or 0) - wanted) > 0.0001 then
    entity.speed = wanted
  end
end

local function fire_beam(entity, target, entry)
  if entry.beam and prototypes.entity[entry.beam] then
    entity.surface.create_entity({
      name = entry.beam,
      position = entity.position,
      force = entity.force,
      source = entity,
      target = target,
      duration = entry.beam_duration or 20,
      max_length = entry.beam_max_length or math.ceil(entry.range or 15),
      source_offset = entry.beam_source_offset
    })
    return true
  end
  return false
end

local function fire_lasers(record, stats, target, now)
  local entity = record.entity
  record.soldier_laser_ready = record.soldier_laser_ready or {}
  local distance = math.sqrt(distance_squared(entity.position, target.position))
  for index, laser in ipairs(stats.lasers) do
    if now >= (record.soldier_laser_ready[index] or 0)
      and distance <= laser.range + 1
      and (record.soldier_energy or 0) >= laser.shot_energy then
      record.soldier_energy = record.soldier_energy - laser.shot_energy
      record.soldier_laser_ready[index] = now + laser.cooldown
      -- The vanilla laser beam carries the damage itself; without a beam
      -- prototype, deal a comparable hit directly.
      if not fire_beam(entity, target, laser) and target.valid then
        local modifier = 1 + entity.force.get_ammo_damage_modifier(laser.ammo_category)
        target.damage(SOLDIER_LASER_FALLBACK_DAMAGE * laser.damage_modifier * modifier,
          entity.force, "laser", entity)
      end
      if not target.valid then
        return
      end
    end
  end
end

-- Discharge defense is a manual trigger for players; Soldiers pull it when
-- swarmed or badly hurt.
local function fire_discharge(record, stats, now)
  local entity = record.entity
  for index, discharge in ipairs(stats.discharges) do
    record.soldier_discharge_ready = record.soldier_discharge_ready or {}
    if now >= (record.soldier_discharge_ready[index] or 0)
      and (record.soldier_energy or 0) >= discharge.shot_energy then
      local enemies = {}
      for _, candidate in pairs(entity.surface.find_entities_filtered({
        position = entity.position,
        radius = discharge.radius,
        type = {"unit", "character"}
      })) do
        if candidate.valid and candidate.force.is_enemy(entity.force) then
          enemies[#enemies + 1] = candidate
        end
      end
      local hurt = entity.health < entity.max_health * SOLDIER_DISCHARGE_HEALTH_RATIO
      if #enemies >= SOLDIER_DISCHARGE_MIN_ENEMIES or (hurt and #enemies > 0) then
        record.soldier_energy = record.soldier_energy - discharge.shot_energy
        record.soldier_discharge_ready[index] = now + discharge.cooldown
        local modifier = 1 + entity.force.get_ammo_damage_modifier(discharge.ammo_category)
        local damage = SOLDIER_DISCHARGE_BASE_DAMAGE * discharge.damage_modifier * modifier
        for _, enemy in ipairs(enemies) do
          if enemy.valid then
            fire_beam(entity, enemy, discharge)
            if prototypes.entity["stun-sticker"] then
              entity.surface.create_entity({
                name = "stun-sticker",
                position = enemy.position,
                target = enemy
              })
            end
            enemy.damage(damage, entity.force, "electric", entity)
          end
        end
      end
      return
    end
  end
end

local function take_repair_durability(record, wanted)
  local taken = 0
  while taken < wanted do
    if (record.soldier_repair_durability or 0) <= 0 then
      local item_name = next(record.soldier_repair or {})
      if not item_name then
        break
      end
      local count = record.soldier_repair[item_name]
      record.soldier_repair[item_name] = count > 1 and count - 1 or nil
      record.soldier_repair_durability = prototypes.item[item_name]
        and prototypes.item[item_name].get_durability() or 0
      record.soldier_repair_speed = prototypes.item[item_name]
        and prototypes.item[item_name].speed or 1
      if record.soldier_repair_durability <= 0 then
        record.soldier_repair_durability = nil
        break
      end
    end
    local step = math.min(wanted - taken, record.soldier_repair_durability)
    record.soldier_repair_durability = record.soldier_repair_durability - step
    taken = taken + step
  end
  return taken
end

-- Personal roboport bots patch up the Soldier, its squad, and nearby
-- buildings, spending repair packs just like a player's bots would.
local function run_repair_bots(record, stats)
  local entity = record.entity
  local bots = sum_counts(record.soldier_bots)
  if bots == 0 or stats.construction_radius <= 0
    or (sum_counts(record.soldier_repair) == 0
      and (record.soldier_repair_durability or 0) <= 0) then
    return
  end
  local damaged = {}
  for _, candidate in pairs(entity.surface.find_entities_filtered({
    position = entity.position,
    radius = stats.construction_radius,
    force = entity.force
  })) do
    if candidate.valid and candidate.is_entity_with_health
      and candidate.health and candidate.max_health > 0
      and candidate.health < candidate.max_health
      and candidate.type ~= "construction-robot" and candidate.type ~= "logistic-robot" then
      damaged[#damaged + 1] = candidate
    end
  end
  if #damaged == 0 then
    return
  end
  table.sort(damaged, function(a, b)
    return a.health / a.max_health < b.health / b.max_health
  end)
  local robot_item = next(record.soldier_bots)
  for index = 1, math.min(bots, #damaged) do
    if (record.soldier_energy or 0) < SOLDIER_REPAIR_ENERGY_PER_BOT then
      return
    end
    local target = damaged[index]
    local heal_rate = (record.soldier_repair_speed or 1) * SOLDIER_REPAIR_HEALTH_PER_SPEED
    local healed = take_repair_durability(record,
      math.min(target.max_health - target.health, heal_rate))
    if healed <= 0 then
      return
    end
    record.soldier_energy = record.soldier_energy - SOLDIER_REPAIR_ENERGY_PER_BOT
    target.health = target.health + healed
    if robot_item then
      rendering.draw_sprite({
        sprite = "item." .. robot_item,
        target = {entity = target, offset = {0, -1.2}},
        surface = target.surface,
        x_scale = 0.6,
        y_scale = 0.6,
        time_to_live = SOLDIER_REPAIR_INTERVAL
      })
    end
    rendering.draw_line({
      color = {r = 1, g = 0.8, b = 0.2, a = 0.4},
      width = 1,
      from = entity,
      to = target,
      surface = entity.surface,
      time_to_live = SOLDIER_REPAIR_INTERVAL / 2
    })
  end
end

-- Like a player, a Soldier throws its best combat robots when a pack of
-- enemies or an enemy base is within throwing range.
local function throw_soldier_capsule(record, now)
  if not record.soldier_capsules or not next(record.soldier_capsules)
    or now < (record.soldier_capsule_ready or 0) then
    return
  end
  local capsule
  for _, candidate in ipairs(get_soldier_capsules()) do
    if (record.soldier_capsules[candidate.item] or 0) > 0 then
      capsule = candidate
      break
    end
  end
  if not capsule then
    return
  end
  local entity = record.entity
  local target = entity.surface.find_nearest_enemy({
    position = entity.position,
    max_distance = capsule.range,
    force = entity.force
  })
  if not target or not target.valid then
    return
  end
  local worth_it = target.type == "unit-spawner" or target.type == "turret"
  if not worth_it then
    local pack = 0
    for _, other in pairs(entity.surface.find_entities_filtered({
      position = target.position,
      radius = SOLDIER_CAPSULE_PACK_RADIUS,
      type = {"unit", "character"}
    })) do
      if other.force.is_enemy(entity.force) then
        pack = pack + 1
      end
    end
    worth_it = pack >= SOLDIER_CAPSULE_MIN_ENEMIES
  end
  if not worth_it then
    return
  end
  entity.surface.create_entity({
    name = capsule.projectile,
    position = entity.position,
    force = entity.force,
    source = entity,
    target = target.position,
    speed = 0.3,
    max_range = capsule.range
  })
  local count = record.soldier_capsules[capsule.item]
  record.soldier_capsules[capsule.item] = count > 1 and count - 1 or nil
  record.soldier_capsule_ready = now + SOLDIER_CAPSULE_COOLDOWN
end

-- Runs every update for deployed Soldiers: charges the suit, spends power on
-- legs and shields, and lets lasers, discharge, and bots act on their own.
function update_soldier_equipment(record)
  local entity = record.entity
  if not entity or not entity.valid or entity.type ~= "unit" then
    return
  end
  local now = game.tick
  local dt = clamp(now - (record.soldier_equipment_tick or now), 0, 600)
  record.soldier_equipment_tick = now
  throw_soldier_capsule(record, now)
  local stats = get_soldier_equipment_stats(record)
  if not stats then
    set_soldier_speed(entity, 0)
    record.soldier_energy = nil
    record.soldier_shield = nil
    return
  end

  local energy = record.soldier_energy or 0
  local solar = 0
  if stats.solar_production > 0 then
    local surface = entity.surface
    solar = stats.solar_production * (1 - surface.darkness)
      * (safe(function() return surface.solar_power_multiplier end) or 1)
  end
  energy = math.min(stats.capacity, energy + (stats.production + solar) * dt)

  local always_on = (stats.legs_draw + stats.misc_draw) * dt
  local powered = energy >= always_on
  if powered then
    energy = energy - always_on
  end
  set_soldier_speed(entity, powered and stats.movement_bonus or 0)

  local shield = math.min(record.soldier_shield or 0, stats.shield_max)
  if shield < stats.shield_max and stats.energy_per_shield > 0 then
    local gain = math.min(stats.shield_max - shield, stats.shield_flow * dt,
      energy / stats.energy_per_shield)
    if gain > 0 then
      shield = shield + gain
      energy = energy - gain * stats.energy_per_shield
    end
  end
  record.soldier_shield = stats.shield_max > 0 and shield or nil
  record.soldier_energy = energy

  if #stats.lasers > 0 or #stats.discharges > 0 then
    local reach = 0
    for _, laser in ipairs(stats.lasers) do
      reach = math.max(reach, laser.range)
    end
    for _, discharge in ipairs(stats.discharges) do
      reach = math.max(reach, discharge.radius)
    end
    local target = entity.surface.find_nearest_enemy({
      position = entity.position,
      max_distance = reach,
      force = entity.force
    })
    if target and target.valid then
      if #stats.lasers > 0 then
        fire_lasers(record, stats, target, now)
      end
      if #stats.discharges > 0 and entity.valid then
        fire_discharge(record, stats, now)
      end
    end
  end

  if stats.robot_limit > 0 and now >= (record.soldier_repair_tick or 0) then
    record.soldier_repair_tick = now + SOLDIER_REPAIR_INTERVAL
    run_repair_bots(record, stats)
  end
end

-- Shields soak damage before armor mitigation applies to the remainder.
-- Returns the health to give back for this hit.
function absorb_soldier_damage(record, damage)
  local restored = 0
  local shield = record.soldier_shield or 0
  if shield > 0 then
    local absorbed = math.min(shield, damage)
    record.soldier_shield = shield - absorbed
    restored = absorbed
    damage = damage - absorbed
  end
  local armor = record.soldier_armor and SOLDIER_ARMORS[record.soldier_armor]
  if armor then
    restored = restored + damage * armor.mitigation
  end
  return restored
end
