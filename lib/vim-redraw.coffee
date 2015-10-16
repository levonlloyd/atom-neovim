VimGlobals = require './vim-globals'

# TODO(levon): this should be a field of VimState (or something like that)
editor_views = {}

module.exports =
class VimRedraw
  session: null

  constructor: (@remoteVim) ->

  # This is directly called by timer and makes sure of a bunch of housekeeping
  #functions like, marking the buffer modified, working around some Neovim for
  #Windows issues and invoking the code to sync the number of lines.
  redraw: ->
    VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
    return unless VimGlobals.current_editor

    uri = VimGlobals.current_editor.getURI()
    editor_views[uri] = atom.views.getView(VimGlobals.current_editor)
    return unless editor_views[uri]

    @setModifiedOnTabBar(uri)

    if not VimGlobals.updating and not VimGlobals.internal_change
      @remoteVim.getCurrentFilename().then (filename) ->
        filename = filename.binarySlice()

        ncefn =  VimUtils.normalize_filename(uri)
        nfn = VimUtils.normalize_filename(filename)

        # if we are looking a different file from nvim, open nvim's file
        if ncefn and nfn and nfn isnt ncefn
          atom.workspace.open(filename)
        else
          @syncLines()

    if not VimGlobals.internal_change
      if editor_views[VimGlobals.current_editor.getURI()].classList.contains('is-focused')
        @remoteVim.moveCursorWithSelection(
          pos.row, pos.column, VimGlobals.current_editor)

    # deleting temp files maybe?
    active_change = false
    for texteditor in atom.workspace.getTextEditors()
      turi = texteditor.getURI()
      if turi
        if turi[turi.length-1] is '~'
          texteditor.destroy()

    active_change = true

  #This code is called indirectly by timer and it's sole purpose is to sync the
  # number of lines from Neovim -> Atom.
  syncLines: () ->
    return if VimGlobals.updating

    if VimGlobals.current_editor
      VimGlobals.internal_change = true

      @remoteVim.getCurrentBufferLineCount().then (nLines) ->
        if VimGlobals.current_editor.buffer.getLastRow() < parseInt(nLines)
          nl = parseInt(nLines) - VimGlobals.current_editor.buffer.getLastRow()
          diff = ''
          for i in [0..nl-1]
            diff = diff + '\n'
          append_options = {normalizeLineEndings: true}
          VimGlobals.current_editor.buffer.append(diff, append_options)

          @remoteVim.redraw().then ->
              VimGlobals.internal_change = false

        else if VimGlobals.current_editor.buffer.getLastRow() > nLines
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

  setModifiedOnTabBar: (uri) ->
    # determine the buffer was modified and indicate in the tab bar if it was
    @remoteVim.bufferHasBeenModified().then( (modified) ->

      q = '.tab-bar .tab [data-path*="'
      q = q.concat(uri)
      q = q.concat('"]')

      tabelement = document.querySelector(q)
      if tabelement
        tabelement = tabelement.parentNode
        if tabelement
          if modified
            if not tabelement.classList.contains('modified')
              tabelement.classList.add('modified')
            tabelement.isModified = true
          else
            if tabelement.classList.contains('modified')
              tabelement.classList.remove('modified')
            tabelement.isModified = false
    )
