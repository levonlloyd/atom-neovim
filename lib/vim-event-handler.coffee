_ = require 'underscore-plus'
VimGlobals = require './vim-globals'

# TODO(levon): tests & put this in 1 place
lineSpacing = ->
  lineheight = parseFloat(atom.config.get('editor.lineHeight'))
  fontsize = parseFloat(atom.config.get('editor.fontSize'))
  return Math.floor(lineheight * fontsize)

module.exports =
#TODO(levon): test this :)
class EventHandler
  constructor: (@vimState) ->
    qtop = VimGlobals.current_editor.getScrollTop()
    qbottom = VimGlobals.current_editor.getScrollBottom()

    @rows = Math.floor((qbottom - qtop)/lineSpacing()+1)
    height = Math.floor(50+(@rows-0.5) * lineSpacing())

    atom.setWindowDimensions ('width': 1400, 'height': height)
    @cols = 100
    @command_mode = true

  setScrollRegion: (region) ->
    @screen_top = parseInt(util.inspect(region[0]))
    @screen_bot = parseInt(util.inspect(region[1]))
    @screen_left = parseInt(util.inspect(region[2]))
    @screen_right = parseInt(util.inspect(region[3]))

  gotoCursor: (listOfLocations) ->
    for location in listOfLocations
      try
        location[0] = util.inspect(location[0])
        location[1] = util.inspect(location[1])
        @vimState.location[0] = parseInt(location[0])
        @vimState.location[1] = parseInt(location[1])
      catch
        console.log 'problem in goto'

  # I don't understand what this is trying to do
  scroll: (counts) ->
    for count in counts
      try
        top = @screen_top
        bot = @screen_bot + 1

        left = @screen_left
        right = @screen_right + 1

        count = parseInt(util.inspect(count))
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

        for row in _.range(start,stop,step)
          dirty[row] = true
          target_row = screen[row]
          source_row = screen[row + count]
          for col in _.range(left,right+1)
            target_row[col] = source_row[col]

        for row in  _.range(stop, stop+count,step)
          for col in  _.range(left,right+1)
            screen[row][col] = ' '

        scrolled = true
        if count > 0
          @vimState.scrolled_down = true
        else
          @vimState.scrolled_down = false
      catch
        console.log 'problem scrolling'

  # this needs further examination
  putChars: (charsToPut) ->
    debugger
    cnt = 0
    for char in charsToPut
      try
        char = VimUtils.buf2str(char[0])
        ly = @vimState.location[0]
        lx = @vimState.location[1]
        if 0<=ly and ly < @rows-1
          qq = char[0]
          screen[ly][lx] = qq[0]
          @vimState.location[1] = lx + 1
          dirty[ly] = true
        else if ly == @rows - 1
          qq = char[0]
          @vimState.status_bar[lx] = qq[0]
          @vimState.location[1] = lx + 1
        else if ly > @rows - 1
          console.log 'over the max'
      catch
        console.log 'problem putting'

  clear: ->
    for posj in [0..@cols-1]
      for posi in [0..@rows-2]
        screen[posi][posj] = ' '
        dirty[posi] = true
      @vimState.status_bar[posj] = ' '

  eolClear: ->
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

  enterInsertMode: ->
    @vimState.activateInsertMode()
    @command_mode = false

  enterNormalMode: ->
    @vimState.activateCommandMode()
    @command_mode = true

  turnCursorOn: ->
    if @command_mode
      @vimState.activateCommandMode()
    else
      @vimState.activateInsertMode()
    @vimState.cursor_visible = true

  turnCursorOff: ->
    @vimState.activateInvisibleMode()
    @vimState.cursor_visible = false


  # TODO(levon): this needs some love.  refactoring, re-naming
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
        command = x[0].binarySlice()
        args = x[1..]
        switch command
          when "cursor_goto" then @gotoCursor(args)
          when "set_scroll_region" then @setScrollRegion(x[1])
          when "insert_mode" then @enterInsertMode()
          when "normal_mode" then @enterNormalMode()
          when "bell" then atom.beep()
          when "cursor_on" then @turnCursorOn()
          when "cursor_off" then @turnCursorOff()
          when "scroll" then @scroll(args)
          when "put" then @putChars(args)
          when "clear"
            console.log('clear called')
            #clear()
          when "eol_clear" then @eolClear()

    @vimState.redraw_screen(@rows, dirty)

    # I'm not sure what happens down here
    if scrolled
      neovim_send_message(['vim_command',['redraw!']],
        (() ->
          scrolled = false
          debugger
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
        debugger
        VimGlobals.current_editor.buffer.setTextInRange(new Range(
          new Point(VimGlobals.current_editor.buffer.getLastRow(),0),
          new Point(VimGlobals.current_editor.buffer.getLastRow(),96)),'',
          options)

      VimGlobals.internal_change = false


