-- Functional area extracted from poc.lua.

function flush_habitat_crew_records(habitat)
  local crews = storage.not_alone_habitat_crews
  local crew = crews and crews[habitat.unit_number]
  if not crew then
    return
  end
  local inventory = get_habitat_inventory(habitat)
  if not inventory then
    return
  end
  local remaining = false
  for kind, count in pairs(crew) do
    if count > 0 and ITEM_NAME_BY_KIND[kind] then
      local inserted = inventory.insert({name = ITEM_NAME_BY_KIND[kind], count = count})
      crew[kind] = count - inserted
      if crew[kind] > 0 then
        remaining = true
      end
    end
  end
  if not remaining then
    crews[habitat.unit_number] = nil
  end
end

function update_habitat_crew_display(habitat)
  storage.not_alone_habitat_crew_renders = storage.not_alone_habitat_crew_renders or {}
  local renders = storage.not_alone_habitat_crew_renders
  local inventory = get_habitat_inventory(habitat)
  local parts = {}
  for _, kind in pairs(TEAM_MATE_KINDS) do
    local count = inventory and inventory.get_item_count(ITEM_NAME_BY_KIND[kind]) or 0
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

TEAM_MATE_PANEL_NAME = "not-alone-team-mates-panel"

function destroy_team_mate_panel(player)
  local panel = player.gui.relative[TEAM_MATE_PANEL_NAME]
    or player.gui.screen[TEAM_MATE_PANEL_NAME]
  if panel then
    panel.destroy()
  end
end

function update_team_mate_panel(player)
  local logistics_open = player.opened_gui_type == defines.gui_type.logistic
    or storage.not_alone_logistics_gui_open
      and storage.not_alone_logistics_gui_open[player.index]
  if not logistics_open then
    destroy_team_mate_panel(player)
    return
  end

  local network = player.opened
  local selected_network = network and network.object_name == "LuaLogisticNetwork"
    and network or nil

  local counts = {}
  local statuses = {}
  for _, kind in pairs(TEAM_MATE_KINDS) do
    counts[kind] = {deployed = 0, docked = 0}
    statuses[kind] = {}
  end

  local surface = player.surface
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record.entity and record.entity.valid
        and record.entity.surface == surface
        and (not selected_network or surface.find_closest_logistic_network_by_position(
          position_table(record.entity.position), player.force
        ) == selected_network) then
        local count = counts[record.kind]
        if count then
          count.deployed = count.deployed + 1
          local status = record.command_kind == "attack" and "fighting"
            or record.command_kind == "move" and "travelling"
            or record.miner_state and "mining"
            or record.builder_state and "building"
            or record.carrier_state and "hauling"
            or record.soldier_state and "arming"
            or "idle"
          statuses[record.kind][status] = (statuses[record.kind][status] or 0) + 1
        end
      end
    end
  end

  for habitat in each_habitat() do
    if habitat.surface == surface and habitat.force == player.force
      and (not selected_network or habitat.logistic_network == selected_network) then
      local inventory = get_habitat_inventory(habitat)
      for _, kind in pairs(TEAM_MATE_KINDS) do
        counts[kind].docked = counts[kind].docked
          + (inventory and inventory.get_item_count(ITEM_NAME_BY_KIND[kind]) or 0)
      end
    end
  end

  local panel = player.gui.screen[TEAM_MATE_PANEL_NAME]
  if not panel then
    destroy_team_mate_panel(player)
    -- Default frame + caption gives the same heading font as "Logistic
    -- networks"; a list-box gives the same row styling as the network list.
    panel = player.gui.screen.add({
      type = "frame",
      name = TEAM_MATE_PANEL_NAME,
      caption = "Team mates",
      direction = "vertical"
    })
    panel.style.width = 260
    local scale = player.display_scale
    panel.location = {x = math.floor(537 * scale), y = math.floor(38 * scale)}
    local rows = panel.add({
      type = "list-box",
      name = "rows",
      ignored_by_interaction = true
    })
    rows.style.horizontally_stretchable = true
  end

  local rows = {}
  for _, kind in pairs(TEAM_MATE_KINDS) do
    local count = counts[kind]
    local status_parts = {}
    for status, amount in pairs(statuses[kind]) do
      status_parts[#status_parts + 1] = status .. " " .. amount
    end
    table.sort(status_parts)
    local caption = string.format(
      "%s  %d out / %d docked",
      KIND_LABEL[kind], count.deployed, count.docked
    )
    if #status_parts > 0 then
      caption = caption .. " (" .. table.concat(status_parts, ", ") .. ")"
    end
    rows[#rows + 1] = caption
  end
  panel.rows.items = rows
end

function poc.on_gui_opened(event)
  if event.gui_type ~= defines.gui_type.logistic then
    return
  end
  storage.not_alone_logistics_gui_open = storage.not_alone_logistics_gui_open or {}
  storage.not_alone_logistics_gui_open[event.player_index] = true
  local player = game.get_player(event.player_index)
  if player then
    update_team_mate_panel(player)
  end
end

function poc.on_gui_closed(event)
  if storage.not_alone_logistics_gui_open then
    storage.not_alone_logistics_gui_open[event.player_index] = nil
  end
  local player = game.get_player(event.player_index)
  if player then
    destroy_team_mate_panel(player)
  end
end

function destroy_route_renderings(record)
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
function destroy_color_marker(record)
  if record.color_marker_render_id then
    local render_object = rendering.get_object_by_id(record.color_marker_render_id)
    if render_object then
      render_object.destroy()
    end
    record.color_marker_render_id = nil
  end
end

function get_render_object(render_id)
  return render_id and rendering.get_object_by_id(render_id) or nil
end

function destroy_inventory_renderings(record)
  for _, render_id in pairs(record.inventory_render_ids or {}) do
    local render_object = get_render_object(render_id)
    if render_object then
      render_object.destroy()
    end
  end
  record.inventory_render_ids = {}
  record.inventory_render_signature = nil
  for _, render_id in pairs(record.builder_target_render_ids or {}) do
    local render_object = get_render_object(render_id)
    if render_object then
      render_object.destroy()
    end
  end
  record.builder_target_render_ids = {}
end

function update_builder_target_renderings(record)
  if record.kind ~= "builder" or not record.builder_target
    or not record.builder_target.valid or not record.builder_item then
    for _, render_id in pairs(record.builder_target_render_ids or {}) do
      local render_object = get_render_object(render_id)
      if render_object then
        render_object.destroy()
      end
    end
    record.builder_target_render_ids = {}
    record.builder_target_render_signature = nil
    return
  end

  local plan = record.builder_plan or {}
  local plan_count = math.max(1, #plan)
  local plan_index = math.min(record.builder_plan_index or plan_count, plan_count)
  local progress = (plan_index - 1) / plan_count
  local action = plan[record.builder_plan_index]
  if record.builder_state == "crafting" and action and action.craft_ticks then
    local elapsed = action.craft_ticks - math.max(
      0,
      (record.builder_craft_ready_tick or game.tick) - game.tick
    )
    progress = progress + math.min(1, elapsed / action.craft_ticks) / plan_count
  elseif record.builder_state == "move-to-ghost" then
    progress = 1
  end
  progress = math.max(0, math.min(1, progress))

  -- Reuse the existing render objects only when both the target entity and the
  -- build progress are unchanged. Keying only on item name + progress can leave
  -- stale renderings to the previous target behind after a save reload or a target swap.
  local target_id = record.builder_target and record.builder_target.valid
    and record.builder_target.unit_number or "none"
  local signature = (record.builder_item and record.builder_item.name or "none")
    .. ":" .. tostring(target_id)
    .. ":" .. string.format("%.3f", progress)
  if record.builder_target_render_signature == signature
    and record.builder_target_render_ids
    and get_render_object(record.builder_target_render_ids[1]) then
    return
  end

  for _, render_id in pairs(record.builder_target_render_ids or {}) do
    local render_object = get_render_object(render_id)
    if render_object then
      render_object.destroy()
    end
  end
  record.builder_target_render_ids = {}
  record.builder_target_render_signature = signature

  local target_icon = rendering.draw_sprite({
    sprite = "item." .. record.builder_item.name,
    target = {entity = record.entity, offset = {1.25, -1.9}},
    surface = record.entity.surface,
    x_scale = INVENTORY_ICON_SCALE,
    y_scale = INVENTORY_ICON_SCALE,
    only_in_alt_mode = true,
    render_layer = "entity-info-icon"
  })
  local bar_background = rendering.draw_rectangle({
    color = {r = 0.08, g = 0.08, b = 0.08, a = 0.9},
    filled = true,
    left_top = {entity = record.entity, offset = {0.55, -2.65}},
    right_bottom = {entity = record.entity, offset = {1.95, -2.4}},
    surface = record.entity.surface,
    only_in_alt_mode = true,
    draw_on_ground = false
  })
  local bar_fill = rendering.draw_rectangle({
    color = KIND_COLOR.builder,
    filled = true,
    left_top = {entity = record.entity, offset = {0.55, -2.65}},
    right_bottom = {entity = record.entity, offset = {0.55 + 1.4 * progress, -2.4}},
    surface = record.entity.surface,
    only_in_alt_mode = true,
    draw_on_ground = false
  })
  record.builder_target_render_ids = {
    target_icon.id,
    bar_background.id,
    bar_fill.id
  }
end

function get_carried_items(record)
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
  if record.vehicle_inventory and record.vehicle_inventory.valid then
    for item_name, count in pairs(record.vehicle_inventory.get_contents()) do
      counts[item_name] = (counts[item_name] or 0) + count
    end
  end

  local items = {}
  for name, count in pairs(counts) do
    items[#items + 1] = {name = name, count = count}
  end
  table.sort(items, function(left, right) return left.name < right.name end)
  return items
end

function update_inventory_renderings(record)
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

