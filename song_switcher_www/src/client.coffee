EXT_SECTION = 'cfillion_song_switcher'
EXT_STATE = 'state'
EXT_REL_MOVE = 'relative_move'
EXT_FILTER = 'filter'
CMD_UPDATE = 'TRANSPORT;GET/EXTSTATE/' + EXT_SECTION + '/' + EXT_STATE

EventEmitter = require './event_emitter'
equal = require 'deep-equal'

class State
  constructor: (data) ->
    if data then @unpack(data) else @fallback()

  unpack: (data) ->
    @currentIndex = parseInt(data[0])
    @songCount = parseInt(data[1])
    @title = data[2]
    @invalid = data[3] == 'true'

  fallback: ->
    [@currentIndex, @songCount, @invalid] = [0, 0, true]
    @title = '## No data from Song Switcher ##'

class Client extends EventEmitter
  makeSetExtState = (key, value) ->
    "SET/EXTSTATE/#{EXT_SECTION}/#{key}/#{encodeURIComponent value}"

  constructor: (timer) ->
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
    @set 'playState', false
    @set 'position', 0
    @set 'state', new State
    return

  parse: (response) ->
    for l in response.split('\n')
      tok = l.split '\t'

      switch tok[0]
        when 'TRANSPORT'
          @set 'playState', tok[1] != '0'
          @set 'position', parseFloat(tok[2])
        when 'EXTSTATE'
          if tok[1] == EXT_SECTION && tok[2] == EXT_STATE
            @set 'state', if tok[3].length
              new State simple_unescape(tok[3]).split('\t')
            else
              new State
    return

  set: (key, value) ->
    @emit "#{key}Changed", this[key] = value unless equal(this[key], value)
    return

module.exports = Client
