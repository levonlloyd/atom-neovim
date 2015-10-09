VimGlobals = require './vim-globals'
{Disposable, CompositeDisposable} = require 'event-kit'
# TODO(levon): this belongs in a class
editor_views = {}
module.exports =
class VimPaneChanger
  session: null
  scrollTopChangeSubscription: null
  cursorPositionChangeSubscription: null
  bufferDestroySubscription: null
  scrollTop: null
  disposables: null

  constructor: (@session) ->
    @disposables.add atom.workspace.onDidDestroyPaneItem @destroyPaneItem
    @disposables.add atom.workspace.onDidChangeActivePaneItem @activePaneChanged

  activePaneChanged: () ->
    debugger
    return if VimGlobals.updating

    VimGlobals.updating = true
    VimGlobals.internal_change = true

    #TODO(levon): is this try/catch still relevant?
    try
      VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
      return unless VimGlobals.current_editor
      filename = atom.workspace.getActiveTextEditor().getURI()
      # load the file that atom is looking at in neovim
      @session.sendMessage(['vim_command',['e! '+ filename]],(x) =>
        # update subscriptions
        if @scrollTopChangeSubscription
          @scrollTopChangeSubscription.dispose()
          @disposables.remove(@scrollTopChangeSubscription)
        if @cursorPositionChangeSubscription
          @cursorPositionChangeSubscription.dispose()
          @disposables.remove(@cursorPositionChangeSubscription)

        if @bufferChangeSubscription
          @bufferChangeSubscription.dispose()
          @disposables.remove(@bufferChangeSubscription)

        VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
        if VimGlobals.current_editors

          @cursorPositionChangeSubscription =
            VimGlobals.current_editor.onDidChangeCursorPosition => @cursorPosChanged
          @disposables.add(@cursorPositionChangeSubscription)

          @scrollTopChangeSubscription =
            VimGlobals.current_editor.onDidChangeScrollTop @scrollTopChanged
          @disposables.add(@scrollTopChangeSubscription)

          @bufferChangeSubscription =
            VimGlobals.current_editor.onDidChange((change) => @bufferChangeHandler(change))
          @registerChangeHandler()

        @scrollTop = null
        tlnumber = 0
        # TODO(levon): put this back when vimstat is transitioned
        #editor_views[VimGlobals.current_editor.getURI()].vimState.afterOpen()
      )
    catch err
      console.log err
      console.log 'problem changing panes'

    VimGlobals.internal_change = false
    VimGlobals.updating = false

  #This code registers the change handler. The undo fix is a workaround
  #a bug I was not able to detect what coupled an extra state when
  #I did Cmd-X and then pressed u. Challenge: give me the set of reasons that
  #trigger such situation in the code.
  bufferChangeHandler: (change) ->
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

  cursorPosChanged: (event) ->
    if not VimGlobals.internal_change
      if editor_views[VimGlobals.current_editor.getURI()].classList.contains('is-focused')
        pos = event.newBufferPosition
        r = pos.row + 1
        c = pos.column + 1
        sel = VimGlobals.current_editor.getSelectedBufferRange()
        #console.log 'sel:',sel
        @session.sendMessage(['vim_command',['cal cursor('+r+','+c+')']],
          (() ->
            if not sel.isEmpty()
              VimGlobals.current_editor.setSelectedBufferRange(sel,
                  sel.end.isLessThan(sel.start))
          )
        )

  scrollTopChanged: () ->
    if not VimGlobals.internal_change
      if editor_views[VimGlobals.current_editor.getURI()].classList.contains('is-focused')
        if @scrollTop
          diff = scrolltop - VimGlobals.current_editor.getScrollTop()
          if  diff > 0
            @session.sendMessage(['vim_input',['<ScrollWheelUp>']])
          else
            @session.sendMessage(['vim_input',['<ScrollWheelDown>']])
      else
        sels = VimGlobals.current_editor.getSelectedBufferRanges()
        for sel in sels
          r = sel.start.row + 1
          c = sel.start.column + 1
          #console.log 'sel:',sel
          @session.sendMessage(['vim_command',['cal cursor('+r+','+c+')']],
            (() ->
              if not sel.isEmpty()
                VimGlobals.current_editor.setSelectedBufferRange(sel,
                    sel.end.isLessThan(sel.start))
            )
          )

    @scrollTop = VimGlobals.current_editor.getScrollTop()

  destroyPaneItem: (event) ->
    if event.item
      console.log 'destroying pane, will send command:', event.item
      console.log 'b:', event.item.getURI()
      uri =event.item.getURI()
      @session.sendMessage(['vim_eval',["expand('%:p')"]],
        ((filename) ->
          filename = filename.binarySlice()
          console.log 'filename reported by vim:',filename
          console.log 'current editor uri:',uri
          ncefn =  VimUtils.normalize_filename(uri)
          nfn =  VimUtils.normalize_filename(filename)

          if ncefn and nfn and nfn isnt ncefn
            console.log '-------------------------------',nfn
            console.log '*******************************',ncefn

            @session.sendMessage(['vim_command',['e! '+ncefn]],
              (() ->
                @session.sendMessage(['vim_command',['bd!']])
              )
            )
          else
            @session.sendMessage(['vim_command',['bd!']])
        )
      )
      console.log 'destroyed pane'
  destroy: ->
    @disposables.dispose()
