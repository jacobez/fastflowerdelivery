ruleset flower_shop {
  meta {
    shares __testing, getAutomaticSelection, getBidsReceived, getOrdersReceived
    use module io.picolabs.subscription alias wrangler_subscription
    use module io.picolabs.lesson_keys
    use module io.picolabs.twilio_v2 alias twilio
          with account_sid = keys:twilio{"account_sid"}
            auth_token =  keys:twilio{"auth_token"}
    use module distance_matrix
          with api_key = keys:google{"google_api"}
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" },
      { "name": "getAutomaticSelection" },
     { "name": "getBidsReceived" },
     { "name": "getOrdersReceived" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ { "domain": "flower_shop", "type": "reset_all" },
      { "domain": "flower_shop", "type": "test_send_order", "attrs": [ "name", "smsNumber", "flowers", "location" ] },
      { "domain": "flower_shop", "type": "send_bid_accepted", "attrs": [ "order", "driver" ] },
       { "domain": "flower_shop", "type": "set_automatic_selection", "attrs": [ "automaticSelection"] },
       { "domain": "flower_shop", "type": "initialize_shop", "attrs": [ "location", "preference"] }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }
    fromSMSNumber = "+13853753036";
    driverRole = "driver"

    getOrdersReceived = function() {
      ent:orders.defaultsTo({});
    }
    
    getBidsReceived = function() {
      ent:bids.defaultsTo({});
    }

    getAutomaticSelection = function() {
      ent:automaticSelection.defaultsTo(true);
    }

    getDriverPreference = function() {
      ent:preference.defaultsTo(0);
    }
    
    getDrivers = function() {
      wrangler_subscription:established().defaultsTo([]).filter(function(subscription) {
        subscription["Tx_role"] == driverRole;
      });
    }

    getViableDrivers = function(order, bidsReceived) {
      shopToCustomerData = distance_matrix:queryDistance([shopLocation()], [order["location"]], unitPreference());
      driverToShopData = distance_matrix:queryDistance(bidsReceived.map(function(bid) { bid["driver"]["location"] }), [shopLocation()], unitPreference());
      bidsReceived.map(function(bid) {
        bid["driver"].put(
          ["distance"],
          driverToShopData["rows"][driverToShopData["origin_addresses"].index(bid["driver"]["location"])]["elements"][0]["distance"]["value"]
          + shopToCustomerData["rows"][0]["elements"][0]["distance"]["value"]
          );
        bid["driver"]
      }).filter(function(value,key){
        value{"ranking"} >= getDriverPreference();
      }).sort(function(driverA, driverB) {driverA{"distance"} <=> driverB{"distance"}})
    }

    shopLocation = function() {
      ent:location.defaultsTo("Orem, Utah")
    }

    unitPreference = function() {
      ent:unitPreference.defaultsTo("imperial")
    }
  }

  rule test_send_order {
    select when flower_shop test_send_order
    fired {
      raise flower_shop event "order_received" attributes {
        "order": {
          "name": event:attr("name"),
          "smsNumber": event:attr("smsNumber"),
          "flowers": event:attr("flowers"),
          "location": event:attr("location"),
          "tx_host": meta:host,
          "deadline": time:add(time:now(), {"minutes": 5})
          }
        };
    }
  }
  rule order_received {
    select when flower_shop order_received
    foreach getDrivers() setting (driver)
    pre {
      tx_host = driver["Tx_host"] != null => Tx_host | meta:host;
      order_id = meta:picoId + ":" + ent:orderID.defaultsTo(0);
    }

    event:send({
      "eci":driver["Tx"],
      "domain":"driver",
      "type":"delivery_requested",
      "attrs":{
        "host": meta:host,
        "eci": driver["Rx"],
        "message_id": order_id,
        "order":event:attr("order")
      }
    },tx_host);

    fired {
      schedule flower_shop event "bids_closed" repeat time:add(time:now(), {"seconds": 5})
      attributes {
        "orderID":ent:orderID.defaultsTo(0),
        "order":event:attr("order")
      } on final;
      ent:orders := ent:orders.defaultsTo({}).put([order_id], event:attr("order"));
      ent:orderID := ent:orderID.defaultsTo(0) + 1 on final;
    }
  }

  rule bid_received {
    select when flower_shop bid_received
    pre {
      bid = event:attr("bid");
    }
    fired {
      ent:bids := ent:bids.defaultsTo({}).put([bid{"id"}], bid);
    }
  }

  rule bids_closed {
    select when flower_shop bids_closed
    pre {
      // Get the bids for this order
      bidsReceived = ent:bids.defaultsTo({}).filter(function(value,key){
        bidIDTokens = key.split(re#:#);
        orderID = bidIDTokens[1].as("Number");
        event:attr("orderID") == orderID
      }).values();
    }

    if bidsReceived.length() > 0 then every {
        send_directive("say", {"Bidding": "Closing bidding"});
    }

    fired {
      // Get the distance matrix for the cars
      viableDrivers = getViableDrivers(event:attr("order"), bidsReceived);

      automaticSelection = getAutomaticSelection();
      eventType = automaticSelection => "auto_select_driver" | "ask_select_driver";

      raise flower_shop event eventType attributes {
        "order":event:attr("order"),
        "viableDrivers":viableDrivers
        };
    } else {
      klog("Error, no bids were received!");
    }
  }

  rule auto_select_driver {
    select when flower_shop auto_select_driver
    pre {
      // Select some driver
      drivers = event:attr("viableDrivers");
      chosenDriverIndex = random:integer(drivers.length() - 1);
      driver = drivers[chosenDriverIndex];
    }

    fired {
      raise flower_shop event "send_bid_accepted" attributes {
        "order":event:attr("order"),
        "driver":driver
        };
    }
  }

  // This used to ask the customer to select a driver. Now, the store has to do that.
//  rule ask_select_driver {
//    select when flower_shop ask_select_driver
//    pre {
//      order = event:attr("order");
//      tx_host = event:attr("order"){"tx_host"} != null => event:attr("order"){"tx_host"} | meta:host;
//    }

    // Send an event to the customer asking to choose a driver
//    event:send({
//      "eci":order["eci"],
//      "domain":"customer",
//      "type":"select_driver",
//      "attrs":{
//        "host": meta:host,
//        "drivers": event:attr("viableDrivers"),
//        "order":order
//      }
//    },tx_host);
//  }

   rule send_bid_accepted {
    select when flower_shop send_bid_accepted
    pre {
      order = event:attr("order");
      selectedDriver = event:attr("driver");
      tx_host = selectedDriver{"tx_host"} != null => selectedDriver{"tx_host"} | meta:host;
      eci = meta:eci;

    }

    event:send({
      "eci":selectedDriver{"eci"},
      "domain":"driver",
      "type":"bid_accepted",
      "attrs":{
        "host": meta:host,
        "eci": eci,
        "order":order,
        "driver": selectedDriver
      }
    },tx_host);
  }

  rule bid_confirmed {
    select when flower_shop bid_confirmed
    pre {
      order = event:attr("order");
      driver = event:attr("driver");
    }
    twilio:send_sms(order["smsNumber"],
                    fromSMSNumber,
                    "Order accepted: " + driver["name"] +" is on his way."
                   );
  }

  rule delivery_confirmed {
    select when flower_shop delivery_confirmed

    pre {
      order = event:attr("order")
      driver = event:attr("driver")
    }

    twilio:send_sms(order["smsNumber"],
                    fromSMSNumber,
                    "Order has been delivered by " + driver["name"] +"."
                   );
  }

  rule autoAccept {
    select when wrangler inbound_pending_subscription_added
    pre {
      attributes = event:attrs;
    }
    always{
      wrangler_subscription:inbound().klog("Inbound subscription");
      attributes.klog();
      raise wrangler event "pending_subscription_approval"
          attributes attributes;
    }
  }

  rule reset_all {
    select when flower_shop reset_all
    fired {
      ent:bids := {};
      ent:orderID := 0;
      ent:orders := {};
      ent:automaticSelection := true;
      ent:location := "Orem, Utah";
    }
  }

  rule initialize_shop {
    select when flower_shop initialize_shop
    fired {
      ent:location := event:attr("location");
      ent:preference := event:attr("preference");
    }
  }
  rule set_automatic_selection {
    select when flower_shop set_automatic_selection
    fired {
      automaticSelection = event:attr("automaticSelection").defaultsTo("true") == "false" => false | true;
      ent:automaticSelection := automaticSelection;
    }
  }
}
