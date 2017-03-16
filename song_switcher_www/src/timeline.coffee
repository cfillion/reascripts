GRID_COLOR = '#888888'
BACKGROUND = '#1e1e1e'
FONT_SIZE = 14
FONT_FAMILY = 'sans-serif'
ALIGN_LEFT = 1
ALIGN_RIGHT = -1
ALIGN_TOP = 0
ALIGN_BOTTOM = 1
PADDING = 20
CURSOR_COLOR = 'yellow'
CURSOR_WIDTH = 3
TYPE_CURSOR = 1
TYPE_GRID = 2
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
    @ctx.font = "#{FONT_SIZE}px #{FONT_FAMILY}"

    @ctx.fillStyle = BACKGROUND
    @ctx.fillRect 0, @rulerTop, @canvas.width, @rulerHeight

    end = @data.state.endTime - @data.state.startTime
    @ctx.strokeStyle = @ctx.fillStyle = GRID_COLOR
    @ctx.fillStyle = GRID_COLOR
    @timeLabel 0, ALIGN_TOP
    @rulerTick 0, TYPE_GRID
    @timeLabel end, ALIGN_TOP
    @timeLabel end / 2, ALIGN_TOP
    @rulerTick end / 2, TYPE_GRID
    @rulerTick end, TYPE_GRID

    cursorPos = @data.position - @data.state.startTime
    @ctx.strokeStyle = @ctx.fillStyle = CURSOR_COLOR
    @rulerTick cursorPos, TYPE_CURSOR
    @timeLabel cursorPos, ALIGN_BOTTOM

    if @data.position < @data.state.startTime
      @outOfBounds ALIGN_LEFT
    else if @data.position > @data.state.endTime
      @outOfBounds ALIGN_RIGHT

    @snapPoints.sort (a, b) -> a - b

  rulerTick: (time, type) ->
    pos = @timeToPx time
    @snapPoints.push pos unless type == TYPE_CURSOR

    switch type
      when TYPE_CURSOR
        @ctx.lineWidth = 3
        @ctx.beginPath()
        @ctx.moveTo pos - @rulerTop, 0
        @ctx.lineTo pos, @rulerTop + CURSOR_WIDTH
        @ctx.lineTo pos + @rulerTop, 0
        @ctx.fill()
      when TYPE_GRID
        @ctx.lineWidth = 1

    @ctx.beginPath()
    @ctx.moveTo pos, @rulerTop
    @ctx.lineTo pos, @rulerBottom
    @ctx.stroke()

  timeLabel: (time, align) ->
    label = @formatTime time
    pos = Math.max(0, Math.min(@timeToPx(time), @canvas.width))
    halfWidth = @ctx.measureText(label).width / 2

    if (diff = pos - halfWidth) < 0
      pos += Math.abs diff
    else if (right = pos + halfWidth) > @canvas.width
      pos -= right - @canvas.width

    @ctx.textAlign = 'center'

    @ctx.fillText label, pos, (@rulerBottom + 3) * align

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
