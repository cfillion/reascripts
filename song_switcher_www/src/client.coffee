EXT_SECTION = 'cfillion_song_switcher'
EXT_STATE = 'state'
EXT_REL_MOVE = 'relative_move'
EXT_FILTER = 'filter'
CMD_UPDATE = 'TRANSPORT;GET/EXTSTATE/' + EXT_SECTION + '/' + EXT_STATE

EventEmitter = require('events').EventEmitter
equal = require 'deep-equal'

class State
  constructor: (data) ->
    if data then @unpack(data) else @fallback()

  unpack: (data) ->
    i = 0
    @currentIndex = parseInt data[i++]
    @songCount = parseInt data[i++]
    @title = data[i++]
    @startTime = parseFloat data[i++]
    @endTime = parseFloat data[i++]
    @invalid = data[i++] == 'true'

  fallback: ->
    @currentIndex = @songCount = @startTime = @endTime = 0
    [@title, @invalid] = ['## No data from Song Switcher ##', true]

class Client extends EventEmitter
  makeSetExtState = (key, value) ->
    "SET/EXTSTATE/#{EXT_SECTION}/#{key}/#{encodeURIComponent value}"

  constructor: (timer) ->
    @data = {}
    (fetch_loop = =>
      @send ''
      setTimeout fetch_loop, timer
    )()

  play: ->
    @send 40044 # Transport: Play/stop
    return

  relativeMove: (move) ->
    @send makeSetExtState(EXT_REL_MOVE, move)
    return

  setFilter: (filter) ->
    @send makeSetExtState(EXT_FILTER, filter)
    return
  
  seek: (time) ->
    @send "SET/POS/#{time}"
    return

  send: (cmd) ->
    req = new XMLHttpRequest
    req.onreadystatechange = =>
      if(req.readyState == XMLHttpRequest.DONE)
        if req.status == 200
          @parse req.responseText
        else
          @reset()
    req.open 'GET', "/_/#{cmd};#{CMD_UPDATE}", true
    req.send null
    return

  reset: ->
    @editData (set) ->
      set 'playState', false
      set 'position', 0
      set 'state', new State
    return

  parse: (response) ->
    @editData (set) ->
      for l in response.split('\n')
        tok = l.split '\t'

        switch tok[0]
          when 'TRANSPORT'
            set 'playState', tok[1] != '0'
            set 'position', parseFloat(tok[2])
          when 'EXTSTATE'
            if tok[1] == EXT_SECTION && tok[2] == EXT_STATE
              set 'state', if tok[3].length
                new State simple_unescape(tok[3]).split('\t')
              else
                new State
    return

  editData: (cb) ->
    modified = []
    cb (key, value) =>
      unless equal @data[key], value
        @data[key] = value
        modified.push key
    @emit "#{key}Changed", @data[key] for key in modified
    return

module.exports = Client
