-- Train gangs: a Crew wagon holds team mates as items, like a Habitat. With
-- Rail gang on, the train drives to the end of its built track, Builders build
-- the player's ghosts ahead from the train's cargo wagons while Soldiers
-- guard, everyone re-boards, and the train moves up to the new end.
--
-- Gang state lives in storage.not_alone_crew_wagons[unit_number]; deployed
-- members carry record.gang_wagon, and team mates walking over to board carry
-- record.gang_join.

local function get_crew_wagon_registry()
  local registry = storage.not_alone_crew_wagons
  if not registry then
    registry = {}
    for _, surface in pairs(game.surfaces) do
      for _, wagon in pairs(surface.find_entities_filtered({name = CREW_WAGON_NAME})) do
        registry[wagon.unit_number] = {wagon = wagon}
      end
    end
    storage.not_alone_crew_wagons = registry
  end
  return registry
end

function get_train_gang(wagon)
  if not wagon or not wagon.valid or wagon.name ~= CREW_WAGON_NAME then
    return nil
  end
  local registry = get_crew_wagon_registry()
  local gang = registry[wagon.unit_number]
  if not gang then
    gang = {wagon = wagon}
    registry[wagon.unit_number] = gang
  end
  if not gang.requests then
    gang.requests = {}
    for kind, count in pairs(GANG_DEFAULT_REQUESTS) do
      gang.requests[kind] = count
    end
  end
  gang.state = gang.state or "idle"
  gang.status = gang.status or "Rail gang off"
  return gang
end

function register_crew_wagon(wagon)
  get_train_gang(wagon)
end

local function crew_wagon_inventory(wagon)
  return wagon.get_inventory(defines.inventory.cargo_wagon)
end

-- Cargo the gang may build from: every cargo wagon in the train except Crew
-- wagons, whose inventory is the crew roster.
local function train_cargo_wagons(train)
  local wagons = {}
  for _, wagon in pairs(train.cargo_wagons) do
    if wagon.name ~= CREW_WAGON_NAME then
      wagons[#wagons + 1] = wagon
    end
  end
  return wagons
end

local function train_item_count(train, item_name)
  local count = 0
  for _, wagon in pairs(train_cargo_wagons(train)) do
    count = count + wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count(item_name)
  end
  return count
end

local function ghost_item(ghost)
  local items = ghost.ghost_prototype.items_to_place_this
  local item = items and items[1]
  if not item then
    return nil
  end
  return {name = item.name, count = item.count or 1}
end

local function each_gang_record(wagon, field)
  local list = {}
  for _, team_mates in pairs(storage.not_alone_team_mates or {}) do
    for _, record in pairs(team_mates) do
      if record[field] == wagon and record.entity and record.entity.valid then
        list[#list + 1] = record
      end
    end
  end
  return list
end

local function count_by_kind(records)
  local counts = {}
  for _, record in pairs(records) do
    counts[record.kind] = (counts[record.kind] or 0) + 1
  end
  return counts
end

local function deploy_team_mate_from(source, inventory, kind, position)
  local player = find_any_player_for_force(source.force)
  if not player or not player.valid or player.surface ~= source.surface then
    return nil
  end
  storage.not_alone_team_mates = storage.not_alone_team_mates or {}
  local team_mates = storage.not_alone_team_mates[player.index] or {}
  local record = create_team_mate(player, kind, #team_mates + 1, position)
  if not record then
    return nil
  end
  if inventory.remove({name = ITEM_NAME_BY_KIND[kind], count = 1}) ~= 1 then
    record.entity.destroy()
    return nil
  end
  restore_docked_team_mate(source, record)
  team_mates[#team_mates + 1] = record
  storage.not_alone_team_mates[player.index] = team_mates
  return record
end

-- Leftover Builder cargo goes back into the train's cargo wagons.
local function unload_builder_cargo(record, train)
  local cargo = record.builder_cargo
  if not cargo or not cargo.valid or cargo.is_empty() then
    return
  end
  for _, wagon in pairs(train_cargo_wagons(train)) do
    local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
    for slot = 1, #cargo do
      local stack = cargo[slot]
      if stack.valid_for_read then
        local inserted = inventory.insert(stack)
        stack.count = stack.count - inserted
      end
    end
  end
end

local function board_wagon(record, wagon)
  local inventory = crew_wagon_inventory(wagon)
  stop_team_mate(record)
  if wagon.train then
    unload_builder_cargo(record, wagon.train)
  end
  if inventory.insert({name = ITEM_NAME_BY_KIND[record.kind], count = 1}) ~= 1 then
    -- Full: wait beside the wagon.
    return true
  end
  destroy_route_renderings(record)
  destroy_inventory_renderings(record)
  destroy_color_marker(record)
  record.gang_wagon = nil
  record.gang_join = nil
  store_docked_team_mate(wagon, record)
  record.entity.destroy()
  return false
end

local function near_wagon(record, wagon)
  return distance_squared_to_box(record.entity.position, wagon.bounding_box)
    <= GANG_BOARD_DISTANCE * GANG_BOARD_DISTANCE
end

local function walk_back_and_board(record, wagon)
  local train = wagon.train
  if not train or train.speed ~= 0 then
    stop_team_mate(record)
    return true
  end
  if not near_wagon(record, wagon) then
    move_team_mate(record, position_table(wagon.position), 2)
    return true
  end
  return board_wagon(record, wagon)
end

local function release_ghost(record, gang)
  local target = record.gang_target
  if target and target.valid and gang.claims then
    gang.claims[target.unit_number] = nil
  end
  record.gang_target = nil
  record.gang_attempts = nil
end

local function claim_ghost(record, gang, train, cargo)
  local position = record.entity.position
  local best, best_distance
  for _, ghost in pairs(gang.ghosts or {}) do
    if ghost.valid and not gang.skipped[ghost.unit_number]
      and not gang.claims[ghost.unit_number] then
      local item = ghost_item(ghost)
      if item and (cargo.get_item_count(item.name) >= item.count
        or train_item_count(train, item.name) >= item.count) then
        local distance = distance_squared(position, ghost.position)
        if not best_distance or distance < best_distance then
          best = ghost
          best_distance = distance
        end
      end
    end
  end
  if best then
    gang.claims[best.unit_number] = record.entity.unit_number
    record.gang_target = best
    record.gang_attempts = 0
  end
  return best
end

-- How many of an item the open ghosts still need, so one trip to the cargo
-- wagon fetches enough for several of them.
local function gang_item_demand(gang, item_name)
  local demand = 0
  for _, ghost in pairs(gang.ghosts or {}) do
    if ghost.valid and not gang.skipped[ghost.unit_number] then
      local item = ghost_item(ghost)
      if item and item.name == item_name then
        demand = demand + item.count
      end
    end
  end
  return demand
end

local function fetch_from_train(record, gang, train, item)
  local source
  for _, wagon in pairs(train_cargo_wagons(train)) do
    if wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count(item.name) >= item.count then
      source = wagon
      break
    end
  end
  if not source then
    gang.skipped[record.gang_target.unit_number] = true
    release_ghost(record, gang)
    return
  end
  if not near_wagon(record, source) then
    move_team_mate(record, position_table(source.position), 2)
    return
  end
  stop_team_mate(record)
  unload_builder_cargo(record, train)
  local cargo = get_builder_cargo(record)
  local stack_size = prototypes.item[item.name].stack_size
  local wanted = math.min(stack_size, math.max(item.count, gang_item_demand(gang, item.name)))
  local inventory = source.get_inventory(defines.inventory.cargo_wagon)
  local removed = inventory.remove({name = item.name, count = wanted})
  if removed > 0 then
    local carried = cargo.insert({name = item.name, count = removed})
    if carried < removed then
      inventory.insert({name = item.name, count = removed - carried})
    end
  end
end

local function update_gang_builder(record, gang, train)
  local cargo = get_builder_cargo(record)
  local target = record.gang_target
  if target and not target.valid then
    release_ghost(record, gang)
    target = nil
  end
  if not target then
    target = claim_ghost(record, gang, train, cargo)
    if not target then
      return walk_back_and_board(record, gang.wagon)
    end
  end

  local item = ghost_item(target)
  if not item then
    gang.skipped[target.unit_number] = true
    release_ghost(record, gang)
    return true
  end
  if cargo.get_item_count(item.name) < item.count then
    fetch_from_train(record, gang, train, item)
    return true
  end

  local reach = GANG_BUILD_REACH
  if distance_squared_to_box(record.entity.position, target.bounding_box) > reach * reach then
    move_team_mate(record, position_table(target.position), reach - 0.5)
    return true
  end
  local force = record.entity.force
  local _, revived = target.revive({raise_revive = true})
  if revived then
    cargo.remove({name = item.name, count = item.count})
    progress_trigger_research(force, "build-entity", revived.name, 1)
    release_ghost(record, gang)
    stop_team_mate(record)
    return true
  end
  -- Blocked, usually by this Builder standing in the footprint.
  record.gang_attempts = (record.gang_attempts or 0) + 1
  if record.gang_attempts > GANG_BUILD_ATTEMPTS then
    gang.skipped[target.unit_number] = true
    release_ghost(record, gang)
  else
    move_team_mate(record, builder_ghost_standing_position(record, target), 0.2)
  end
  return true
end

local function update_gang_soldier(record, gang)
  update_soldier_equipment(record)
  local entity = record.entity
  local target = find_soldier_immediate_target(record)
    or entity.surface.find_nearest_enemy({
      position = gang.work_position,
      max_distance = GANG_GUARD_RADIUS * 2,
      force = entity.force
    })
  if target then
    attack_with_team_mate(record, target)
    return true
  end
  if distance_squared(entity.position, gang.work_position) > GANG_GUARD_RADIUS * GANG_GUARD_RADIUS then
    move_team_mate(record, gang.work_position, GANG_GUARD_RADIUS / 2)
  else
    wander_team_mate(record)
  end
  return true
end

-- Returns nil for team mates outside any gang, else whether the record stays
-- deployed (false once it has boarded).
function update_train_gang_member(record)
  local joining = record.gang_join
  if joining then
    local train = joining.valid and joining.train
    if not train or train.speed ~= 0 then
      record.gang_join = nil
      return nil
    end
    if not near_wagon(record, joining) then
      move_team_mate(record, position_table(joining.position), 2)
      return true
    end
    return board_wagon(record, joining)
  end

  local wagon = record.gang_wagon
  if not wagon then
    return nil
  end
  local gang = wagon.valid and get_train_gang(wagon)
  local train = gang and wagon.train
  if not train then
    record.gang_wagon = nil
    record.gang_target = nil
    return nil
  end
  if record.gang_state == "return" or gang.state ~= "building" then
    release_ghost(record, gang)
    return walk_back_and_board(record, wagon)
  end
  if record.kind == "builder" then
    return update_gang_builder(record, gang, train)
  elseif record.kind == "soldier" then
    return update_gang_soldier(record, gang)
  end
  return walk_back_and_board(record, wagon)
end

-- Habitats near a stopped Crew wagon send over the crew it requests.
local function recruit_gang_crew(gang)
  local wagon = gang.wagon
  local inventory = crew_wagon_inventory(wagon)
  local joining = count_by_kind(each_gang_record(wagon, "gang_join"))
  for _, kind in ipairs(GANG_KINDS) do
    local needed = (gang.requests[kind] or 0)
      - inventory.get_item_count(ITEM_NAME_BY_KIND[kind])
      - (joining[kind] or 0)
    if needed > 0 then
      for base in each_base() do
        if get_base_type(base) == "habitat"
          and base.surface == wagon.surface
          and base.force == wagon.force
          and distance_squared(base.position, wagon.position)
            <= GANG_RECRUIT_RADIUS * GANG_RECRUIT_RADIUS then
          local base_inventory = get_base_inventory(base)
          if base_inventory and base_inventory.get_item_count(ITEM_NAME_BY_KIND[kind]) > 0 then
            local record = deploy_team_mate_from(base, base_inventory, kind, base.position)
            if record then
              record.gang_join = wagon
              break
            end
          end
        end
      end
    end
  end
end

local function lead_locomotive(train)
  local locomotives = train.locomotives
  return locomotives.front_movers[1] or locomotives.back_movers[1]
end

local function train_has_fuel(train)
  local locomotives = train.locomotives
  for _, group in pairs({locomotives.front_movers, locomotives.back_movers}) do
    for _, locomotive in pairs(group) do
      local burner = locomotive.burner
      if not burner or burner.currently_burning
        or (burner.inventory and not burner.inventory.is_empty()) then
        return true
      end
    end
  end
  return false
end

local function gang_readiness_problem(gang, train)
  if not lead_locomotive(train) then
    return "Needs a locomotive"
  end
  if not train_has_fuel(train) then
    return "Needs fuel in the locomotive"
  end
  if train_item_count(train, GANG_RAIL_ITEM_NAME) == 0 then
    return "Needs rails in a cargo wagon"
  end
  local inventory = crew_wagon_inventory(gang.wagon)
  if inventory.get_item_count(ITEM_NAME_BY_KIND.carrier) == 0 then
    return "Needs a Carrier aboard to drive"
  end
  if inventory.get_item_count(ITEM_NAME_BY_KIND.builder) == 0 then
    return "Needs a Builder aboard"
  end
  return nil
end

-- Rails from the leading carriage to the end of the built track, with the
-- running distance to each.
local function find_track_end(train)
  local forward = #train.locomotives.front_movers > 0
  local lead = forward and train.front_stock or train.back_stock
  local rail_end = forward and train.front_end or train.back_end
  if not lead or not rail_end or not rail_end.valid then
    return nil
  end
  rail_end = rail_end.make_copy()
  local steps = {}
  local distance = 0
  local previous = lead.position
  for _ = 1, GANG_MAX_TRACK_RAILS do
    local rail = rail_end.rail
    if not rail or not rail.valid then
      break
    end
    local position = rail.position
    distance = distance + math.sqrt(distance_squared(previous, position))
    steps[#steps + 1] = {rail = rail, distance = distance}
    previous = position
    if not rail_end.move_natural() then
      return steps
    end
  end
  -- A loop or a very long line: no end in reach.
  return nil
end

local function refresh_gang_ghosts(gang, position)
  gang.ghosts = gang.wagon.surface.find_entities_filtered({
    type = "entity-ghost",
    force = gang.wagon.force,
    position = position,
    radius = GANG_BUILD_RADIUS
  })
end

-- Ghosts some Builder can still build: an item is in the train or in hand,
-- or a Builder has already claimed it.
local function count_open_ghosts(gang, train)
  local open = 0
  local carried = {}
  for _, record in pairs(each_gang_record(gang.wagon, "gang_wagon")) do
    local cargo = record.builder_cargo
    if cargo and cargo.valid then
      for _, item in pairs(cargo.get_contents()) do
        carried[item.name] = (carried[item.name] or 0) + item.count
      end
    end
  end
  for _, ghost in pairs(gang.ghosts or {}) do
    if ghost.valid and not gang.skipped[ghost.unit_number] then
      local item = ghost_item(ghost)
      if gang.claims[ghost.unit_number]
        or (item and ((carried[item.name] or 0) >= item.count
          or train_item_count(train, item.name) >= item.count)) then
        open = open + 1
      end
    end
  end
  return open
end

local function remove_temporary_records(train)
  local schedule = train.get_schedule()
  local records = schedule.get_records() or {}
  for index = #records, 1, -1 do
    if records[index].temporary then
      schedule.remove_record({schedule_index = index})
    end
  end
end

-- The Carrier visibly takes the locomotive's seat while the train moves.
local function seat_gang_driver(gang, train)
  local locomotive = lead_locomotive(train)
  if not locomotive or locomotive.get_driver() then
    return
  end
  local driver = locomotive.surface.create_entity({
    name = CAR_DRIVER_NAME,
    position = locomotive.position,
    force = locomotive.force,
    create_build_effect_smoke = false
  })
  if driver then
    driver.destructible = false
    locomotive.set_driver(driver)
    gang.driver = driver
  end
end

local function unseat_gang_driver(gang)
  if gang.driver and gang.driver.valid then
    gang.driver.destroy()
  end
  gang.driver = nil
end

local function stop_gang_train(gang, train)
  train.manual_mode = true
  remove_temporary_records(train)
  unseat_gang_driver(gang)
end

local function recall_gang(gang)
  gang.state = "recalling"
  gang.status = "Crew boarding"
  for _, record in pairs(each_gang_record(gang.wagon, "gang_wagon")) do
    record.gang_state = "return"
  end
end

local function start_build(gang, train)
  gang.state = "building"
  gang.build_tick = game.tick
  gang.claims = {}
  gang.skipped = {}
  refresh_gang_ghosts(gang, gang.work_position)
  local wagon = gang.wagon
  local inventory = crew_wagon_inventory(wagon)
  for _, kind in ipairs({"builder", "soldier"}) do
    for _ = 1, inventory.get_item_count(ITEM_NAME_BY_KIND[kind]) do
      local record = deploy_team_mate_from(wagon, inventory, kind, wagon.position)
      if not record then
        break
      end
      record.gang_wagon = wagon
      record.gang_state = "work"
    end
  end
  gang.status = "Building"
end

local function start_advance(gang, train, steps)
  local last = steps[#steps]
  local stop_distance = last.distance - GANG_STOP_SHORT_DISTANCE
  local target = steps[1]
  for index = #steps, 1, -1 do
    if steps[index].distance <= stop_distance then
      target = steps[index]
      break
    end
  end
  remove_temporary_records(train)
  local schedule = train.get_schedule()
  local index = schedule.add_record({
    rail = target.rail,
    temporary = true,
    wait_conditions = {{type = "time", ticks = GANG_STOP_WAIT_TICKS}}
  })
  if not index then
    gang.status = "Couldn't add a stop at the end of the track"
    gang.next_tick = game.tick + GANG_RETRY_TICKS
    return
  end
  seat_gang_driver(gang, train)
  schedule.go_to_station(index)
  train.manual_mode = false
  gang.state = "advancing"
  gang.advance_tick = game.tick
  gang.target_rail = target.rail
  gang.status = "Driving to the end of the track"
end

local function update_advance(gang, train)
  if train.manual_mode then
    -- The player took the controls.
    unseat_gang_driver(gang)
    gang.state = "idle"
    return
  end
  local target = gang.target_rail
  local lead = train.speed >= 0 and train.front_stock or train.back_stock
  local arrived = train.state == defines.train_state.wait_station
    or (train.speed == 0 and target and target.valid and lead
      and distance_squared(lead.position, target.position) <= 64)
  if arrived then
    stop_gang_train(gang, train)
    start_build(gang, train)
    return
  end
  if train.state == defines.train_state.no_path
    or game.tick - (gang.advance_tick or game.tick) > GANG_ADVANCE_TIMEOUT_TICKS then
    stop_gang_train(gang, train)
    gang.state = "idle"
    gang.status = "Couldn't reach the end of the track"
    gang.next_tick = game.tick + GANG_RETRY_TICKS
  end
end

local function update_idle(gang, train)
  if train.speed ~= 0 then
    gang.status = "Waiting for the train to stop"
    return
  end
  recruit_gang_crew(gang)
  local problem = gang_readiness_problem(gang, train)
  if problem then
    gang.status = problem
    return
  end
  local steps = find_track_end(train)
  if not steps then
    gang.status = "Can't find the end of the track ahead"
    gang.next_tick = game.tick + GANG_RETRY_TICKS
    return
  end
  local last = steps[#steps]
  gang.work_position = position_table(last.rail.position)
  gang.claims = {}
  gang.skipped = {}
  refresh_gang_ghosts(gang, gang.work_position)
  if count_open_ghosts(gang, train) == 0 then
    gang.status = #gang.ghosts > 0
      and "Missing items for the ghosts past the end of the track"
      or "Waiting for ghosts past the end of the track"
    return
  end
  if last.distance - GANG_STOP_SHORT_DISTANCE <= GANG_ARRIVE_SLACK then
    start_build(gang, train)
  else
    start_advance(gang, train, steps)
  end
end

local function update_building(gang, train)
  refresh_gang_ghosts(gang, gang.work_position)
  local open = count_open_ghosts(gang, train)
  local members = each_gang_record(gang.wagon, "gang_wagon")
  if open == 0 or #members == 0
    or game.tick - (gang.build_tick or game.tick) > GANG_BUILD_TIMEOUT_TICKS then
    recall_gang(gang)
    return
  end
  gang.status = "Building, " .. open .. " ghosts left"
end

local function update_train_gang(gang)
  local wagon = gang.wagon
  local train = wagon.train
  if not train then
    return
  end
  if not gang.enabled then
    if train.speed == 0 then
      recruit_gang_crew(gang)
    end
    gang.status = "Rail gang off"
    return
  end
  if gang.state == "advancing" then
    update_advance(gang, train)
  elseif gang.state == "building" then
    update_building(gang, train)
  elseif gang.state == "recalling" then
    if #each_gang_record(wagon, "gang_wagon") == 0 then
      gang.state = "idle"
      update_idle(gang, train)
    end
  else
    update_idle(gang, train)
  end
end

function update_train_gangs()
  local registry = get_crew_wagon_registry()
  for unit_number, gang in pairs(registry) do
    if not gang.wagon or not gang.wagon.valid then
      unseat_gang_driver(gang)
      registry[unit_number] = nil
    elseif game.tick >= (gang.next_tick or 0) then
      gang.next_tick = game.tick + GANG_UPDATE_INTERVAL
      get_train_gang(gang.wagon)
      update_train_gang(gang)
    end
  end
end

function set_train_gang_enabled(wagon, enabled)
  local gang = get_train_gang(wagon)
  if not gang or gang.enabled == enabled then
    return
  end
  gang.enabled = enabled
  local train = wagon.train
  if train then
    -- The gang owns the train while it works; off hands it back stopped.
    stop_gang_train(gang, train)
  end
  if enabled then
    gang.state = "idle"
    gang.next_tick = 0
  else
    recall_gang(gang)
    gang.state = "idle"
    gang.status = "Rail gang off"
  end
end

function on_crew_wagon_removed(wagon)
  local registry = storage.not_alone_crew_wagons
  local gang = registry and registry[wagon.unit_number]
  if gang then
    unseat_gang_driver(gang)
    registry[wagon.unit_number] = nil
  end
  for _, field in pairs({"gang_wagon", "gang_join"}) do
    for _, record in pairs(each_gang_record(wagon, field)) do
      record[field] = nil
      record.gang_target = nil
      record.gang_state = nil
      if record.entity.valid then
        stop_team_mate(record)
      end
    end
  end
  if storage.not_alone_docked_team_mates then
    storage.not_alone_docked_team_mates[wagon.unit_number] = nil
  end
end

-- GUI: a panel beside the wagon's own train GUI.
CREW_WAGON_FRAME_NAME = "not-alone-crew-wagon"

function destroy_crew_wagon_gui(player)
  local frame = player.gui.relative[CREW_WAGON_FRAME_NAME]
  if frame then
    frame.destroy()
  end
  if storage.not_alone_crew_wagon_gui_targets then
    storage.not_alone_crew_wagon_gui_targets[player.index] = nil
  end
end

function open_crew_wagon_gui(player, wagon)
  destroy_crew_wagon_gui(player)
  local gang = get_train_gang(wagon)
  if not gang then
    return
  end
  storage.not_alone_crew_wagon_gui_targets = storage.not_alone_crew_wagon_gui_targets or {}
  storage.not_alone_crew_wagon_gui_targets[player.index] = wagon

  local frame = player.gui.relative.add({
    type = "frame",
    name = CREW_WAGON_FRAME_NAME,
    caption = {"entity-name.not-alone-crew-wagon"},
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.train_gui,
      position = defines.relative_gui_position.right
    }
  })
  local content = frame.add({
    type = "frame",
    name = "content",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical"
  })
  content.add({
    type = "checkbox",
    name = "not-alone-gang-enabled",
    caption = "Rail gang",
    state = gang.enabled == true,
    tooltip = "Drive to the end of the track, build the rail ghosts ahead from this train's cargo, then move up and repeat."
  })
  content.add({type = "label", name = "status", caption = gang.status})
  content.add({type = "label", caption = "Crew requests", style = "caption_label"})
  local rows = content.add({type = "table", name = "requests", column_count = 3})
  for _, kind in ipairs(GANG_KINDS) do
    rows.add({type = "sprite", sprite = "item/" .. ITEM_NAME_BY_KIND[kind], tooltip = KIND_LABEL[kind]})
    rows.add({type = "label", caption = KIND_LABEL[kind]})
    local field = rows.add({
      type = "textfield",
      name = "not-alone-gang-request-" .. kind,
      text = tostring(gang.requests[kind] or 0),
      numeric = true,
      allow_decimal = false,
      allow_negative = false
    })
    field.style.width = 60
  end
end

local function crew_wagon_gui_target(player)
  local targets = storage.not_alone_crew_wagon_gui_targets
  local wagon = targets and targets[player.index]
  return wagon and wagon.valid and wagon or nil
end

function update_crew_wagon_gui(player)
  local frame = player.gui.relative[CREW_WAGON_FRAME_NAME]
  if not frame then
    return
  end
  local gang = get_train_gang(crew_wagon_gui_target(player))
  if not gang then
    destroy_crew_wagon_gui(player)
    return
  end
  frame.content.status.caption = gang.status
end

-- Returns true when the element belonged to the Crew wagon panel.
function on_crew_wagon_gui_changed(player, element)
  local gang = get_train_gang(crew_wagon_gui_target(player))
  if not gang then
    return false
  end
  if element.name == "not-alone-gang-enabled" then
    set_train_gang_enabled(gang.wagon, element.state)
    update_crew_wagon_gui(player)
    return true
  end
  local kind = element.name:match("^not%-alone%-gang%-request%-(.+)$")
  if kind and ITEM_NAME_BY_KIND[kind] then
    gang.requests[kind] = math.max(0, math.floor(tonumber(element.text) or 0))
    return true
  end
  return false
end
