VimGlobals = require './vim-globals'
KeymapManager = require('atom-keymap')

translateCode = (code, shift, control) ->
  if control && code>=65 && code<=90
    String.fromCharCode(code-64)
  else if code>=8 && code<=10 || code==13 || code==27
    String.fromCharCode(code)
  else if code==35
    '<End>'
  else if code==36
    '<Home>'
  else if code==33
    '<PageUp>'
  else if code==34
    '<PageDown>'
  else if code==37
    '<left>'
  else if code==38
    '<up>'
  else if code==39
    '<right>'
  else if code==40
    '<down>'
  else if code==188 and shift
    '<lt>'
  else
    ""

module.exports =
class KeyObserver
  editorView: null
  counter: 0

  constructor: (@editorView) ->
    # ultimately I think this should be document, not view.  We'll see
    # This should be global and direct key events to the appropriate buffer
    editorView.addEventListener('keydown', (event) =>
      @handleKeyboardEvent(event)
    )

  # TODO(levon): investigate preventDefault vs stopPropagation
  # V1 will just read the state of ctrl, alt, meta from the event
  handleKeyboardEvent: (event) ->
    console.log(event)
    if event.altKey
      @modifierKeys.alt = true
      event.stopPropagation()
      return
    else if event.ctrlKey
      @modifierKeys.ctrl = true
      event.stopPropagation()
      return
    else if event.metaKey
      @modifierKeys.cmd = true
      event.stopPropagation()
      return
    event.stopPropagation()
    @counter += 1
    #debugger

  sendSpecialCharacter: (e) ->
    debugger
    q1 = @editorView.classList.contains('is-focused')
    q2 = @editorView.classList.contains('autocomplete-active')
    if q1 and not q2 and not e.altKey
      translation = translateCode(e.which, e.shiftKey, e.ctrlKey)
      if translation != ""
        VimGlobals.session.sendMessage(['vim_input',[translation]])
        false
    else
      true

  sendKeyPress: (e) ->
    debugger
    q1 = @editorView.classList.contains('is-focused')
    q2 = @editorView.classList.contains('autocomplete-active')
    if q1 and not q2
      q =  String.fromCharCode(e.which)
      VimGlobals.session.sendMessage(['vim_input',[q]])
      false
    else
      true

