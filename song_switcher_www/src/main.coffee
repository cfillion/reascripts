Client = require './client'
Timeline = require './timeline'

class SongSwitcherWWW
  constructor: ->
    @client = new Client 1000

    @timeline = new Timeline document.getElementById('timeline')
    @ctrlBar  = document.getElementById 'controls'
    @prevBtn  = document.getElementById 'prev'
    @nextBtn  = document.getElementById 'next'
    @playBtn  = document.getElementById 'play'
    @songBox  = document.getElementById 'song_box'
    @songName = document.getElementById 'title'
    @filter   = document.getElementById 'filter'

    @client.on 'playStateChanged', (playing) =>
      @setClass @playBtn, 'active', playing
    @client.on 'stateChanged', (state) =>
      @setVisible @prevBtn, state.currentIndex > 1
      @setVisible @nextBtn, state.currentIndex < state.songCount
      @setClass @ctrlBar, 'invalid', state.invalid
      @setText @songName, state.title || '## No Song Selected ##'
      @timeline.update @client.data
    @client.on 'positionChanged', =>
      @timeline.update @client.data
    @timeline.on 'seek', (time) =>
      @client.seek time
    @playBtn.addEventListener 'click', => @client.play()
    @prevBtn.addEventListener 'click', => @client.relativeMove -1
    @nextBtn.addEventListener 'click', => @client.relativeMove 1
    @songName.addEventListener 'click', =>
      @setClass @songBox, 'edit', true
      @filter.focus()
    @filter.addEventListener 'blur', => @closeFilter()
    @filter.addEventListener 'keypress', (e) =>
      if e.keyCode == 8 && !@filter.value.length
        @closeFilter()
      else if(e.keyCode != 13)
        return

      if(@filter.value.length > 0)
        @client.setFilter @filter.value

      @closeFilter()
    window.addEventListener 'resize', => @timeline.update @client.data

  setText: (node, text) ->
    if(textNode = node.lastChild)
      textNode.nodeValue = text
    else
      node.appendChild document.createTextNode(text)

  setClass: (node, klass, enable) ->
    if(enable)
      node.classList.add klass
    else
      node.classList.remove klass

  setVisible: (node, visible) ->
    @setClass node, 'hidden', !visible

  closeFilter: ->
    @setClass @songBox, 'edit', false
    @filter.value = ''
    document.activeElement.blur() # close android keyboard

module.exports = SongSwitcherWWW
