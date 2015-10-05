_ = require 'underscore-plus'
$ = require  'jquery'
{Point, Range} = require 'atom'
Marker = require 'atom'
net = require 'net'
os = require 'os'
util = require 'util'
EventHandler = require './vim-event-handler'
VimUtils = require './vim-utils'
VimGlobals = require './vim-globals'
VimSync = require './vim-sync'
VimSession = require './vim-session'

if os.platform() is 'win32'
  CONNECT_TO = '\\\\.\\pipe\\neovim'
else
  CONNECT_TO = '/tmp/neovim/neovim'

DEBUG = false

subscriptions = {}
subscriptions['redraw'] = false
screen = []
screen_f = []
scrolled = false
editor_views = {}
active_change = true

scrolltopchange_subscription = undefined
bufferchange_subscription = undefined
bufferchangeend_subscription = undefined
cursorpositionchange_subscription = undefined

buffer_change_subscription = undefined
buffer_destroy_subscription = undefined

scrolltop = undefined

element = document.createElement("item-view")

VimSession.attachToNeoVim(CONNECT_TO)

# TODO(levon): make a class for Session and move all communication there
neovim_send_message = (message,f = undefined) ->
  try
    if message[0] and message[1] and VimGlobals.session
      console.log("MESSAGE 1: " + message[0])
      console.log("MESSAGE 2: " + message[1])
      VimGlobals.session.request(message[0], message[1], (err, res) ->
        if f
          console.log("RES: " + res)
          if typeof(res) is 'number'
            f(util.inspect(res))
          else
            f(res)
      )
  catch err
    console.log 'error in neovim_send_message '+err
    console.log 'm1:',message[0]
    console.log 'm2:',message[1]

#This code registers the change handler. The undo fix is a workaround
#a bug I was not able to detect what coupled an extra state when
#I did Cmd-X and then pressed u. Challenge: give me the set of reasons that
#trigger such situation in the code.

register_change_handler = () ->
  bufferchange_subscription = VimGlobals.current_editor.onDidChange ( (change)  ->

    if not VimGlobals.internal_change and not VimGlobals.updating

      last_text = VimGlobals.current_editor.getText()
      text_list = last_text.split('\n')
      undo_fix =
          not (change.start is 0 and change.end is text_list.length-1 \
                  and change.bufferDelta is 0)


      tln = VimGlobals.tlnumber

      qtop = VimGlobals.current_editor.getScrollTop()
      qbottom = VimGlobals.current_editor.getScrollBottom()

      rows = Math.floor((qbottom - qtop)/lineSpacing()+1)
      valid_loc = not (change.bufferDelta is 0 and \
          change.end-change.start > rows-3)  and (change.start >= tln and \
          change.start < tln+rows-3)


      if undo_fix and valid_loc
        console.log 'change:',change
        console.log 'tln:',tln,'start:',change.start, 'rows:',rows
        console.log '(uri:',VimGlobals.current_editor.getURI(),'start:',change.start
        console.log 'end:',change.end,'delta:',change.bufferDelta,')'

        VimGlobals.lupdates.push({uri: VimGlobals.current_editor.getURI(), \
                text: last_text, start: change.start, end: change.end, \
                delta: change.bufferDelta})

        VimSync.real_update()
  )

#This code is called indirectly by timer and it's sole purpose is to sync the
# number of lines from Neovim -> Atom.

sync_lines = () ->
  debugger
  return if VimGlobals.updating

  if VimGlobals.current_editor
    VimGlobals.internal_change = true
    neovim_send_message(['vim_eval',["line('$')"]], (nLines) ->

      if VimGlobals.current_editor.buffer.getLastRow() < parseInt(nLines)
        nl = parseInt(nLines) - VimGlobals.current_editor.buffer.getLastRow()
        diff = ''
        for i in [0..nl-1]
          diff = diff + '\n'
        append_options = {normalizeLineEndings: true}
        debugger
        VimGlobals.current_editor.buffer.append(diff, append_options)

        neovim_send_message(['vim_command',['redraw!']],
          (() ->
            VimGlobals.internal_change = false
          )
        )
      else if VimGlobals.current_editor.buffer.getLastRow() > parseInt(nLines)
        for i in [parseInt(nLines)..VimGlobals.current_editor.buffer.getLastRow()-1]
          debugger
          VimGlobals.current_editor.buffer.deleteRow(i)

        VimGlobals.internal_change = false
      else
        VimGlobals.internal_change = false

      #This should be done but breaks things:

      #lines = VimGlobals.current_editor.buffer.getLines()
      #pos = 0
      #for item in lines
          #if item.length > 96
              #options =  { normalizeLineEndings: true, undo: 'skip' }
              #VimGlobals.current_editor.buffer.setTextInRange(new Range(
                  #new Point(pos,96),
                  #new Point(pos,item.length)),'',options)
          #pos = pos + 1

    )

# This is directly called by timer and makes sure of a bunch of housekeeping
#functions like, marking the buffer modified, working around some Neovim for
#Windows issues and invoking the code to sync the number of lines.

# TODO(levon): move this to its own file?
ns_redraw_win_end = () ->
  debugger
  VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
  return unless VimGlobals.current_editor

  uri = VimGlobals.current_editor.getURI()
  editor_views[uri] = atom.views.getView(VimGlobals.current_editor)
  return unless editor_views[uri]

  setModifiedOnTabBar(uri)

  if not VimGlobals.updating and not VimGlobals.internal_change
    neovim_send_message(['vim_eval',["expand('%:p')"]], (filename) ->
      filename = filename.binarySlice()

      ncefn =  VimUtils.normalize_filename(uri)
      nfn = VimUtils.normalize_filename(filename)

      # if we are looking a different file from nvim, open nvim's file
      if ncefn and nfn and nfn isnt ncefn
        atom.workspace.open(filename)
      else
        sync_lines()
    )

  # deleting temp files maybe?
  active_change = false
  for texteditor in atom.workspace.getTextEditors()
    turi = texteditor.getURI()
    if turi
      if turi[turi.length-1] is '~'
        texteditor.destroy()

  active_change = true

interval_sync = setInterval ( -> ns_redraw_win_end()), 150

setModifiedOnTabBar = (uri) ->
  # determine the buffer was modified and indicate in the tab bar if it was
  neovim_send_message(['vim_eval',['&modified']], (mod) ->

    q = '.tab-bar .tab [data-path*="'
    q = q.concat(uri)
    q = q.concat('"]')

    tabelement = document.querySelector(q)
    if tabelement
      tabelement = tabelement.parentNode
      if tabelement
        if parseInt(mod) == 1
          if not tabelement.classList.contains('modified')
            tabelement.classList.add('modified')
          tabelement.isModified = true
        else
          if tabelement.classList.contains('modified')
            tabelement.classList.remove('modified')
          tabelement.isModified = false
  )

vim_mode_save_file = () ->
  neovim_send_message(['vim_command',['write']])

cursorPosChanged = (event) ->
  if not VimGlobals.internal_change
    if editor_views[VimGlobals.current_editor.getURI()].classList.contains('is-focused')
      pos = event.newBufferPosition
      r = pos.row + 1
      c = pos.column + 1
      sel = VimGlobals.current_editor.getSelectedBufferRange()
      #console.log 'sel:',sel
      neovim_send_message(['vim_command',['cal cursor('+r+','+c+')']],
        (() ->
          if not sel.isEmpty()
            VimGlobals.current_editor.setSelectedBufferRange(sel,
                sel.end.isLessThan(sel.start))
        )
      )

scrollTopChanged = () ->
  if not VimGlobals.internal_change
    if editor_views[VimGlobals.current_editor.getURI()].classList.contains('is-focused')
      if scrolltop
        diff = scrolltop - VimGlobals.current_editor.getScrollTop()
        if  diff > 0
          neovim_send_message(['vim_input',['<ScrollWheelUp>']])
        else
          neovim_send_message(['vim_input',['<ScrollWheelDown>']])
    else
      sels = VimGlobals.current_editor.getSelectedBufferRanges()
      for sel in sels
        r = sel.start.row + 1
        c = sel.start.column + 1
        #console.log 'sel:',sel
        neovim_send_message(['vim_command',['cal cursor('+r+','+c+')']],
          (() ->
            if not sel.isEmpty()
              VimGlobals.current_editor.setSelectedBufferRange(sel,
                  sel.end.isLessThan(sel.start))
          )
        )

  scrolltop = VimGlobals.current_editor.getScrollTop()

destroyPaneItem = (event) ->
  if event.item
    console.log 'destroying pane, will send command:', event.item
    console.log 'b:', event.item.getURI()
    uri =event.item.getURI()
    neovim_send_message(['vim_eval',["expand('%:p')"]],
      ((filename) ->
        filename = filename.binarySlice()
        console.log 'filename reported by vim:',filename
        console.log 'current editor uri:',uri
        ncefn =  VimUtils.normalize_filename(uri)
        nfn =  VimUtils.normalize_filename(filename)

        if ncefn and nfn and nfn isnt ncefn
          console.log '-------------------------------',nfn
          console.log '*******************************',ncefn

          neovim_send_message(['vim_command',['e! '+ncefn]],
            (() ->
              neovim_send_message(['vim_command',['bd!']])
            )
          )
        else
          neovim_send_message(['vim_command',['bd!']])
      )
    )
    console.log 'destroyed pane'

activePaneChanged = () ->
  if active_change
    if VimGlobals.updating
      return

    VimGlobals.updating = true
    VimGlobals.internal_change = true

    try
      VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
      return unless VimGlobals.current_editor
      filename = atom.workspace.getActiveTextEditor().getURI()
      neovim_send_message(['vim_command',['e! '+ filename]],(x) ->
        if scrolltopchange_subscription
          scrolltopchange_subscription.dispose()
        if cursorpositionchange_subscription
          cursorpositionchange_subscription.dispose()

        VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
        if VimGlobals.current_editor
          scrolltopchange_subscription =
            VimGlobals.current_editor.onDidChangeScrollTop scrollTopChanged

          cursorpositionchange_subscription =
            VimGlobals.current_editor.onDidChangeCursorPosition cursorPosChanged

          if bufferchange_subscription
            bufferchange_subscription.dispose()

          if bufferchangeend_subscription
            bufferchangeend_subscription.dispose()

          register_change_handler()

        scrolltop = undefined
        tlnumber = 0
        editor_views[VimGlobals.current_editor.getURI()].vimState.afterOpen()
      )
    catch err
      console.log err
      console.log 'problem changing panes'

    VimGlobals.internal_change = false
    VimGlobals.updating = false

lineSpacing = ->
  lineheight = parseFloat(atom.config.get('editor.lineHeight'))
  fontsize = parseFloat(atom.config.get('editor.fontSize'))
  return Math.floor(lineheight * fontsize)

module.exports =
class VimState
  editor: null
  mode: null

  constructor: (@editorView) ->
    @editor = @editorView.getModel()
    editor_views[@editor.getURI()] = @editorView
    @editorView.component.setInputEnabled(false)
    @mode = 'command'
    @cursor_visible = true
    @scrolled_down = false
    VimGlobals.tlnumber = 0
    @status_bar = []
    @location = []

    if not VimGlobals.current_editor
      VimGlobals.current_editor = @editor
    @changeModeClass('command-mode')
    @activateCommandMode()

    atom.packages.onDidActivatePackage(  ->
      element.innerHTML = ''
      @statusbar =
        document.querySelector('status-bar').addLeftTile(item:element,
        priority:10 )
    )

    if not buffer_change_subscription
      buffer_change_subscription =
        atom.workspace.onDidChangeActivePaneItem activePaneChanged
    if not buffer_destroy_subscription
      buffer_destroy_subscription =
        atom.workspace.onDidDestroyPaneItem destroyPaneItem

    atom.commands.add 'atom-text-editor', 'core:save', (e) ->
      e.preventDefault()
      e.stopPropagation()
      vim_mode_save_file()

    @editorView.onkeypress = (e) =>
      q1 = @editorView.classList.contains('is-focused')
      q2 = @editorView.classList.contains('autocomplete-active')
      if q1 and not q2
        q =  String.fromCharCode(e.which)
        neovim_send_message(['vim_input',[q]])
        false
      else
        true

    @editorView.onkeydown = (e) =>
      q1 = @editorView.classList.contains('is-focused')
      q2 = @editorView.classList.contains('autocomplete-active')
      if q1 and not q2 and not e.altKey
        translation = @translateCode(e.which, e.shiftKey, e.ctrlKey)
        if translation != ""
          neovim_send_message(['vim_input',[translation]])
          false
      else
        true

    @afterOpen()

  translateCode: (code, shift, control) ->
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

  afterOpen: =>
    if not subscriptions['redraw']
      @neovim_subscribe()

  postprocess: (rows, dirty) ->
    screen_f = []
    for posi in [0..rows-1]
      line = undefined
      if screen[posi] and dirty[posi]
        line = []
        for posj in [0..screen[posi].length-2]
          if screen[posi][posj]=='$' and screen[posi][posj+1]==' ' and
           screen[posi][posj+2]==' '
            break
          line.push screen[posi][posj]
      else
        if screen[posi]
          line = screen[posi]
      screen_f.push line

  redraw_screen:(rows, dirty) =>
    return unless VimGlobals.current_editor

    @postprocess(rows, dirty)
    tlnumberarr = []
    for posi in [0..rows-1]
      try
        pos = parseInt(screen_f[posi][0..3].join(''))
        if not isNaN(pos)
          tlnumberarr.push (  (pos - 1) - posi  )
        else
          tlnumberarr.push -1
      catch err
        tlnumberarr.push -1

    if scrolled and @scrolled_down
      VimGlobals.tlnumber = tlnumberarr[tlnumberarr.length-2]
    else if scrolled and not @scrolled_down
      VimGlobals.tlnumber = tlnumberarr[0]
    else
      VimGlobals.tlnumber = tlnumberarr[0]

    if dirty
      options =  { normalizeLineEndings: true, undo: 'skip' }
      if DEBUG
        initial = 0
      else
        initial = 4

      debugger
      for posi in [0..rows-2]
        if not (tlnumberarr[posi] is -1)
          if (tlnumberarr[posi] + posi == VimGlobals.tlnumber + posi) and dirty[posi]
            qq = screen_f[posi]
            qq = qq[initial..].join('')
            linerange = new Range(new Point(VimGlobals.tlnumber+posi,0),
                                    new Point(VimGlobals.tlnumber + posi, 96))
            VimGlobals.current_editor.buffer.setTextInRange(linerange,
                qq, options)
            dirty[posi] = false

    sbt = @status_bar.join('')
    @updateStatusBarWithText(sbt, (rows - 1 == @location[0]), @location[1])

    if @cursor_visible and @location[0] <= rows - 2
      if not DEBUG
        VimGlobals.current_editor.setCursorBufferPosition(
          new Point(VimGlobals.tlnumber + @location[0],
          @location[1]-4),{autoscroll:true})
      else
        VimGlobals.current_editor.setCursorBufferPosition(
          new Point(VimGlobals.tlnumber + @location[0],
          @location[1]),{autoscroll:true})

    VimGlobals.current_editor.setScrollTop(lineSpacing()*VimGlobals.tlnumber)

  neovim_subscribe: =>
    debugger
    eventHandler = new EventHandler this

    message = ['ui_attach',[eventHandler.cols,eventHandler.rows,true]]
    neovim_send_message(message)

    debugger
    VimGlobals.session.on('notification', eventHandler.handleEvent)
    #rows = @editor.getScreenLineCount()
    @location = [0,0]
    @status_bar = (' ' for ux in [1..eventHandler.cols])
    screen = ((' ' for ux in [1..eventHandler.cols])  for uy in [1..eventHandler.rows-1])

    subscriptions['redraw'] = true

  #Used to enable command mode.
  activateCommandMode: ->
    @mode = 'command'
    @changeModeClass('command-mode')
    @updateStatusBar()

  #Used to enable insert mode.
  activateInsertMode: (transactionStarted = false)->
    @mode = 'insert'
    @changeModeClass('insert-mode')
    @updateStatusBar()

  activateInvisibleMode: (transactionStarted = false)->
    @mode = 'insert'
    @changeModeClass('invisible-mode')
    @updateStatusBar()

  changeModeClass: (targetMode) ->
    if VimGlobals.current_editor
      editorview = editor_views[VimGlobals.current_editor.getURI()]
      if editorview
        for mode in ['command-mode', 'insert-mode', 'visual-mode',
                    'operator-pending-mode', 'invisible-mode']
          if mode is targetMode
            editorview.classList.add(mode)
          else
            editorview.classList.remove(mode)

  updateStatusBarWithText:(text, addcursor, loc) ->
    if addcursor
      text = text[0..loc-1].concat('&#9632').concat(text[loc+1..])
    text = text.split(' ').join('&nbsp;')
    q = '<samp>'
    qend = '</samp>'
    element.innerHTML = q.concat(text).concat(qend)

  updateStatusBar: ->
    element.innerHTML = @mode

