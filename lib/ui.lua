-- Functional area extracted from not-alone.lua.

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
  local existing = renders[habitat.unit_number]
  local render_object = existing and rendering.get_object_by_id(existing)
  if render_object then
    render_object.destroy()
  end
  renders[habitat.unit_number] = nil
end

TEAM_MATE_PANEL_NAME = "not-alone-team-mates-panel"
TEAM_MATE_REQUEST_FRAME_NAME = "not-alone-team-mate-requests"

local function is_team_mate_request_entity(entity)
  return is_base(entity) and get_base_type(entity) == "outpost"
end

local function request_kinds_for_entity(entity)
  local policy = get_base_policy(entity)
  return get_base_type(entity) == "outpost" and policy and policy.allowed_kinds or {}
end

local function destroy_team_mate_request_gui(player)
  local frame = player.gui.screen[TEAM_MATE_REQUEST_FRAME_NAME]
  if frame then
    frame.destroy()
  end
end

local function team_mate_request_target(player)
  local targets = storage.not_alone_team_mate_request_targets
  local target = targets and targets[player.index]
  local entity = target and target.entity
  if entity and entity.valid then
    return entity
  end
  return nil
end

local function allowed_request_item(entity, item_name)
  for _, kind in ipairs(request_kinds_for_entity(entity)) do
    if ITEM_NAME_BY_KIND[kind] == item_name then
      return kind
    end
  end
  return nil
end

local function member_slot_tooltip(kind)
  return {
    "",
    KIND_LABEL[kind],
    "\nClick to take out. Click holding ",
    KIND_LABEL[kind],
    " items to put them in."
  }
end

local function refresh_player_inventory_grid(player, entity, grid)
  local main = player.get_main_inventory()
  if not main then
    return
  end
  if #grid.children ~= #main then
    grid.clear()
    for index = 1, #main do
      grid.add({
        type = "sprite-button",
        name = "not-alone-player-slot-" .. index,
        style = "inventory_slot"
      })
    end
  end
  for index = 1, #main do
    local button = grid.children[index]
    local stack = main[index]
    if stack.valid_for_read then
      button.sprite = "item/" .. stack.name
      button.number = stack.count
      if allowed_request_item(entity, stack.name) then
        button.tooltip = {"", prototypes.item[stack.name].localised_name,
          "\nClick to station in this building."}
      else
        button.tooltip = prototypes.item[stack.name].localised_name
      end
    else
      button.sprite = ""
      button.number = nil
      button.tooltip = ""
    end
  end
end

function update_team_mate_request_gui(player)
  local frame = player.gui.screen[TEAM_MATE_REQUEST_FRAME_NAME]
  if not frame then
    return
  end
  local entity = team_mate_request_target(player)
  if not entity then
    frame.destroy()
    return
  end
  local body = frame.body
  if not body then
    return
  end
  local inventory = get_base_inventory(entity)
  local members = body.content
    and body.content.members_frame
    and body.content.members_frame.members
  if members then
    for _, kind in ipairs(request_kinds_for_entity(entity)) do
      local button = members["not-alone-member-slot-" .. kind]
      if button then
        button.number = get_base_member_count(entity, kind)
      end
    end
  end
  local grid = body.character
    and body.character.inventory_scroll
    and body.character.inventory_scroll.player_inventory
  if grid then
    refresh_player_inventory_grid(player, entity, grid)
  end
end

function open_team_mate_request_gui(player, entity)
  destroy_team_mate_request_gui(player)
  storage.not_alone_team_mate_requests = storage.not_alone_team_mate_requests or {}
  local requests = storage.not_alone_team_mate_requests[entity.unit_number] or {}
  local inventory = entity.get_inventory(defines.inventory.roboport_material)
  local kinds = request_kinds_for_entity(entity)

  local frame = player.gui.screen.add({
    type = "frame",
    name = TEAM_MATE_REQUEST_FRAME_NAME,
    direction = "vertical"
  })
  frame.auto_center = true

  local titlebar = frame.add({type = "flow", direction = "horizontal"})
  titlebar.drag_target = frame
  titlebar.add({
    type = "label",
    caption = entity.localised_name,
    style = "frame_title",
    ignored_by_interaction = true
  })
  local drag = titlebar.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  titlebar.add({
    type = "sprite-button",
    name = "not-alone-request-close",
    sprite = "utility/close",
    style = "frame_action_button"
  })

  local body = frame.add({type = "flow", name = "body", direction = "horizontal"})

  local character = body.add({
    type = "frame",
    name = "character",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical"
  })
  character.add({
    type = "label",
    caption = "Character",
    style = "caption_label"
  })
  local inventory_scroll = character.add({
    type = "scroll-pane",
    name = "inventory_scroll",
    style = "shallow_slots_scroll_pane"
  })
  inventory_scroll.style.maximal_height = 420
  local player_grid = inventory_scroll.add({
    type = "table",
    name = "player_inventory",
    column_count = 10,
    style = "filter_slot_table"
  })

  local content = body.add({
    type = "frame",
    name = "content",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical"
  })
  content.style.minimal_width = 300

  local status = content.add({type = "flow", direction = "horizontal"})
  status.style.vertical_align = "center"
  status.add({type = "sprite", sprite = "utility/status_working"})
  status.add({type = "label", caption = "Working"})

  local preview = content.add({type = "entity-preview", name = "preview"})
  preview.style.height = 148
  preview.style.horizontally_stretchable = true
  preview.entity = entity

  content.add({
    type = "label",
    caption = "Stationed team mates",
    style = "caption_label"
  })
  local members_frame = content.add({
    type = "frame",
    name = "members_frame",
    style = "inventory_frame"
    --style = "slot_button_deep_frame"
  })
  local members = members_frame.add({
    type = "table",
    name = "members",
    column_count = math.max(#kinds, 1),
    style = "filter_slot_table"
  })
  for _, kind in ipairs(kinds) do
    members.add({
      type = "sprite-button",
      name = "not-alone-member-slot-" .. kind,
      sprite = "item/" .. ITEM_NAME_BY_KIND[kind],
      style = "inventory_slot",
      number = get_base_member_count(entity, kind),
      tooltip = member_slot_tooltip(kind)
    })
  end

  content.add({
    type = "label",
    caption = "Team mate requests",
    style = "caption_label"
  })
  local request_rows = content.add({
    type = "table",
    name = "requests",
    column_count = 3
  })
  for _, kind in ipairs(kinds) do
    request_rows.add({
      type = "sprite",
      sprite = "item/" .. ITEM_NAME_BY_KIND[kind],
      tooltip = KIND_LABEL[kind]
    })
    request_rows.add({
      type = "label",
      caption = KIND_LABEL[kind]
    })
    local count_field = request_rows.add({
      type = "textfield",
      name = "not-alone-request-count-" .. kind,
      text = tostring(requests[kind] or 0),
      numeric = true,
      allow_decimal = false,
      allow_negative = false
    })
    count_field.style.width = 60
  end

  refresh_player_inventory_grid(player, entity, player_grid)

  player.opened = frame
end

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

  for base in each_base() do
    if base.surface == surface and base.force == player.force
      and (not selected_network or base.logistic_network == selected_network) then
      local inventory = get_base_inventory(base)
      local policy = get_base_policy(base)
      for _, kind in ipairs(policy.allowed_kinds) do
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

local function update_team_mate_request(player, element)
  local kind = element.name:match("^not%-alone%-request%-count%-(.+)$")
  if not kind or not ITEM_NAME_BY_KIND[kind] then
    return
  end
  local targets = storage.not_alone_team_mate_request_targets or {}
  local target = targets[player.index]
  local unit_number = target and target.unit_number
  if not unit_number then
    return
  end
  storage.not_alone_team_mate_requests = storage.not_alone_team_mate_requests or {}
  local requests = storage.not_alone_team_mate_requests[unit_number] or {}
  requests[kind] = math.max(0, math.floor(tonumber(element.text) or 0))
  storage.not_alone_team_mate_requests[unit_number] = requests
end

local take_outpost_soldier

function notalone.on_gui_click(event)
  local element = event.element
  if not element or not element.valid then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if element.name == "not-alone-request-close" then
    destroy_team_mate_request_gui(player)
    return
  end
  local slot_index = element.name:match("^not%-alone%-player%-slot%-(%d+)$")
  if slot_index then
    local entity = team_mate_request_target(player)
    local inventory = entity and get_base_inventory(entity)
    local main = player.get_main_inventory()
    local stack = main and main[tonumber(slot_index)]
    if inventory and stack and stack.valid_for_read
      and allowed_request_item(entity, stack.name) then
      local inserted = inventory.insert({name = stack.name, count = stack.count})
      if inserted > 0 then
        stack.count = stack.count - inserted
      end
    end
    update_team_mate_request_gui(player)
    return
  end
  local kind = element.name:match("^not%-alone%-member%-slot%-(.+)$")
  if not kind or not ITEM_NAME_BY_KIND[kind] then
    return
  end
  local entity = team_mate_request_target(player)
  local inventory = entity and get_base_inventory(entity)
  if not inventory then
    return
  end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read then
    if allowed_request_item(entity, cursor.name) then
      local inserted = inventory.insert({name = cursor.name, count = cursor.count})
      if inserted > 0 then
        cursor.count = cursor.count - inserted
      end
    end
  else
    local item_name = ITEM_NAME_BY_KIND[kind]
    local available = inventory.get_item_count(item_name)
    if available > 0 then
      local removed = inventory.remove({name = item_name, count = available})
      local given = player.insert({name = item_name, count = removed})
      if given < removed then
        inventory.insert({name = item_name, count = removed - given})
      end
    elseif item_name == ITEM_NAME_BY_KIND.soldier
      and entity.name == OUTPOST_NAME then
      take_outpost_soldier(player, entity)
    end
  end
  update_team_mate_request_gui(player)
end

function notalone.on_gui_text_changed(event)
  local element = event.element
  if element and element.valid then
    update_team_mate_request(game.get_player(event.player_index), element)
  end
end

take_outpost_soldier = function(player, outpost)
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for index, record in pairs(team_mates) do
      if record.kind == "soldier"
        and record.entity and record.entity.valid
        and (record.home_base == outpost or record.pending_home_base == outpost) then
        if player.insert({name = ITEM_NAME_BY_KIND.soldier, count = 1}) ~= 1 then
          return false
        end

        local surface = record.entity.surface
        local position = position_table(record.entity.position)
        local function spill(item_name, count)
          if count and count > 0 and prototypes.item[item_name] then
            surface.spill_item_stack({
              position = position,
              stack = {name = item_name, count = count}
            })
          end
        end
        for weapon_kind in pairs(record.soldier_weapons or {}) do
          local weapon = SOLDIER_WEAPON_BY_KIND[weapon_kind]
          if weapon then
            spill(weapon.gun, 1)
          end
        end
        for ammo_name, count in pairs(record.soldier_ammo or {}) do
          spill(ammo_name, count)
        end
        if record.soldier_armor and SOLDIER_ARMORS[record.soldier_armor] then
          spill(SOLDIER_ARMORS[record.soldier_armor].item, 1)
        end
        destroy_route_renderings(record)
        destroy_inventory_renderings(record)
        destroy_color_marker(record)
        if record.vehicle_inventory and record.vehicle_inventory.valid then
          surface.spill_inventory({position = position, inventory = record.vehicle_inventory})
          record.vehicle_inventory.destroy()
        end
        if record.vehicle_fuel_inventory and record.vehicle_fuel_inventory.valid then
          surface.spill_inventory({position = position, inventory = record.vehicle_fuel_inventory})
          record.vehicle_fuel_inventory.destroy()
        end
        if record.vehicle_ammo_inventory and record.vehicle_ammo_inventory.valid then
          surface.spill_inventory({position = position, inventory = record.vehicle_ammo_inventory})
          record.vehicle_ammo_inventory.destroy()
        end
        record.entity.destroy()
        table.remove(team_mates, index)
        fulfill_base_requests(outpost)
        return true
      end
    end
  end
  return false
end

function notalone.on_gui_opened(event)
  -- Roboport-derived buildings open as an entity GUI, not the logistics screen.
  if event.gui_type == defines.gui_type.entity
    and is_team_mate_request_entity(event.entity) then
    local player = game.get_player(event.player_index)
    if player then
      storage.not_alone_team_mate_request_targets =
        storage.not_alone_team_mate_request_targets or {}
      storage.not_alone_team_mate_request_targets[player.index] = {
        unit_number = event.entity.unit_number,
        entity = event.entity
      }
      player.opened = nil
      open_team_mate_request_gui(player, event.entity)
    end
    return
  end
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

function notalone.on_gui_closed(event)
  if storage.not_alone_logistics_gui_open then
    storage.not_alone_logistics_gui_open[event.player_index] = nil
  end
  local player = game.get_player(event.player_index)
  if player then
    destroy_team_mate_panel(player)
    destroy_team_mate_request_gui(player)
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
  if progress >= 1 then
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
    for _, item in pairs(record.vehicle_inventory.get_contents()) do
      counts[item.name] = (counts[item.name] or 0) + item.count
    end
  end
  if record.vehicle_fuel_inventory and record.vehicle_fuel_inventory.valid then
    for _, item in pairs(record.vehicle_fuel_inventory.get_contents()) do
      counts[item.name] = (counts[item.name] or 0) + item.count
    end
  end
  if record.vehicle_ammo_inventory and record.vehicle_ammo_inventory.valid then
    for _, item in pairs(record.vehicle_ammo_inventory.get_contents()) do
      counts[item.name] = (counts[item.name] or 0) + item.count
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
  -- The hidden driver only teleports to the car periodically; anchoring to
  -- the car keeps icons from lagging and flashing behind it.
  local anchor = record.entity
  if record.vehicle_state and record.vehicle_entity and record.vehicle_entity.valid then
    anchor = record.vehicle_entity
  end
  local signature_parts = {tostring(anchor.unit_number)}
  for _, item in pairs(items) do
    signature_parts[#signature_parts + 1] = item.name .. ":" .. item.count
  end
  local signature = table.concat(signature_parts, ",")
  local first_object = record.inventory_render_ids and record.inventory_render_ids[1]
    and rendering.get_object_by_id(record.inventory_render_ids[1])
  if record.inventory_render_signature == signature
    and (#items == 0 or first_object) then
    return
  end

  destroy_inventory_renderings(record)
  record.inventory_render_signature = signature
  local start_x = -((#items - 1) * INVENTORY_ICON_SPACING) / 2
  for index, item in ipairs(items) do
    local offset = {start_x + (index - 1) * INVENTORY_ICON_SPACING, -1.9}
    local icon = rendering.draw_sprite({
      sprite = "item." .. item.name,
      target = {entity = anchor, offset = offset},
      surface = anchor.surface,
      x_scale = INVENTORY_ICON_SCALE,
      y_scale = INVENTORY_ICON_SCALE,
      only_in_alt_mode = true,
      render_layer = "entity-info-icon"
    })
    local count = rendering.draw_text({
      text = tostring(item.count),
      target = {entity = anchor, offset = {offset[1] + 0.2, offset[2] + 0.2}},
      surface = anchor.surface,
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

