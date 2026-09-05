-- Functional area extracted from not-alone.lua.

function builder_is_at_target(record, target)
  if target.type == "item-entity" then
    return distance_squared(record.entity.position, target.position)
      <= BUILDER_ITEM_PICKUP_DISTANCE * BUILDER_ITEM_PICKUP_DISTANCE
  end
  return distance_squared_to_box(record.entity.position, target.bounding_box)
    <= BUILDER_TARGET_INTERACTION_DISTANCE * BUILDER_TARGET_INTERACTION_DISTANCE
end

function builder_target_destination(record, target)
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

function builder_ghost_standing_position(record, target)
  local box = target.bounding_box
  local position = record.entity.position
  if position.x > box.left_top.x and position.x < box.right_bottom.x
    and position.y > box.left_top.y and position.y < box.right_bottom.y then
    -- Standing inside the footprint blocks revive; leave through the nearest edge.
    local exits = {
      {x = box.left_top.x - BUILDER_GHOST_ESCAPE_DISTANCE, y = position.y},
      {x = box.right_bottom.x + BUILDER_GHOST_ESCAPE_DISTANCE, y = position.y},
      {x = position.x, y = box.left_top.y - BUILDER_GHOST_ESCAPE_DISTANCE},
      {x = position.x, y = box.right_bottom.y + BUILDER_GHOST_ESCAPE_DISTANCE}
    }
    local best, best_distance
    for _, exit in pairs(exits) do
      local exit_distance = distance_squared(position, exit)
      if not best_distance or exit_distance < best_distance then
        best = exit
        best_distance = exit_distance
      end
    end
    return best
  end
  return builder_target_destination(record, target)
end

function update_builder(record)
  -- Never let cargo go undelivered: whatever the state machine was doing,
  -- unspent deconstruction cargo always takes priority over new jobs or
  -- docking, so it can never be silently lost or abandoned mid-route.
  if not record.builder_plan
    and record.builder_state ~= "return-deconstruction"
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
  if record.builder_state == "crafting" then
    if game.tick < (record.builder_craft_ready_tick or 0) then
      stop_team_mate(record)
      return true
    end
    local action = record.builder_plan and record.builder_plan[record.builder_plan_index]
    local cargo = action and get_builder_cargo(record)
    if not action or action.type ~= "craft" then
      record.builder_state = nil
      return true
    end
    for _, ingredient in pairs(action.ingredients or {}) do
      local count = math.ceil((ingredient.amount or 1) * action.batches)
      if ingredient.type and ingredient.type ~= "item"
        or cargo.get_item_count({name = ingredient.name, quality = "normal"}) < count then
        record.builder_state = nil
        record.builder_plan = nil
        return true
      end
    end
    for _, ingredient in pairs(action.ingredients or {}) do
      local count = math.ceil((ingredient.amount or 1) * action.batches)
      cargo.remove({name = ingredient.name, quality = "normal", count = count})
    end
    cargo.insert({
      name = action.product.name,
      quality = action.product.quality,
      count = action.count
    })
    record.builder_craft_ready_tick = nil
    record.builder_plan_index = record.builder_plan_index + 1
    record.builder_state = "execute-plan"
    return true
  end
  if record.builder_state == "execute-plan" then
    local action = record.builder_plan and record.builder_plan[record.builder_plan_index]
    if not action then
      local cargo = get_builder_cargo(record)
      local product = record.builder_item
      if product and cargo.get_item_count(product) > 0 then
        cargo.remove({name = product.name, quality = product.quality, count = 1})
        record.builder_carried_count = 1
        if record.builder_target and record.builder_target.valid
          and record.builder_target.type == "entity-ghost" then
          record.builder_state = "move-to-ghost"
        else
          record.builder_state = "move-to-repair"
        end
      else
        record.builder_state = nil
        record.builder_plan = nil
      end
      return true
    end
    local cargo = size_builder_cargo_for_plan(record, record.builder_plan)
    if action.type == "craft" then
      record.builder_craft_ready_tick = game.tick + action.craft_ticks
      record.builder_state = "crafting"
      stop_team_mate(record)
      return true
    end
    local source = record.builder_source
    local inventory = get_logistics_source_inventory(source)
    local item_name = type(action.item) == "table" and action.item.name or action.item
    if not source or not source.valid or not inventory
      or inventory.get_item_count(item_name) < action.count then
      source = find_builder_source(
        record.entity.surface.find_closest_logistic_network_by_position(
          position_table(record.entity.position), record.entity.force
        ),
        action.item,
        position_table(record.entity.position)
      )
      record.builder_source = source
      inventory = get_logistics_source_inventory(source)
    end
    if not source or not inventory then
      record.builder_state = nil
      record.builder_plan = nil
    elseif distance_squared(record.entity.position, source.position) <= 4 then
      local removed = inventory.remove({
        name = action.item.name,
        quality = action.item.quality,
        count = action.count
      })
      if removed > 0 then
        cargo.insert({
          name = action.item.name,
          quality = action.item.quality,
          count = removed
        })
        -- Partial withdrawals continue at the next source for the remainder.
        action.count = action.count - removed
      end
      record.builder_source = nil
      if action.count <= 0 then
        record.builder_plan_index = record.builder_plan_index + 1
      end
    else
      move_team_mate(record, source.position, 2)
    end
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
    local target = record.builder_target
    if not target or not target.valid then
      record.builder_state = "return-material"
    elseif builder_is_at_target(record, target) then
      record.builder_approach_position = nil
      record.builder_approach_stalls = nil
      local _, revived_entity = target.revive({raise_revive = true})
      if revived_entity then
        local cargo = get_builder_cargo(record)
        cargo.remove({
          name = record.builder_item.name,
          quality = record.builder_item.quality,
          count = 1
        })
        if record.builder_item and record.builder_item.name then
          trigger_research_unlocks_for_item(record.entity.force, record.builder_item.name)
        end
        record.builder_item = nil
        record.builder_carried_count = 0
        record.builder_source = nil
        record.builder_plan = nil
        record.builder_plan_index = nil
        record.builder_target = nil
        record.builder_state = nil
        record.builder_ghost_attempts = nil
        stop_team_mate(record)
      else
        -- Blocked, usually by a unit standing in the footprint (often this
        -- builder itself); step clear and retry before giving up.
        record.builder_ghost_attempts = (record.builder_ghost_attempts or 0) + 1
        if record.builder_ghost_attempts > 120 then
          record.builder_ghost_attempts = nil
          record.builder_state = "return-material"
          stop_team_mate(record)
        else
          move_team_mate(record, builder_ghost_standing_position(record, target), 0.2)
        end
      end
    else
      -- A ghost the pathfinder cannot reach otherwise pins this builder
      -- forever; give up like the deconstruction path does and let another
      -- job (or a later retry) have a turn.
      local position = record.entity.position
      if record.builder_approach_position
        and distance_squared(position, record.builder_approach_position) < 0.01 then
        record.builder_approach_stalls = (record.builder_approach_stalls or 0) + 1
        if record.builder_approach_stalls >= 30 then
          record.builder_unreachable = record.builder_unreachable or {}
          record.builder_unreachable[#record.builder_unreachable + 1] = {
            entity = target,
            tick = game.tick
          }
          record.builder_approach_position = nil
          record.builder_approach_stalls = nil
          record.builder_ghost_attempts = nil
          record.builder_state = "return-material"
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
  if record.builder_state == "move-to-repair" then
    local target = record.builder_target
    if not target or not target.valid
      or (target.get_health_ratio and target.get_health_ratio() >= 1) then
      -- Already fixed (by someone else, or destroyed): the pack in hand
      -- still needs to go back into logistics storage.
      record.builder_target = nil
      record.builder_plan = nil
      record.builder_plan_index = nil
      record.builder_state = "return-material"
    elseif builder_is_at_target(record, target) then
      -- Factorio clamps an out-of-range write to the entity's real max
      -- health; prototype.max_health isn't exposed for every entity type
      -- that still reports get_health_ratio, so this avoids reading it.
      target.health = target.health + 1e9
      record.builder_item = nil
      record.builder_carried_count = 0
      record.builder_source = nil
      record.builder_plan = nil
      record.builder_plan_index = nil
      record.builder_target = nil
      record.builder_state = nil
      stop_team_mate(record)
    else
      move_team_mate(record, builder_target_destination(record, target), 0.2)
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

  if game.tick >= (record.next_job_search_tick or 0) then
    if assign_builder_job(record) then
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

