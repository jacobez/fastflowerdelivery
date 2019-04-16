ruleset driver_base {
    meta {
      shares __testing, available
        use module driver_model alias model
    }

    global {
       __testing = { "queries":
      [ { "name": "__testing" },
      { "name": "available" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ 
        { "domain": "driver", "type": "reset_driver" },
        { "domain": "driver", "type": "delivery_confirmed" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }
        //
        // MODEL
        //

        available = function() {
            ent:available.defaultsTo(true)
        }

        messages = function() {
            ent:messages.defaultsTo({})
        }

        //
        // HELPERS
        //

        needs_request = function(peer, message_id) {
            has_seen = model:peers_seen().get([message_id, peer{"Tx"}]).as("Boolean");
            not has_seen;
        }

        extract_message_num = function(message_id) {
            message_id.split(re#:#)[1]
        }
    }

    rule place_bid {
        select when driver delivery_requested

        pre {
            host = event:attr("host")
            eci = event:attr("eci")
            message_id = event:attr("message_id")
            order = event:attr("order")

            eid = random:word()
            available = available()
            message_num = extract_message_num(message_id)
            bid_id = meta:picoId + ":" + message_num
        }

        if available then
            event:send({
                "eci": eci,
                "eid": eid,
                "domain": "flower_shop",
                "type": "bid_received",
                "attrs": {
                    "bid": {
                        "id": bid_id,
                        "driver": {
                            "name": model:name(),
                            "location": model:location(),
                            "host": meta:host,
                            "eci": meta:eci,
                            "ranking": model:ranking()
                        }
                    }
                }
            }, host)
        
        always {
            ent:messages := messages().put([message_id], {
                "host": host,
                "eci": eci,
                "order": order
            })
        }
    }

    rule report_seen {
        select when driver delivery_requested
            foreach model:peers() setting(peer)

        pre {
            message_id = event:attr("message_id")
            tx_host = peer{"Tx_host"}
        }

        event:send({
            "eci": peer{"Tx"},
            "eid": random:word(),
            "domain": "driver",
            "type": "delivery_request_seen",
            "attrs": {
                "tx": peer{"Rx"},
                "message_id": message_id
            }
        }, tx_host)
    }

    rule propogate_delivery_request {
        select when driver delivery_requested
            foreach model:peers() setting(peer)

        pre {
            attributes = event:attrs
            tx_host = peer{"Tx_host"}
            should_send = needs_request(peer, attributes{"message_id"})
        }

        if should_send then
            event:send({
                "eci": peer{"Tx"},
                "eid": random:word(),
                "domain": "driver",
                "type": "delivery_requested",
                "attrs": attributes
            }, tx_host)
    }

    rule handle_seen {
        select when driver delivery_request_seen

        pre {
            tx = event:attr("tx")
            message_id = event:attr("message_id")
        }

        always {
            raise driver event "peers_seen_reported" attributes {
                "report": {
                    "tx": tx,
                    "message_id": message_id
                }
            }
        }
    }

    rule confirm_bid {
        select when driver bid_accepted

        pre {
            host = event:attr("host")
            eci = event:attr("eci")
            order = event:attr("order")
            driver = event:attr("driver")

            eid = random:word()
            available = available()
        }

        event:send({
            "eci": eci,
            "eid": eid,
            "domain": "flower_shop",
            "type": "bid_confirmed",
            "attrs": {
              "order":order,
              "driver": driver,
              "confirmed": available
            }
        }, host)

        fired {
            ent:available := false
        }
    }

    rule confirm_deliver {
        select when driver delivery_confirmed

        pre {
            order_id = event:attr("order_id")
            eci = messages(){[order_id]}{"eci"}
            order = messages(){[order_id]}{"order"}
        }

        event:send({
            "eci": eci,
            "eid": random:word(),
            "domain": "flower_shop",
            "type": "delivery_confirmed",
            "attrs": {
                "order": order,
                "driver": {
                    "name": model:name(),
                    "location": model:location(),
                    "host": meta:host,
                    "eci": meta:eci,
                    "ranking": model:ranking()
                }
            }
        })

        always {
            ent:available := true
        }
    }
    
    rule reset_driver {
      select when driver reset_driver
      fired {
        ent:available := true
      }
    }
}