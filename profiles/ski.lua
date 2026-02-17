api_version = 4

function setup()
  return {
    default_speed = 10
  }
end

function process_way(profile, way, result, relations)
    local difficulty = way:get_value_by_key("piste:difficulty")
    local grooming = way:get_value_by_key("piste:grooming")

    result.forward_speed = profile.default_speed
    result.backward_speed = profile.default_speed / 10
    result.forward_rate = profile.default_speed
    result.backward_rate = profile.default_speed / 10
    result.forward_mode = mode.walking
    result.backward_mode = mode.walking

    if difficulty == "freeride" or grooming == "backcountry" then
        result.forward_rate = result.forward_rate / 5
        result.backward_rate = result.backward_rate / 5
    end
end

return {
    setup = setup,
    process_way = process_way
}