-- Functional area extracted from poc.lua.

function get_resource_info(resource_name)
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

function get_marked_resources(surface_index)
  storage.not_alone_marked_resources = storage.not_alone_marked_resources or {}
  storage.not_alone_marked_resources[surface_index] =
    storage.not_alone_marked_resources[surface_index] or {}
  return storage.not_alone_marked_resources[surface_index]
end

function destroy_mark_rendering(mark)
  local render_object = mark and mark.render_id and rendering.get_object_by_id(mark.render_id)
  if render_object then
    render_object.destroy()
  end
end

-- Resource entities have no unit_number, so mark them by tile position.
function resource_mark_key(resource)
  local position = resource.position
  return math.floor(position.x) .. "," .. math.floor(position.y)
end

function mark_resource_for_mining(resource)
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

function unmark_resource_for_mining(resource)
  local marks = get_marked_resources(resource.surface.index)
  local key = resource_mark_key(resource)
  local mark = marks[key]
  if mark then
    destroy_mark_rendering(mark)
    marks[key] = nil
  end
end

function is_resource_marked(resource)
  local marks = storage.not_alone_marked_resources
    and storage.not_alone_marked_resources[resource.surface.index]
  return marks and marks[resource_mark_key(resource)] ~= nil
end

function cleanup_marked_resources(surface_index)
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

function get_resource_claimant(resource)
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

function find_marked_resource(record, surface, force, position)
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

function assign_miner_job(record, surface, force, position)
  local resource = find_marked_resource(record, surface, force, position)
  if not resource then
    return false
  end
  record.miner_target = resource
  record.mining_resource_info = get_resource_info(resource.name)
  record.miner_state = "move-to-ore"
  return true
end

function update_miner(record, player)
  update_mining_animation(record, record.miner_state == "mine")

  if record.miner_state == "move-to-ore" then
    if not record.miner_target or not record.miner_target.valid
      or not is_resource_marked(record.miner_target) then
      record.miner_state = nil
      record.miner_target = nil
    elseif distance_squared(record.entity.position, record.miner_target.position)
      <= MINER_ORE_STOPPING_DISTANCE * MINER_ORE_STOPPING_DISTANCE then
      record.miner_state = "mine"
      record.next_mining_tick = game.tick + math.random(get_mining_interval(player))
      stop_team_mate(record)
    else
      move_team_mate(record, record.miner_target.position, MINER_ORE_STOPPING_DISTANCE)
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
      or not is_resource_marked(resource) then
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
  if game.tick >= (record.next_job_search_tick or 0) then
    if assign_miner_job(record) then
      record.next_job_search_tick = nil
      record.idle_search_failures = nil
      return true
    end
    record.next_job_search_tick = game.tick + IDLE_JOB_SEARCH_INTERVAL
    record.idle_search_failures = (record.idle_search_failures or 0) + 1
  end
  if (record.idle_search_failures or 0) < IDLE_DOCK_AFTER_FAILURES then
    stop_team_mate(record)
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

