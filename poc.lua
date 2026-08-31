local poc = {}

local INITIAL_HABITAT_COUNT = 1
local INITIAL_COUNT_BY_KIND = {miner = 7, builder = 3, soldier = 0}
local STARTER_INVENTORY_VERSION = 4
local UPDATE_INTERVAL = 10
local ENGAGEMENT_RADIUS = 16
local COMMAND_REFRESH_DISTANCE = 2
local CHUNK_SIZE = 32
local SCOUT_WAYPOINT_DISTANCE = 64
local SCOUT_GENERATION_RADIUS = 2
local MINER_CAPACITY = 50
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
local TEAM_MATE_NAME = "not-alone-team-mate"
local COMMAND_TOOL_NAME = "not-alone-command-tool"
local MINING_TOOL_NAME = "not-alone-mining-tool"
local LOGISTICS_HUB_NAME = "not-alone-logistics-hub"
local BUILDING_REQUESTER_NAME = "not-alone-building-logistics-requester"
local ITEM_NAME_BY_KIND = {
  miner = "not-alone-miner",
  builder = "not-alone-builder",
  soldier = "not-alone-soldier"
}
local KIND_BY_ITEM_NAME = {}
for kind, item_name in pairs(ITEM_NAME_BY_KIND) do
  KIND_BY_ITEM_NAME[item_name] = kind
end
local TEAM_MATE_KINDS = {"miner", "builder", "soldier"}
local KIND_LABEL = {miner = "Miner", builder = "Builder", soldier = "Soldier"}
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
  "inserter",
  "mining-drill",
  "rocket-silo"
}
local RECIPE_ENTITY_TYPES = {
  ["assembling-machine"] = true,
  ["furnace"] = true,
  ["rocket-silo"] = true
}
local dock_team_mate
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

local function get_habitat_team_mate_count(habitat)
  local inventory = get_habitat_inventory(habitat)
  if not inventory then
    return 0
  end
  local total = 0
  for _, kind in pairs(TEAM_MATE_KINDS) do
    total = total + inventory.get_item_count(ITEM_NAME_BY_KIND[kind])
  end
  return total
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

local function get_manual_destinations(record)
  if not record.manual_destinations then
    record.manual_destinations = {}
    if record.manual_destination then
      record.manual_destinations[1] = {
        x = record.manual_destination.x,
        y = record.manual_destination.y
      }
    end
    record.manual_destination = nil
  end
  return record.manual_destinations
end

local function consumer_accepts_item(consumer, mining_role, count)
  local inventory = consumer.get_inventory(
    consumer.name == BUILDING_REQUESTER_NAME
      and defines.inventory.chest
      or mining_role.inventory
  )
  return inventory and inventory.get_insertable_count(mining_role.item_name) >= count
end

local function find_requesting_consumer(record, mining_role)
  local network = record.entity.surface.find_logistic_network_by_position(
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
  return target.get_inventory(defines.inventory.crafter_input)
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
        local item_prototype = prototypes.item[item.name]
        if item_prototype and burner.fuel_categories[item_prototype.fuel_category] then
          return item.name
        end
      end
    end
  end

  -- Fuel mined by team mates exists in no chest yet but is en route.
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      local resource_info = record.kind == "miner" and record.mining_resource_info
      local item_prototype = resource_info and prototypes.item[resource_info.item_name]
      if item_prototype and record.entity.valid
        and record.entity.force == target.force
        and burner.fuel_categories[item_prototype.fuel_category] then
        return resource_info.item_name
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

  local requests = get_building_requests(target, network)
  local request_by_item = {}
  for _, request in pairs(requests) do
    request_by_item[request.item_name] = request
  end

  local requester_inventory = requester.get_inventory(defines.inventory.chest)
  for _, item in pairs(requester_inventory.get_contents()) do
    local request = request_by_item[item.name]
    local target_inventory = request
      and get_logistics_target_inventory(target, request.inventory_kind)
    if target_inventory then
      local inserted = target_inventory.insert({name = item.name, count = item.count})
      requester_inventory.remove({name = item.name, count = inserted})
    end
  end

  requests = get_building_requests(target, network)

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
  local network = record.entity.surface.find_logistic_network_by_position(
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
    if inventory and inventory.get_insertable_count(item_name or record.logistics_item_name) > 0 then
      local current_distance = distance_squared(record.entity.position, source.position)
      if not nearest_distance or current_distance < nearest_distance then
        nearest_source = source
        nearest_distance = current_distance
      end
    end
  end
  return nearest_source
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

local function mark_resource_for_mining(resource)
  local marks = get_marked_resources(resource.surface.index)
  if marks[resource.unit_number] then
    return
  end
  marks[resource.unit_number] = {
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
  local mark = marks[resource.unit_number]
  if mark then
    destroy_mark_rendering(mark)
    marks[resource.unit_number] = nil
  end
end

local function is_resource_marked(resource)
  local marks = storage.not_alone_marked_resources
    and storage.not_alone_marked_resources[resource.surface.index]
  return marks and marks[resource.unit_number] ~= nil
end

local function cleanup_marked_resources(surface_index)
  local marks = storage.not_alone_marked_resources
    and storage.not_alone_marked_resources[surface_index]
  if not marks then
    return
  end
  for unit_number, mark in pairs(marks) do
    if not mark.entity.valid or mark.entity.amount <= 0 then
      destroy_mark_rendering(mark)
      marks[unit_number] = nil
    end
  end
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
  record.role_target = resource
  record.mining_resource_info = get_resource_info(resource.name)
  record.role_state = "move-to-ore"
  return true
end

local function update_miner(record, player)
  if record.carried_count == nil then
    record.carried_count = record.carried_ore or 0
    record.carried_ore = nil
  end
  update_mining_animation(record, record.role_state == "mine")

  if record.role_state == "find-ore" then
    if not assign_miner_job(record) then
      return dock_team_mate(record)
    end
  elseif record.role_state == "move-to-ore" then
    if not record.role_target or not record.role_target.valid then
      record.role_state = "find-ore"
    elseif distance_squared(record.entity.position, record.role_target.position) <= 4 then
      record.role_state = "mine"
      record.next_mining_tick = game.tick + math.random(get_mining_interval(player))
      stop_team_mate(record)
    else
      move_team_mate(record, record.role_target.position, 2)
    end
  elseif record.role_state == "mine" then
    stop_team_mate(record)
    if game.tick >= (record.next_mining_tick or 0) then
      local resource = record.role_target
      if not resource or not resource.valid or resource.amount <= 0 then
        record.role_state = "find-ore"
        record.role_target = nil
      else
        local mined = 1
        local mining_position = resource.position
        local remaining_amount = resource.amount - mined
        if remaining_amount > 0 then
          resource.amount = remaining_amount
        else
          resource.deplete()
        end
        record.carried_count = (record.carried_count or 0) + mined
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
        if remaining_amount <= 0 then
          unmark_resource_for_mining(resource)
        end
        if record.carried_count >= MINER_CAPACITY or remaining_amount <= 0 then
          record.role_state = "find-consumer"
          record.role_target = nil
        end
      end
    end
  elseif record.role_state == "find-consumer" then
    local consumer = find_requesting_consumer(record, record.mining_resource_info)
    if consumer then
      record.role_target = consumer
      record.role_state = "move-to-consumer"
    else
      return dock_team_mate(record)
    end
  elseif record.role_state == "move-to-consumer" then
    if not record.role_target or not record.role_target.valid then
      record.role_state = "find-consumer"
    elseif not consumer_accepts_item(record.role_target, record.mining_resource_info, 1) then
      record.role_target = nil
      record.role_state = "find-consumer"
    elseif distance_squared(record.entity.position, record.role_target.position) <= 4 then
      record.role_state = "deliver"
      stop_team_mate(record)
    else
      move_team_mate(record, record.role_target.position, 2)
    end
  elseif record.role_state == "deliver" then
    local consumer = record.role_target
    if not consumer or not consumer.valid then
      record.role_state = "find-consumer"
    else
      local inventory = consumer.get_inventory(
        consumer.name == BUILDING_REQUESTER_NAME
          and defines.inventory.chest
          or record.mining_resource_info.inventory
      )
      local inserted = 0
      if inventory and (record.carried_count or 0) > 0 then
        local insertable = math.min(
          inventory.get_insertable_count(record.mining_resource_info.item_name),
          record.carried_count
        )
        if insertable > 0 then
          inserted = inventory.insert({name = record.mining_resource_info.item_name, count = insertable})
        end
      end
      record.carried_count = (record.carried_count or 0) - inserted
      record.role_target = nil
      if record.carried_count <= 0 then
        record.carried_count = 0
        record.mining_resource_info = nil
        record.role_state = "find-ore"
      else
        -- Deposit what fit; find another destination for the remainder.
        record.role_state = "find-consumer"
      end
    end
  else
    record.role_state = "find-ore"
  end

  return true
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
      record.mining_color = record.team_mate_color or record.entity.color
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
      name = TEAM_MATE_NAME,
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

local function find_nearest_habitat(record, require_space)
  local team_mate = record.entity
  local nearest_habitat = nil
  local nearest_distance = nil
  local nearest_available_habitat = nil
  local nearest_available_distance = nil
  for _, habitat in pairs(team_mate.surface.find_entities_filtered({
    name = LOGISTICS_HUB_NAME,
    force = team_mate.force
  })) do
    local distance = distance_squared(team_mate.position, habitat.position)
    if not nearest_distance or distance < nearest_distance then
      nearest_habitat = habitat
      nearest_distance = distance
    end
    local inventory = get_habitat_inventory(habitat)
    if inventory and inventory.get_insertable_count(ITEM_NAME_BY_KIND[record.kind]) > 0
      and (not nearest_available_distance or distance < nearest_available_distance) then
      nearest_available_habitat = habitat
      nearest_available_distance = distance
    end
  end
  record.habitat = require_space and nearest_available_habitat or nearest_habitat
  return record.habitat or nearest_habitat
end

local function can_enter_habitat(record)
  return (record.carried_count or record.carried_ore or 0) == 0
    and (record.logistics_carried_count or 0) == 0
    and (record.builder_carried_count or 0) == 0
    and (not record.builder_cargo or not record.builder_cargo.valid
      or record.builder_cargo.is_empty())
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

local function return_builder_cargo(record)
  local cargo = record.builder_cargo
  if not cargo or not cargo.valid or cargo.is_empty() then
    record.builder_return_source = nil
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

  local stack = cargo[1]
  local source_inventory = get_logistics_source_inventory(record.builder_return_source)
  if not source_inventory or not source_inventory.can_insert(stack) then
    record.builder_return_source = find_logistics_return_source(record, {
      name = stack.name,
      quality = stack.quality.name
    })
    source_inventory = get_logistics_source_inventory(record.builder_return_source)
  end
  if not source_inventory then
    record.entity.surface.spill_inventory({
      position = position_table(record.entity.position),
      inventory = cargo,
      force = record.entity.force,
      drop_full_stack = true
    })
    record.builder_deconstruction_started = nil
    record.builder_return_source = nil
    if record.kind == "builder" then
      record.builder_state = nil
    end
    return false
  end
  if distance_squared(record.entity.position, record.builder_return_source.position) <= 4 then
    source_inventory.transfer_from_inventory(cargo)
    if cargo.is_empty() then
      record.builder_return_source = nil
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
  else
    move_team_mate(record, record.builder_return_source.position, 2)
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
    record.entity.surface.spill_item_stack({
      position = position_table(record.entity.position),
      stack = {
        name = record.builder_item.name,
        quality = record.builder_item.quality,
        count = 1
      }
    })
    record.builder_item = nil
    record.builder_carried_count = 0
    record.builder_state = nil
    return false
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

dock_team_mate = function(record)
  local habitat = find_nearest_habitat(record, true)
  if not habitat then
    stop_team_mate(record)
    return true
  end
  if distance_squared(record.entity.position, habitat.position) > 9 then
    move_team_mate(record, habitat.position, 3)
    return true
  end

  stop_team_mate(record)
  local inventory = get_habitat_inventory(habitat)
  if not inventory or inventory.insert({name = ITEM_NAME_BY_KIND[record.kind], count = 1}) ~= 1 then
    return true
  end

  update_mining_animation(record, false)
  destroy_route_renderings(record)
  record.team_mate_id = record.team_mate_id or record.entity.unit_number
  record.team_mate_name = record.entity.name_tag
  record.team_mate_health = record.entity.health
  record.docked_habitat = habitat
  if record.entity.valid then
    record.entity.destroy()
  end
  return true
end

local function deploy_docked_team_mate(record)
  local habitat = record.docked_habitat
  if not habitat or not habitat.valid then
    return false
  end
  local item_name = ITEM_NAME_BY_KIND[record.kind]
  local inventory = get_habitat_inventory(habitat)
  if not inventory or inventory.get_item_count(item_name) == 0 then
    return false
  end
  local spawn_position = habitat.surface.find_non_colliding_position(
    TEAM_MATE_NAME,
    habitat.position,
    8,
    0.5
  )
  if not spawn_position then
    return true
  end
  local entity = habitat.surface.create_entity({
    name = TEAM_MATE_NAME,
    position = spawn_position,
    force = habitat.force,
    create_build_effect_smoke = false
  })
  if not entity then
    return true
  end
  if inventory.remove({name = item_name, count = 1}) ~= 1 then
    entity.destroy()
    return false
  end

  entity.color = record.team_mate_color
  entity.name_tag = record.team_mate_name or (KIND_LABEL[record.kind] or "Team mate")
  entity.health = math.min(record.team_mate_health or entity.max_health, entity.max_health)
  record.entity = entity
  record.docked_habitat = nil
  record.command_kind = nil
  record.command_destination = nil
  record.command_target = nil
  return true
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

local function wake_docked_team_mate(record)
  local habitat = record.docked_habitat
  if not habitat or not habitat.valid then
    return false
  end
  if record.kind == "builder" then
    if not assign_builder_job(
        record,
        habitat.surface,
        habitat.force,
        position_table(habitat.position)
      ) then
      return true
    end
  elseif record.kind == "miner" then
    if not assign_miner_job(
        record,
        habitat.surface,
        habitat.force,
        position_table(habitat.position)
      ) then
      return true
    end
  end
  return deploy_docked_team_mate(record)
end

local function update_builder(record)
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
  return dock_team_mate(record)
end

local function create_team_mate(player, kind, index, total, spawn_center)
  -- Units do not collide with each other, so find_non_colliding_position
  -- returns the same spot for every spawn; ring offsets keep them apart
  -- because perfectly co-located units cannot be separated by the engine.
  local center = spawn_center or player.position
  local angle = (index - 1) / total * 2 * math.pi
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
    name = TEAM_MATE_NAME,
    position = spawn_position,
    force = player.force,
    create_build_effect_smoke = false
  })
  if not character then
    return nil
  end

  character.color = player.color
  character.name_tag = (KIND_LABEL[kind] or "Team mate") .. " " .. index
  local record = {entity = character, team_mate_color = player.color, kind = kind}
  if kind == "miner" then
    record.role_state = "find-ore"
  end
  find_nearest_habitat(record)
  return record
end

local function get_team_mate_id(record)
  record.team_mate_id = record.team_mate_id or record.entity.unit_number
  return record.team_mate_id
end

local function migrate_builder_item(record)
  if record.builder_item or not record.builder_item_name then
    return
  end
  local quality = record.builder_target and record.builder_target.valid
    and record.builder_target.quality.name or "normal"
  record.builder_item = {name = record.builder_item_name, quality = quality}
  record.builder_item_name = nil
end

local function find_any_player_for_force(force)
  if force.connected_players and force.connected_players[1] then
    return force.connected_players[1]
  end
  return force.players and force.players[1]
end

local function auto_deploy_from_habitat(habitat)
  local player = find_any_player_for_force(habitat.force)
  if not player or not player.valid then
    return
  end
  local inventory = get_habitat_inventory(habitat)
  if not inventory then
    return
  end

  for _, kind in pairs(TEAM_MATE_KINDS) do
    local item_name = ITEM_NAME_BY_KIND[kind]
    if inventory.get_item_count(item_name) > 0 then
      local fake_record = {entity = habitat, kind = kind}
      local has_work
      if kind == "builder" then
        has_work = assign_builder_job(
          fake_record,
          habitat.surface,
          habitat.force,
          position_table(habitat.position)
        )
      elseif kind == "miner" then
        has_work = assign_miner_job(
          fake_record,
          habitat.surface,
          habitat.force,
          position_table(habitat.position)
        )
      end
      if has_work then
        storage.not_alone_team_mates = storage.not_alone_team_mates or {}
        local team_mates = storage.not_alone_team_mates[player.index] or {}
        local record = create_team_mate(player, kind, #team_mates + 1, #team_mates + 1, habitat.position)
        if record then
          if inventory.remove({name = item_name, count = 1}) ~= 1 then
            record.entity.destroy()
          else
            record.habitat = habitat
            if kind == "builder" then
              record.builder_target = fake_record.builder_target
              record.builder_source = fake_record.builder_source
              record.builder_item = fake_record.builder_item
              record.builder_carried_count = 0
              record.builder_state = fake_record.builder_state
            elseif kind == "miner" then
              record.role_target = fake_record.role_target
              record.mining_resource_info = fake_record.mining_resource_info
              record.role_state = fake_record.role_state
            end
            team_mates[#team_mates + 1] = record
            storage.not_alone_team_mates[player.index] = team_mates
          end
        end
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
  migrate_builder_item(record)
  local character = record.entity
  if record.docked_habitat then
    if not record.docked_habitat.valid then
      destroy_route_renderings(record)
      return false
    end
    if record.kind == "builder" or record.kind == "miner" then
      return wake_docked_team_mate(record)
    end
    return true
  end
  if not character.valid or character.type ~= "unit" then
    destroy_route_renderings(record)
    return false
  end

  rescue_immobile_team_mate(record)
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

  if enemy and enemy.valid then
    attack_with_team_mate(record, enemy)
    return true
  end

  if record.kind == "miner" then
    return update_miner(record, player)
  elseif record.kind == "builder" then
    return update_builder(record)
  end
  return dock_team_mate(record)
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
  if event.item == MINING_TOOL_NAME then
    local marked_count = 0
    for _, entity in pairs(event.entities) do
      if entity.valid and entity.type == "resource" then
        mark_resource_for_mining(entity)
        marked_count = marked_count + 1
      end
    end
    local player = game.get_player(event.player_index)
    player.print({"not-alone.resources-marked", marked_count})
    return
  end

  if event.item ~= COMMAND_TOOL_NAME then
    return
  end

  local owned_team_mates = {}
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    if record.entity.valid then
      owned_team_mates[record.entity.unit_number] = get_team_mate_id(record)
    end
  end

  local selected = {}
  local selected_count = 0
  for _, entity in pairs(event.entities) do
    local team_mate_id = entity.valid and owned_team_mates[entity.unit_number]
    if team_mate_id then
      selected[team_mate_id] = true
      selected_count = selected_count + 1
    end
  end

  storage.not_alone_selected_team_mates = storage.not_alone_selected_team_mates or {}
  storage.not_alone_selected_team_mates[event.player_index] = selected
  local player = game.get_player(event.player_index)
  player.print({"not-alone.team-mates-selected", selected_count})
end

function poc.on_alt_selected_area(event)
  if event.item ~= MINING_TOOL_NAME then
    return
  end
  local unmarked_count = 0
  for _, entity in pairs(event.entities) do
    if entity.valid and entity.type == "resource" and is_resource_marked(entity) then
      unmark_resource_for_mining(entity)
      unmarked_count = unmarked_count + 1
    end
  end
  local player = game.get_player(event.player_index)
  player.print({"not-alone.resources-unmarked", unmarked_count})
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
      and selected[get_team_mate_id(record)]
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
      if record.kind == "miner" and record.role_state == "find-ore"
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
      update_building_requesters_for_network(
        surface,
        habitat.force,
        habitat.position,
        habitat.logistic_network
      )
      auto_deploy_from_habitat(habitat)
    end
  end

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
          active_ids[get_team_mate_id(record)] = true
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

function poc.register()
  script.on_init(poc.on_init)
  script.on_configuration_changed(poc.on_configuration_changed)
  script.on_event(defines.events.on_player_created, poc.on_player_created)
  script.on_event(defines.events.on_player_removed, poc.on_player_removed)
  script.on_event(defines.events.on_player_selected_area, poc.on_selected_area)
  script.on_event(defines.events.on_player_alt_selected_area, poc.on_alt_selected_area)
  script.on_event(defines.events.on_player_reverse_selected_area, poc.on_reverse_selected_area)
  script.on_event(
    defines.events.on_player_alt_reverse_selected_area,
    poc.on_alt_reverse_selected_area
  )
  script.on_event(defines.events.on_built_entity, poc.on_roboport_built)
  script.on_event(defines.events.on_robot_built_entity, poc.on_roboport_built)
  script.on_event(defines.events.script_raised_built, poc.on_roboport_built)
  script.on_event(defines.events.script_raised_revive, poc.on_roboport_built)
  script.on_nth_tick(UPDATE_INTERVAL, poc.on_update)
end

return poc