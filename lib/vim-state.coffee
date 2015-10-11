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
KeyObserver = require './vim-key-observer'

DEBUG = false

screen_f = []
# These need to be accessible from event handler
screen = []  # currently visible screen I think 
scrolled = false #whether scrolled (scrollStateDirty?)
editor_views = {} # map from file names to editorViews

element = document.createElement("item-view")

# TODO(levon): get rid of VimGlobals
VimGlobals.session = new VimSession(CONNECT_TO)

lineSpacing = ->
  lineheight = parseFloat(atom.config.get('editor.lineHeight'))
  fontsize = parseFloat(atom.config.get('editor.fontSize'))
  return Math.floor(lineheight * fontsize)

module.exports =
class VimState
  editor: null
  mode: null
  keyObserver: null

  constructor: (@editorView) ->
    @editor = @editorView.getModel()
    editor_views[@editor.getURI()] = @editorView
    @editorView.component.setInputEnabled(false)
    @mode = 'command'
    @scrolled_down = false # which direction the scroll is
    VimGlobals.tlnumber = 0
    @status_bar = [] # things to go in the status bar
    @location = [] #cursor location

    if not VimGlobals.current_editor
      VimGlobals.current_editor = @editor
    @changeModeClass('command-mode')
    @activateCommandMode()

    # TODO(levon) figure out how this works!!
    atom.packages.onDidActivatePackage(  ->
      element.innerHTML = ''
      @statusbar =
        document.querySelector('status-bar').addLeftTile(item:element,
        priority:10 )
    )

    @keyObserver = new KeyObserver(@editorView)
    @afterOpen()

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

      # looks like this loop is responsible for  putting things on screen
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

  # TODO(levon): move this to vim-mode as part of initialization
  neovim_subscribe: =>
    #rows = @editor.getScreenLineCount()
    @location = [0,0]
    @status_bar = (' ' for ux in [1..eventHandler.cols])
    screen = ((' ' for ux in [1..eventHandler.cols])  for uy in [1..eventHandler.rows-1])

  updateStatusBarWithText:(text, addcursor, loc) ->
    if addcursor
      text = text[0..loc-1].concat('&#9632').concat(text[loc+1..])
    text = text.split(' ').join('&nbsp;')
    q = '<samp>'
    qend = '</samp>'
    element.innerHTML = q.concat(text).concat(qend)

