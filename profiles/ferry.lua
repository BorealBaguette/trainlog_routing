api_version = 4

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")

function setup()
  local ferry_speed = 30  -- ferry speed in km/h
  local connector_speed = 5  -- km/h, port transfers added by scripts/connect_ferries.py
  return {
    properties = {
      weight_name                   = 'duration',
      max_speed_for_map_matching    = 120/3.6,  -- kmph -> m/s
      call_tagless_node_function    = false,
      use_turn_restrictions         = false,
      -- Ferries reverse at ports: don't force the route to sail past a via
      -- waypoint looking for somewhere to turn around
      continue_straight_at_waypoint = false,
    },

    default_mode            = mode.ferry,
    default_speed           = ferry_speed,
    connector_speed         = connector_speed,
    oneway_handling         = 'ignore',  -- allow traversal in both directions

    -- Only allow ways tagged as ferry route
    access_tag_whitelist = Set {
      'ferry'
    },

    speeds = Sequence {
      route = {
        ferry = ferry_speed,
      }
    },
  }
end

function process_node(profile, node, result)
  -- empty, ferry routes are mainly defined by ways, not nodes
end

function process_way(profile, way, result)
  -- only consider ways tagged with 'route=ferry'
  local is_ferry = way:get_value_by_key('route')
  if is_ferry == 'ferry' then
    result.forward_mode = mode.ferry
    result.backward_mode = mode.ferry
    local speed = profile.default_speed
    if way:get_value_by_key('trainlog:connector') == 'yes' then
      speed = profile.connector_speed
    end
    result.forward_speed = speed
    result.backward_speed = speed
  else
    -- If it's not a ferry, simply return without setting any mode or speed
    return
  end
end

return {
  setup = setup,
  process_way =  process_way,
  process_node = process_node,
}
