local poc = {}

local INITIAL_HABITAT_COUNT = 1
local INITIAL_COUNT_BY_KIND = {miner = 7, builder = 3, soldier = 7, carrier = 10}
local STARTER_INVENTORY_VERSION = 5
local UPDATE_INTERVAL = 10
local ENGAGEMENT_RADIUS = 16
local COMMAND_REFRESH_DISTANCE = 2
local CHUNK_SIZE = 32
local SCOUT_WAYPOINT_DISTANCE = 64
local SCOUT_GENERATION_RADIUS = 2
local MINER_CAPACITY = 50
local CARRIER_CAPACITY = 50
local RESOURCE_MINING_TIME = 1
local NORMAL_CHARACTER_MINING_SPEED = 0.5
local LOGISTICS_SEARCH_RADIUS = 128
local BUILDER_CARGO_SLOTS = 1
local MAX_BUILDER_CARGO_SLOTS = 65535
local FUEL_REQUEST_COUNT = 5
local INGREDIENT_REQUEST_COUNT = 10
local BUILDING_REQUEST_SLOT_COUNT = 20
local BUILDER_ITEM_PICKUP_DISTANCE = 0.5
local BUILDER_TARGET_CLEARANCE = 0.4
-- Must exceed clearance plus the 0.2 move stopping distance or arrivals stall.
local BUILDER_TARGET_INTERACTION_DISTANCE = 0.7
local MINING_ANIMATION_FRAMES = 51
local MINING_ANIMATION_SPEED = 51 / 60
local HIDDEN_TEAM_MATE_NAME = "not-alone-team-mate-hidden"
local ROUTE_COLOR = {r = 0.2, g = 0.7, b = 1, a = 0.9}
local MARK_COLOR = {r = 1, g = 0.6, b = 0, a = 0.9}
local INVENTORY_ICON_SCALE = 0.5
local INVENTORY_ICON_SPACING = 0.65
local TEAM_MATE_NAME = "not-alone-team-mate"
local TEAM_MATE_ENTITY_BY_KIND = {
  miner = "not-alone-team-mate-miner",
  builder = "not-alone-team-mate-builder",
  carrier = "not-alone-team-mate-carrier",
  soldier = "not-alone-team-mate-fists"
}
local KIND_BY_ENTITY_NAME = {
  ["not-alone-team-mate-miner"] = "miner",
  ["not-alone-team-mate-builder"] = "builder",
  ["not-alone-team-mate-carrier"] = "carrier",
  ["not-alone-team-mate-fists"] = "soldier",
  ["not-alone-team-mate-smg"] = "soldier",
  ["not-alone-team-mate-shotgun"] = "soldier",
  ["not-alone-team-mate-combat-shotgun"] = "soldier",
  ["not-alone-team-mate-flamethrower"] = "soldier",
  ["not-alone-team-mate-rocket"] = "soldier"
}
local TEAM_MATE_NAMES = {TEAM_MATE_NAME}
for entity_name in pairs(KIND_BY_ENTITY_NAME) do
  TEAM_MATE_NAMES[#TEAM_MATE_NAMES + 1] = entity_name
end
local COMMAND_TOOL_NAME = "not-alone-command-tool"
local LOGISTICS_HUB_NAME = "not-alone-logistics-hub"
local BUILDING_REQUESTER_NAME = "not-alone-building-logistics-requester"
local ITEM_NAME_BY_KIND = {
  miner = "not-alone-miner",
  builder = "not-alone-builder",
  soldier = "not-alone-soldier",
  carrier = "not-alone-carrier"
}
local TEAM_MATE_KINDS = {"miner", "builder", "soldier", "carrier"}
local KIND_LABEL = {miner = "Miner", builder = "Builder", soldier = "Soldier", carrier = "Carrier"}
local KIND_BY_LABEL = {Miner = "miner", Builder = "builder", Soldier = "soldier", Carrier = "carrier"}
-- Division colors borrowed from classic sci-fi uniforms: engineering gold for
-- Builders, command red for Soldiers, sciences blue for Carriers, and a
-- hazard-suit orange for Miners (mining/EVA suits across many settings).
local KIND_COLOR = {
  miner = {r = 0.92, g = 0.42, b = 0.04},
  builder = {r = 0.87, g = 0.72, b = 0.2},
  soldier = {r = 0.72, g = 0.08, b = 0.08},
  carrier = {r = 0.2, g = 0.55, b = 0.85}
}
-- Soldier arsenal, ordered worst to best. Soldiers fight with the best owned
-- weapon that still has ammo, and restock the best ammo tier listed first.
-- Either the crafted kit or the vanilla gun item arms the tier.
local SOLDIER_WEAPONS = {
  {
    kind = "smg",
    item = "not-alone-soldier-smg",
    gun = "submachine-gun",
    entity = "not-alone-team-mate-smg",
    ammo = {"uranium-rounds-magazine", "piercing-rounds-magazine", "firearm-magazine"}
  },
  {
    kind = "shotgun",
    item = "not-alone-soldier-shotgun",
    gun = "shotgun",
    entity = "not-alone-team-mate-shotgun",
    ammo = {"piercing-shotgun-shell", "shotgun-shell"}
  },
  {
    kind = "combat-shotgun",
    item = "not-alone-soldier-combat-shotgun",
    gun = "combat-shotgun",
    entity = "not-alone-team-mate-combat-shotgun",
    ammo = {"piercing-shotgun-shell", "shotgun-shell"}
  },
  {
    kind = "flamethrower",
    item = "not-alone-soldier-flamethrower",
    gun = "flamethrower",
    entity = "not-alone-team-mate-flamethrower",
    ammo = {"flamethrower-ammo"}
  },
  {
    kind = "rocket",
    item = "not-alone-soldier-rocket",
    gun = "rocket-launcher",
    entity = "not-alone-team-mate-rocket",
    ammo = {"explosive-rocket", "rocket"}
  }
}
local SOLDIER_WEAPON_BY_KIND = {}
for _, weapon in pairs(SOLDIER_WEAPONS) do
  SOLDIER_WEAPON_BY_KIND[weapon.kind] = weapon
end
local SOLDIER_FISTS_ENTITY = "not-alone-team-mate-fists"
local SOLDIER_AMMO_RESTOCK_COUNT = 20
local SOLDIER_AMMO_TICKS_PER_ROUND = 30
-- Armor tiers, worst to best; a Soldier wears the best suit it has found and
-- shrugs off that fraction of every hit.
local SOLDIER_ARMORS = {
  {item = "light-armor", mitigation = 0.2},
  {item = "heavy-armor", mitigation = 0.4},
  {item = "modular-armor", mitigation = 0.5},
  {item = "power-armor", mitigation = 0.65},
  {item = "power-armor-mk2", mitigation = 0.8}
}
-- Other crews crashed here too: derelict ships seeded from the map seed,
-- rare overall, but one is always placed inside the initially charted area
-- so the player has a visible lead to investigate.
local CRASH_SHIP_NAME = "crash-site-spaceship"
local CRASH_SHIP_BASE_CHANCE = 0.002
local CRASH_SHIP_FALLOFF_CHUNKS = 8
local CRASH_SHIP_MAX_CREW = 10
local CRASH_SHIP_STARTER_MIN_CHUNKS = 2
local CRASH_SHIP_STARTER_MAX_CHUNKS = 5
local LOGISTICS_SOURCE_MODES = {

  ["active-provider"] = true,
  ["passive-provider"] = true,
  ["storage"] = true,
  ["buffer"] = true
}
local LOGISTICS_DESTINATION_TYPES = {
  "assembling-machine",
  "boiler",
  "burner-generator",
  "furnace",
  "lab",
  "rocket-silo"
}
local RECIPE_ENTITY_TYPES = {
  ["assembling-machine"] = true,
  ["furnace"] = true,
  ["rocket-silo"] = true
}
local dock_at_habitat
local stop_team_mate
local move_team_mate
local update_mining_animation

local function distance_squared(first, second)
  local delta_x = first.x - second.x
  local delta_y = first.y - second.y
  return delta_x * delta_x + delta_y * delta_y
end

local function distance_squared_to_box(position, box)
  local delta_x = math.max(box.left_top.x - position.x, 0, position.x - box.right_bottom.x)
  local delta_y = math.max(box.left_top.y - position.y, 0, position.y - box.right_bottom.y)
  return delta_x * delta_x + delta_y * delta_y
end

local function position_table(position)
  return {x = position.x, y = position.y}
end

local function create_mining_particles(surface, position, particle_name)
  if not prototypes.particle[particle_name] then
    return
  end
  for _ = 1, 5 do
    surface.create_particle({
      name = particle_name,
      position = position,
      movement = {
        (math.random() - 0.5) * 0.08,
        (math.random() - 0.5) * 0.08
      },
      height = 0.1,
      vertical_speed = 0.08 + math.random() * 0.04,
      frame_speed = 1
    })
  end
end

local function get_habitat_inventory(habitat)
  return habitat and habitat.valid
    and habitat.get_inventory(defines.inventory.roboport_material)
    or nil
end

-- Docked team mates live as script-side crew counts, not items: a roboport's
-- material inventory leaks into logistic network contents, so real items
-- would show up in the network as if they sat in storage.
local function get_habitat_crew(habitat)
  storage.not_alone_habitat_crews = storage.not_alone_habitat_crews or {}
  local crew = storage.not_alone_habitat_crews[habitat.unit_number]
  if not crew then
    crew = {}
    storage.not_alone_habitat_crews[habitat.unit_number] = crew
  end
  return crew
end

-- The material inventory stays as the player-facing inbox: inserted team
-- mate items are absorbed into the crew within one update.
local function absorb_habitat_inbox(habitat)
  local inventory = get_habitat_inventory(habitat)
  if not inventory then
    return
  end
  for kind, item_name in pairs(ITEM_NAME_BY_KIND) do
    local count = inventory.get_item_count(item_name)
    if count > 0 then
      local removed = inventory.remove({name = item_name, count = count})
      if removed > 0 then
        local crew = get_habitat_crew(habitat)
        crew[kind] = (crew[kind] or 0) + removed
      end
    end
  end
end

local function update_habitat_crew_display(habitat)
  storage.not_alone_habitat_crew_renders = storage.not_alone_habitat_crew_renders or {}
  local renders = storage.not_alone_habitat_crew_renders
  local crew = storage.not_alone_habitat_crews
    and storage.not_alone_habitat_crews[habitat.unit_number]
  local parts = {}
  for _, kind in pairs(TEAM_MATE_KINDS) do
    local count = crew and crew[kind] or 0
    if count > 0 then
      parts[#parts + 1] = (KIND_LABEL[kind] or kind) .. " " .. count
    end
  end
  local text = table.concat(parts, "  ")
  local existing = renders[habitat.unit_number]
  local render_object = existing and rendering.get_object_by_id(existing)
  if text == "" then
    if render_object then
      render_object.destroy()
    end
    renders[habitat.unit_number] = nil
    return
  end
  if render_object then
    render_object.text = text
  else
    renders[habitat.unit_number] = rendering.draw_text({
      text = text,
      target = {entity = habitat, offset = {0, -2.4}},
      surface = habitat.surface,
      color = {1, 1, 1},
      alignment = "center",
      only_in_alt_mode = true,
      scale = 0.8
    }).id
  end
end

local function destroy_route_renderings(record)
  for _, render_id in pairs(record.route_render_ids or {}) do
    local render_object = rendering.get_object_by_id(render_id)
    if render_object then
      render_object.destroy()
    end
  end
  record.route_render_ids = {}
end

-- Role colors are baked into each kind's unit prototype (units ignore
-- LuaEntity.color); this only cleans up markers left by older versions.
local function destroy_color_marker(record)
  if record.color_marker_render_id then
    local render_object = rendering.get_object_by_id(record.color_marker_render_id)
    if render_object then
      render_object.destroy()
    end
    record.color_marker_render_id = nil
  end
end

local function destroy_inventory_renderings(record)
  for _, render_id in pairs(record.inventory_render_ids or {}) do
    local render_object = rendering.get_object_by_id(render_id)
    if render_object then
      render_object.destroy()
    end
  end
  record.inventory_render_ids = {}
  record.inventory_render_signature = nil
end

local function get_carried_items(record)
  local counts = {}
  if record.kind == "miner" and record.mining_resource_info
    and (record.carried_count or 0) > 0 then
    counts[record.mining_resource_info.item_name] = record.carried_count
  end
  if record.kind == "builder" and record.builder_item
    and (record.builder_carried_count or 0) > 0 then
    counts[record.builder_item.name] = (counts[record.builder_item.name] or 0)
      + record.builder_carried_count
  end
  if record.kind == "builder" and record.builder_cargo and record.builder_cargo.valid then
    for _, item in pairs(record.builder_cargo.get_contents()) do
      counts[item.name] = (counts[item.name] or 0) + item.count
    end
  end
  if record.kind == "carrier" and record.carrier_item
    and (record.carrier_carried_count or 0) > 0 then
    counts[record.carrier_item.name] = (counts[record.carrier_item.name] or 0)
      + record.carrier_carried_count
  end
  if record.kind == "soldier" and record.soldier_ammo then
    for ammo_name, count in pairs(record.soldier_ammo) do
      if count > 0 then
        counts[ammo_name] = (counts[ammo_name] or 0) + count
      end
    end
  end

  local items = {}
  for name, count in pairs(counts) do
    items[#items + 1] = {name = name, count = count}
  end
  table.sort(items, function(left, right) return left.name < right.name end)
  return items
end

local function update_inventory_renderings(record)
  local items = get_carried_items(record)
  local signature_parts = {}
  for _, item in pairs(items) do
    signature_parts[#signature_parts + 1] = item.name .. ":" .. item.count
  end
  local signature = table.concat(signature_parts, ",")
  local first_object = record.inventory_render_ids and record.inventory_render_ids[1]
    and rendering.get_object_by_id(record.inventory_render_ids[1])
  if record.inventory_render_signature == signature
    and (signature == "" or first_object) then
    return
  end

  destroy_inventory_renderings(record)
  record.inventory_render_signature = signature
  local start_x = -((#items - 1) * INVENTORY_ICON_SPACING) / 2
  for index, item in ipairs(items) do
    local offset = {start_x + (index - 1) * INVENTORY_ICON_SPACING, -1.9}
    local icon = rendering.draw_sprite({
      sprite = "item." .. item.name,
      target = {entity = record.entity, offset = offset},
      surface = record.entity.surface,
      x_scale = INVENTORY_ICON_SCALE,
      y_scale = INVENTORY_ICON_SCALE,
      only_in_alt_mode = true,
      render_layer = "entity-info-icon"
    })
    local count = rendering.draw_text({
      text = tostring(item.count),
      target = {entity = record.entity, offset = {offset[1] + 0.2, offset[2] + 0.2}},
      surface = record.entity.surface,
      color = {1, 1, 1},
      alignment = "center",
      vertical_alignment = "middle",
      scale = 0.7,
      only_in_alt_mode = true
    })
    record.inventory_render_ids[#record.inventory_render_ids + 1] = icon.id
    record.inventory_render_ids[#record.inventory_render_ids + 1] = count.id
  end
end

local function get_manual_destinations(record)
  record.manual_destinations = record.manual_destinations or {}
  return record.manual_destinations
end

local function get_consumer_inventory(consumer, mining_role)
  if consumer.name == BUILDING_REQUESTER_NAME
    or LOGISTICS_SOURCE_MODES[consumer.prototype.logistic_mode] then
    return consumer.get_inventory(defines.inventory.chest)
  end
  return consumer.get_inventory(mining_role.inventory)
end

local function consumer_accepts_item(consumer, mining_role, count)
  local inventory = get_consumer_inventory(consumer, mining_role)
  return inventory and inventory.get_insertable_count(mining_role.item_name) >= count
end

local function find_requesting_consumer(record, mining_role)
  -- Use the closest network, not just one that exactly covers this position:
  -- a full Miner/Builder may have wandered just outside coverage while
  -- gathering and must still be able to find its way back to deliver.
  local network = record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  local requester_point = network and network.select_drop_point({
    stack = {name = mining_role.item_name, count = 1},
    members = "requester"
  })
  local requester = requester_point and requester_point.owner
  if requester and requester.valid and requester.name == BUILDING_REQUESTER_NAME then
    return requester
  end
  return nil
end

local function get_mining_interval(player)
  local mining_speed_modifier = player.character_mining_speed_modifier
  local effective_mining_speed = NORMAL_CHARACTER_MINING_SPEED * (1 + mining_speed_modifier)
  return math.max(1, math.ceil(RESOURCE_MINING_TIME * 60 / effective_mining_speed))
end

local function get_logistics_source_inventory(source)
  if not source or not source.valid
    or not LOGISTICS_SOURCE_MODES[source.prototype.logistic_mode] then
    return nil
  end
  return source.get_inventory(defines.inventory.chest)
end

local function get_logistics_target_inventory(target, inventory_kind)
  if not target or not target.valid then
    return nil
  end
  if inventory_kind == "fuel" then
    return target.burner and target.burner.inventory
  end
  if inventory_kind == "requester" then
    return target.get_inventory(defines.inventory.chest)
  end
  if inventory_kind == "lab" then
    return target.get_inventory(defines.inventory.lab_input)
  end
  return target.get_inventory(defines.inventory.crafter_input)
end

local function item_is_fuel_for(item_name, burner)
  local item_prototype = prototypes.item[item_name]
  return item_prototype and item_prototype.fuel_category
    and burner.fuel_categories[item_prototype.fuel_category]
end

local function find_available_fuel(target, network)
  local burner = target.burner
  if not burner or not burner.inventory then
    return nil
  end

  for _, source in pairs(network.storages) do
    local inventory = get_logistics_source_inventory(source)
    if inventory then
      for _, item in pairs(inventory.get_contents()) do
        if item_is_fuel_for(item.name, burner) then
          return item.name
        end
      end
    end
  end

  -- Fuel carried by team mates exists in no chest yet but is en route.
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      local resource_info = record.kind == "miner" and record.mining_resource_info
      if resource_info and record.entity.valid
        and record.entity.force == target.force
        and item_is_fuel_for(resource_info.item_name, burner) then
        return resource_info.item_name
      end
      if record.kind == "builder" and record.entity.valid
        and record.entity.force == target.force then
        if record.builder_item and (record.builder_carried_count or 0) > 0
          and item_is_fuel_for(record.builder_item.name, burner) then
          return record.builder_item.name
        end
        if record.builder_cargo and record.builder_cargo.valid then
          for _, item in pairs(record.builder_cargo.get_contents()) do
            if item_is_fuel_for(item.name, burner) then
              return item.name
            end
          end
        end
      end
    end
  end
  return nil
end

local function inventory_kind_for_item(target, item_name)
  local burner = target.burner
  if burner and burner.inventory and item_is_fuel_for(item_name, burner) then
    return "fuel"
  end
  if RECIPE_ENTITY_TYPES[target.type] then
    local recipe = target.get_recipe()
    if recipe then
      for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" and ingredient.name == item_name then
          return "input"
        end
      end
    end
  end
  if target.type == "lab" then
    for _, input_name in pairs(target.prototype.lab_inputs or {}) do
      if input_name == item_name then
        return "lab"
      end
    end
  end
  return nil
end

local function get_building_requests(target, network)
  local requests = {}
  if RECIPE_ENTITY_TYPES[target.type] then
    local recipe = target.get_recipe()
    local inventory = target.get_inventory(defines.inventory.crafter_input)
    if recipe and inventory then
      for _, ingredient in pairs(recipe.ingredients) do
        if ingredient.type == "item" then
          -- Batch requests so carriers deliver loads, not single items.
          local desired_count = math.max(math.ceil(ingredient.amount), INGREDIENT_REQUEST_COUNT)
          local missing_count = desired_count - inventory.get_item_count(ingredient.name)
          if missing_count > 0 and inventory.get_insertable_count(ingredient.name) > 0 then
            requests[#requests + 1] = {
              item_name = ingredient.name,
              count = missing_count,
              inventory_kind = "input"
            }
          end
        end
      end
    end
  end

  local fuel_name = find_available_fuel(target, network)
  local fuel_inventory = target.burner and target.burner.inventory
  if fuel_name and fuel_inventory then
    local missing_count = FUEL_REQUEST_COUNT - fuel_inventory.get_item_count(fuel_name)
    if missing_count > 0 and fuel_inventory.get_insertable_count(fuel_name) > 0 then
      requests[#requests + 1] = {
        item_name = fuel_name,
        count = missing_count,
        inventory_kind = "fuel"
      }
    end
  end

  if target.type == "lab" then
    local inventory = target.get_inventory(defines.inventory.lab_input)
    if inventory then
      for _, input_name in pairs(target.prototype.lab_inputs or {}) do
        local missing_count = INGREDIENT_REQUEST_COUNT - inventory.get_item_count(input_name)
        if missing_count > 0 and inventory.get_insertable_count(input_name) > 0 then
          requests[#requests + 1] = {
            item_name = input_name,
            count = missing_count,
            inventory_kind = "lab"
          }
        end
      end
    end
  end
  return requests
end

local function update_building_requester(requester_record, network)
  local target = requester_record.target
  local requester = requester_record.requester
  if not target.valid or not requester.valid then
    if requester.valid then
      requester.destroy()
    end
    return false
  end

  local requester_inventory = requester.get_inventory(defines.inventory.chest)
  for _, item in pairs(requester_inventory.get_contents()) do
    -- Move whatever the target can currently accept, even if the fresh
    -- request that originally justified delivering it has since expired.
    local inventory_kind = inventory_kind_for_item(target, item.name)
    local target_inventory = inventory_kind
      and get_logistics_target_inventory(target, inventory_kind)
    if target_inventory then
      local inserted = target_inventory.insert({name = item.name, count = item.count})
      if inserted > 0 then
        requester_inventory.remove({name = item.name, count = inserted})
      end
    end
  end

  local requests = get_building_requests(target, network)

  local requester_point = requester.get_requester_point()
  local section = requester_point and requester_point.get_section(1)
  if requester_point and not section then
    section = requester_point.add_section()
  end
  if section then
    for slot = 1, BUILDING_REQUEST_SLOT_COUNT do
      section.clear_slot(slot)
    end
    for slot, request in ipairs(requests) do
      if slot > BUILDING_REQUEST_SLOT_COUNT then
        break
      end
      section.set_slot(slot, {
        value = {type = "item", name = request.item_name, quality = "normal"},
        min = request.count
      })
    end
  end
  return true
end

local function update_building_requesters_for_network(surface, force, position, network)
  network = network or surface.find_logistic_network_by_position(
    position_table(position),
    force
  )
  if not network then
    return
  end

  storage.not_alone_building_requesters = storage.not_alone_building_requesters or {}
  storage.not_alone_building_requester_ticks = storage.not_alone_building_requester_ticks or {}
  local network_key = surface.index .. ":" .. force.index
    .. ":" .. network.network_id
  if storage.not_alone_building_requester_ticks[network_key] == game.tick then
    return
  end
  storage.not_alone_building_requester_ticks[network_key] = game.tick

  local requesters = storage.not_alone_building_requesters
  local destinations = surface.find_entities_filtered({
    type = LOGISTICS_DESTINATION_TYPES,
    force = force,
    position = position,
    radius = LOGISTICS_SEARCH_RADIUS
  })
  for _, target in pairs(destinations) do
    local target_network = surface.find_logistic_network_by_position(
      position_table(target.position),
      force
    )
    if target_network == network and target.unit_number then
      local requester_record = requesters[target.unit_number]
      if not requester_record or not requester_record.requester.valid then
        local requester = surface.create_entity({
          name = BUILDING_REQUESTER_NAME,
          position = target.position,
          force = force,
          create_build_effect_smoke = false
        })
        if requester then
          requester.destructible = false
          requester.operable = false
          requester_record = {target = target, requester = requester}
          requesters[target.unit_number] = requester_record
        end
      end
      if requester_record and not update_building_requester(requester_record, network) then
        requesters[target.unit_number] = nil
      end
    end
  end

  for unit_number, requester_record in pairs(requesters) do
    if not requester_record.target.valid or not requester_record.requester.valid then
      if requester_record.requester.valid then
        requester_record.requester.destroy()
      end
      requesters[unit_number] = nil
    end
  end
end

local function update_building_requesters(record)
  update_building_requesters_for_network(
    record.entity.surface,
    record.entity.force,
    record.entity.position
  )
end

local function find_logistics_return_source(record, item_name)
  -- Use the closest network, not just one that exactly covers this position:
  -- a full Miner/Builder may have wandered just outside coverage while
  -- gathering and must still be able to find its way back to deliver.
  local network = record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  if not network then
    return nil
  end

  local nearest_source
  local nearest_distance
  for _, source in pairs(network.storages) do
    local inventory = get_logistics_source_inventory(source)
    if inventory and inventory.get_insertable_count(item_name) > 0 then
      local current_distance = distance_squared(record.entity.position, source.position)
      if not nearest_distance or current_distance < nearest_distance then
        nearest_source = source
        nearest_distance = current_distance
      end
    end
  end
  return nearest_source
end

local function find_logistics_item_source(record, item_name)
  local network = record.entity.surface.find_closest_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  if not network then
    return nil
  end
  local pickup_point = network.select_pickup_point({
    name = item_name,
    position = position_table(record.entity.position),
    include_buffers = true
  })
  local source = pickup_point and pickup_point.owner
  local inventory = get_logistics_source_inventory(source)
  return inventory and inventory.get_item_count(item_name) > 0 and source or nil
end

local function get_resource_info(resource_name)
  local resource_prototype = prototypes.entity[resource_name]
  local mineable = resource_prototype and resource_prototype.mineable_properties
  local product = mineable and mineable.products and mineable.products[1]
  if not product then
    return nil
  end
  local item_prototype = prototypes.item[product.name]
  return {
    item_name = product.name,
    particle_name = resource_name .. "-particle",
    inventory = item_prototype and item_prototype.fuel_category
      and defines.inventory.fuel or defines.inventory.crafter_input
  }
end

local function get_marked_resources(surface_index)
  storage.not_alone_marked_resources = storage.not_alone_marked_resources or {}
  storage.not_alone_marked_resources[surface_index] =
    storage.not_alone_marked_resources[surface_index] or {}
  return storage.not_alone_marked_resources[surface_index]
end

local function destroy_mark_rendering(mark)
  local render_object = mark and mark.render_id and rendering.get_object_by_id(mark.render_id)
  if render_object then
    render_object.destroy()
  end
end

-- Resource entities have no unit_number, so mark them by tile position.
local function resource_mark_key(resource)
  local position = resource.position
  return math.floor(position.x) .. "," .. math.floor(position.y)
end

local function mark_resource_for_mining(resource)
  local marks = get_marked_resources(resource.surface.index)
  local key = resource_mark_key(resource)
  if marks[key] then
    return
  end
  marks[key] = {
    entity = resource,
    render_id = rendering.draw_rectangle({
      color = MARK_COLOR,
      filled = false,
      width = 2,
      left_top = {resource.position.x - 0.4, resource.position.y - 0.4},
      right_bottom = {resource.position.x + 0.4, resource.position.y + 0.4},
      surface = resource.surface,
      draw_on_ground = true
    }).id
  }
end

local function unmark_resource_for_mining(resource)
  local marks = get_marked_resources(resource.surface.index)
  local key = resource_mark_key(resource)
  local mark = marks[key]
  if mark then
    destroy_mark_rendering(mark)
    marks[key] = nil
  end
end

local function is_resource_marked(resource)
  local marks = storage.not_alone_marked_resources
    and storage.not_alone_marked_resources[resource.surface.index]
  return marks and marks[resource_mark_key(resource)] ~= nil
end

local function cleanup_marked_resources(surface_index)
  local marks = storage.not_alone_marked_resources
    and storage.not_alone_marked_resources[surface_index]
  if not marks then
    return
  end
  for key, mark in pairs(marks) do
    if not mark.entity.valid or mark.entity.amount <= 0 then
      destroy_mark_rendering(mark)
      marks[key] = nil
    end
  end
end

local function get_resource_claimant(resource)
  local claimant
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, other_record in pairs(team_mates) do
      if other_record.kind == "miner"
        and other_record.miner_target == resource
        and (other_record.miner_state == "move-to-ore"
          or other_record.miner_state == "mine")
        and other_record.entity and other_record.entity.valid
        and (not claimant
          or other_record.entity.unit_number < claimant.entity.unit_number) then
        claimant = other_record
      end
    end
  end
  return claimant
end

local function find_marked_resource(record, surface, force, position)
  surface = surface or record.entity.surface
  force = force or record.entity.force
  position = position or position_table(record.entity.position)
  local network = surface.find_logistic_network_by_position(position, force)
  if not network then
    return nil
  end
  local marks = get_marked_resources(surface.index)
  local nearest_resource
  local nearest_distance
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      for _, mark in pairs(marks) do
        local resource = mark.entity
        if resource.valid and resource.amount > 0
          and not get_resource_claimant(resource)
          and cell.is_in_logistic_range(resource.position) then
          local current_distance = distance_squared(position, resource.position)
          if not nearest_distance or current_distance < nearest_distance then
            nearest_resource = resource
            nearest_distance = current_distance
          end
        end
      end
    end
  end
  return nearest_resource
end

local function assign_miner_job(record, surface, force, position)
  local resource = find_marked_resource(record, surface, force, position)
  if not resource then
    return false
  end
  record.miner_target = resource
  record.mining_resource_info = get_resource_info(resource.name)
  record.miner_state = "move-to-ore"
  return true
end

local function update_miner(record, player)
  update_mining_animation(record, record.miner_state == "mine")

  if record.miner_state == "move-to-ore" then
    if not record.miner_target or not record.miner_target.valid
      or not is_resource_marked(record.miner_target)
      or get_resource_claimant(record.miner_target) ~= record then
      record.miner_state = nil
      record.miner_target = nil
    elseif distance_squared(record.entity.position, record.miner_target.position) <= 4 then
      record.miner_state = "mine"
      record.next_mining_tick = game.tick + math.random(get_mining_interval(player))
      stop_team_mate(record)
    else
      move_team_mate(record, record.miner_target.position, 2)
    end
    return true
  end

  if record.miner_state == "mine" then
    stop_team_mate(record)
    if game.tick < (record.next_mining_tick or 0) then
      return true
    end
    local resource = record.miner_target
    if not resource or not resource.valid or resource.amount <= 0
      or not is_resource_marked(resource)
      or get_resource_claimant(resource) ~= record then
      record.miner_state = nil
      record.miner_target = nil
      return true
    end

    local mining_position = resource.position
    local remaining_amount = resource.amount - 1
    if remaining_amount > 0 then
      resource.amount = remaining_amount
    else
      -- deplete() invalidates the entity, so drop the mark while it is alive.
      unmark_resource_for_mining(resource)
      resource.deplete()
    end
    record.carried_count = (record.carried_count or 0) + 1
    create_mining_particles(
      record.entity.surface,
      mining_position,
      record.mining_resource_info.particle_name
    )
    record.entity.surface.play_sound({
      path = "not-alone-team-mate-mining-sound",
      position = mining_position,
      volume_modifier = 0.8
    })
    record.next_mining_tick = record.next_mining_tick + get_mining_interval(player)
    if record.carried_count >= MINER_CAPACITY or remaining_amount <= 0 then
      record.miner_state = "find-consumer"
      record.miner_target = nil
    end
    return true
  end

  if record.miner_state == "find-consumer" then
    local consumer = find_requesting_consumer(record, record.mining_resource_info)
      or find_logistics_return_source(record, record.mining_resource_info.item_name)
    if consumer then
      record.miner_target = consumer
      record.miner_state = "move-to-consumer"
    else
      stop_team_mate(record)
    end
    return true
  end

  if record.miner_state == "move-to-consumer" then
    if not record.miner_target or not record.miner_target.valid
      or not consumer_accepts_item(record.miner_target, record.mining_resource_info, 1) then
      record.miner_target = nil
      record.miner_state = "find-consumer"
    elseif distance_squared(record.entity.position, record.miner_target.position) <= 4 then
      record.miner_state = "deliver"
      stop_team_mate(record)
    else
      move_team_mate(record, record.miner_target.position, 2)
    end
    return true
  end

  if record.miner_state == "deliver" then
    local consumer = record.miner_target
    record.miner_target = nil
    if not consumer or not consumer.valid then
      record.miner_state = "find-consumer"
      return true
    end
    local inventory = get_consumer_inventory(consumer, record.mining_resource_info)
    if inventory then
      local insertable = math.min(
        inventory.get_insertable_count(record.mining_resource_info.item_name),
        record.carried_count
      )
      if insertable > 0 then
        record.carried_count = record.carried_count - inventory.insert({
          name = record.mining_resource_info.item_name,
          count = insertable
        })
      end
    end
    -- Deposit what fit; find another destination for any remainder.
    record.miner_state = record.carried_count > 0 and "find-consumer" or nil
    return true
  end

  if (record.carried_count or 0) > 0 then
    record.miner_state = "find-consumer"
    stop_team_mate(record)
    return true
  end
  record.carried_count = 0
  record.mining_resource_info = nil
  if assign_miner_job(record) then
    return true
  end
  return dock_at_habitat(record)
end

update_mining_animation = function(record, should_show)
  local render_object = record.mining_animation_id
    and rendering.get_object_by_id(record.mining_animation_id)
  local mask_object = record.mining_mask_animation_id
    and rendering.get_object_by_id(record.mining_mask_animation_id)
  -- Body and mask only make sense as a pair; a lone survivor (stale save data
  -- or a half-destroyed pair) shows as a second uncolored animation.
  if not should_show or not render_object or not mask_object then
    if render_object then
      render_object.destroy()
    end
    if mask_object then
      mask_object.destroy()
    end
    record.mining_animation_id = nil
    record.mining_mask_animation_id = nil
    render_object = nil
  end
  if should_show then
    if not record.mining_hidden then
      record.mining_color = KIND_COLOR[record.kind]
        or {r = 1, g = 1, b = 1, a = 1}
      local visible_entity = record.entity
      local hidden_entity = visible_entity.surface.create_entity({
        name = HIDDEN_TEAM_MATE_NAME,
        position = visible_entity.position,
        force = visible_entity.force,
        orientation = visible_entity.orientation,
        create_build_effect_smoke = false
      })
      if not hidden_entity then
        return
      end
      hidden_entity.color = record.mining_color
      if visible_entity.name_tag then
        hidden_entity.name_tag = visible_entity.name_tag
      end
      hidden_entity.health = visible_entity.health
      visible_entity.destroy()
      record.entity = hidden_entity
      hidden_entity.commandable.set_command({type = defines.command.stop})
      record.command_kind = "stop"
      record.command_destination = nil
      record.command_target = nil
      record.mining_hidden = true
    end
    if render_object then
      return
    end

    -- Script animations run on the global tick clock; anchor frame zero to this
    -- miner's own strike schedule so miners desync and redraws never jump frames.
    local anchor_tick = record.next_mining_tick or game.tick
    local animation_offset = (MINING_ANIMATION_FRAMES
      - ((anchor_tick * MINING_ANIMATION_SPEED) % MINING_ANIMATION_FRAMES)) % MINING_ANIMATION_FRAMES
    -- Facing selects one of the 8 per-direction prototypes; passing orientation
    -- to draw_animation would rotate the bitmap instead.
    local direction_index = math.floor((record.entity.orientation or 0) * 8 + 0.5) % 8
    record.mining_animation_id = rendering.draw_animation({
      animation = "not-alone-team-mate-mining-" .. direction_index,
      target = record.entity,
      surface = record.entity.surface,
      animation_offset = animation_offset,
      render_layer = "object"
    }).id
    local mask_color = record.mining_color
    record.mining_mask_animation_id = rendering.draw_animation({
      animation = "not-alone-team-mate-mining-mask-" .. direction_index,
      target = record.entity,
      surface = record.entity.surface,
      animation_offset = animation_offset,
      tint = {r = mask_color.r, g = mask_color.g, b = mask_color.b, a = 1},
      -- Strictly above the body layer; sharing "object" leaves the stacking
      -- order tied, letting the untinted body render on top some frames.
      render_layer = "higher-object-under"
    }).id
  end
  if not should_show and record.mining_hidden then
    local hidden_entity = record.entity
    local visible_entity = hidden_entity.surface.create_entity({
      name = TEAM_MATE_ENTITY_BY_KIND[record.kind] or TEAM_MATE_NAME,
      position = hidden_entity.position,
      force = hidden_entity.force,
      orientation = hidden_entity.orientation,
      create_build_effect_smoke = false
    })
    if visible_entity then
      visible_entity.color = record.mining_color
      if hidden_entity.name_tag then
        visible_entity.name_tag = hidden_entity.name_tag
      end
      visible_entity.health = hidden_entity.health
      hidden_entity.destroy()
      record.entity = visible_entity
      record.command_kind = nil
      record.command_destination = nil
      record.command_target = nil
      record.mining_hidden = nil
      record.mining_color = nil
    end
  end
end

local function refresh_route_renderings(record, player_index)
  destroy_route_renderings(record)

  local destinations = get_manual_destinations(record)
  if #destinations == 0 or not record.entity.valid then
    return
  end

  local surface = record.entity.surface
  local previous_target = record.entity
  for _, destination in ipairs(destinations) do
    local line = rendering.draw_line({
      color = ROUTE_COLOR,
      width = 3,
      from = previous_target,
      to = destination,
      surface = surface,
      players = {player_index},
      draw_on_ground = true
    })
    local marker = rendering.draw_circle({
      color = ROUTE_COLOR,
      radius = 0.45,
      width = 3,
      filled = false,
      target = destination,
      surface = surface,
      players = {player_index},
      draw_on_ground = true
    })
    record.route_render_ids[#record.route_render_ids + 1] = line.id
    record.route_render_ids[#record.route_render_ids + 1] = marker.id
    previous_target = destination
  end
end

local function enable_logistics_network_gui(force)
  force.unlock_logistic_network = true
  force.character_logistic_requests = true
end

stop_team_mate = function(record)
  if record.command_kind ~= "stop" then
    record.entity.commandable.set_command({type = defines.command.stop})
    record.command_kind = "stop"
    record.command_destination = nil
    record.command_target = nil
  end
end

move_team_mate = function(record, destination, stopping_distance)
  if distance_squared(record.entity.position, destination) <= stopping_distance * stopping_distance then
    record.move_failures = nil
    stop_team_mate(record)
    return
  end

  if record.command_kind == "move"
    and record.command_destination
    and distance_squared(record.command_destination, destination)
      <= COMMAND_REFRESH_DISTANCE * COMMAND_REFRESH_DISTANCE then
    if record.entity.commandable.has_command
      and record.entity.commandable.command
      and record.entity.commandable.command.type == defines.command.go_to_location then
      return
    end
    -- The same move ended without arrival: retry with a fresh path while
    -- staying focused on the requested destination.
    record.move_failures = (record.move_failures or 0) + 1
    if record.move_failures >= 2 then
      record.move_failures = 0
      record.entity.commandable.set_command({type = defines.command.stop})
      record.command_kind = "stop"
      record.command_destination = nil
      record.command_target = nil
      return
    end
  end

  record.entity.commandable.set_command({
    type = defines.command.go_to_location,
    destination = destination,
    radius = stopping_distance,
    distraction = defines.distraction.none,
    -- Cached path failures otherwise repeat forever, and crowded spawns need
    -- paths that may pass through fellow team mates.
    pathfind_flags = {cache = false, allow_paths_through_own_entities = true}
  })
  record.command_kind = "move"
  record.command_destination = {x = destination.x, y = destination.y}
  record.command_target = nil
end

local function find_nearest_habitat(record)
  local team_mate = record.entity
  local nearest_habitat = nil
  local nearest_distance = nil
  for _, habitat in pairs(team_mate.surface.find_entities_filtered({
    name = LOGISTICS_HUB_NAME,
    force = team_mate.force
  })) do
    local distance = distance_squared(team_mate.position, habitat.position)
    if not nearest_distance or distance < nearest_distance then
      nearest_habitat = habitat
      nearest_distance = distance
    end
  end
  record.habitat = nearest_habitat
  return nearest_habitat
end

local function move_team_mate_toward_destination(record, destination)
  local position = record.entity.position
  local delta_x = destination.x - position.x
  local delta_y = destination.y - position.y
  local distance = math.sqrt(delta_x * delta_x + delta_y * delta_y)
  local waypoint = destination

  if distance > SCOUT_WAYPOINT_DISTANCE then
    local scale = SCOUT_WAYPOINT_DISTANCE / distance
    waypoint = {
      x = position.x + delta_x * scale,
      y = position.y + delta_y * scale
    }
  end

  local surface = record.entity.surface
  local waypoint_chunk = {
    x = math.floor(waypoint.x / CHUNK_SIZE),
    y = math.floor(waypoint.y / CHUNK_SIZE)
  }
  surface.request_to_generate_chunks(waypoint, SCOUT_GENERATION_RADIUS)
  if not surface.is_chunk_generated(waypoint_chunk) then
    stop_team_mate(record)
    return
  end

  move_team_mate(record, waypoint, 1)
end

local function find_soldier_target(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_closest_logistic_network_by_position(position, force)
  if not network then
    return nil
  end

  local nearest_enemy
  local nearest_distance
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      local radius = math.max(cell.logistic_radius, cell.construction_radius)
      if radius > 0 then
        for _, enemy in pairs(surface.find_enemy_units(cell.owner.position, radius, force)) do
          if enemy.valid then
            local current_distance = distance_squared(position, enemy.position)
            if not nearest_distance or current_distance < nearest_distance then
              nearest_enemy = enemy
              nearest_distance = current_distance
            end
          end
        end
      end
    end
  end

  -- Clear the covered enemy units first; only then move on to enemy bases.
  if not nearest_enemy then
    for _, cell in pairs(network.cells) do
      if cell.valid and cell.owner.valid then
        local radius = math.max(cell.logistic_radius, cell.construction_radius)
        if radius > 0 then
          for _, base in pairs(surface.find_entities_filtered({
            position = cell.owner.position,
            radius = radius,
            force = "enemy",
            type = {"unit-spawner", "turret"}
          })) do
            if base.valid then
              local current_distance = distance_squared(position, base.position)
              if not nearest_distance or current_distance < nearest_distance then
                nearest_enemy = base
                nearest_distance = current_distance
              end
            end
          end
        end
      end
    end
  end
  return nearest_enemy
end

local function attack_with_team_mate(record, enemy)
  if record.command_kind == "attack"
    and record.command_target
    and record.command_target.valid
    and record.entity.commandable.has_command
    and record.command_target == enemy then
    return
  end

  record.entity.commandable.set_command({
    type = defines.command.attack,
    target = enemy,
    distraction = defines.distraction.none
  })
  record.command_kind = "attack"
  record.command_destination = nil
  record.command_target = enemy
end

local function get_soldier_ammo_count(record, weapon)
  local total = 0
  for _, ammo_name in pairs(weapon.ammo) do
    total = total + ((record.soldier_ammo and record.soldier_ammo[ammo_name]) or 0)
  end
  return total
end

-- Best owned weapon that still has ammo; nil means fall back to fists.
local function select_soldier_weapon(record)
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if record.soldier_weapons and record.soldier_weapons[weapon.kind]
      and get_soldier_ammo_count(record, weapon) > 0 then
      return weapon
    end
  end
  return nil
end

local function consume_soldier_ammo(record, weapon)
  for _, ammo_name in ipairs(weapon.ammo) do
    local count = record.soldier_ammo and record.soldier_ammo[ammo_name] or 0
    if count > 0 then
      record.soldier_ammo[ammo_name] = count > 1 and count - 1 or nil
      return
    end
  end
end

-- Swap the unit prototype in place, keeping the record, name tag, health,
-- and network membership.
local function replace_team_mate_entity(record, wanted)
  local old_entity = record.entity
  if old_entity.name == wanted then
    return true
  end
  local replacement = old_entity.surface.create_entity({
    name = wanted,
    position = old_entity.position,
    force = old_entity.force,
    create_build_effect_smoke = false
  })
  if not replacement then
    return false
  end
  local tag = old_entity.name_tag
  local health = old_entity.health
  destroy_color_marker(record)
  destroy_inventory_renderings(record)
  old_entity.destroy()
  if tag then
    replacement.name_tag = tag
  end
  replacement.health = math.min(health, replacement.max_health)
  record.entity = replacement
  record.command_kind = nil
  record.command_destination = nil
  record.command_target = nil
  return true
end

-- Swap the unit prototype to match the weapon in hand (nil means fists).
local function ensure_soldier_entity(record, weapon)
  return replace_team_mate_entity(record, weapon and weapon.entity or SOLDIER_FISTS_ENTITY)
end

-- Best owned weapon's ammo first, then that weapon's best ammo tier.
local function find_soldier_ammo_source(record)
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if record.soldier_weapons and record.soldier_weapons[weapon.kind] then
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

local function find_soldier_weapon_source(record, weapon)
  for _, item_name in pairs({weapon.item, weapon.gun}) do
    if item_name and prototypes.item[item_name] then
      local source = find_logistics_item_source(record, item_name)
      if source then
        return source, item_name
      end
    end
  end
  return nil
end

local function assign_soldier_job(record, surface, force, position)
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

local function try_soldier_weapon_pickup(record)
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if not (record.soldier_weapons and record.soldier_weapons[weapon.kind]) then
      local source, item_name = find_soldier_weapon_source(record, weapon)
      if source then
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

local function try_soldier_armor_pickup(record)
  for tier = #SOLDIER_ARMORS, (record.soldier_armor or 0) + 1, -1 do
    local armor = SOLDIER_ARMORS[tier]
    if prototypes.item[armor.item] then
      local source = find_logistics_item_source(record, armor.item)
      if source then
        record.soldier_state = "pickup-armor"
        record.soldier_pickup_armor = tier
        record.soldier_pickup_source = source
        return true
      end
    end
  end
  return false
end

local function start_soldier_restock(record)
  local source, ammo_name = find_soldier_ammo_source(record)
  if not source then
    return false
  end
  record.soldier_state = "restock"
  record.soldier_ammo_source = source
  record.soldier_restock_name = ammo_name
  return true
end

local function update_soldier(record)
  if record.soldier_state == "restock" then
    local source = record.soldier_ammo_source
    local inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not inventory
      or inventory.get_item_count(record.soldier_restock_name) == 0 then
      record.soldier_state = nil
      record.soldier_ammo_source = nil
      record.soldier_restock_name = nil
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
      stop_team_mate(record)
    else
      move_team_mate(record, source.position, 2)
    end
    return true
  end

  if record.soldier_state == "pickup-weapon" then
    local source = record.soldier_pickup_source
    local weapon = SOLDIER_WEAPON_BY_KIND[record.soldier_pickup_kind]
    local pickup_item = record.soldier_pickup_item or (weapon and weapon.item)
    local inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not inventory or not weapon
      or inventory.get_item_count(pickup_item) == 0 then
      record.soldier_state = nil
      record.soldier_pickup_source = nil
      record.soldier_pickup_kind = nil
      record.soldier_pickup_item = nil
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      if inventory.remove({name = pickup_item, count = 1}) == 1 then
        record.soldier_weapons = record.soldier_weapons or {}
        record.soldier_weapons[weapon.kind] = true
      end
      record.soldier_state = nil
      record.soldier_pickup_source = nil
      record.soldier_pickup_kind = nil
      record.soldier_pickup_item = nil
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
      stop_team_mate(record)
    else
      move_team_mate(record, source.position, 2)
    end
    return true
  end

  local target = find_soldier_target(record)
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
    if weapon and game.tick >= (record.soldier_next_ammo_tick or 0) then
      consume_soldier_ammo(record, weapon)
      record.soldier_next_ammo_tick = game.tick + SOLDIER_AMMO_TICKS_PER_ROUND
    end
    return true
  end

  -- Idle: collect new weapons, then armor upgrades, then ammo, then dock.
  if try_soldier_weapon_pickup(record) then
    return true
  end
  if try_soldier_armor_pickup(record) then
    return true
  end
  if not select_soldier_weapon(record) and start_soldier_restock(record) then
    return true
  end
  return dock_at_habitat(record)
end

local function get_ghost_item(ghost)
  if not ghost or not ghost.valid or ghost.type ~= "entity-ghost" then
    return nil
  end
  for key, item in pairs(ghost.ghost_prototype.items_to_place_this or {}) do
    return {
      name = item.name or key,
      quality = ghost.quality.name
    }
  end
  return nil
end

local function find_builder_source(network, item, position)
  local pickup_point = network.select_pickup_point({
    name = item,
    position = position,
    include_buffers = true
  })
  local source = pickup_point and pickup_point.owner
  local inventory = get_logistics_source_inventory(source)
  return inventory and inventory.get_item_count(item) > 0 and source or nil
end

local function builder_target_is_claimed(target, current_record)
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record ~= current_record and record.builder_target == target then
        return true
      end
    end
  end
  return false
end

local function find_builder_job(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_logistic_network_by_position(
    position_table(position),
    force
  )
  if not network then
    return nil, nil, nil
  end

  local nearest_ghost = nil
  local nearest_source = nil
  local nearest_item_name = nil
  local nearest_distance = nil
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      for _, ghost in pairs(surface.find_entities_filtered({
        type = "entity-ghost",
        force = force,
        position = cell.owner.position,
        radius = cell.logistic_radius * 1.5
      })) do
        if cell.is_in_logistic_range(ghost.position)
          and not builder_target_is_claimed(ghost, record) then
          local item = get_ghost_item(ghost)
          local source = item and find_builder_source(
            network,
            item,
            position_table(ghost.position)
          )
          local distance = distance_squared(position, ghost.position)
          if source and (not nearest_distance or distance < nearest_distance) then
            nearest_ghost = ghost
            nearest_source = source
            nearest_item_name = item
            nearest_distance = distance
          end
        end
      end
    end
  end
  return nearest_ghost, nearest_source, nearest_item_name
end

local BUILDER_UNREACHABLE_RETRY_TICKS = 7200

local function builder_target_is_unreachable(record, target)
  local unreachable = record.builder_unreachable
  if not unreachable then
    return false
  end
  local kept = {}
  local found = false
  for _, entry in pairs(unreachable) do
    if entry.entity.valid and game.tick - entry.tick < BUILDER_UNREACHABLE_RETRY_TICKS then
      kept[#kept + 1] = entry
      if entry.entity == target then
        found = true
      end
    end
  end
  record.builder_unreachable = kept[1] and kept or nil
  return found
end

local function find_builder_deconstruction_target(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_logistic_network_by_position(position, force)
  if not network then
    return nil
  end

  local function network_can_store(stack)
    local item = {name = stack.name, quality = stack.quality.name}
    for _, storage_entity in pairs(network.storages) do
      local inventory = get_logistics_source_inventory(storage_entity)
      if inventory and inventory.get_insertable_count(item) > 0 then
        return true
      end
    end
    return false
  end

  local nearest_target
  local nearest_distance
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      local habitat_cell = cell.owner.name == LOGISTICS_HUB_NAME
      local search_radius = habitat_cell and cell.logistic_radius or cell.construction_radius
      local targets = surface.find_entities_filtered({
        position = cell.owner.position,
        radius = search_radius * 1.5,
        to_be_deconstructed = true
      })
      for _, item_entity in pairs(surface.find_entities_filtered({
        position = cell.owner.position,
        radius = search_radius * 1.5,
        type = "item-entity"
      })) do
        targets[#targets + 1] = item_entity
      end
      for _, target in pairs(targets) do
        local distance = distance_squared(position, target.position)
        local can_collect = target.type == "item-entity"
          and target.stack.valid_for_read
        if (target.minable or can_collect)
          and (not can_collect or network_can_store(target.stack))
          and target.is_registered_for_deconstruction(force)
          and not builder_target_is_unreachable(record, target)
          and (habitat_cell and cell.is_in_logistic_range(target.position)
            or not habitat_cell and cell.is_in_construction_range(target.position))
          and not builder_target_is_claimed(target, record)
          and (not nearest_distance or distance < nearest_distance) then
          nearest_target = target
          nearest_distance = distance
        end
      end
    end
  end
  return nearest_target
end

local function assign_builder_job(record, surface, force, position)
  local target, source, item = find_builder_job(record, surface, force, position)
  if target then
    record.builder_target = target
    record.builder_source = source
    record.builder_item = item
    record.builder_carried_count = 0
    record.builder_state = "move-to-source"
    return true
  end

  target = find_builder_deconstruction_target(record, surface, force, position)
  if target then
    record.builder_target = target
    record.builder_source = nil
    record.builder_item = nil
    record.builder_carried_count = 0
    record.builder_state = "move-to-deconstruction"
    return true
  end
  return false
end

local function get_builder_cargo(record)
  if not record.builder_cargo or not record.builder_cargo.valid then
    record.builder_cargo = game.create_inventory(BUILDER_CARGO_SLOTS)
  end
  return record.builder_cargo
end

local function grow_builder_cargo(record)
  local cargo = record.builder_cargo
  if not cargo or not cargo.valid or not cargo.is_empty()
    or #cargo >= MAX_BUILDER_CARGO_SLOTS then
    return cargo
  end
  local new_size = math.min(#cargo * 2, MAX_BUILDER_CARGO_SLOTS)
  cargo.destroy()
  record.builder_cargo = game.create_inventory(new_size)
  return record.builder_cargo
end

local function size_builder_cargo_for_target(record, target)
  local required_slots = #(target.prototype.mineable_properties.products or {})
  for inventory_index = 1, target.get_max_inventory_index() do
    local inventory = target.get_inventory(inventory_index)
    if inventory then
      required_slots = required_slots + #inventory
    end
  end
  required_slots = math.max(required_slots, BUILDER_CARGO_SLOTS)
  local cargo = get_builder_cargo(record)
  if cargo.is_empty() and #cargo < required_slots then
    cargo.destroy()
    record.builder_cargo = game.create_inventory(
      math.min(required_slots, MAX_BUILDER_CARGO_SLOTS)
    )
  end
  return record.builder_cargo
end

local function find_builder_cargo_action(record, cargo)
  for slot = 1, #cargo do
    local stack = cargo[slot]
    if stack.valid_for_read then
      local item = {name = stack.name, quality = stack.quality.name}
      local delivery_info = {item_name = item.name, inventory = defines.inventory.chest}
      local consumer = find_requesting_consumer(record, delivery_info)
      if consumer and consumer.valid
        and consumer_accepts_item(consumer, delivery_info, 1) then
        return item, consumer, consumer.get_inventory(defines.inventory.chest)
      end
    end
  end

  for slot = 1, #cargo do
    local stack = cargo[slot]
    if stack.valid_for_read then
      local item = {name = stack.name, quality = stack.quality.name}
      local source = find_logistics_return_source(record, item)
      local inventory = get_logistics_source_inventory(source)
      if inventory then
        return item, source, inventory
      end
    end
  end
  return nil, nil, nil
end

local function return_builder_cargo(record)
  local cargo = record.builder_cargo
  if not cargo or not cargo.valid or cargo.is_empty() then
    record.builder_delivery_item = nil
    record.builder_delivery_target = nil
    record.builder_delivery_inventory = nil
    if record.kind == "builder" and record.builder_deconstruction_started
      and record.builder_target and record.builder_target.valid
      and record.builder_target.to_be_deconstructed() then
      record.builder_state = "move-to-deconstruction"
    else
      record.builder_deconstruction_started = nil
      if record.kind == "builder" then
        record.builder_state = nil
      end
    end
    return false
  end

  -- Keep walking toward an already-chosen destination instead of re-running
  -- the network search every tick, which can transiently fail (returning no
  -- destination) while the team mate is between logistic cells en route.
  local item = record.builder_delivery_item
  local destination = record.builder_delivery_target
  local inventory = destination and destination.valid and record.builder_delivery_inventory
  if not item or not destination or not destination.valid or not inventory
    or cargo.get_item_count(item.name) == 0
    or inventory.get_insertable_count(item.name) == 0 then
    item, destination, inventory = find_builder_cargo_action(record, cargo)
    record.builder_delivery_item = item
    record.builder_delivery_target = destination
    record.builder_delivery_inventory = inventory
  end
  if not destination then
    stop_team_mate(record)
    return true
  end

  if distance_squared(record.entity.position, destination.position) <= 4 then
    local count = math.min(
      cargo.get_item_count(item),
      inventory.get_insertable_count(item)
    )
    if count > 0 then
      local inserted = inventory.insert({
        name = item.name,
        quality = item.quality,
        count = count
      })
      if inserted > 0 then
        cargo.remove({name = item.name, quality = item.quality, count = inserted})
      end
    end
    -- Force a fresh search next tick: this slot may be empty, or the
    -- destination may now be full, or another cargo item needs a turn.
    record.builder_delivery_item = nil
    record.builder_delivery_target = nil
    record.builder_delivery_inventory = nil
  else
    move_team_mate(record, destination.position, 2)
  end
  return true
end

local function return_builder_material(record)
  if not record.builder_item or (record.builder_carried_count or 0) == 0 then
    record.builder_item = nil
    record.builder_source = nil
    record.builder_target = nil
    record.builder_carried_count = 0
    record.builder_state = nil
    return false
  end
  local inventory = get_logistics_source_inventory(record.builder_source)
  if not inventory or inventory.get_insertable_count(record.builder_item) == 0 then
    record.builder_source = find_logistics_return_source(record, record.builder_item)
    inventory = get_logistics_source_inventory(record.builder_source)
  end
  if not inventory then
    record.builder_source = nil
    stop_team_mate(record)
    return true
  end
  if distance_squared(record.entity.position, record.builder_source.position) <= 4 then
    local inserted = inventory.insert({
      name = record.builder_item.name,
      quality = record.builder_item.quality,
      count = 1
    })
    if inserted == 1 then
      record.builder_item = nil
      record.builder_source = nil
      record.builder_target = nil
      record.builder_carried_count = 0
      record.builder_state = nil
      return false
    end
  end
  move_team_mate(record, record.builder_source.position, 2)
  return true
end

dock_at_habitat = function(record)
  local habitat = find_nearest_habitat(record)
  if not habitat then
    stop_team_mate(record)
    return true
  end
  if distance_squared(record.entity.position, habitat.position) > 9 then
    move_team_mate(record, habitat.position, 3)
    return true
  end

  stop_team_mate(record)
  update_mining_animation(record, false)
  if not habitat.unit_number then
    return true
  end
  local crew = get_habitat_crew(habitat)
  crew[record.kind] = (crew[record.kind] or 0) + 1
  -- Docked Soldiers keep their weapons and ammo; the arsenal waits in the
  -- Habitat's locker and is restored to the next Soldier deployed from it.
  if record.kind == "soldier"
    and ((record.soldier_weapons and next(record.soldier_weapons))
      or (record.soldier_ammo and next(record.soldier_ammo))
      or record.soldier_armor) then
    storage.not_alone_soldier_lockers = storage.not_alone_soldier_lockers or {}
    local lockers = storage.not_alone_soldier_lockers[habitat.unit_number] or {}
    lockers[#lockers + 1] = {
      weapons = record.soldier_weapons,
      ammo = record.soldier_ammo,
      armor = record.soldier_armor
    }
    storage.not_alone_soldier_lockers[habitat.unit_number] = lockers
  end
  destroy_route_renderings(record)
  destroy_inventory_renderings(record)
  destroy_color_marker(record)
  if record.builder_cargo and record.builder_cargo.valid then
    -- Should be empty already (see update_builder's cargo-priority guard);
    -- spill anything left at the habitat rather than deleting it.
    if not record.builder_cargo.is_empty() then
      record.entity.surface.spill_inventory({
        position = position_table(habitat.position),
        inventory = record.builder_cargo
      })
    end
    record.builder_cargo.destroy()
  end
  record.entity.destroy()
  return false
end

local function builder_is_at_target(record, target)
  if target.type == "item-entity" then
    return distance_squared(record.entity.position, target.position)
      <= BUILDER_ITEM_PICKUP_DISTANCE * BUILDER_ITEM_PICKUP_DISTANCE
  end
  return distance_squared_to_box(record.entity.position, target.bounding_box)
    <= BUILDER_TARGET_INTERACTION_DISTANCE * BUILDER_TARGET_INTERACTION_DISTANCE
end

local function builder_target_destination(record, target)
  if target.type == "item-entity" then
    return position_table(target.position)
  end
  local box = target.bounding_box
  local position = record.entity.position
  return {
    x = math.max(
      box.left_top.x - BUILDER_TARGET_CLEARANCE,
      math.min(position.x, box.right_bottom.x + BUILDER_TARGET_CLEARANCE)
    ),
    y = math.max(
      box.left_top.y - BUILDER_TARGET_CLEARANCE,
      math.min(position.y, box.right_bottom.y + BUILDER_TARGET_CLEARANCE)
    )
  }
end

local function update_builder(record)
  -- Never let cargo go undelivered: whatever the state machine was doing,
  -- unspent deconstruction cargo always takes priority over new jobs or
  -- docking, so it can never be silently lost or abandoned mid-route.
  if record.builder_state ~= "return-deconstruction"
    and record.builder_cargo and record.builder_cargo.valid
    and not record.builder_cargo.is_empty() then
    record.builder_state = "return-deconstruction"
  end

  if record.builder_state == "return-deconstruction" then
    return_builder_cargo(record)
    return true
  end
  if record.builder_state == "return-material" then
    return_builder_material(record)
    return true
  end
  if record.builder_state == "move-to-source" then
    local inventory = get_logistics_source_inventory(record.builder_source)
    if not record.builder_target or not record.builder_target.valid
      or not inventory or inventory.get_item_count(record.builder_item) == 0 then
      record.builder_state = nil
      record.builder_target = nil
      record.builder_source = nil
      record.builder_item = nil
      record.builder_carried_count = 0
    elseif distance_squared(record.entity.position, record.builder_source.position) <= 4 then
      if inventory.remove({
        name = record.builder_item.name,
        quality = record.builder_item.quality,
        count = 1
      }) == 1 then
        record.builder_carried_count = 1
        record.builder_state = "move-to-ghost"
      else
        record.builder_state = nil
        record.builder_target = nil
        record.builder_source = nil
        record.builder_item = nil
      end
    else
      move_team_mate(record, record.builder_source.position, 2)
    end
    return true
  end
  if record.builder_state == "move-to-ghost" then
    if not record.builder_target or not record.builder_target.valid then
      record.builder_state = "return-material"
    elseif distance_squared(record.entity.position, record.builder_target.position) <= 16 then
      local _, revived_entity = record.builder_target.revive({raise_revive = true})
      if revived_entity then
        record.builder_item = nil
        record.builder_carried_count = 0
        record.builder_source = nil
        record.builder_target = nil
        record.builder_state = nil
      else
        record.builder_state = "return-material"
      end
      stop_team_mate(record)
    else
      move_team_mate(record, record.builder_target.position, 4)
    end
    return true
  end
  if record.builder_state == "move-to-deconstruction" then
    local target = record.builder_target
    if not target or not target.valid
      or not target.to_be_deconstructed()
      or (not record.builder_deconstruction_started
        and not target.is_registered_for_deconstruction(record.entity.force)) then
      record.builder_deconstruction_started = nil
      record.builder_target = nil
      record.builder_state = nil
      record.builder_approach_position = nil
      record.builder_approach_stalls = nil
    elseif builder_is_at_target(record, target) then
      record.builder_approach_position = nil
      record.builder_approach_stalls = nil
      if target.type == "item-entity" then
        local cargo = get_builder_cargo(record)
        local transferred = cargo[1].transfer_stack(target.stack)
        if transferred and target.valid then
          target.destroy()
        end
        stop_team_mate(record)
        if transferred then
          record.builder_deconstruction_started = nil
          record.builder_target = nil
          record.builder_state = "return-deconstruction"
        end
      else
        local cargo = size_builder_cargo_for_target(record, target)
        local mined = target.mine({inventory = cargo, force = false})
        stop_team_mate(record)
        if not cargo.is_empty() then
          record.builder_deconstruction_started = target.valid or nil
          record.builder_state = "return-deconstruction"
        elseif mined then
          record.builder_deconstruction_started = nil
          record.builder_target = nil
          record.builder_state = nil
        else
          grow_builder_cargo(record)
        end
      end
    else
      local position = record.entity.position
      if record.builder_approach_position
        and distance_squared(position, record.builder_approach_position) < 0.01 then
        record.builder_approach_stalls = (record.builder_approach_stalls or 0) + 1
        if record.builder_approach_stalls >= 30 then
          -- This builder cannot path to the target; release the claim so
          -- other builders may take it, and skip it for a while ourselves.
          record.builder_unreachable = record.builder_unreachable or {}
          record.builder_unreachable[#record.builder_unreachable + 1] = {
            entity = target,
            tick = game.tick
          }
          record.builder_deconstruction_started = nil
          record.builder_target = nil
          record.builder_state = nil
          record.builder_approach_position = nil
          record.builder_approach_stalls = nil
          stop_team_mate(record)
          return true
        end
      else
        record.builder_approach_position = position_table(position)
        record.builder_approach_stalls = 0
      end
      move_team_mate(record, builder_target_destination(record, target), 0.2)
    end
    return true
  end

  if assign_builder_job(record) then
    return true
  end
  return dock_at_habitat(record)
end

local function create_team_mate(player, kind, index, spawn_center)
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

  local character = player.surface.create_entity({
    name = TEAM_MATE_ENTITY_BY_KIND[kind] or TEAM_MATE_NAME,
    position = spawn_position,
    force = player.force,
    create_build_effect_smoke = false
  })
  if not character then
    return nil
  end

  character.name_tag = (KIND_LABEL[kind] or "Team mate") .. " " .. index
  local record = {entity = character, kind = kind}
  find_nearest_habitat(record)
  return record
end

local function find_any_player_for_force(force)
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
local function reconcile_orphaned_team_mates()
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
local function get_requested_count(logistic_point, item_name, quality)
  for _, filter in pairs(logistic_point.filters or {}) do
    if filter.name == item_name and (not filter.quality or filter.quality == quality) then
      return filter.count
    end
  end
  return nil
end

local function find_carrier_job(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local network = surface.find_logistic_network_by_position(position, force)
  if not network then
    return nil, nil, nil, nil
  end

  for _, item in pairs(network.get_contents()) do
    local item_id = {name = item.name, quality = item.quality}
    local drop_point = network.select_drop_point({
      stack = {name = item.name, quality = item.quality, count = 1},
      members = "requester"
    })
    local consumer = drop_point and drop_point.owner
    local consumer_inventory = consumer and consumer.valid
      and consumer.get_inventory(defines.inventory.chest)
    if consumer_inventory then
      -- Only deliver up to what's actually still requested, not a full stack.
      local requested = get_requested_count(drop_point, item.name, item.quality)
      local missing = requested
        and math.max(requested - consumer_inventory.get_item_count(item_id), 0)
        or consumer_inventory.get_insertable_count(item_id)
      missing = math.min(missing, consumer_inventory.get_insertable_count(item_id))
      if missing > 0 then
        local pickup_point = network.select_pickup_point({
          name = item_id,
          position = position,
          include_buffers = true
        })
        local source = pickup_point and pickup_point.owner
        local source_inventory = get_logistics_source_inventory(source)
        local available = source_inventory and source_inventory.get_item_count(item_id) or 0
        if available > 0 then
          return source, consumer, item_id, math.min(missing, available)
        end
      end
    end
  end
  return nil, nil, nil, nil
end

local function assign_carrier_job(record, surface, force, position)
  local source, target, item, needed = find_carrier_job(record, surface, force, position)
  if not source then
    return false
  end
  record.carrier_source = source
  record.carrier_target = target
  record.carrier_item = item
  record.carrier_needed_count = needed
  record.carrier_carried_count = 0
  record.carrier_state = "move-to-source"
  return true
end

local function update_carrier(record)
  if record.carrier_state == "move-to-source" then
    local source = record.carrier_source
    local inventory = get_logistics_source_inventory(source)
    if not source or not source.valid or not inventory
      or inventory.get_item_count(record.carrier_item) == 0 then
      record.carrier_state = nil
      record.carrier_source = nil
      record.carrier_target = nil
      record.carrier_item = nil
      record.carrier_needed_count = nil
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      local removed = inventory.remove({
        name = record.carrier_item.name,
        quality = record.carrier_item.quality,
        count = math.min(CARRIER_CAPACITY, record.carrier_needed_count or CARRIER_CAPACITY)
      })
      if removed > 0 then
        record.carrier_carried_count = removed
        record.carrier_state = "move-to-target"
      else
        record.carrier_state = nil
        record.carrier_source = nil
        record.carrier_target = nil
        record.carrier_item = nil
        record.carrier_needed_count = nil
      end
    else
      move_team_mate(record, source.position, 2)
    end
    return true
  end

  if record.carrier_state == "move-to-target" then
    local target = record.carrier_target
    local target_inventory = target and target.valid
      and target.get_inventory(defines.inventory.chest)
    if not target_inventory
      or target_inventory.get_insertable_count(record.carrier_item) == 0 then
      -- No longer wanted: return it to network storage instead of stranding it.
      target = find_logistics_return_source(record, record.carrier_item)
      record.carrier_target = target
      target_inventory = target and get_logistics_source_inventory(target)
    end
    if not target then
      record.carrier_state = nil
      record.carrier_source = nil
      record.carrier_item = nil
      record.carrier_carried_count = 0
      record.carrier_needed_count = nil
    elseif distance_squared(record.entity.position, target.position) <= 4 then
      local inserted = target_inventory.insert({
        name = record.carrier_item.name,
        quality = record.carrier_item.quality,
        count = record.carrier_carried_count
      })
      record.carrier_carried_count = record.carrier_carried_count - inserted
      stop_team_mate(record)
      if record.carrier_carried_count <= 0 then
        record.carrier_state = nil
        record.carrier_source = nil
        record.carrier_target = nil
        record.carrier_item = nil
        record.carrier_needed_count = nil
      end
    else
      move_team_mate(record, target.position, 2)
    end
    return true
  end

  if assign_carrier_job(record) then
    return true
  end
  return dock_at_habitat(record)
end

local function assign_job(record, surface, force, position)
  if record.kind == "miner" then
    return assign_miner_job(record, surface, force, position)
  elseif record.kind == "builder" then
    return assign_builder_job(record, surface, force, position)
  elseif record.kind == "carrier" then
    return assign_carrier_job(record, surface, force, position)
  elseif record.kind == "soldier" then
    return assign_soldier_job(record, surface, force, position)
  end
  return false
end

local function auto_deploy_from_habitat(habitat)
  local player = find_any_player_for_force(habitat.force)
  if not player or not player.valid or not habitat.unit_number then
    return
  end
  local crew = get_habitat_crew(habitat)

  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  for _, kind in pairs(TEAM_MATE_KINDS) do
    local job = {entity = habitat, kind = kind}
    if (crew[kind] or 0) > 0
      and assign_job(job, habitat.surface, habitat.force, position_table(habitat.position)) then
      local team_mates = storage.not_alone_team_mates[player.index] or {}
      local record = create_team_mate(player, kind, #team_mates + 1, habitat.position)
      if record then
        crew[kind] = crew[kind] - 1
        job.entity = nil
        job.kind = nil
        for key, value in pairs(job) do
          record[key] = value
        end
        record.habitat = habitat
        -- Restore a docked Soldier's stashed weapons and ammo.
        if kind == "soldier" then
          local lockers = storage.not_alone_soldier_lockers
            and storage.not_alone_soldier_lockers[habitat.unit_number]
          if lockers and #lockers > 0 then
            local locker = table.remove(lockers)
            record.soldier_weapons = locker.weapons
            record.soldier_ammo = locker.ammo
            record.soldier_armor = locker.armor
          end
        end
        team_mates[#team_mates + 1] = record
        storage.not_alone_team_mates[player.index] = team_mates
      end
    end
  end
end

local function configure_freeplay_starter_inventory()
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

local function queue_starter_inventory(player_index)
  storage.not_alone_starter_inventory_pending =
    storage.not_alone_starter_inventory_pending or {}
  storage.not_alone_starter_inventory_pending[player_index] = true
end

local function queue_starter_inventory_migration()
  if storage.not_alone_starter_inventory_version == STARTER_INVENTORY_VERSION then
    return
  end
  for _, player in pairs(game.players) do
    queue_starter_inventory(player.index)
  end
  storage.not_alone_starter_inventory_version = STARTER_INVENTORY_VERSION
end

local function ensure_starter_inventory(player)
  if not player or not player.valid or not player.character or not player.character.valid then
    return false
  end

  local satisfied = true
  for kind, item_name in pairs(ITEM_NAME_BY_KIND) do
    local missing = math.max(INITIAL_COUNT_BY_KIND[kind] - player.get_item_count(item_name), 0)
    if missing > 0 then
      player.insert({name = item_name, count = missing})
    end
    if player.get_item_count(item_name) < INITIAL_COUNT_BY_KIND[kind] then
      satisfied = false
    end
  end

  local missing_habitats = math.max(
    INITIAL_HABITAT_COUNT - player.get_item_count(LOGISTICS_HUB_NAME),
    0
  )
  if missing_habitats > 0 then
    player.insert({name = LOGISTICS_HUB_NAME, count = missing_habitats})
  end

  return satisfied and player.get_item_count(LOGISTICS_HUB_NAME) >= INITIAL_HABITAT_COUNT
end

local function rescue_immobile_team_mate(record)
  local entity = record.entity
  if record.command_kind ~= "move" then
    record.stall_position = nil
    record.stall_count = nil
    return
  end
  if record.stall_position
    and distance_squared(entity.position, record.stall_position) < 0.01 then
    record.stall_count = (record.stall_count or 0) + 1
    if record.stall_count >= 30 then
      record.stall_count = 0
      record.move_failures = 2
      record.command_kind = nil
      record.command_destination = nil
    end
  else
    record.stall_position = position_table(entity.position)
    record.stall_count = 0
  end
end

local function update_team_mate(record, player)
  local character = record.entity
  if not character.valid or character.type ~= "unit" then
    destroy_route_renderings(record)
    destroy_inventory_renderings(record)
    destroy_color_marker(record)
    return false
  end

  rescue_immobile_team_mate(record)
  destroy_color_marker(record)
  -- Older saves deployed the untinted generic unit; swap in the role variant.
  if not record.mining_hidden and record.kind ~= "soldier" then
    local wanted = TEAM_MATE_ENTITY_BY_KIND[record.kind]
    if wanted and character.name ~= wanted then
      if not replace_team_mate_entity(record, wanted) then
        return true
      end
      character = record.entity
    end
  end
  update_inventory_renderings(record)
  update_building_requesters(record)

  local manual_destinations = get_manual_destinations(record)
  if record.route_render_ids == nil and #manual_destinations > 0 then
    refresh_route_renderings(record, player.index)
  end

  if #manual_destinations > 0 then
    if character.surface_index == record.manual_surface_index then
      local route_changed = false
      -- The engine parks units near, not on, a waypoint; a finished move
      -- command also counts as arrival so crowded routes cannot loop forever.
      while #manual_destinations > 0
        and (distance_squared(character.position, manual_destinations[1]) <= 4
          or (record.command_kind == "move"
            and not character.commandable.has_command)) do
        table.remove(manual_destinations, 1)
        route_changed = true
      end

      if route_changed then
        record.command_kind = nil
        record.command_destination = nil
        refresh_route_renderings(record, player.index)
      end

      if #manual_destinations == 0 then
        record.manual_surface_index = nil
        stop_team_mate(record)
      else
        move_team_mate_toward_destination(record, manual_destinations[1])
      end
    else
      record.manual_destinations = {}
      record.manual_surface_index = nil
      stop_team_mate(record)
      refresh_route_renderings(record, player.index)
    end
    return true
  end

  local enemy = character.surface.find_nearest_enemy({
    position = character.position,
    max_distance = ENGAGEMENT_RADIUS,
    force = character.force
  })

  -- Soldiers manage their own combat (with ammo) in update_soldier.
  if enemy and enemy.valid and record.kind ~= "soldier" then
    attack_with_team_mate(record, enemy)
    return true
  end

  if record.kind == "miner" then
    return update_miner(record, player)
  elseif record.kind == "builder" then
    return update_builder(record)
  elseif record.kind == "carrier" then
    return update_carrier(record)
  elseif record.kind == "soldier" then
    return update_soldier(record)
  end
  return dock_at_habitat(record)
end

function poc.on_init()
  storage.not_alone_team_mates = {}
  storage.not_alone_selected_team_mates = {}
  storage.not_alone_starter_inventory_pending = {}
  storage.not_alone_marked_resources = {}
  configure_freeplay_starter_inventory()
  for _, player in pairs(game.players) do
    enable_logistics_network_gui(player.force)
    queue_starter_inventory(player.index)
  end
  storage.not_alone_starter_inventory_version = STARTER_INVENTORY_VERSION
end

function poc.on_configuration_changed()
  rendering.clear("not-alone")
  for _, requester_record in pairs(storage.not_alone_building_requesters or {}) do
    if requester_record.requester and requester_record.requester.valid then
      requester_record.requester.destroy()
    end
  end
  storage.not_alone_building_requesters = nil
  storage.not_alone_building_requester_ticks = nil
  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  storage.not_alone_selected_team_mates = {}
  storage.not_alone_marked_resources = {}
  queue_starter_inventory_migration()
  configure_freeplay_starter_inventory()
  for _, player in pairs(game.players) do
    enable_logistics_network_gui(player.force)
  end
end

function poc.on_player_created(event)
  local player = game.get_player(event.player_index)
  enable_logistics_network_gui(player.force)
  queue_starter_inventory(player.index)
end

function poc.on_player_removed(event)
  local team_mates = storage.not_alone_team_mates
    and storage.not_alone_team_mates[event.player_index]
  if team_mates then
    for _, record in pairs(team_mates) do
      destroy_route_renderings(record)
      destroy_inventory_renderings(record)
      destroy_color_marker(record)
      if record.builder_cargo and record.builder_cargo.valid then
        if not record.builder_cargo.is_empty() and record.entity.valid then
          record.entity.surface.spill_inventory({
            position = position_table(record.entity.position),
            inventory = record.builder_cargo
          })
        end
        record.builder_cargo.destroy()
      end
      if record.entity.valid then
        record.entity.destroy()
      end
    end
    storage.not_alone_team_mates[event.player_index] = nil
  end
  if storage.not_alone_selected_team_mates then
    storage.not_alone_selected_team_mates[event.player_index] = nil
  end
end

function poc.on_selected_area(event)
  if event.item ~= COMMAND_TOOL_NAME then
    return
  end

  local owned_team_mates = {}
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    if record.entity.valid then
      owned_team_mates[record.entity.unit_number] = true
    end
  end

  local selected = {}
  local selected_count = 0
  for _, entity in pairs(event.entities) do
    if entity.valid and owned_team_mates[entity.unit_number] then
      selected[entity.unit_number] = true
      selected_count = selected_count + 1
    end
  end

  storage.not_alone_selected_team_mates = storage.not_alone_selected_team_mates or {}
  storage.not_alone_selected_team_mates[event.player_index] = selected
  local player = game.get_player(event.player_index)
  player.print({"not-alone.team-mates-selected", selected_count})
end

local function deconstruction_planner_accepts(stack, resource_name)
  if not stack or not stack.valid_for_read then
    return true
  end
  if stack.trees_and_rocks_only then
    return false
  end
  local filters = stack.entity_filters
  if not filters or #filters == 0 then
    return true
  end
  local listed = false
  for _, filter in pairs(filters) do
    -- The filter entries are prototype names, or prototypes on some versions.
    if filter == resource_name or (type(filter) == "table" and filter.name == resource_name) then
      listed = true
      break
    end
  end
  if stack.entity_filter_mode == defines.deconstruction_item.entity_filter_mode.whitelist then
    return listed
  end
  return not listed
end

function poc.on_deconstructed_area(event)
  local changed_count = 0
  for _, resource in pairs(event.surface.find_entities_filtered({
    area = event.area,
    type = "resource"
  })) do
    if deconstruction_planner_accepts(event.stack, resource.name) then
      if not event.alt then
        mark_resource_for_mining(resource)
        changed_count = changed_count + 1
      elseif is_resource_marked(resource) then
        unmark_resource_for_mining(resource)
        changed_count = changed_count + 1
      end
    end
  end
  if changed_count > 0 then
    local player = game.get_player(event.player_index)
    player.print({
      event.alt and "not-alone.resources-unmarked" or "not-alone.resources-marked",
      changed_count
    })
  end
end

local function order_selected_team_mates(event, append)
  if event.item ~= COMMAND_TOOL_NAME then
    return
  end

  local player = game.get_player(event.player_index)
  local selected = storage.not_alone_selected_team_mates
    and storage.not_alone_selected_team_mates[event.player_index]
  if not selected or not next(selected) then
    player.print({"not-alone.no-team-mates-selected"})
    return
  end

  local destination = {
    x = (event.area.left_top.x + event.area.right_bottom.x) / 2,
    y = (event.area.left_top.y + event.area.right_bottom.y) / 2
  }
  local ordered_count = 0
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    local entity = record.entity
    if entity.valid
      and selected[record.entity.unit_number]
      and entity.surface_index == event.surface.index then
      local manual_destinations = get_manual_destinations(record)
      if not append then
        manual_destinations = {}
        record.manual_destinations = manual_destinations
      end
      manual_destinations[#manual_destinations + 1] = {
        x = destination.x,
        y = destination.y
      }
      record.manual_surface_index = event.surface.index
      if #manual_destinations == 1 then
        move_team_mate_toward_destination(record, destination)
      end
      refresh_route_renderings(record, event.player_index)
      ordered_count = ordered_count + 1
    end
  end

  if append then
    player.print({"not-alone.team-mates-waypoint-added", ordered_count})
  else
    player.print({"not-alone.team-mates-ordered", ordered_count})
  end
end

function poc.on_reverse_selected_area(event)
  order_selected_team_mates(event, false)
end

function poc.on_alt_reverse_selected_area(event)
  order_selected_team_mates(event, true)
end

function poc.on_roboport_built(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.type ~= "roboport" then
    return
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

function poc.on_update(event)
  queue_starter_inventory_migration()
  for player_index in pairs(storage.not_alone_starter_inventory_pending or {}) do
    if ensure_starter_inventory(game.get_player(player_index)) then
      storage.not_alone_starter_inventory_pending[player_index] = nil
    end
  end

  for _, surface in pairs(game.surfaces) do
    cleanup_marked_resources(surface.index)
    for _, habitat in pairs(surface.find_entities_filtered({name = LOGISTICS_HUB_NAME})) do
      absorb_habitat_inbox(habitat)
      update_habitat_crew_display(habitat)
      update_building_requesters_for_network(
        surface,
        habitat.force,
        habitat.position,
        habitat.logistic_network
      )
      auto_deploy_from_habitat(habitat)
    end
  end

  reconcile_orphaned_team_mates()

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
function poc.on_entity_damaged(event)
  local entity = event.entity
  if not entity.valid or entity.health <= 0 then
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

local function spawn_crash_ship(surface, area, rng)
  local ship_target = {
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
function poc.on_chunk_generated(event)
  local surface = event.surface
  if not surface.valid or surface.platform then
    return
  end
  local chunk = event.position
  if (chunk.x == 0 and chunk.y == 0) or not prototypes.entity[CRASH_SHIP_NAME] then
    return
  end
  local seed = surface.map_gen_settings.seed
  local mixed = (seed + (chunk.x + 2048) * 40093 + (chunk.y + 2048) * 92821) % 4294967291
  local rng = game.create_random_generator(mixed > 0 and mixed or 1)
  local distance_chunks = math.sqrt(chunk.x * chunk.x + chunk.y * chunk.y)
  -- Guarantee one wreck inside the initially charted area so the player
  -- always spots a lead worth investigating.
  if not storage.not_alone_starter_ship_placed
    and distance_chunks >= CRASH_SHIP_STARTER_MIN_CHUNKS
    and distance_chunks <= CRASH_SHIP_STARTER_MAX_CHUNKS then
    if spawn_crash_ship(surface, event.area, rng) then
      storage.not_alone_starter_ship_placed = true
    end
    return
  end
  local chance = CRASH_SHIP_BASE_CHANCE * math.exp(
    -distance_chunks / CRASH_SHIP_FALLOFF_CHUNKS
  )
  if rng() >= chance then
    return
  end
  spawn_crash_ship(surface, event.area, rng)
end

-- A removed Habitat drops its docked crew and lockers as real items so
-- nothing is silently lost with the building.
function poc.on_habitat_removed(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.name ~= LOGISTICS_HUB_NAME
    or not entity.unit_number then
    return
  end
  local surface = entity.surface
  local position = position_table(entity.position)
  local function spill(item_name, count)
    if count and count > 0 and prototypes.item[item_name] then
      surface.spill_item_stack({
        position = position,
        stack = {name = item_name, count = count}
      })
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

  local lockers = storage.not_alone_soldier_lockers
    and storage.not_alone_soldier_lockers[entity.unit_number]
  if lockers then
    for _, locker in pairs(lockers) do
      for weapon_kind in pairs(locker.weapons or {}) do
        local weapon = SOLDIER_WEAPON_BY_KIND[weapon_kind]
        if weapon then
          spill(weapon.item, 1)
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

  local renders = storage.not_alone_habitat_crew_renders
  if renders then
    renders[entity.unit_number] = nil
  end
end

function poc.register()
  script.on_init(poc.on_init)
  script.on_configuration_changed(poc.on_configuration_changed)
  script.on_event(defines.events.on_player_created, poc.on_player_created)
  script.on_event(defines.events.on_player_removed, poc.on_player_removed)
  script.on_event(defines.events.on_player_selected_area, poc.on_selected_area)
  script.on_event(defines.events.on_player_deconstructed_area, poc.on_deconstructed_area)
  script.on_event(defines.events.on_player_reverse_selected_area, poc.on_reverse_selected_area)
  script.on_event(
    defines.events.on_player_alt_reverse_selected_area,
    poc.on_alt_reverse_selected_area
  )
  script.on_event(defines.events.on_built_entity, poc.on_roboport_built)
  script.on_event(defines.events.on_robot_built_entity, poc.on_roboport_built)
  script.on_event(defines.events.script_raised_built, poc.on_roboport_built)
  script.on_event(defines.events.script_raised_revive, poc.on_roboport_built)
  script.on_event(defines.events.on_chunk_generated, poc.on_chunk_generated)
  local habitat_filters = {{filter = "name", name = LOGISTICS_HUB_NAME}}
  script.on_event(defines.events.on_entity_died, poc.on_habitat_removed, habitat_filters)
  script.on_event(defines.events.on_player_mined_entity, poc.on_habitat_removed, habitat_filters)
  script.on_event(defines.events.on_robot_mined_entity, poc.on_habitat_removed, habitat_filters)
  local damage_filters = {}
  for _, name in pairs(TEAM_MATE_NAMES) do
    damage_filters[#damage_filters + 1] = {filter = "name", name = name}
  end
  script.on_event(defines.events.on_entity_damaged, poc.on_entity_damaged, damage_filters)
  script.on_nth_tick(UPDATE_INTERVAL, poc.on_update)
end

return poc