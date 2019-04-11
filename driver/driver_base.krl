ruleset driver_base {
    meta {
        use module driver_model alias model
        use module distance_matrix
    }

    rule place_bid {
        select when bid requested
    }

    rule confirm_bid {
        select when bid accepted
    }

    rule confirm_delivery {
        select when delivery completed
    }
}