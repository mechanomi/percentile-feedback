chart_local_start_hour = 6.0

floor_to_seconds = (unixtime, seconds) ->
  unixtime - (unixtime % seconds)

floor_to_minute = (unixtime) ->
  floor_to_seconds unixtime, 60

floor_to_hour = (unixtime) ->
  floor_to_seconds unixtime, 3600

floor_to_day = (unixtime) ->
  floor_to_seconds unixtime, 86400

unixtime_now = () ->
  new Date().getTime() / 1000

isotime_to_unixtime = (isotime) ->
  new Date(isotime).getTime() / 1000

format_seconds = (seconds) ->
  days = Math.floor(seconds / 86400)
  seconds = seconds % 86400
  hours = Math.floor(seconds / 3600)
  seconds = seconds % 3600
  minutes = Math.floor(seconds / 60)
  seconds = seconds % 60
  # "#{ days }d #{ hours }h #{ minutes }m #{ seconds }s"
  if days is 0
    "#{ hours }hrs #{ minutes }m"
  else
    "#{ days }d, #{ hours }hrs #{ minutes }m"

loaded = unixtime_now()

mean_percentile_rank = (values, value) ->
  strict = values[..].filter (v) -> v < value
  weak = values[..].filter (v) -> v <= value
  (strict.length + weak.length) * 50 / values.length

timezone = -(new Date().getTimezoneOffset() / 60)
console.log "timezone", timezone
utc_midnight = chart_local_start_hour - timezone

draw_chart = (history, today) ->
  $("svg").remove()

  # http://bl.ocks.org/mbostock/3019563
  margin = {top: 10, right: 10, bottom: 35, left: 50}
  width = 960 - margin.left - margin.right
  height = 360 - margin.top - margin.bottom

  # xValue = (d) -> d[0]
  xScale = d3.scale.linear()
    .domain([0, 24])
    .range([0, width])
  xMap = (d, e) -> xScale(e)
  xMapJitter = (d, e) ->
    shim = e % 24
    shim += 1 * (Math.random() - 0.5)
    if e is 23
      shim += 0.5
    if shim < 0
      shim = -shim
    if shim > 24
      shim = 24 - (shim - 24)
    xScale(shim)
  xAxis = d3.svg.axis()
    .scale(xScale)
    .orient("bottom")
    .ticks(24)
    .tickFormat (tick) ->
      (tick + chart_local_start_hour + 24) % 24

  # yValue = (d) -> d[1]
  yScale = d3.scale.linear()
    .domain([0, 100])
    .range([height, 0])
  yMap = (d, e) ->
    yScale(d) # yValue(d))
  yAxis = d3.svg.axis()
    .scale(yScale)
    .orient("left")
    .ticks(3)

  outerWidth = width + margin.left + margin.right
  outerHeight = height + margin.top + margin.bottom
  svg = d3.select("body")
    .append("svg")
      .attr(
        width: "100%"
        height: "100%"
        id: "chart"
        viewBox: "0 0 #{ outerWidth } #{ outerHeight }"
        preserveAspectRatio: "xMidYMid meet" # Or just xMinYMid?
      ).style(
        background: "white"
        "max-height": "480"
      )
    .append("g")
      .attr("transform", "translate(#{ margin.left }, #{ margin.top })")

  svg.append("g")
      .attr("class", "x axis")
      .attr("transform", "translate(0, #{ height })") # height + 2
      .call(xAxis)
    .append("text")
      .attr("class", "label")
      .attr("x", width / 2)
      .attr("y", 30)
      .style("text-anchor", "end")
      .text("Hour")

  svg.append("g")
      .attr("class", "y axis")
      .call(yAxis)
    .append("text")
      .attr("class", "label")
      .attr("transform", "rotate(-90)")
      .attr("x", -(height / 2.75))
      .attr("y", -30)
      .style("text-anchor", "end")
      .text("Work Efficiency")

  # history is a list of views
  merged = []
  for view in history
    for efficiency in view.efficiencies
      merged.push efficiency

  # merged = merged.concat.apply merged, d3.values(history)

  svg.append("g")
    .attr("class", "history")
    .selectAll("circle")
    .data(merged)
    .enter()
    .append("circle")
    .attr(
      cx: xMapJitter
      cy: yMap
      r: 4
    )
    .style(
      fill: "#cde"
      opacity: "0.5"
    )

  line = d3.svg.line()
      .x(xMap)
      .y(yMap)
      .interpolate("monotone")

  today = today.efficiencies
  # Use most recent time logged? Or current time?
  now = unixtime_now()
  hours = (now - (floor_to_day now)) / 3600
  hours = hours - utc_midnight
  # Current UTC hours as a float
  # hour = new Date().getHours()
  # Supply missing first value
  today.unshift 0
  # Duplicate the last value, as a fake boundary
  # today.push today[today.length - 1]

  values = merged[..].filter (e, i) ->
    (i % Math.floor(hours)) is 0
  values = values.sort d3.ascending
  # Uncomment this to ignore 0 values
  # values = values[..].filter (e, i) -> e isnt 0
  value = today[Math.floor(hours)]
  mean_pr = mean_percentile_rank values, value

  svg.append("defs")
    .append("clipPath")
    .attr("id", "clip")
    .append("rect")
    .attr("width", xScale(hours))
    .attr("height", height + 20)
    .style("fill", "blue")

  svg.append("g")
    .attr("class", "today line")
    .datum(today[..]) # Math.floor(hours)])
    .append("path")
    .attr("clip-path", "url(#clip)")
    .attr("d", line)

  svg.append("text")
    .attr("class", "pr")
    .attr("x", 20)
    .attr("y", 40)
    .text("PR #{ Math.floor mean_pr }")

histogram_to_efficiencies = (histogram) ->
  efficiencies = []
  actual = 0
  maximum = 0
  for bin in histogram
    actual += bin.y
    maximum += (bin.dx / 60)
    efficiencies.push (actual / maximum) * 100
  efficiencies

uptodate = (db) ->
  db.allDocs {include_docs: true, ascending: true}, (err, doc) ->
    console.log "WAYPOINT: Queried all documents", unixtime_now() - loaded
    if not err
      # A view can be "rolling" or "fixed"
      # This is a lot easier since keys are guaranteed ascending
      views = []
      create_view = ->
        {"start": null, "points": [], "duration": 0}
      view = create_view()
      view_tick = 3600
      view_width = 24 * view_tick

      for row in doc.rows
        unixtime = isotime_to_unixtime row.doc._id

        # This is a fixed:24h solution, flooring to local day
        view_start = (floor_to_day unixtime) + (3600 * utc_midnight)
        if view.start is null
          view.start = view_start
          views.push view
        else if view.start isnt view_start
          view = create_view()

        view.duration += row.doc.duration
        start_minute = floor_to_minute unixtime
        for minute in [0...row.doc.duration] by 60
          view.points.push start_minute + minute

      console.log "WAYPOINT: Aggregated views", unixtime_now() - loaded

      margin = {top: 10, right: 30, bottom: 30, left: 30}
      width = 960 - margin.left - margin.right
      height = 500 - margin.top - margin.bottom

      for view in views
        # day = view.start
        view.finish = view.start + view_width

        x = d3.scale.linear()
          .domain([view.start, view.finish])
          .range([0, width])

        bins = []
        bins.push n for n in [view.start..view.finish] by view_tick
        histogram = d3.layout.histogram()
          .bins(bins)(view.points)
        delete view.points
        view.efficiencies = histogram_to_efficiencies histogram

      console.log "WAYPOINT: Computed efficiencies", unixtime_now() - loaded
      current_view = views.pop()
      draw_chart views, current_view
      console.log "WAYPOINT: Drew chart", unixtime_now() - loaded

      sum = (a) ->
        total = 0
        for n in a
          total += n
        total
      total_duration = sum(view.duration for view in views)
      today_duration = views[views.length - 1].duration
      $("body").append $("<p>Total: #{ format_seconds total_duration } —
                             Today: #{ format_seconds today_duration }</p>")
    else
      console.log "Sorry, there was an error!"

main = ->
  database_name = "pf-periods"
  db = PouchDB(database_name)
  db.replicate.from("http://127.0.0.1:5984/#{ database_name }", {live: true})
    .on("uptodate", ->
      console.log "WAYPOINT: Replicated remote DB", unixtime_now() - loaded
      uptodate db
    )

$ ->
  cors_failure = ->
    $("body").append("<p>You must set up CORS correctly!</p>")

  $.get("http://127.0.0.1:5984/_config/cors/credentials")
    .done((arg) ->
      text = JSON.parse arg
      if text isnt "true"
        cors_failure()
      else
        main()
    )
    .fail((arg) ->
      cors_failure()
    )
