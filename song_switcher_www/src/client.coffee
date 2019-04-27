EXT_SECTION  = 'cfillion_song_switcher'
EXT_STATE    = 'state'
EXT_REL_MOVE = 'relative_move'
EXT_FILTER   = 'filter'
EXT_RESET    = 'reset'
CMD_UPDATE   = "TRANSPORT;MARKER;GET/EXTSTATE/#{EXT_SECTION}/#{EXT_STATE}"

EventEmitter = require('events').EventEmitter
equal = require 'deep-equal'

parseTime = (str) ->
  # workaround for Javascript's weird floating point approximation
  Math.trunc(parseFloat(str) * 1000) / 1000

class State
  constructor: (data) ->
    if typeof(data) == 'object'
      @_unpack data
    else
      @_fallback data || '## No data from host ##'

  _unpack: (data) ->
    i = 0
    @currentIndex = parseInt data[i++]
    @songCount = parseInt data[i++]
    @title = data[i++] || '## No song selected ##'
    @startTime = parseTime data[i++]
    @endTime = parseTime data[i++]
    @invalid = data[i++] == 'true'

  _fallback: (title) ->
    @currentIndex = @songCount = @startTime = @endTime = 0
    [@title, @invalid] = [title, true]

class Marker
  constructor: (data) ->
    i = 1
    @name = data[i++]
    @id = data[i++]
    @time = parseTime data[i++]
    @rawColor = parseInt data[i++]
    @color = '#' + Number(@rawColor & 0xFFFFFF).toString(16).padStart(6, '0') if @rawColor

class Client extends EventEmitter
  makeSetExtState = (key, value) ->
    "SET/EXTSTATE/#{EXT_SECTION}/#{key}/#{encodeURIComponent value}"

  constructor: (timer) ->
    @data = {}
    @_resetData [] # pass an empty state different from fallback for initialization

    (fetch_loop = =>
      @_send ''
      setTimeout fetch_loop, timer
    )()

  play: ->
    @_send 40044 # Transport: Play/stop

  relativeMove: (move) ->
    @_send makeSetExtState(EXT_REL_MOVE, move)

  setFilter: (filter) ->
    @_send makeSetExtState(EXT_FILTER, filter)
  
  seek: (time) ->
    @_send "SET/POS/#{time}"

  panic: ->
    @_send 40345 # Send all notes off to all MIDI outputs/plug-ins

  reset: ->
    @_send makeSetExtState(EXT_RESET, 'true')

  _send: (cmd) ->
    req = new XMLHttpRequest
    req.onreadystatechange = =>
      if(req.readyState == XMLHttpRequest.DONE)
        if req.status == 200
          @_parse req.responseText
        else
          @_resetData '## Network error ##'
    req.open 'GET', "/_/#{cmd};#{CMD_UPDATE}", true
    req.send null

  _resetData: (state) ->
    @_editData (set) ->
      set 'playState', false
      set 'position', 0
      set 'state', new State(state)
      set 'markerList', []

  _parse: (response) ->
    markers = []
    @_editData (set) ->
      for l in response.split('\n')
        tok = l.split '\t'

        switch tok[0]
          when 'TRANSPORT'
            set 'playState', parseInt(tok[1])
            set 'position', parseTime(tok[2])
          when 'MARKER'
            markers.push new Marker(tok)
          when 'EXTSTATE'
            if tok[1] == EXT_SECTION && tok[2] == EXT_STATE
              set 'state', if tok[3].length
                new State simple_unescape(tok[3]).split('\t')
              else
                new State
      set 'markerList', markers

  _editData: (cb) ->
    modified = []
    cb (key, value) =>
      unless equal @data[key], value
        @data[key] = value
        modified.push key
    @emit "#{key}Changed", @data[key] for key in modified

module.exports = Client
