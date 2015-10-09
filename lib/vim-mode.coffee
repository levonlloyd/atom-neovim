os = require 'os'
{Disposable, CompositeDisposable} = require 'event-kit'
#VimState = require './vim-state'
KeyObserver = require './vim-key-observer'
{NeoVimSession} = require './vim-session'
VimRedraw = require './vim-redraw'
VimPaneChanger = require './vim-pane-changer'

# TODO(levon): remove these constants and generate them on startup
if os.platform() is 'win32'
  CONNECT_TO = '\\\\.\\pipe\\neovim'
else
  CONNECT_TO = '/tmp/neovim/neovim'

vimSaveFile = (session) ->
  session.sendMessage(['vim_command',['write']])

module.exports =

  activate: ->

    @disposables = new CompositeDisposable

    @disposables.add atom.workspace.observeTextEditors (editor) =>

      console.log 'uri:',editor.getURI()
      editorView = atom.views.getView(editor)

      if editorView
        console.log 'view:',editorView
        editorView.classList.add('vim-mode')
        #keyObserver =  new KeyObserver(editorView)
        session = new NeoVimSession(CONNECT_TO)
        #editorView.vimState = new VimState(editorView)
        #redrawer = new VimRedraw(session)
        #redrawer.redraw()
        #interval_sync = setInterval ( -> redrawer.redraw()), 150

        atom.commands.add 'atom-text-editor', 'core:save', (e) ->
          e.preventDefault()
          e.stopPropagation()
          vimSaveFile(session)

        filename = atom.workspace.getActiveTextEditor().getURI()
        session.sendMessage(['vim_command',['e! '+ filename]],(x) =>
          debugger
          session.sendMessage(['vim_get_current_buffer',[]],
            ((buf) ->
              debugger
              session.sendMessage(['buffer_line_count',[buf]],
                ((vim_cnt) ->
                  debugger
                  session.sendMessage(['buffer_get_line_slice', [buf, 0,
                                                                  parseInt(vim_cnt),
                                                                  true,
                                                                  false]],
                                                                  (vim_lines_r) ->
                                                                    debugger
                  ))))))
        @paneChanger = new VimPaneChanger(session)


  deactivate: ->

    atom.workspaceView?.eachEditorView (editorView) ->
      editorView.off('.vim-mode')

    @disposables.dispose()
    @paneChanger.destroy()

