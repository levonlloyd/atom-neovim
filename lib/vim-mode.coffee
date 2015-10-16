os = require 'os'
{Disposable, CompositeDisposable} = require 'event-kit'
#VimState = require './vim-state'
KeyObserver = require './vim-key-observer'
{NeoVimSession} = require './vim-session'
VimRedraw = require './vim-redraw'
RemoteVim = require './vim-remote-vim'
VimPaneChanger = require './vim-pane-changer'
EventHandler = require './vim-event-handler'
AtomState = require './atom-state'

# TODO(levon): remove these constants and generate them on startup
if os.platform() is 'win32'
  CONNECT_TO = '\\\\.\\pipe\\neovim'
else
  CONNECT_TO = '/tmp/neovim/neovim'

module.exports =

  activate: ->

    @disposables = new CompositeDisposable
    session = new NeoVimSession(CONNECT_TO)
    message = ['ui_attach',[100,53,true]]
    session.sendMessage(message).then
    remoteVim = new RemoteVim(session)
    #@paneChanger = new VimPaneChanger(remoteVim)

    @disposables.add atom.workspace.observeTextEditors (editor) =>

      console.log 'uri:',editor.getURI()
      editorView = atom.views.getView(editor)

      if editorView
        console.log 'view:',editorView
        editorView.classList.add('vim-mode')
        atomState = new AtomState()
        @eventHandler = new EventHandler(editorView.getModel(), atomState)
        session.subscribe(@eventHandler)
        keyObserver =  new KeyObserver(editorView, remoteVim)
        #editorView.vimState = new VimState(editorView)
        #redrawer = new VimRedraw(session)
        #redrawer.redraw()
        #interval_sync = setInterval ( -> redrawer.redraw()), 150

        atom.commands.add 'atom-text-editor', 'core:save', (e) ->
          e.preventDefault()
          e.stopPropagation()
          vimSaveFile(session)

        filename = atom.workspace.getActiveTextEditor().getURI()


  deactivate: ->

    atom.workspaceView?.eachEditorView (editorView) ->
      editorView.off('.vim-mode')

    @disposables.dispose()
    @paneChanger.destroy()

