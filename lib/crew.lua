-- Functional area extracted from not-alone.lua.

function create_team_mate(player, kind, index, spawn_center)
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

function find_any_player_for_force(force)
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
function reconcile_orphaned_team_mates()
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
