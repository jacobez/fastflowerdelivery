ruleset driver_base {
    meta {
        use module driver_model alias model
    }

    global {
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

        needs_request = function(peer, messageID) {
            model:peers_seen().get([messageID, peer{"driverID"}])
        }

        extract_message_num = function(messageID) {
            messageID.split(re#:#)[1]
        }
    }

    rule place_bid {
        select when driver delivery_requested

        pre {
            host = event:attr("host")
            eci = event:attr("eci")
            messageID = event:attr("messageID")
            order = event:attr("order")

            eid = random:word()
            available = available()
            message_num = extract_message_num(messageID)
            bidID = meta:picoId + ":" + message_num
        }

        if available then
            event:send({
                "eci": eci,
                "eid": eid,
                "domain": "flower_shop",
                "type": "bid_received",
                "attrs": {
                    "bid": {
                        "id": bidID,
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
            ent:messages := messages().put([messageID], {
                "host": host,
                "eci": eci,
                "order": order
            })
        }
    }

    rule report_seen {
        select when driver delivery_requested

        pre {
            messageID = event:attr("messageID")
        }

        event:send({
            "domain": "driver",
            "type": "delivery_request_seen",
            "attrs": {
                "driverID": meta:picoId,
                "messageID": messageID
            }
        })
    }

    rule propogate_delivery_request {
        select when driver delivery_requested
            foreach model:peers() setting(peer)

        pre {
            attributes = event:attrs

            should_send = needs_request(peer)
        }

        if should_send then
            event:send({
                "domain": "driver",
                "type": "delivery_requested",
                "attrs": attributes
            })
    }

    rule handle_seen {
        select when driver delivery_request_seen

        pre {
            driverID = event:attr("driverID")
            messageID = event:attr("messageID")
        }

        always {
            raise driver event "peers_seen_reported" attributes {
                "report": {
                    "driverID": driverID,
                    "messageID": messageID
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

        always {
            ent:available := true
        }
    }
}