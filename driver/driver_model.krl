ruleset driver_model {
    meta {
        provides location
    }

    global {
        location = function() {
            ent:location
        }
    }
}