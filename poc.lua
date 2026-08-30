local poc = {}

local TEAM_MATE_COUNT = 10
local UPDATE_INTERVAL = 10
local ENGAGEMENT_RADIUS = 16
local WANDER_RADIUS = 10
local COMMAND_REFRESH_DISTANCE = 2
local CHUNK_SIZE = 32
local SCOUT_WAYPOINT_DISTANCE = 64
local SCOUT_GENERATION_RADIUS = 2
local MINER_TECHNOLOGY_NAME = "not-alone-iron-miner"
local MINER_CAPACITY = 50
local RESOURCE_MINING_TIME = 1
local NORMAL_CHARACTER_MINING_SPEED = 0.5
local LOGISTICS_SEARCH_RADIUS = 128
local LOGISTICS_CAPACITY = 50
local FUEL_REQUEST_COUNT = 5
local BUILDING_REQUEST_SLOT_COUNT = 20
local MINING_ANIMATION_FRAMES = 51
local MINING_ANIMATION_SPEED = 51 / 60
local HIDDEN_TEAM_MATE_NAME = "not-alone-team-mate-hidden"
local ROUTE_COLOR = {r = 0.2, g = 0.7, b = 1, a = 0.9}
local TEAM_MATE_NAME = "not-alone-team-mate"
local COMMAND_TOOL_NAME = "not-alone-command-tool"
local LOGISTICS_HUB_NAME = "not-alone-logistics-hub"
local LOGISTICS_HUB_SOUTH_OFFSET = 8
local LOGISTICS_MEMBER_NAME = "not-alone-team-mate-logistics-member"
local BUILDING_REQUESTER_NAME = "not-alone-building-logistics-requester"
local MINING_ROLES = {
  {
    name = "iron-miner",
    resource_name = "iron-ore",
    item_name = "iron-ore",
    inventory = defines.inventory.crafter_input,
    button_name = "not_alone_assign_iron_miner",
    caption = "not-alone.assign-iron-miner",
    tooltip = "not-alone.assign-iron-miner-tooltip",
    assigned_message = "not-alone.iron-miners-assigned"
  },
  {
    name = "copper-miner",
    resource_name = "copper-ore",
    item_name = "copper-ore",
    inventory = defines.inventory.crafter_input,
    button_name = "not_alone_assign_copper_miner",
    caption = "not-alone.assign-copper-miner",
    tooltip = "not-alone.assign-copper-miner-tooltip",
    assigned_message = "not-alone.copper-miners-assigned"
  },
  {
    name = "coal-miner",
    resource_name = "coal",
    item_name = "coal",
    inventory = defines.inventory.fuel,
    button_name = "not_alone_assign_coal_miner",
    caption = "not-alone.assign-coal-miner",
    tooltip = "not-alone.assign-coal-miner-tooltip",
    assigned_message = "not-alone.coal-miners-assigned"
  },
  {
    name = "stone-miner",
    resource_name = "stone",
    item_name = "stone",
    inventory = defines.inventory.crafter_input,
    button_name = "not_alone_assign_stone_miner",
    caption = "not-alone.assign-stone-miner",
    tooltip = "not-alone.assign-stone-miner-tooltip",
    assigned_message = "not-alone.stone-miners-assigned"
  }
}
local MINING_ROLE_BY_NAME = {}
local MINING_ROLE_BY_BUTTON = {}
for _, mining_role in pairs(MINING_ROLES) do
  MINING_ROLE_BY_NAME[mining_role.name] = mining_role
  MINING_ROLE_BY_BUTTON[mining_role.button_name] = mining_role
end
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
local wander_with_team_mate
local stop_team_mate
local move_team_mate
local update_mining_animation

local function distance_squared(first, second)
  local delta_x = first.x - second.x
  local delta_y = first.y - second.y
  return delta_x * delta_x + delta_y * delta_y
end

local function position_table(position)
  return {x = position.x, y = position.y}
end

local function destroy_logistics_member(record)
  if record.logistics_member and record.logistics_member.valid then
    record.logistics_member.destroy()
  end
  record.logistics_member = nil
end

local function update_logistics_member(record)
  local team_mate = record.entity
  local member = record.logistics_member
  if not member or not member.valid then
    member = team_mate.surface.create_entity({
      name = LOGISTICS_MEMBER_NAME,
      position = team_mate.position,
      force = team_mate.force,
      create_build_effect_smoke = false
    })
    if not member then
      return
    end
    member.destructible = false
    member.operable = false
    record.logistics_member = member
  elseif distance_squared(member.position, team_mate.position) > 0 then
    member.destroy()
    record.logistics_member = nil
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

local function find_nearest_resource(record, mining_role)
  local network = record.entity.surface.find_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  if not network then
    return nil
  end
  local surface = record.entity.surface
  local nearest_resource
  local nearest_distance
  for _, cell in pairs(network.cells) do
    if cell.valid and cell.owner.valid then
      -- Cover the square logistic area's corners; is_in_logistic_range is exact.
      for _, resource in pairs(surface.find_entities_filtered({
        type = "resource",
        name = mining_role.resource_name,
        position = cell.owner.position,
        radius = cell.logistic_radius * 1.5
      })) do
        if resource.amount > 0 and cell.is_in_logistic_range(resource.position) then
          local current_distance = distance_squared(resource.position, record.entity.position)
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
          local missing_count = math.ceil(ingredient.amount)
            - inventory.get_item_count(ingredient.name)
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

local function update_building_requesters(record)
  local entity = record.entity
  local network = entity.surface.find_logistic_network_by_position(
    position_table(entity.position),
    entity.force
  )
  if not network then
    return
  end

  storage.not_alone_building_requesters = storage.not_alone_building_requesters or {}
  storage.not_alone_building_requester_ticks = storage.not_alone_building_requester_ticks or {}
  local network_key = entity.surface.index .. ":" .. entity.force.index
    .. ":" .. network.network_id
  if storage.not_alone_building_requester_ticks[network_key] == game.tick then
    return
  end
  storage.not_alone_building_requester_ticks[network_key] = game.tick

  local requesters = storage.not_alone_building_requesters
  local destinations = entity.surface.find_entities_filtered({
    type = LOGISTICS_DESTINATION_TYPES,
    force = entity.force,
    position = entity.position,
    radius = LOGISTICS_SEARCH_RADIUS
  })
  for _, target in pairs(destinations) do
    local target_network = entity.surface.find_logistic_network_by_position(
      position_table(target.position),
      entity.force
    )
    if target_network == network and target.unit_number then
      local requester_record = requesters[target.unit_number]
      if not requester_record or not requester_record.requester.valid then
        local requester = entity.surface.create_entity({
          name = BUILDING_REQUESTER_NAME,
          position = target.position,
          force = entity.force,
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

local function get_reserved_delivery_count(target, item_name)
  local reserved_count = 0
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, other_record in pairs(team_mates) do
      if other_record.logistics_target == target
        and other_record.logistics_item_name == item_name
        and (other_record.logistics_state == "move-to-source"
          or other_record.logistics_state == "move-to-target") then
        reserved_count = reserved_count + (other_record.logistics_requested_count or 0)
      end
    end
  end
  return reserved_count
end

local function get_request_count(requester_point, item_name)
  local requested_count = 0
  for _, filter in pairs(requester_point.filters or {}) do
    if filter.value and filter.value.type == "item" and filter.value.name == item_name then
      requested_count = requested_count + math.max(filter.min or 0, 0)
    end
  end
  return requested_count
end

local function get_targeted_delivery_count(requester_point, item_name)
  local targeted_count = 0
  for _, item in pairs(requester_point.targeted_items_deliver) do
    if item.name == item_name then
      targeted_count = targeted_count + item.count
    end
  end
  return targeted_count
end

local function find_logistics_job(record)
  local surface = record.entity.surface
  local network = surface.find_logistic_network_by_position(
    position_table(record.entity.position),
    record.entity.force
  )
  if not network then
    return nil
  end

  for _, candidate_point in pairs(network.requester_points) do
    if candidate_point.valid and candidate_point.enabled
      and candidate_point.owner.valid and candidate_point.owner.name == BUILDING_REQUESTER_NAME then
      for _, filter in pairs(candidate_point.filters or {}) do
        local item_name = filter.value and filter.value.type == "item" and filter.value.name
        if item_name and (filter.min or 0) > 0 then
          local requester_point = network.select_drop_point({
            stack = {name = item_name, count = 1},
            members = "requester"
          })
          local target = requester_point and requester_point.owner
          local outstanding_count = target and target.name == BUILDING_REQUESTER_NAME
            and get_request_count(requester_point, item_name)
              - target.get_item_count(item_name)
              - get_targeted_delivery_count(requester_point, item_name)
              - get_reserved_delivery_count(target, item_name)
          local pickup_point = outstanding_count and outstanding_count > 0
            and network.select_pickup_point({
              name = item_name,
              position = position_table(target.position),
              include_buffers = true
            })
          local source = pickup_point and pickup_point.owner
          local source_inventory = get_logistics_source_inventory(source)
          if source_inventory and source_inventory.get_item_count(item_name) > 0 then
            return {
              source = source,
              target = target,
              item_name = item_name,
              count = math.min(outstanding_count, LOGISTICS_CAPACITY),
              inventory_kind = "requester"
            }
          end
        end
      end
    end
  end
  return nil
end

local function clear_logistics_job(record)
  record.logistics_state = nil
  record.logistics_source = nil
  record.logistics_target = nil
  record.logistics_item_name = nil
  record.logistics_requested_count = nil
  record.logistics_inventory_kind = nil
end

local function find_logistics_return_source(record)
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
    if inventory and inventory.get_insertable_count(record.logistics_item_name) > 0 then
      local current_distance = distance_squared(record.entity.position, source.position)
      if not nearest_distance or current_distance < nearest_distance then
        nearest_source = source
        nearest_distance = current_distance
      end
    end
  end
  return nearest_source
end

local function update_logistics(record)
  if not record.logistics_state then
    local job = find_logistics_job(record)
    if not job then
      return false
    end
    record.logistics_source = job.source
    record.logistics_target = job.target
    record.logistics_item_name = job.item_name
    record.logistics_requested_count = job.count
    record.logistics_inventory_kind = job.inventory_kind
    record.logistics_state = "move-to-source"
  end

  if record.logistics_state == "move-to-source" then
    local source_inventory = get_logistics_source_inventory(record.logistics_source)
    local target_inventory = get_logistics_target_inventory(
      record.logistics_target,
      record.logistics_inventory_kind
    )
    if not source_inventory or not target_inventory
      or source_inventory.get_item_count(record.logistics_item_name) <= 0
      or target_inventory.get_insertable_count(record.logistics_item_name) <= 0 then
      clear_logistics_job(record)
      return false
    elseif distance_squared(record.entity.position, record.logistics_source.position) <= 4 then
      local pickup_count = math.min(
        record.logistics_requested_count,
        source_inventory.get_item_count(record.logistics_item_name),
        target_inventory.get_insertable_count(record.logistics_item_name)
      )
      record.logistics_carried_count = source_inventory.remove({
        name = record.logistics_item_name,
        count = pickup_count
      })
      if record.logistics_carried_count > 0 then
        record.logistics_state = "move-to-target"
      else
        clear_logistics_job(record)
        return false
      end
    else
      move_team_mate(record, record.logistics_source.position, 2)
    end
  elseif record.logistics_state == "move-to-target" then
    local target_inventory = get_logistics_target_inventory(
      record.logistics_target,
      record.logistics_inventory_kind
    )
    if not target_inventory
      or target_inventory.get_insertable_count(record.logistics_item_name) <= 0 then
      record.logistics_state = "return-cargo"
    elseif distance_squared(record.entity.position, record.logistics_target.position) <= 4 then
      local inserted = target_inventory.insert({
        name = record.logistics_item_name,
        count = record.logistics_carried_count
      })
      record.logistics_carried_count = record.logistics_carried_count - inserted
      if record.logistics_carried_count > 0 then
        record.logistics_state = "return-cargo"
      else
        clear_logistics_job(record)
      end
    else
      move_team_mate(record, record.logistics_target.position, 2)
    end
  elseif record.logistics_state == "return-cargo" then
    local source_inventory = get_logistics_source_inventory(record.logistics_source)
    if not source_inventory
      or source_inventory.get_insertable_count(record.logistics_item_name) <= 0 then
      record.logistics_source = find_logistics_return_source(record)
      source_inventory = get_logistics_source_inventory(record.logistics_source)
    end
    if not source_inventory then
      -- No chest can take the cargo back; drop it rather than freeze forever.
      record.entity.surface.spill_item_stack({
        position = position_table(record.entity.position),
        stack = {name = record.logistics_item_name, count = record.logistics_carried_count}
      })
      record.logistics_carried_count = 0
      clear_logistics_job(record)
      return false
    elseif distance_squared(record.entity.position, record.logistics_source.position) <= 4 then
      local inserted = source_inventory.insert({
        name = record.logistics_item_name,
        count = record.logistics_carried_count
      })
      record.logistics_carried_count = record.logistics_carried_count - inserted
      if record.logistics_carried_count <= 0 then
        record.logistics_carried_count = 0
        clear_logistics_job(record)
      end
    else
      move_team_mate(record, record.logistics_source.position, 2)
    end
  end
  return true
end

local function update_miner(record, player, mining_role)
  if record.carried_count == nil then
    record.carried_count = record.carried_ore or 0
    record.carried_ore = nil
  end
  update_mining_animation(record, record.role_state == "mine")

  if record.role_state == "find-ore" then
    local resource = find_nearest_resource(record, mining_role)
    if resource then
      record.role_target = resource
      record.role_state = "move-to-ore"
    else
      wander_with_team_mate(record)
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
        record.entity.surface.play_sound({
          path = "not-alone-team-mate-mining-sound",
          position = mining_position,
          volume_modifier = 0.8
        })
        record.next_mining_tick = record.next_mining_tick + get_mining_interval(player)
        if record.carried_count >= MINER_CAPACITY or remaining_amount <= 0 then
          record.role_state = "find-consumer"
          record.role_target = nil
        end
      end
    end
  elseif record.role_state == "find-consumer" then
    local consumer = find_requesting_consumer(record, mining_role)
    if consumer then
      record.role_target = consumer
      record.role_state = "move-to-consumer"
    else
      wander_with_team_mate(record)
    end
  elseif record.role_state == "move-to-consumer" then
    if not record.role_target or not record.role_target.valid then
      record.role_state = "find-consumer"
    elseif not consumer_accepts_item(record.role_target, mining_role, 1) then
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
          or mining_role.inventory
      )
      local inserted = 0
      if inventory and (record.carried_count or 0) > 0 then
        local insertable = math.min(
          inventory.get_insertable_count(mining_role.item_name),
          record.carried_count
        )
        if insertable > 0 then
          inserted = inventory.insert({name = mining_role.item_name, count = insertable})
        end
      end
      record.carried_count = (record.carried_count or 0) - inserted
      record.role_target = nil
      if record.carried_count <= 0 then
        record.carried_count = 0
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

local function ensure_mining_role_buttons(frame)
  for _, mining_role in ipairs(MINING_ROLES) do
    if not frame[mining_role.button_name] then
      frame.add({
        type = "button",
        name = mining_role.button_name,
        caption = {mining_role.caption},
        tooltip = {mining_role.tooltip}
      })
    end
  end
end

local function ensure_role_gui(player)
  if not player.valid then
    return
  end

  local existing_frame = player.gui.left.not_alone_role_frame
  if existing_frame then
    ensure_mining_role_buttons(existing_frame)
    return
  end

  local frame = player.gui.left.add({
    type = "frame",
    name = "not_alone_role_frame",
    direction = "vertical",
    caption = {"not-alone.role-frame-title"}
  })
  frame.add({
    type = "label",
    name = "not_alone_role_selection_status",
    caption = {"not-alone.role-selection-status", 0}
  })
  frame.add({
    type = "button",
    name = "not_alone_add_team_mate",
    caption = {"not-alone.add-team-mate"},
    tooltip = {"not-alone.add-team-mate-tooltip"}
  })
  ensure_mining_role_buttons(frame)
end

local function ensure_miner_technology(force)
  local technology = force.technologies[MINER_TECHNOLOGY_NAME]
  if technology then
    technology.researched = true
  end
end

local function enable_logistics_network_gui(force)
  force.unlock_logistic_network = true
end

local function update_role_selection_status(player)
  local frame = player.gui.left.not_alone_role_frame
  if not frame or not frame.valid then
    return
  end

  local status = frame.not_alone_role_selection_status
  if not status or not status.valid then
    return
  end

  local selected = storage.not_alone_selected_team_mates
    and storage.not_alone_selected_team_mates[player.index]
  local selected_count = 0
  for _ in pairs(selected or {}) do
    selected_count = selected_count + 1
  end
  status.caption = {"not-alone.role-selection-status", selected_count}
end

stop_team_mate = function(record)
  if record.command_kind ~= "stop" then
    record.entity.commandable.set_command({type = defines.command.stop})
    record.command_kind = "stop"
    record.command_destination = nil
    record.command_target = nil
  end
end

wander_with_team_mate = function(record)
  if record.command_kind == "wander" and record.entity.commandable.has_command then
    return
  end

  record.entity.commandable.set_command({
    type = defines.command.wander,
    radius = WANDER_RADIUS,
    distraction = defines.distraction.by_enemy
  })
  record.command_kind = "wander"
  record.command_destination = nil
  record.command_target = nil
end

move_team_mate = function(record, destination, stopping_distance)
  if distance_squared(record.entity.position, destination) <= stopping_distance * stopping_distance then
    record.move_failures = nil
    stop_team_mate(record)
    return
  end

  if record.command_kind == "move-recovery" then
    if record.entity.commandable.has_command then
      return
    end
    record.command_kind = nil
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
    -- The same move ended without arrival: the path failed. After repeated
    -- failures, wander briefly to leave the dead pocket before retrying.
    record.move_failures = (record.move_failures or 0) + 1
    if record.move_failures >= 2 then
      record.move_failures = 0
      record.entity.commandable.set_command({
        type = defines.command.wander,
        radius = WANDER_RADIUS,
        ticks_to_wait = 120,
        distraction = defines.distraction.none
      })
      record.command_kind = "move-recovery"
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

local function create_team_mate(player, index, spawn_center)
  -- Units do not collide with each other, so find_non_colliding_position
  -- returns the same spot for every spawn; ring offsets keep them apart
  -- because perfectly co-located units cannot be separated by the engine.
  local center = spawn_center or player.position
  local angle = (index - 1) / TEAM_MATE_COUNT * 2 * math.pi
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
  character.name_tag = "Team mate " .. index
  return {entity = character, team_mate_color = player.color}
end

local function add_team_mate(player, spawn_center)
  if not player.valid or not player.character or not player.character.valid then
    return nil
  end

  if player.get_item_count(COMMAND_TOOL_NAME) == 0 then
    player.insert({name = COMMAND_TOOL_NAME, count = 1})
  end

  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local team_mates = storage.not_alone_team_mates[player.index] or {}
  local record = create_team_mate(player, #team_mates + 1, spawn_center)
  if not record then
    return nil
  end

  team_mates[#team_mates + 1] = record
  storage.not_alone_team_mates[player.index] = team_mates
  return record
end

local function ensure_starter_logistics_hub(player)
  local surface = player.surface
  local spawn_position = player.force.get_spawn_position(surface)
  local existing_hub = surface.find_entities_filtered({
    name = LOGISTICS_HUB_NAME,
    force = player.force,
    position = spawn_position,
    radius = 32,
    limit = 1
  })[1]
  if existing_hub then
    return existing_hub
  end

  local desired_position = {
    x = spawn_position.x,
    y = spawn_position.y + LOGISTICS_HUB_SOUTH_OFFSET
  }
  local hub_position = surface.find_non_colliding_position(
    LOGISTICS_HUB_NAME,
    desired_position,
    8,
    0.5
  )
  if not hub_position then
    return nil
  end
  return surface.create_entity({
    name = LOGISTICS_HUB_NAME,
    position = hub_position,
    force = player.force,
    create_build_effect_smoke = false
  })
end

local function spawn_team_mates(player)
  if not player.valid or not player.character or not player.character.valid then
    return false
  end

  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local existing = storage.not_alone_team_mates[player.index]
  if existing and #existing > 0 then
    return true
  end

  local logistics_hub = ensure_starter_logistics_hub(player)
  local spawn_center = logistics_hub and logistics_hub.position or player.position
  local spawned_count = 0
  for _ = 1, TEAM_MATE_COUNT do
    if add_team_mate(player, spawn_center) then
      spawned_count = spawned_count + 1
    end
  end
  player.print({"not-alone.team-mates-arrived", spawned_count})
  return spawned_count > 0
end

local function rescue_immobile_team_mate(record)
  local entity = record.entity
  if record.command_kind ~= "move" and record.command_kind ~= "move-recovery" then
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
    destroy_logistics_member(record)
    return false
  end

  rescue_immobile_team_mate(record)
  update_logistics_member(record)
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

  local mining_role = MINING_ROLE_BY_NAME[record.role]
  if mining_role then
    if (record.logistics_carried_count or 0) > 0 then
      record.logistics_state = "return-cargo"
      update_logistics(record)
      return true
    end
    if record.logistics_state then
      record.logistics_carried_count = 0
      clear_logistics_job(record)
    end
    return update_miner(record, player, mining_role)
  end

  if update_logistics(record) then
    return true
  else
    wander_with_team_mate(record)
  end

  return true
end

function poc.on_init()
  storage.not_alone_team_mates = {}
  storage.not_alone_pending_spawns = {}
  storage.not_alone_selected_team_mates = {}
  for _, player in pairs(game.players) do
    ensure_miner_technology(player.force)
    enable_logistics_network_gui(player.force)
    ensure_starter_logistics_hub(player)
    storage.not_alone_pending_spawns[player.index] = game.tick + 1
    ensure_role_gui(player)
  end
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
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      destroy_logistics_member(record)
      if record.entity and record.entity.valid then
        record.entity.destroy()
      end
    end
  end

  storage.not_alone_team_mates = {}
  storage.not_alone_pending_spawns = {}
  storage.not_alone_selected_team_mates = {}
  for _, player in pairs(game.players) do
    ensure_miner_technology(player.force)
    enable_logistics_network_gui(player.force)
    ensure_starter_logistics_hub(player)
    storage.not_alone_pending_spawns[player.index] = game.tick + 1
    ensure_role_gui(player)
  end
end

function poc.on_player_created(event)
  local player = game.get_player(event.player_index)
  ensure_miner_technology(player.force)
  enable_logistics_network_gui(player.force)
  ensure_starter_logistics_hub(player)
  storage.not_alone_pending_spawns = storage.not_alone_pending_spawns or {}
  storage.not_alone_pending_spawns[event.player_index] = game.tick + 1
  ensure_role_gui(player)
end

function poc.on_gui_click(event)
  if not event.element or not event.element.valid then
    return
  end

  local mining_role = MINING_ROLE_BY_BUTTON[event.element.name]
  if event.element.name ~= "not_alone_add_team_mate" and not mining_role then
    return
  end

  local player = game.get_player(event.player_index)
  if not player or not player.valid then
    return
  end

  if event.element.name == "not_alone_add_team_mate" then
    if add_team_mate(player) then
      player.print({"not-alone.team-mate-added"})
    else
      player.print({"not-alone.team-mate-could-not-be-added"})
    end
    return
  end

  local technology = player.force.technologies[MINER_TECHNOLOGY_NAME]
  if not technology or not technology.researched then
    player.print({"not-alone.miner-technology-required"})
    return
  end

  local selected = storage.not_alone_selected_team_mates
    and storage.not_alone_selected_team_mates[event.player_index]
  local assigned_count = 0
  for _, record in pairs(storage.not_alone_team_mates[event.player_index] or {}) do
    local entity = record.entity
    if entity.valid and selected and selected[entity.unit_number] then
      record.role = mining_role.name
      record.role_state = "find-ore"
      record.role_target = nil
      record.carried_count = 0
      record.carried_ore = nil
      record.next_mining_tick = nil
      record.manual_destinations = {}
      record.manual_surface_index = nil
      if (record.logistics_carried_count or 0) > 0 then
        record.logistics_state = "return-cargo"
      else
        record.logistics_carried_count = 0
        clear_logistics_job(record)
      end
      refresh_route_renderings(record, event.player_index)
      assigned_count = assigned_count + 1
    end
  end

  player.print({mining_role.assigned_message, assigned_count})
  update_role_selection_status(player)
end

function poc.on_player_removed(event)
  local team_mates = storage.not_alone_team_mates
    and storage.not_alone_team_mates[event.player_index]
  if team_mates then
    for _, record in pairs(team_mates) do
      destroy_route_renderings(record)
      destroy_logistics_member(record)
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
  update_role_selection_status(player)
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
      and selected[entity.unit_number]
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
  -- New coverage may reveal resources to miners still looking for ore.
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      local mining_role = MINING_ROLE_BY_NAME[record.role]
      if mining_role and record.role_state == "find-ore"
        and record.entity.valid and record.entity.surface == entity.surface then
        local resource = find_nearest_resource(record, mining_role)
        if resource then
          record.role_target = resource
          record.role_state = "move-to-ore"
        end
      end
    end
  end
end

function poc.on_update(event)
  storage.not_alone_pending_spawns = storage.not_alone_pending_spawns or {}
  for player_index, spawn_tick in pairs(storage.not_alone_pending_spawns) do
    if event.tick >= spawn_tick then
      local player = game.get_player(player_index)
      if player and spawn_team_mates(player) then
        storage.not_alone_pending_spawns[player_index] = nil
      end
    end
  end

  for player_index, team_mates in pairs(storage.not_alone_team_mates or {}) do
    local player = game.get_player(player_index)
    if player then
      ensure_role_gui(player)
    end
    if player and player.character and player.character.valid then
      local active_team_mates = {}
      for _, record in pairs(team_mates) do
        if update_team_mate(record, player) then
          active_team_mates[#active_team_mates + 1] = record
        end
      end
      storage.not_alone_team_mates[player_index] = active_team_mates
    end
  end
end

function poc.register()
  script.on_init(poc.on_init)
  script.on_configuration_changed(poc.on_configuration_changed)
  script.on_event(defines.events.on_player_created, poc.on_player_created)
  script.on_event(defines.events.on_gui_click, poc.on_gui_click)
  script.on_event(defines.events.on_player_removed, poc.on_player_removed)
  script.on_event(defines.events.on_player_selected_area, poc.on_selected_area)
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