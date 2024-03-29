ruleset driver_model {
    meta {
        use module io.picolabs.subscription alias subscription
        provides location, peers, peers_seen, name, ranking
        shares __testing, peers_seen, peers
    }

    global {
      __testing = { "queries":
      [ { "name": "__testing" },
      { "name": "peers_seen" },
      { "name": "peers" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ 
       { "domain": "driver", "type": "initialize", "attrs": [ "name", "location"] },
       { "domain": "driver", "type": "reset_driver" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }
    
        location = function() {
            ent:location
        }

        peers = function() {
            subscription:established().filter(function(subscription) {
                subscription{"Tx_role"} == "driver"
            })
        }

        peers_seen = function() {
            ent:peers_seen.defaultsTo({})
        }

        updated_peers_seen = function(report) {
            peers_seen().put([report{"message_id"}, report{"driver_id"}], true)
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
    
    rule reset_driver {
      select when driver reset_driver
      fired {
        ent:peers_seen := {};
      }
    }
}