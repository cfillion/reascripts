Client = require './client'
Timeline = require './timeline'

class SongSwitcherWWW
  constructor: ->
    @_client = new Client 1000

    @_setClass document.body, 'js'

    @_timeline = new Timeline document.getElementById('timeline')
    @_ctrlBar  = document.getElementById 'controls'
    @_prevBtn  = document.getElementById 'prev'
    @_nextBtn  = document.getElementById 'next'
    @_playBtn  = document.getElementById 'play'
    @_panicBtn = document.getElementById 'panic'
    @_resetBtn = document.getElementById 'reset'
    @_songBox  = document.getElementById 'song_box'
    @_songName = document.getElementById 'title'
    @_filter   = document.getElementById 'filter'

    @_client.on 'playStateChanged', (playing) =>
      @_setClass @_playBtn, 'active', playing
    @_client.on 'stateChanged', (state) =>
      @_setVisible @_prevBtn, state.currentIndex > 1
      @_setVisible @_nextBtn, state.currentIndex < state.songCount
      @_setClass @_ctrlBar, 'invalid', state.invalid
      @_setText @_songName, state.title || '## No Song Selected ##'
      @_timeline.update @_client.data
    @_client.on 'positionChanged', => @_timeline.update @_client.data
    @_client.on 'markerListChanged', => @_timeline.update @_client.data

    @_timeline.on 'seek', (time) => @_client.seek time

    @_prevBtn.addEventListener 'click', => @_client.relativeMove -1
    @_nextBtn.addEventListener 'click', => @_client.relativeMove 1
    @_playBtn.addEventListener 'click', => @_client.play()
    @_panicBtn.addEventListener 'click', => @_client.panic()
    @_resetBtn.addEventListener 'click', => @_client.reset()
    @_songName.addEventListener 'click', =>
      @_setClass @_songBox, 'edit', true
      @_filter.focus()
    @_filter.addEventListener 'blur', => @_closeFilter()
    @_filter.addEventListener 'keypress', (e) =>
      if e.keyCode == 8 && !@_filter.value.length
        @_closeFilter()
      else if(e.keyCode != 13)
        return

      if(@_filter.value.length > 0)
        @_client.setFilter @_filter.value

      @_closeFilter()

    window.addEventListener 'resize', => @_timeline.update @_client.data
    window.addEventListener 'keydown', (e) =>
      @_client.play() if e.keyCode == 32 && e.target == document.body

  _setText: (node, text) ->
    if(textNode = node.lastChild)
      textNode.nodeValue = text
    else
      node.appendChild document.createTextNode(text)

  _setClass: (node, klass, enable = true) ->
    if(enable)
      node.classList.add klass
    else
      node.classList.remove klass

  _setVisible: (node, visible) ->
    @_setClass node, 'hidden', !visible

  _closeFilter: ->
    @_setClass @_songBox, 'edit', false
    @_filter.value = ''
    document.activeElement.blur() # close android keyboard

module.exports = SongSwitcherWWW
