# This is conventional CoffeeScript boilerplate for allowing exports from a
# file in a widely compatible way. This is necessary because CoffeeScript
# encapsulates input files in code that acts like a namespace. If we want to
# export any objects, then we simply attach them to the root object that we
# create here.
root = exports ? this

# The only top-level object that we export is named pf. In other words, we
# use pf as a namespace for everything that we export, a bit like a module.
root.pf = {}

# This sets the left hand side of the chart view. The chart view is the period
# displayed in the chart, which could be any width but in the present code
# we're using 24h which may be hard coded in places. Therefore, setting this
# variable to 6.0 means that the left and right hand sides of the chart are 6am
# local time.
chart_local_start_hour = 6.0

# Current unixtime, in seconds since the unix epoch.
unixtime_now = () ->
  new Date().getTime() / 1000

# This is a debug variable, used for displaying how long it took to perform
# each activity. Think of this as an epoch for when the script started loading.
loaded = unixtime_now()

# The following series of floor functions convert a unixtime to the nearest
# previous boundary. Boundaries are defined by specific functions built on top
# of the more general floor_to_seconds, but they are all expressed in terms of
# a modulus from the unix epoch.
#
# For example, the floor_to_minute function floors any unixtime to the nearest
# multiple of 60 seconds. So if you pass 63 as a value it will return 60, and
# if you pass 185, it will return 180.
#
# These functions are used in various places, for example to align to a
# particular view width (e.g. a day) or a particular histogram bucket within a
# view (e.g. an hour). Sometimes we have to involve extra complicated offsets,
# to help deal with timezones and view offsets.
floor_to_seconds = (unixtime, seconds) ->
  unixtime - (unixtime % seconds)

floor_to_minute = (unixtime) ->
  floor_to_seconds unixtime, 60

floor_to_hour = (unixtime) ->
  floor_to_seconds unixtime, 3600

floor_to_day = (unixtime) ->
  floor_to_seconds unixtime, 86400

# This converts an ISO formatted time, of the type that we stored in CouchDB,
# to a unix timestamp as an integer.
isotime_to_unixtime = (isotime) ->
  new Date(isotime).getTime() / 1000

# This function is used for displaying how long we've been working, either
# during the present day or overall.
format_seconds = (seconds) ->
  # Unfortunately JavaScript does not have a divmod function like Python
  # Perhaps it would be useful to write one
  days = Math.floor(seconds / 86400)
  seconds = seconds % 86400
  hours = Math.floor(seconds / 3600)
  seconds = seconds % 3600
  minutes = Math.floor(seconds / 60)
  seconds = seconds % 60
  if days is 0
    "#{ hours }hrs #{ minutes }m"
  else
    "#{ days }d, #{ hours }hrs #{ minutes }m"

# There are various ways to "reckon" a percentile rank, just like there are
# many different kinds of average (mean, median, mode). In fact, one of the
# reasons why there are various ways to reckon a percentile rank is that the
# function uses averaging. In this case, we use the mean percentile rank.
#
# Using different kinds of percentile rank could in some cases radically alter
# how the user perceives their current productivity. For example, some forms of
# PR would tend to ignore or lessen the effect of days on which there was no
# productivity logged. The mean percentile rank has the nice feature of
# averaging the various methods out and providing a reasonable value.
mean_percentile_rank = (values, value) ->
  # The mean is an average of the strict and weak percentile rank reckonings
  strict = values[..].filter (v) -> v < value
  weak = values[..].filter (v) -> v <= value
  # This gives us a figure out of 100%
  (strict.length + weak.length) * 50 / values.length

# This code calculates the present timezone, which we get from the browser (and
# that the browser gets from the user's system). We then use it to calculate
# the left hand side of the chart view in UTC. We will be using both the UTC
# and the local values elsewhere in the code.
timezone = -(new Date().getTimezoneOffset() / 60)
# timezone, on the other hand, is only used in the two lines below
console.log "timezone", timezone
utc_midnight = chart_local_start_hour - timezone

# Plotting the percentile feedback chart is a five step process:
#
# 1. root.pf.compute
# 2. check_cors_setup and cors_succeeded
# 3. sync_succeeded
# 4. query_succeeded
# 5. chart_data and draw_chart [YOU ARE HERE]
#
# The following function, draw_chart, represents the second half of the last
# step. If you're reading this file top down, you're going in the wrong
# direction! To get the full story, try reading from the bottom up.
#
# By now, we have all the data that we need to render the percentile-feedback
# chart. We will still need to manipulate the data to some extent to prepare it
# for charting.
#
# We're using Mike Bostock's excellent d3.js as the charting library. We create
# a new SVG element, set the dimensions, and then plot the axes and their
# labels. Then we chart the two series:
#
# 1. The historical data points
# 2. Data points from today
#
# The historical data points are rendered in a light blue, slightly translucent
# colour, whereas the data points for today are rendered as a green
# line. Because the historical data points are time aligned, we jitter them at
# random slightly in the display.
draw_chart = (data) ->
  # Remove any existing SVG charts, in case we're redrawing
  $("svg").remove()

  # This is a nice method, devised by Mike Bostock, for computing the
  # dimensions of the chart and containing some margins.
  # Cf. http://bl.ocks.org/mbostock/3019563
  margin = {top: 10, right: 10, bottom: 35, left: 50}
  width = 960 - margin.left - margin.right
  height = 360 - margin.top - margin.bottom

  # The following variables pertain to the x-axis.
  #
  # The Scale function provides a linear mapping from the input data to the
  # size of the chart. Everything from the range 0-24 in the input is mapped
  # from 0 to the width of the chart. This is an example of where the view
  # width is hardcoded (to 24h).
  xScale = d3.scale.linear()
    .domain([0, 24])
    .range([0, width])
  # The Map, and MapJitter variant, function provides a mapping from the
  # specific data point (denoted by e) to the place on the x-axis in real pixel
  # terms for the graph. So for example, if our graph is 240px wide, and e is
  # 1, then xMap will convert that to 240 / 24 * 1 = 10px. The jitter is again
  # hard coded for 24 buckets of data in the histogram.
  xMap = (d, e) -> xScale(e)
  xMapJitter = (d, e) ->
    shim = e % 24
    shim += 1 * (Math.random() - 0.5)
    # The following conditionals make the data smoother towards the edges
    if e is 23
      shim += 0.5
    if shim < 0
      shim = -shim
    if shim > 24
      shim = 24 - (shim - 24)
    xScale(shim)
  # The Axis function is used as the basis for plotting the actual axis, though
  # that is accomplished in code further down. Again, 24h is hard coded here.
  xAxis = d3.svg.axis()
    .scale(xScale)
    .orient("bottom")
    .ticks(24)
    .tickFormat (tick) ->
      (tick + chart_local_start_hour + 24) % 24

  # The following variables pertain to the x-axis.
  #
  # The Scale function provides a linear mapping from the input data to the
  # size of the chart. This time 0-100 is mapped to the height of the chart.
  yScale = d3.scale.linear()
    .domain([0, 100])
    .range([height, 0])
  # The Map function provides the y-scale mapping. This is more straightforward
  # than the x-scale because we don't have to apply any jitter; y-scale values
  # are in a percentile continuum, and fall at random on that continuum.
  yMap = (d, e) ->
    yScale(d) # yValue(d))
  # The Axis function provides data for the actual y-axis construction.
  yAxis = d3.svg.axis()
    .scale(yScale)
    .orient("left")
    .ticks(3)

  # Here we create the SVG element. The outerWidth and outerHeight variables
  # make Bostock's margin code work. The viewBox and preserveAspectRatio
  # attributes are intended to make the chart resizeable, so that it could be
  # rendered at any size in the browser.
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

  # Construct the x-axis, and label
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

  # Construct the y-axis, and label
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

  # Plot the first data onto the chart. We start here with the historical data,
  # the values recorded before today. The call to .data(data.merged) feeds the
  # data to d3. The circle attributes use the Map functions defined above to
  # convert the attributes of the data into the actual plotting values. The "r"
  # attribute is for radius, and can be adjusted to taste, as can the style
  # properties.
  svg.append("g")
    .attr("class", "history")
    .selectAll("circle")
    .data(data.merged)
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

  # We now prepare to plot today's data. There are two differences between
  # today's data and the historical data:
  #
  # 1. Instead of a scatterplot, we use a neater looking line.
  # 2. We don't want to plot the line for all of today, only today up to the
  # present time.
  #
  # The next two sections achieve these goals in order.

  # This converts a series of values into a line. There are many different
  # interpolation schemes offered by d3, but monotone has the most accurate and
  # pleasing results.
  line = d3.svg.line()
      .x(xMap)
      .y(yMap)
      .interpolate("monotone")

  # To only plot up to the present time, we actually use an overlay and then
  # set that as an SVG clip path. The value of data.hours, which is used for
  # the clipping, is computed in prepare_data.
  svg.append("defs")
    .append("clipPath")
    .attr("id", "clip")
    .append("rect")
    .attr("width", xScale(data.hours))
    .attr("height", height + 20)
    .style("fill", "blue")

  # We now plot today's data. We use .datum instead of .data because of the
  # shape of the data: we're only plotting one series now. We also set the clip
  # path here that we created above, which has to be done by reference rather
  # than through the API as might be expected. On the other hand, the line
  # interpolation is set through the API.
  svg.append("g")
    .attr("class", "today line")
    .datum(data.today[..]) # no [..]?
    .append("path")
    .attr("clip-path", "url(#clip)")
    .attr("d", line)

  # The cherry on the cake is rendering the actual PR value. This was computed
  # in prepare_data, and is styled in the accompanying CSS.
  #
  # TODO: Make sure that style is centralised.
  svg.append("text")
    .attr("class", "pr")
    .attr("x", 20)
    .attr("y", 40)
    .text("PR #{ data.pr }")

# This function is used in query_succeeded. It takes a histogram, which was
# computed by d3, and converts it into an array of efficiencies. The difference
# between the two is that a histogram records how much time was spent working
# during each bucket, whereas the efficiencies returned tell you how much time
# you have spent working as a *percentage of all the buckets so far*. So not
# only is the scale different (percentage, instead of time spent working), but
# the measurement is also cumulative instead of per-bucket.
histogram_to_efficiencies = (histogram) ->
  efficiencies = []
  actual = 0
  maximum = 0
  for bin in histogram
    # We use += in both of the following statements to make them cumulative
    # bin.y is the number of minutes in the bucket
    # i.e. this corresponds to total work time spent in this bucket
    actual += bin.y
    # bin.dx is the width of the bucket in minutes
    # i.e. this corresponds to maximum available time in this bucket
    maximum += (bin.dx / 60)
    # Calculate and push the current efficiency
    efficiencies.push (actual / maximum) * 100
  efficiencies

# prepare_data is used by query_succeeded to annotate the data that was already
# computed with some further values. It takes in the data series for the
# historical data and today's values, and returns:
#
# 1. A merged data-structure which is more suited to charting
# 2. A slightly modified version of today's series for charting
# 3. The current time (hours) for clipping today's series in the chart
# 4. The actual current percentile rank
#
# This data is then passed to root.pf.action with the current view data which
# can be used for charting. root.pf.action is a callback which can be set
# dynamically. It is the action that the user wants the software to take. By
# default it charts the data in HTML using d3, but the Chrome extension sets
# this callback so that the software only computes the PR value and displays it
# in the extension button, instead of plotting the SVG in the browser.
prepare_data = (history, today) ->
  # history is a list of views
  merged = []
  for view in history
    for efficiency in view.efficiencies
      merged.push efficiency

  # The following block of code is complicated, fragile, and mostly a shim. The
  # main purpose is to allow today's series to be clipped in the charting, but
  # it also serves to calculate the present percentile rank, because we need to
  # know where today's series goes up to in order to calculate the true present
  # value.
  #
  # One possible alternative is to move this logic elsewhere, but ultimately it
  # would be helpful to refactor this code so that all of the inherent display
  # offsets are easy to understand and debug.
  #
  # NOTE: Further comments in this block are development notes.
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

  {merged: merged, today: today, hours: hours, pr: Math.floor mean_pr}

# Plotting the percentile feedback chart is a five step process:
#
# 1. root.pf.compute
# 2. check_cors_setup and cors_succeeded
# 3. sync_succeeded
# 4. query_succeeded
# 5. chart_data [YOU ARE HERE] and draw_chart
#
# This is the default callback for root.pf.action. In other words, this is what
# the browser calls by default when all of the percentile-feedback data has
# been computed. So steps 1 to 4 inclusive in the list above are always
# performed when pf.compute is called. Step 5, on the other hand, is only
# performed when the chart is rendered; it is not performed, for example, in
# the Chrome extension.
#
# This is a simple function that calls draw_chart to do most of the work, and
# then displays the total time worked, and the time worked today.
chart_data = (views, data) ->
  draw_chart data
  console.log "WAYPOINT: Drew chart", unixtime_now() - loaded

  # JavaScript has no sum function!
  # We have to write our own
  sum = (a) ->
    total = 0
    for n in a
      total += n
    total
  total_duration = sum(view.duration for view in views)
  today_duration = views[views.length - 1].duration
  $("body").append $("<p>Total: #{ format_seconds total_duration } —
                         Today: #{ format_seconds today_duration }</p>")

# Plotting the percentile feedback chart is a five step process:
#
# 1. root.pf.compute
# 2. check_cors_setup and cors_succeeded
# 3. sync_succeeded
# 4. query_succeeded [YOU ARE HERE]
# 5. chart_data and draw_chart
#
# query_succeeded is the core functionality of the charting, taking all of the
# data from the CouchDB database and converting it into a form suitable for
# charting. There are two major steps involved in this process:
#
# i. Convert the continuous input into discrete data for d3
# ii. Create a histogram using d3, then convert to cumulative efficiencies
#
# We then prepare the data (with the aptly named prepare_data), and send it to
# whatever callback is registered as the current value of root.pf.action.
query_succeeded = (doc) ->
  # We reach this point as soon as the query performed in sync_succeeded
  # succeeds. The main task in the present function is to create a list of
  # views. A view corresponds to a series of data to the charted, or
  # manipulated in some other way such as to show the PR in the Chrome
  # extension.
  #
  # Though a view can be thought of as a single series of data, it will have a
  # variety of metadata associated with it. There will be a start point; we
  # will store discrete data for making a histogram; we will convert that into
  # efficiencies; we will note the width of the view as the view's
  # duration. There will also be information such as the number of histogram
  # buckets in the view, e.g. an hour for a 24h day. All of the views are
  # stored in an array of the same name.
  #
  # NOTE: A view can be "rolling" or "fixed"
  # This is a lot easier since keys are guaranteed ascending
  views = []
  create_view = ->
    {"start": null, "points": [], "duration": 0}
  view = create_view()
  view_tick = 3600
  view_width = 24 * view_tick

  # Iterate through the results of the PouchDB query, and convert the
  # continuous data ranges into discrete data, called view.points. We do this
  # because d3's handy histogram function only works with discrete data, not
  # continuous. We could write our own histogram function, but doing it this
  # way is more economical, and has a negligable cost in speed and memory
  # requirements.
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
    # This is the main loop where we convert from continuous to discrete
    for minute in [0...row.doc.duration] by 60
      view.points.push start_minute + minute

  console.log "WAYPOINT: Aggregated views", unixtime_now() - loaded

  # We now create a histogram from each view.points using d3, and then convert
  # that histogram into cumulative efficiency data. Because there may be many
  # view.points, we delete them; they are no longer needed.
  for view in views
    view.finish = view.start + view_width

    bins = []
    bins.push n for n in [view.start..view.finish] by view_tick
    histogram = d3.layout.histogram()
      .bins(bins)(view.points)
    delete view.points
    view.efficiencies = histogram_to_efficiencies histogram

  console.log "WAYPOINT: Computed efficiencies", unixtime_now() - loaded
  # The current_view is today's series of data
  current_view = views.pop()
  # We need to calculate and modify the existing data to make it more
  # compatible with charting. This includes calculating the current time
  # relative to the data, so that we can clip it and calculate the actual PR.
  data = prepare_data views, current_view
  # root.pf.action can be a custom callback, but charts the data by default
  root.pf.action views, data

# Plotting the percentile feedback chart is a five step process:
#
# 1. root.pf.compute
# 2. check_cors_setup and cors_succeeded
# 3. sync_succeeded [YOU ARE HERE]
# 4. query_succeeded
# 5. chart_data and draw_chart
#
# If we reach sync_succeeded, it means that we successfully synchronised with
# the remote CouchDB database. In other words we have replicated the CouchDB
# database into PouchDB. The next step is to query all of the documents in
# PouchDB, and then set another callback, query_succeeded, to continue
# processing.
sync_succeeded = (db) ->
  db.allDocs {include_docs: true, ascending: true}, (err, doc) ->
    console.log "WAYPOINT: Queried all documents", unixtime_now() - loaded
    if not err
      query_succeeded doc
    else
      console.log "Sorry, there was an error!"

# Plotting the percentile feedback chart is a five step process:
#
# 1. root.pf.compute
# 2. check_cors_setup and cors_succeeded [YOU ARE HERE]
# 3. sync_succeeded
# 4. query_succeeded
# 5. chart_data and draw_chart
#
# If we get to cors_succeeded, it means that our heuristic for determining
# whether CORS is successfully implemented on the remote CouchDB instance has
# indicated that everything is okay. We perform this CORS check because there
# can be problems with PouchDB when CORS fails, and clearing the cache
# etc. doesn't seem to fix it.
#
# The function itself is straightforward, performing live replication from the
# remote CouchDB instance, and then setting an event listener that is called
# whenever the CouchDB instance has been replicated locally. Note that this can
# happen multiple times during a session. This means that potentially we could
# be performing all of the succeeding steps, 3-5, in this process more than
# once. This would happen if the remote data is changed.
cors_succeeded = ->
  # TODO: Both database_name and the server address should be configurable
  database_name = "pf-periods"
  db = PouchDB database_name
  db.replicate.from("http://127.0.0.1:5984/#{ database_name }", {live: true})
    .on("uptodate", ->
      console.log "WAYPOINT: Replicated remote DB", unixtime_now() - loaded
      sync_succeeded db
    )

# Check that CORS is setup correctly on the remote CouchDB server. This is just
# an heuristic, because for example the CouchDB server may require user
# authorisation or authentication in order to view the CORS configuration
# options. We also assume that the CouchDB server is running locally, on the
# default port. But, assuming that these standard defaults have been chosen,
# this CORS function should accurately determine whether CORS is successfully
# setup.
check_cors_setup = (cors_succeeded, cors_failed) ->
  # TODO: The server address should be configurable
  # TODO: Non-remote servers should have CORS detection
  $.get("http://127.0.0.1:5984/_config/cors/credentials")
    .done((arg) ->
      text = JSON.parse arg
      if text isnt "true"
        cors_failed()
      else
        cors_succeeded()
    )
    .fail((arg) ->
      cors_failed()
    )

# Plotting the percentile feedback chart is a five step process:
#
# 1. root.pf.compute [YOU ARE HERE]
# 2. check_cors_setup and cors_succeeded
# 3. sync_succeeded
# 4. query_succeeded
# 5. chart_data and draw_chart
#
# This is the first step in the process, and must be initiated by the user. For
# example, the default index.html contains the following code:
#
#   <script>$(function() { $(pf.compute()); });</script>
#
# This then proceeds through the rest of the process, starting with the initial
# heuristic CORS check to make sure that PouchDB can operate correctly.
#
# We call this pf.compute rather than pf.chart because the action to be taken
# is determined by the user by setting pf.action (or using the default).
root.pf.compute = ->
  show_cors_error_message = ->
    $("body").append("<p>You must set up CORS correctly!</p>")
  check_cors_setup cors_succeeded, show_cors_error_message

# This is a kind of global callback. The user can set it to determine what
# action is taken as step 5 in the five step process.
root.pf.action = chart_data

# $ ->
#   pf.compute()
