ruleset driver_model {
    meta {
        use module io.picolabs.subscription alias subscription

        provides location, peers, peers_seen
    }

    global {
        location = function() {
            ent:location
        }

        peers = function() {
            subscription:established().filter(function(sub) {
                subscription{"Tx_role"} == "driver"
            })
        }

        peers_seen = function() {
            ent:peers_seen.defaultsTo({})
        }

        updated_peers_seen = function(report) {
            peers_seen().put([report{"messageID"}, report{"driverID"}], true)
        }

        ranking = function() {
            ent:ranking.defaultsTo(50)
        }

        name = function() {
            ent:name
        }
    }

    rule update_peers_seen {
        select when driver peers_seen_reported

        pre {
            report = event:attr("report")
        }

        always {
            ent:peers_seen := updated_peers_seen(report)
        }
    }

    rule update_ranking {
        select when driver delivery_confirmed

        pre {
            late = event:attr("late")
        }

        always {
            ent:ranking := late => ranking() - 1 | ranking() + 1
        }
    }

    rule initialize_model {
        select when driver initialize

        pre {
            name = event:attr("name")
            location = event:attr("location")
        }

        always {
            ent:name := name;
            ent:location := location;
        }
    }
}