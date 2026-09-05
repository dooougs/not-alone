local constants = {}

constants.INITIAL_HABITAT_COUNT = 1
constants.INITIAL_COUNT_BY_KIND = {miner = 7, builder = 3, soldier = 7, carrier = 10}
constants.STARTER_INVENTORY_VERSION = 5
constants.UPDATE_INTERVAL = 10
constants.IDLE_JOB_SEARCH_INTERVAL = 60
constants.IDLE_DOCK_AFTER_FAILURES = 5
constants.HABITAT_DEPLOY_RETRY_INTERVAL = 120
constants.BUILDING_REQUESTER_UPDATE_INTERVAL = 60
constants.ORPHAN_RECONCILE_INTERVAL = 600
constants.ENGAGEMENT_RADIUS = 16
constants.COMMAND_REFRESH_DISTANCE = 2
constants.CHUNK_SIZE = 32
constants.SCOUT_WAYPOINT_DISTANCE = 64
constants.SCOUT_GENERATION_RADIUS = 2
constants.CAR_MINIMUM_DISTANCE = 80
constants.CAR_DEPLOYMENT_SEARCH_RADIUS = 20
constants.CAR_ARRIVAL_RADIUS = 8
constants.CAR_STUCK_TICKS = 120
constants.CAR_PATH_LOOKAHEAD = 4
constants.CAR_ITEM_NAME = "car"
constants.CAR_ENTITY_NAME = "car"
constants.CAR_DRIVER_NAME = "not-alone-vehicle-driver"
constants.MINER_CAPACITY = 50
constants.MINER_ORE_STOPPING_DISTANCE = 0.2
constants.CARRIER_CAPACITY = 50
constants.RESOURCE_MINING_TIME = 1
constants.NORMAL_CHARACTER_MINING_SPEED = 0.5
constants.LOGISTICS_SEARCH_RADIUS = 128
constants.BUILDER_CARGO_SLOTS = 1
constants.MAX_BUILDER_CARGO_SLOTS = 65535
constants.FUEL_REQUEST_COUNT = 5
constants.INGREDIENT_REQUEST_COUNT = 10
constants.BUILDING_REQUEST_SLOT_COUNT = 20
constants.BUILDER_ITEM_PICKUP_DISTANCE = 0.5
constants.BUILDER_TARGET_CLEARANCE = 0.4
constants.BUILDER_GHOST_ESCAPE_DISTANCE = 1
constants.BUILDER_TARGET_INTERACTION_DISTANCE = 0.7
constants.REPAIR_PACK_ITEM_NAME = "repair-pack"
constants.MINING_ANIMATION_FRAMES = 51
constants.MINING_ANIMATION_SPEED = 51 / 60
constants.HIDDEN_TEAM_MATE_NAME = "not-alone-team-mate-hidden"
constants.ROUTE_COLOR = {r = 0.2, g = 0.7, b = 1, a = 0.9}
constants.MARK_COLOR = {r = 1, g = 0.6, b = 0, a = 0.9}
constants.INVENTORY_ICON_SCALE = 0.5
constants.INVENTORY_ICON_SPACING = 0.65
constants.TEAM_MATE_NAME = "not-alone-team-mate"
constants.TEAM_MATE_ENTITY_BY_KIND = {
  miner = "not-alone-team-mate-miner",
  builder = "not-alone-team-mate-builder",
  carrier = "not-alone-team-mate-carrier",
  soldier = "not-alone-team-mate-fists"
}
constants.KIND_BY_ENTITY_NAME = {
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
constants.TEAM_MATE_NAMES = {constants.TEAM_MATE_NAME}
constants.COMMAND_TOOL_NAME = "not-alone-command-tool"
constants.LOGISTICS_HUB_NAME = "not-alone-logistics-hub"
constants.BUILDING_REQUESTER_NAME = "not-alone-building-logistics-requester"
constants.BUILDING_REQUESTER_PREFIX = constants.BUILDING_REQUESTER_NAME .. "-"
constants.ITEM_NAME_BY_KIND = {
  miner = "not-alone-miner",
  builder = "not-alone-builder",
  soldier = "not-alone-soldier",
  carrier = "not-alone-carrier"
}
constants.TEAM_MATE_KINDS = {"miner", "builder", "soldier", "carrier"}
constants.KIND_LABEL = {miner = "Miner", builder = "Builder", soldier = "Soldier", carrier = "Carrier"}
constants.KIND_BY_LABEL = {Miner = "miner", Builder = "builder", Soldier = "soldier", Carrier = "carrier"}
constants.KIND_COLOR = {
  miner = {r = 0.92, g = 0.42, b = 0.04},
  builder = {r = 0.87, g = 0.72, b = 0.2},
  soldier = {r = 0.72, g = 0.08, b = 0.08},
  carrier = {r = 0.2, g = 0.55, b = 0.85}
}
constants.SOLDIER_WEAPONS = {
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
constants.SOLDIER_FISTS_ENTITY = "not-alone-team-mate-fists"
constants.SOLDIER_AMMO_RESTOCK_COUNT = 20
constants.SOLDIER_AMMO_TICKS_PER_ROUND = 30
constants.SOLDIER_ARMORS = {
  {item = "light-armor", mitigation = 0.2},
  {item = "heavy-armor", mitigation = 0.4},
  {item = "modular-armor", mitigation = 0.5},
  {item = "power-armor", mitigation = 0.65},
  {item = "power-armor-mk2", mitigation = 0.8},
  {item = "mech-armor", mitigation = 0.9, flying = true}
}
constants.SOLDIER_ARMOR_ENTITY_SUFFIX = {
  [2] = "-armor-heavy",
  [3] = "-armor-heavy",
  [4] = "-armor-power",
  [5] = "-armor-power"
}
constants.CRASH_SHIP_NAME = "crash-site-spaceship"
constants.CRASH_SHIP_MAX_CREW = 10
constants.CRASH_SHIP_VISIBLE_RADIUS_MULTIPLIER = 5
constants.CRASH_SHIP_LOCAL_TARGET = 3
constants.FURNACE_ENTITY_NAMES = {
  ["stone-furnace"] = true,
  ["steel-furnace"] = true,
  ["electric-furnace"] = true
}
constants.FURNACE_ENTITY_NAME_LIST = {"stone-furnace", "steel-furnace", "electric-furnace"}
constants.LOGISTICS_SOURCE_MODES = {
  ["active-provider"] = true,
  ["passive-provider"] = true,
  ["storage"] = true,
  ["buffer"] = true
}
constants.LOGISTICS_DESTINATION_TYPES = {
  "assembling-machine",
  "boiler",
  "burner-generator",
  "furnace",
  "lab",
  "rocket-silo"
}
constants.RECIPE_ENTITY_TYPES = {
  ["assembling-machine"] = true,
  ["furnace"] = true,
  ["rocket-silo"] = true
}

return constants
