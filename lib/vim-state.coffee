_ = require 'underscore-plus'
$ = require  'jquery'
{Point, Range} = require 'atom'
Marker = require 'atom'
net = require 'net'
os = require 'os'
util = require 'util'

Session = require 'msgpack5rpc'

VimUtils = require './vim-utils'
VimGlobals = require './vim-globals'
VimSync = require './vim-sync'

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
interval_sync = setInterval ( -> ns_redraw_win_end()), 150

socket2 = new net.Socket()
socket2.connect(CONNECT_TO)
socket2.on('error', (error) ->
  console.log 'error communicating (send message): ' + error
  socket2.destroy()
)
tmpsession = new Session()
tmpsession.attach(socket2, socket2)

class RBuffer
  constructor:(data) ->
    @data = data

class RWindow
  constructor:(data) ->
    @data = data

class RTabpage
  constructor:(data) ->
    @data = data

types = []
tmpsession.request('vim_get_api_info', [], (err, res) ->
  metadata = res[1]
  constructors = [
    RBuffer
    RWindow
    RTabpage
  ]
  i = 0
  l = constructors.length
  while i < l
    ((constructor) ->
      types.push
        constructor: constructor
        code: metadata.types[constructor.name[1..]].id
        decode: (data) ->
          new constructor(data)
        encode: (obj) ->
          obj.data
      return
    ) constructors[i]
    i++


    tmpsession.detach()
    socket = new net.Socket()
    socket.connect(CONNECT_TO)
    VimGlobals.session = new Session(types)
    VimGlobals.session.attach(socket, socket)
)


neovim_send_message = (message,f = undefined) ->
  try
    debugger
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
    debugger
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

  if VimGlobals.updating
    return

  if VimGlobals.current_editor
    VimGlobals.internal_change = true
    neovim_send_message(['vim_eval',["line('$')"]], (nLines) ->

      if VimGlobals.current_editor.buffer.getLastRow() < parseInt(nLines)
        nl = parseInt(nLines) - VimGlobals.current_editor.buffer.getLastRow()
        diff = ''
        for i in [0..nl-1]
          diff = diff + '\n'
        append_options = {normalizeLineEndings: true}
        VimGlobals.current_editor.buffer.append(diff, append_options)

        neovim_send_message(['vim_command',['redraw!']],
            (() ->
              VimGlobals.internal_change = false
            )
         )
      else if VimGlobals.current_editor.buffer.getLastRow() > parseInt(nLines)
        for i in [parseInt(nLines)..VimGlobals.current_editor.buffer.getLastRow()-1]
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

ns_redraw_win_end = () ->

  VimGlobals.current_editor = atom.workspace.getActiveTextEditor()

  if not VimGlobals.current_editor
    return

  uri = VimGlobals.current_editor.getURI()

  editor_views[uri] = atom.views.getView(VimGlobals.current_editor)

  if not editor_views[uri]
    return

  neovim_send_message(['vim_eval',['&modified']], (mod) ->
    mod = VimUtils.buf2str(mod)

    q = '.tab-bar .tab [data-path*="'
    q = q.concat(uri)
    q = q.concat('"]')
    #console.log q

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

  focused = editor_views[uri].classList.contains('is-focused')

  if not VimGlobals.updating and not VimGlobals.internal_change
    neovim_send_message(['vim_eval',["expand('%:p')"]], (filename) ->
      filename = VimUtils.buf2str(filename)
      #console.log 'filename reported by vim:',filename
      #console.log 'current editor uri:',uri

      ncefn =  VimUtils.normalize_filename(uri)
      nfn = VimUtils.normalize_filename(filename)

      if ncefn and nfn and nfn isnt ncefn
        atom.workspace.open(filename)
      else
        sync_lines()
    )

  active_change = false
  for texteditor in atom.workspace.getTextEditors()
    turi = texteditor.getURI()
    if turi
      if turi[turi.length-1] is '~'
        texteditor.destroy()

  active_change = true

lineSpacing = ->
  lineheight = parseFloat(atom.config.get('editor.lineHeight'))
  fontsize = parseFloat(atom.config.get('editor.fontSize'))
  return Math.floor(lineheight * fontsize)

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
        filename = VimUtils.buf2str(filename)
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
      if VimGlobals.current_editor
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

class EventHandler
  constructor: (@vimState) ->
      qtop = VimGlobals.current_editor.getScrollTop()
      qbottom = VimGlobals.current_editor.getScrollBottom()

      @rows = Math.floor((qbottom - qtop)/lineSpacing()+1)
      #console.log 'rows:', @rows

      height = Math.floor(50+(@rows-0.5) * lineSpacing())

      atom.setWindowDimensions ('width': 1400, 'height': height)
      @cols = 100
      @command_mode = true

  handleEvent: (event, q) =>
    if q.length is 0
      return
    if VimGlobals.updating
      return

    VimGlobals.internal_change = true
    dirty = (false for i in [0..@rows-2])

    if event is "redraw"
      for x in q
        if not x
          continue
        x[0] = VimUtils.buf2str(x[0])
        if x[0] is "cursor_goto"
          for v in x[1..]
            try
              v[0] = util.inspect(v[0])
              v[1] = util.inspect(v[1])
              @vimState.location[0] = parseInt(v[0])
              @vimState.location[1] = parseInt(v[1])
            catch
              console.log 'problem in goto'

        else if x[0] is 'set_scroll_region'
          @screen_top = parseInt(util.inspect(x[1][0]))
          @screen_bot = parseInt(util.inspect(x[1][1]))
          @screen_left = parseInt(util.inspect(x[1][2]))
          @screen_right = parseInt(util.inspect(x[1][3]))

        else if x[0] is "insert_mode"
          @vimState.activateInsertMode()
          @command_mode = false

        else if x[0] is "normal_mode"
          @vimState.activateCommandMode()
          @command_mode = true

        else if x[0] is "bell"
          atom.beep()

        else if x[0] is "cursor_on"
          if @command_mode
            @vimState.activateCommandMode()
          else
            @vimState.activateInsertMode()
          @vimState.cursor_visible = true

        else if x[0] is "cursor_off"
          @vimState.activateInvisibleMode()
          @vimState.cursor_visible = false

        else if x[0] is "scroll"
          for v in x[1..]
            try
              top = @screen_top
              bot = @screen_bot + 1

              left = @screen_left
              right = @screen_right + 1

              count = parseInt(util.inspect(v[0]))
              #console.log 'scrolling:',count
              #tlnumber = tlnumber + count
              if count > 0
                src_top = top+count
                src_bot = bot
                dst_top = top
                dst_bot = bot - count
                clr_top = dst_bot
                clr_bot = src_bot
              else
                src_top = top
                src_bot = bot + count
                dst_top = top - count
                dst_bot = bot
                clr_top = src_top
                clr_bot = dst_top

              top = @screen_top
              bottom = @screen_bot
              left = @screen_left
              right = @screen_right
              if count > 0
                start = top
                stop = bottom - count + 1
                step = 1
              else
                start = bottom
                stop = top - count + 1
                step = -1

              for row in VimUtils.range(start,stop,step)
                dirty[row] = true
                target_row = screen[row]
                source_row = screen[row + count]
                for col in VimUtils.range(left,right+1)
                  target_row[col] = source_row[col]

              for row in  VimUtils.range(stop, stop+count,step)
                for col in  VimUtils.range(left,right+1)
                  screen[row][col] = ' '

              scrolled = true
              if count > 0
                @vimState.scrolled_down = true
              else
                @vimState.scrolled_down = false
            catch
              console.log 'problem scrolling'

        else if x[0] is "put"
          cnt = 0
          for v in x[1..]
            try
              v[0] = VimUtils.buf2str(v[0])
              ly = @vimState.location[0]
              lx = @vimState.location[1]
              if 0<=ly and ly < @rows-1
                qq = v[0]
                screen[ly][lx] = qq[0]
                @vimState.location[1] = lx + 1
                dirty[ly] = true
              else if ly == @rows - 1
                qq = v[0]
                @vimState.status_bar[lx] = qq[0]
                @vimState.location[1] = lx + 1
              else if ly > @rows - 1
                console.log 'over the max'
            catch
              console.log 'problem putting'

        else if x[0] is "clear"
          for posj in [0..@cols-1]
            for posi in [0..@rows-2]
              screen[posi][posj] = ' '
              dirty[posi] = true

            @vimState.status_bar[posj] = ' '

        else if x[0] is "eol_clear"
          ly = @vimState.location[0]
          lx = @vimState.location[1]
          if ly < @rows - 1
            for posj in [lx..@cols-1]
              for posi in [ly..ly]
                if posj >= 0
                  dirty[posi] = true
                  screen[posi][posj] = ' '

          else if ly == @rows - 1
            for posj in [lx..@cols-1]
              @vimState.status_bar[posj] = ' '
          else if ly > @rows - 1
            console.log 'over the max'

    @vimState.redraw_screen(@rows, dirty)

    if scrolled
      neovim_send_message(['vim_command',['redraw!']],
        (() ->
          scrolled = false
          options =  { normalizeLineEndings: true, undo: 'skip' }
          if VimGlobals.current_editor
            VimGlobals.current_editor.buffer.setTextInRange(new Range(
              new Point(VimGlobals.current_editor.buffer.getLastRow(),0),
              new Point(VimGlobals.current_editor.buffer.getLastRow(),96)),'',
              options)

          VimGlobals.internal_change = false
        )
      )
    else
      options =  { normalizeLineEndings: true, undo: 'skip' }
      if VimGlobals.current_editor
        VimGlobals.current_editor.buffer.setTextInRange(new Range(
          new Point(VimGlobals.current_editor.buffer.getLastRow(),0),
          new Point(VimGlobals.current_editor.buffer.getLastRow(),96)),'',
          options)

      VimGlobals.internal_change = false

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

  # This looks unnecessary
  destroy_sockets:(editor) =>
    if subscriptions['redraw']
      if editor.getURI() != @editor.getURI()
        console.log 'unsubscribing'

  afterOpen: =>
    neovim_send_message(['vim_command',['set scrolloff=2']])
    neovim_send_message(['vim_command',['set nocompatible']])
    neovim_send_message(['vim_command',['set noswapfile']])
    neovim_send_message(['vim_command',['set nowrap']])
    neovim_send_message(['vim_command',['set nu']])
    neovim_send_message(['vim_command',['set autochdir']])
    neovim_send_message(['vim_command',['set autoindent']])
    neovim_send_message(['vim_command',['set smartindent']])
    neovim_send_message(['vim_command',['set hlsearch']])
    neovim_send_message(['vim_command',['set tabstop=4']])
    neovim_send_message(['vim_command',['set shiftwidth=4']])
    neovim_send_message(['vim_command',['set expandtab']])
    neovim_send_message(['vim_command',['set hidden']])
    neovim_send_message(['vim_command',['set list']])
    neovim_send_message(['vim_command',['set wildmenu']])
    neovim_send_message(['vim_command',['set showcmd']])
    neovim_send_message(['vim_command',['set incsearch']])
    neovim_send_message(['vim_command',['set autoread']])
    neovim_send_message(['vim_command',
      ['set backspace=indent,eol,start']])

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
    if VimGlobals.current_editor
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
    eventHandler = new EventHandler this

    message = ['ui_attach',[eventHandler.cols,eventHandler.rows,true]]
    neovim_send_message(message)

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

