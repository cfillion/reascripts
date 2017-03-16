RULER_COLOR = '#888888'
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

EventEmitter = require('events').EventEmitter
sprintf = require('sprintf-js').sprintf

class Timeline extends EventEmitter
  constructor: (@canvas) ->
    @ctx = @canvas.getContext '2d'

    @rulerTop = FONT_SIZE
    @rulerHeight = @canvas.clientHeight - (@rulerTop * 2)
    @rulerBottom = @rulerTop + @rulerHeight

    @canvas.addEventListener 'click', (e) =>
      @emit 'seek', @pxToTime(e.offsetX) + @data.state.startTime

  update: (@data) ->
    [@canvas.width, @canvas.height] = [@canvas.clientWidth, @canvas.clientHeight]
    @scale = (@data.state.endTime - @data.state.startTime) / @canvas.width

    @ctx.textBaseline = 'top'
    @ctx.font = "#{FONT_SIZE}px #{FONT_FAMILY}"

    @ctx.fillStyle = BACKGROUND
    @ctx.fillRect 0, @rulerTop, @canvas.width, @rulerHeight

    @ctx.fillStyle = RULER_COLOR
    @timeLabel 0, ALIGN_TOP
    @timeLabel @data.state.endTime - @data.state.startTime, ALIGN_TOP

    cursorPos = @data.position - @data.state.startTime
    @ctx.strokeStyle = @ctx.fillStyle = CURSOR_COLOR
    @marker cursorPos
    @timeLabel cursorPos, ALIGN_BOTTOM

    if @data.position < @data.state.startTime
      @outOfBounds ALIGN_LEFT
    else if @data.position > @data.state.endTime
      @outOfBounds ALIGN_RIGHT

  marker: (time) ->
    pos = @timeToPx time

    @ctx.beginPath()
    @ctx.moveTo pos - @rulerTop, 0
    @ctx.lineTo pos, @rulerTop + CURSOR_WIDTH
    @ctx.lineTo pos + @rulerTop, 0
    @ctx.fill()

    @ctx.lineWidth = 3
    @ctx.beginPath()
    @ctx.moveTo pos, @rulerTop
    @ctx.lineTo pos, @rulerBottom
    @ctx.stroke()

  timeLabel: (time, align) ->
    label = @formatTime time
    pos = Math.max(0, Math.min(@timeToPx(time), @canvas.width))
    metrics = @ctx.measureText label

    if pos - (metrics.width / 2) < 0
      @ctx.textAlign = 'left'
    else if pos + metrics.width > @canvas.width
      @ctx.textAlign = 'right'
    else
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

module.exports = Timeline
