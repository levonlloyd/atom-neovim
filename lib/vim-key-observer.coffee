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

  constructor: (@editorView, @remoteVim) ->
    # ultimately I think this should be document, not view.  We'll see
    # This should be global and direct key events to the appropriate buffer
    @editorView.addEventListener('keydown', (event) =>
      @handleKeyboardEvent(event)
    )

  # TODO(levon): investigate preventDefault vs stopPropagation
  # V1 will just read the state of ctrl, alt, meta from the event
  handleKeyboardEvent: (event) ->
    console.log(event)
    if event.altKey
      event.stopPropagation()
      return
    else if event.ctrlKey
      event.stopPropagation()
      return
    else if event.metaKey
      event.stopPropagation()
      return
    event.stopPropagation()
    q =  String.fromCharCode(event.which)
    @remoteVim.typeKey(q)
