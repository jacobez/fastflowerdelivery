ruleset distance_matrix {
  meta {
    configure using api_key = ""
    provides queryDistance
  }
  global {
    queryDistance = function (origins, destinations, units = null) {
      base_url = <<https://maps.googleapis.com/maps/api/distancematrix/json>>;
      params = {};
      params = params.put(["origins"], origins.join("|"));
      params = params.put(["destinations"], destinations.join("|"));
      params = (not units.isnull()) => params.put(["units"], units) | params;
      params = params.put(["key"], api_key);
      result = http:get(base_url, params).klog();
      result{"content"}.decode()
    }
  }
}
