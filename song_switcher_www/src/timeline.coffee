BACKGROUND = '#1e1e1e'
FONT_SIZE = 15
FONT_FAMILY = 'sans-serif'
ALIGN_LEFT = 1
ALIGN_RIGHT = -1
PADDING = 20
CURSOR_COLOR = 'yellow'
CURSOR_WIDTH = 3
GRID_COLOR = '#888888'
GRID_WIDTH = 1
MARKER_FG = 'white'
MARKER_BG = 'red'
MARKER_WIDTH = 2
TYPE_CURSOR = 1
TYPE_GRID = 2
TYPE_MARKER = 3
SNAP_THRESHOLD = 50

EventEmitter = require('events').EventEmitter
sprintf = require('sprintf-js').sprintf

class Timeline extends EventEmitter
  constructor: (@canvas) ->
    @ctx = @canvas.getContext '2d'

    @rulerTop = FONT_SIZE
    @rulerHeight = @canvas.clientHeight - (@rulerTop * 2)
    @rulerBottom = @rulerTop + @rulerHeight
    @snapPoints = []

    @canvas.addEventListener 'click', (e) => @emitSnap(e.offsetX)

  update: (@data) ->
    [@canvas.width, @canvas.height] = [@canvas.clientWidth, @canvas.clientHeight]
    @scale = (@data.state.endTime - @data.state.startTime) / @canvas.width
    @scale ||= 1 / Math.pow(2,32)
    @snapPoints.length = 0

    @ctx.textBaseline = 'top'

    @ctx.fillStyle = BACKGROUND
    @ctx.fillRect 0, @rulerTop, @canvas.width, @rulerHeight

    end = @data.state.endTime - @data.state.startTime
    @gridLine 0
    @gridLine end / 2
    @gridLine end

    [@ctx.strokeStyle, @ctx.fillStyle] = [MARKER_BG, MARKER_BG]
    for marker in @data.markerList when marker.time >= @data.state.startTime and marker.time <= @data.state.endTime
      @marker marker

    @editCursor @data.position - @data.state.startTime

    if @data.position < @data.state.startTime
      @outOfBounds ALIGN_LEFT
    else if @data.position > @data.state.endTime
      @outOfBounds ALIGN_RIGHT

    @snapPoints.sort (a, b) -> a - b

  editCursor: (time) ->
    pos = @timeToPx time

    @ctx.strokeStyle = @ctx.fillStyle = CURSOR_COLOR
    @ctx.lineWidth = CURSOR_WIDTH

    @ctx.beginPath()
    @ctx.moveTo pos - @rulerTop, 0
    @ctx.lineTo pos, @rulerTop + CURSOR_WIDTH
    @ctx.lineTo pos + @rulerTop, 0
    @ctx.fill()

    @rulerTick time, false

  gridLine: (time) ->
    @ctx.strokeStyle = @ctx.fillStyle = GRID_COLOR
    @ctx.lineWidth = GRID_WIDTH
    @rulerTick time

  marker: (marker) ->
    time = marker.time - @data.state.startTime
    pos = @timeToPx time

    @ctx.strokeStyle = @ctx.fillStyle = MARKER_BG
    @ctx.lineWidth = MARKER_WIDTH
    @rulerTick time

    @ctx.font = "bold #{FONT_SIZE}px #{FONT_FAMILY}"
    label = marker.name || marker.id
    boxWidth = @ctx.measureText(label).width + (MARKER_WIDTH * 2)
    @ctx.fillRect pos, @rulerTop, boxWidth, FONT_SIZE

    @ctx.fillStyle = MARKER_FG
    @ctx.textAlign = 'left'
    @ctx.fillText label, pos + MARKER_WIDTH, @rulerTop + 2

  rulerTick: (time, ruler = true) ->
    pos = @timeToPx time
    @snapPoints.push pos if ruler

    @ctx.beginPath()
    @ctx.moveTo pos, @rulerTop
    @ctx.lineTo pos, @rulerBottom
    @ctx.stroke()

    @ctx.font = "#{FONT_SIZE}px #{FONT_FAMILY}"

    align = if ruler then 0 else 1
    label = @formatTime time
    [pos, _] = @alignCenter pos, label
    @ctx.fillText label, pos, (@rulerBottom + 3) * align

  alignCenter: (pos, text) ->
    width = @ctx.measureText(text).width
    halfWidth = width / 2

    if (diff = pos - halfWidth) < 0
      pos += Math.abs diff
    else if (right = pos + halfWidth) > @canvas.width
      pos -= right - @canvas.width

    @ctx.textAlign = 'center'
    [pos, width]

  outOfBounds: (dir) ->
    pos = PADDING
    pos = @canvas.width - pos if dir == ALIGN_RIGHT

    height = @rulerHeight / 2.5
    width = height
    top = (@canvas.height - height) / 2

    @ctx.lineWidth = 3

    @ctx.beginPath()
    @ctx.moveTo pos + (width * dir), top
    @ctx.lineTo pos, top + (height / 2)
    @ctx.lineTo pos + (width * dir), top + height
    @ctx.stroke()

  timeToPx: (time) ->
    time / @scale

  pxToTime: (px) ->
    px * @scale

  formatTime: (time) ->
    sign = if time < 0 then '-' else ''
    min = Math.abs time / 60
    sec = Math.abs time % 60
    ms = Math.abs time * 1000 % 1000

    sprintf '%s%02d:%02d.%03d', sign, min, sec, ms

  emitSnap: (pos) ->
    [min, max] = [-1, @snapPoints.length]

    while max - min > 1
      i = Math.round((min + max) / 2)
      point = @snapPoints[i]
      if point <= pos
        min = i
      else
        max = i

    min = @snapPoints[min] - pos
    max = @snapPoints[max] - pos
    distance = Math.min Math.abs(min), Math.abs(max)

    if distance < SNAP_THRESHOLD
      pos = (if distance == Math.abs(min) then min else max) + pos

    @emit 'seek', @pxToTime(pos) + @data.state.startTime

module.exports = Timeline
