-- Functional area extracted from not-alone.lua.

-- Every soldier polling the whole network multiplied identical spatial
-- queries by the soldier count; one cached scan per surface+force serves all.
-- Damage events invalidate the cache so combat response stays immediate.
function get_network_threats(surface, force)
  storage.not_alone_threat_scans = storage.not_alone_threat_scans or {}
  local key = surface.index .. ":" .. force.name
  local entry = storage.not_alone_threat_scans[key]
  if entry and game.tick < entry.expires then
    return entry
  end
  entry = {
    units = {},
    bases = {},
    expires = game.tick + THREAT_SCAN_INTERVAL
  }
  storage.not_alone_threat_scans[key] = entry

  local hostile_forces = {}
  for _, other_force in pairs(game.forces) do
    if other_force ~= force
      and other_force.name ~= "enemy"
      and other_force.name ~= "neutral"
      and not force.get_friend(other_force)
      and not force.get_cease_fire(other_force)
      and not other_force.get_cease_fire(force) then
      hostile_forces[#hostile_forces + 1] = other_force
    end
  end

  local seen = {}
  local function consider(list, target)
    if target.valid then
      local id = target.unit_number or target
      if not seen[id] then
        seen[id] = true
        list[#list + 1] = target
      end
    end
  end

  for _, network in pairs(force.logistic_networks[surface.name] or {}) do
    for _, cell in pairs(network.cells) do
      if cell.valid and cell.owner.valid then
        -- Pad past the network edge: worms out-range the boundary and would
        -- otherwise shell the base from just outside the scan.
        local radius = math.max(cell.logistic_radius, cell.construction_radius)
        if radius > 0 then
          radius = radius + ENGAGEMENT_RADIUS
          for _, enemy in pairs(surface.find_enemy_units(cell.owner.position, radius, force)) do
            consider(entry.units, enemy)
          end
          -- find_enemy_units excludes player characters. Scan only hostile
          -- player forces so PvP combat stays a bounded search.
          for _, other_force in ipairs(hostile_forces) do
            for _, target in pairs(surface.find_entities_filtered({
              position = cell.owner.position,
              radius = radius,
              force = other_force,
              type = {"character", "unit"}
            })) do
              consider(entry.units, target)
            end
          end
          for _, base in pairs(surface.find_entities_filtered({
            position = cell.owner.position,
            radius = radius,
            force = "enemy",
            type = {"unit-spawner", "turret"}
          })) do
            consider(entry.bases, base)
          end
        end
      end
    end
  end
  return entry
end

function invalidate_network_threats(surface, force)
  local scans = storage.not_alone_threat_scans
  if scans then
    scans[surface.index .. ":" .. force.name] = nil
  end
end

function find_soldier_target(record, surface, force, position)
  local team_mate = record.entity
  surface = surface or team_mate.surface
  force = force or team_mate.force
  position = position or position_table(team_mate.position)
  local threats = get_network_threats(surface, force)

  local nearest_enemy
  local nearest_distance
  local function consider(target)
    if target.valid then
      local current_distance = distance_squared(position, target.position)
      if not nearest_distance or current_distance < nearest_distance then
        nearest_enemy = target
        nearest_distance = current_distance
      end
    end
  end

  for _, target in ipairs(threats.units) do
    consider(target)
  end
  -- Clear the covered enemy units first; then target spawners, turrets, and
  -- worms (worms are turret-type entities) as enemy bases.
  if not nearest_enemy then
    for _, target in ipairs(threats.bases) do
      consider(target)
    end
  end
  return nearest_enemy
end

function find_soldier_immediate_target(record)
  local entity = record.entity
  local surface = entity.surface
  local force = entity.force
  local position = position_table(entity.position)
  local nearest_target
  local nearest_distance

  local function consider(target)
    if target and target.valid then
      local distance = distance_squared(position, target.position)
      if distance <= ENGAGEMENT_RADIUS * ENGAGEMENT_RADIUS
        and (not nearest_distance or distance < nearest_distance) then
        nearest_target = target
        nearest_distance = distance
      end
    end
  end

  consider(surface.find_nearest_enemy({
    position = position,
    max_distance = ENGAGEMENT_RADIUS,
    force = force
  }))

  for _, other_force in pairs(game.forces) do
    if other_force ~= force
      and other_force.name ~= "enemy"
      and other_force.name ~= "neutral"
      and not force.get_friend(other_force)
      and not force.get_cease_fire(other_force)
      and not other_force.get_cease_fire(force) then
      for _, target in pairs(surface.find_entities_filtered({
        position = position,
        radius = ENGAGEMENT_RADIUS,
        force = other_force,
        type = {"character", "unit", "turret", "unit-spawner"}
      })) do
        consider(target)
      end
    end
  end
  return nearest_target
end

function attack_with_team_mate(record, enemy)
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
    -- Fight back when bodyblocked or bitten on the way to a distant target;
    -- ignoring all distractions froze whole squads mid-march.
    distraction = defines.distraction.by_enemy
  })
  record.command_kind = "attack"
  record.command_destination = nil
  record.command_target = enemy
end

function get_soldier_ammo_count(record, weapon)
  local total = 0
  for _, ammo_name in pairs(weapon.ammo) do
    total = total + ((record.soldier_ammo and record.soldier_ammo[ammo_name]) or 0)
  end
  return total
end

-- Best owned weapon that still has ammo; nil means fall back to fists.
function select_soldier_weapon(record)
  for rank = #SOLDIER_WEAPONS, 1, -1 do
    local weapon = SOLDIER_WEAPONS[rank]
    if record.soldier_weapons and record.soldier_weapons[weapon.kind]
      and get_soldier_ammo_count(record, weapon) > 0 then
      return weapon
    end
  end
  return nil
end

function consume_soldier_ammo(record, weapon)
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
function replace_team_mate_entity(record, wanted)
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
  local old_unit_number = old_entity.unit_number
  destroy_color_marker(record)
  destroy_inventory_renderings(record)
  old_entity.destroy()
  if tag then
    replacement.name_tag = tag
  end
  replacement.health = math.min(health, replacement.max_health)
  record.entity = replacement
  -- Keep the team mate selected across the swap: pruning goes by unit number.
  for _, selected in pairs(storage.not_alone_selected_team_mates or {}) do
    if selected[old_unit_number] then
      selected[old_unit_number] = nil
      selected[replacement.unit_number] = true
    end
  end
  record.command_kind = nil
  record.command_destination = nil
  record.command_target = nil
  return true
end

-- Swap the unit prototype to match the weapon in hand (nil means fists).
-- Mech-armored Soldiers use the hovering "-mech" twin of each variant.
function ensure_soldier_entity(record, weapon)
  local wanted = weapon and weapon.entity or SOLDIER_FISTS_ENTITY
  local armor = record.soldier_armor and SOLDIER_ARMORS[record.soldier_armor]
  if armor and armor.flying and prototypes.entity[wanted .. "-mech"] then
    wanted = wanted .. "-mech"
  else
    local suffix = record.soldier_armor
      and SOLDIER_ARMOR_ENTITY_SUFFIX[record.soldier_armor]
    if suffix and prototypes.entity[wanted .. suffix] then
      wanted = wanted .. suffix
    end
  end
  return replace_team_mate_entity(record, wanted)
end

-- Best owned weapon's ammo first, then that weapon's best ammo tier.
-- only_empty restricts the search to weapons with dry ammo pools so
-- preparation cannot loop on topping up an already stocked weapon.
