notalone = {}

local constants = require("lib/constants")
local utils = require("lib/utils")

for name, value in pairs(constants) do
  _G[name] = value
end
for name, value in pairs(utils) do
  _G[name] = value
end

INITIAL_HABITAT_COUNT = 1
INITIAL_COUNT_BY_KIND = {miner = 7, builder = 3, soldier = 7, carrier = 10}
STARTER_INVENTORY_VERSION = 5
UPDATE_INTERVAL = 10
-- Idle units and empty habitats re-scan the whole network for work; doing
-- that every update dominated frame time, so retries run on cooldowns.
IDLE_JOB_SEARCH_INTERVAL = 60
-- Work arrives sporadically (new ghosts, new requests), so a single failed
-- search no longer sends a team mate home; only a sustained drought does,
-- avoiding needless dock/undeploy/redeploy churn between short job gaps.
IDLE_DOCK_AFTER_FAILURES = 5
HABITAT_DEPLOY_RETRY_INTERVAL = 120
BUILDING_REQUESTER_UPDATE_INTERVAL = 60
ORPHAN_RECONCILE_INTERVAL = 600
ENGAGEMENT_RADIUS = 16
COMMAND_REFRESH_DISTANCE = 2
CHUNK_SIZE = 32
SCOUT_WAYPOINT_DISTANCE = 64
SCOUT_GENERATION_RADIUS = 2
MINER_CAPACITY = 50
MINER_ORE_STOPPING_DISTANCE = 0.2
CARRIER_CAPACITY = 50
RESOURCE_MINING_TIME = 1
NORMAL_CHARACTER_MINING_SPEED = 0.5
LOGISTICS_SEARCH_RADIUS = 128
BUILDER_CARGO_SLOTS = 1
MAX_BUILDER_CARGO_SLOTS = 65535
FUEL_REQUEST_COUNT = 5
INGREDIENT_REQUEST_COUNT = 10
BUILDING_REQUEST_SLOT_COUNT = 20
BUILDER_ITEM_PICKUP_DISTANCE = 0.5
BUILDER_TARGET_CLEARANCE = 0.4
-- Must exceed the 0.2 stopping distance used when stepping out of a ghost's
-- footprint; otherwise the escape point can land within arrival range of an
-- already-close position, so move_team_mate no-ops and the builder never
-- actually moves (seen wedged between adjacent belt ghosts).
BUILDER_GHOST_ESCAPE_DISTANCE = 1
-- Must exceed clearance plus the 0.2 move stopping distance or arrivals stall.
BUILDER_TARGET_INTERACTION_DISTANCE = 0.7
REPAIR_PACK_ITEM_NAME = "repair-pack"
MINING_ANIMATION_FRAMES = 51
MINING_ANIMATION_SPEED = 51 / 60
HIDDEN_TEAM_MATE_NAME = "not-alone-team-mate-hidden"
ROUTE_COLOR = {r = 0.2, g = 0.7, b = 1, a = 0.9}
MARK_COLOR = {r = 1, g = 0.6, b = 0, a = 0.9}
INVENTORY_ICON_SCALE = 0.5
INVENTORY_ICON_SPACING = 0.65
TEAM_MATE_NAME = "not-alone-team-mate"
TEAM_MATE_ENTITY_BY_KIND = {
  miner = "not-alone-team-mate-miner",
  builder = "not-alone-team-mate-builder",
  carrier = "not-alone-team-mate-carrier",
  soldier = "not-alone-team-mate-fists"
}
KIND_BY_ENTITY_NAME = {
  ["not-alone-team-mate-miner"] = "miner",
  ["not-alone-team-mate-builder"] = "builder",
  ["not-alone-team-mate-carrier"] = "carrier",
  ["not-alone-team-mate-fists"] = "soldier",
  ["not-alone-team-mate-smg"] = "soldier",
  ["not-alone-team-mate-shotgun"] = "soldier",
  ["not-alone-team-mate-combat-shotgun"] = "soldier",
  ["not-alone-team-mate-flamethrower"] = "soldier",
  ["not-alone-team-mate-rocket"] = "soldier",
  ["not-alone-team-mate-fists-mech"] = "soldier",
  ["not-alone-team-mate-smg-mech"] = "soldier",
  ["not-alone-team-mate-shotgun-mech"] = "soldier",
  ["not-alone-team-mate-combat-shotgun-mech"] = "soldier",
  ["not-alone-team-mate-flamethrower-mech"] = "soldier",
  ["not-alone-team-mate-rocket-mech"] = "soldier"
}
for _, entity_name in pairs({
  "not-alone-team-mate-fists",
  "not-alone-team-mate-smg",
  "not-alone-team-mate-shotgun",
  "not-alone-team-mate-combat-shotgun",
  "not-alone-team-mate-flamethrower",
  "not-alone-team-mate-rocket"
}) do
  KIND_BY_ENTITY_NAME[entity_name .. "-armor-heavy"] = "soldier"
  KIND_BY_ENTITY_NAME[entity_name .. "-armor-power"] = "soldier"
end
TEAM_MATE_NAMES = {TEAM_MATE_NAME}
for entity_name in pairs(KIND_BY_ENTITY_NAME) do
  -- Mech variants only exist when Space Age provides mech armor.
  if prototypes.entity[entity_name] then
    TEAM_MATE_NAMES[#TEAM_MATE_NAMES + 1] = entity_name
  end
end
COMMAND_TOOL_NAME = "not-alone-command-tool"
LOGISTICS_HUB_NAME = "not-alone-logistics-hub"
BUILDING_REQUESTER_NAME = "not-alone-building-logistics-requester"
BUILDING_REQUESTER_PREFIX = BUILDING_REQUESTER_NAME .. "-"
ITEM_NAME_BY_KIND = {
  miner = "not-alone-miner",
  builder = "not-alone-builder",
  soldier = "not-alone-soldier",
  carrier = "not-alone-carrier"
}
TEAM_MATE_KINDS = {"miner", "builder", "soldier", "carrier"}
KIND_LABEL = {miner = "Miner", builder = "Builder", soldier = "Soldier", carrier = "Carrier"}
KIND_BY_LABEL = {Miner = "miner", Builder = "builder", Soldier = "soldier", Carrier = "carrier"}
-- Division colors borrowed from classic sci-fi uniforms: engineering gold for
-- Builders, command red for Soldiers, sciences blue for Carriers, and a
-- hazard-suit orange for Miners (mining/EVA suits across many settings).
KIND_COLOR = {
  miner = {r = 0.92, g = 0.42, b = 0.04},
  builder = {r = 0.87, g = 0.72, b = 0.2},
  soldier = {r = 0.72, g = 0.08, b = 0.08},
  carrier = {r = 0.2, g = 0.55, b = 0.85}
}
-- Soldier arsenal, ordered worst to best. Soldiers fight with the best owned
-- weapon that still has ammo, and restock the best ammo tier listed first.
-- Soldiers collect the vanilla gun item directly from logistics storage.
SOLDIER_WEAPONS = {
  {
    kind = "smg",
    gun = "submachine-gun",
    entity = "not-alone-team-mate-smg",
    ammo = {"uranium-rounds-magazine", "piercing-rounds-magazine", "firearm-magazine"}
  },
  {
    kind = "shotgun",
    gun = "shotgun",
    entity = "not-alone-team-mate-shotgun",
    ammo = {"piercing-shotgun-shell", "shotgun-shell"}
  },
  {
    kind = "combat-shotgun",
    gun = "combat-shotgun",
    entity = "not-alone-team-mate-combat-shotgun",
    ammo = {"piercing-shotgun-shell", "shotgun-shell"}
  },
  {
    kind = "flamethrower",
    gun = "flamethrower",
    entity = "not-alone-team-mate-flamethrower",
    ammo = {"flamethrower-ammo"}
  },
  {
    kind = "rocket",
    gun = "rocket-launcher",
    entity = "not-alone-team-mate-rocket",
    ammo = {"explosive-rocket", "rocket"}
  }
}
SOLDIER_WEAPON_BY_KIND = {}
for _, weapon in pairs(SOLDIER_WEAPONS) do
  SOLDIER_WEAPON_BY_KIND[weapon.kind] = weapon
end
SOLDIER_FISTS_ENTITY = "not-alone-team-mate-fists"
SOLDIER_AMMO_RESTOCK_COUNT = 20
SOLDIER_AMMO_TICKS_PER_ROUND = 30
-- Armor tiers, worst to best; a Soldier wears the best suit it has found and
-- shrugs off that fraction of every hit.
SOLDIER_ARMORS = {
  {item = "light-armor", mitigation = 0.2},
  {item = "heavy-armor", mitigation = 0.4},
  {item = "modular-armor", mitigation = 0.5},
  {item = "power-armor", mitigation = 0.65},
  {item = "power-armor-mk2", mitigation = 0.8},
  {item = "mech-armor", mitigation = 0.9, flying = true}
}
SOLDIER_ARMOR_ENTITY_SUFFIX = {
  [2] = "-armor-heavy",
  [3] = "-armor-heavy",
  [4] = "-armor-power",
  [5] = "-armor-power"
}
-- Other crews crashed here too: derelict ships seeded from the map seed and
-- distributed by a rate derived from the opening charted area.
CRASH_SHIP_NAME = "crash-site-spaceship"
CRASH_SHIP_MAX_CREW = 10
CRASH_SHIP_VISIBLE_RADIUS_MULTIPLIER = 5
CRASH_SHIP_LOCAL_TARGET = 3
FURNACE_ENTITY_NAMES = {
  ["stone-furnace"] = true,
  ["steel-furnace"] = true,
  ["electric-furnace"] = true
}
FURNACE_ENTITY_NAME_LIST = {"stone-furnace", "steel-furnace", "electric-furnace"}
LOGISTICS_SOURCE_MODES = {

  ["active-provider"] = true,
  ["passive-provider"] = true,
  ["storage"] = true,
  ["buffer"] = true
}
LOGISTICS_DESTINATION_TYPES = {
  "assembling-machine",
  "boiler",
  "burner-generator",
  "furnace",
  "lab",
  "rocket-silo"
}
RECIPE_ENTITY_TYPES = {
  ["assembling-machine"] = true,
  ["furnace"] = true,
  ["rocket-silo"] = true
}
dock_at_habitat = nil
stop_team_mate = nil
move_team_mate = nil
update_mining_animation = nil
require("lib/ui")
require("lib/vehicle")
require("lib/logistics")
require("lib/logistics_sources")
require("lib/mining")
require("lib/movement")
require("lib/soldier_target")
require("lib/soldier")
require("lib/builder_planning")
require("lib/builder_targets")
require("lib/builder_cargo")
require("lib/builder")
require("lib/crew")
require("lib/carrier")
require("lib/lifecycle")
require("lib/lifecycle_events")
require("lib/lifecycle_handlers")
update_vehicle_travel = nil

function distance_squared(first, second)
  local delta_x = first.x - second.x
  local delta_y = first.y - second.y
  return delta_x * delta_x + delta_y * delta_y
end

function distance_squared_to_box(position, box)
  local delta_x = math.max(box.left_top.x - position.x, 0, position.x - box.right_bottom.x)
  local delta_y = math.max(box.left_top.y - position.y, 0, position.y - box.right_bottom.y)
  return delta_x * delta_x + delta_y * delta_y
end

function position_table(position)
  return {x = position.x, y = position.y}
end

function create_mining_particles(surface, position, particle_name)
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

function get_habitat_inventory(habitat)
  return habitat and habitat.valid
    and habitat.get_inventory(defines.inventory.roboport_material)
    or nil
end

-- Whole-surface habitat scans dominated update time; track Habitats in a
-- registry maintained by build/remove events instead (lazy-built for old saves).
function get_habitat_registry()
  local registry = storage.not_alone_habitats
  if not registry then
    registry = {}
    for _, surface in pairs(game.surfaces) do
      for _, habitat in pairs(surface.find_entities_filtered({name = LOGISTICS_HUB_NAME})) do
        if habitat.unit_number then
          registry[habitat.unit_number] = habitat
        end
      end
    end
    storage.not_alone_habitats = registry
  end
  return registry
end

function each_habitat()
  local registry = get_habitat_registry()
  local key, habitat
  return function()
    repeat
      key, habitat = next(registry, key)
      if habitat and not habitat.valid then
        registry[key] = nil
        habitat = nil
      end
    until key == nil or habitat
    return habitat
  end
end

-- Docked team mates are real items in the Habitat's material inventory, so
-- they count as genuine network storage. Older builds briefly tracked them
-- as script-side crew records; convert any such records back into items.

return notalone
