_ = require 'underscore-plus'
net = require 'net'
Session = require 'msgpack5rpc'
VimGlobals = require './vim-globals'

class RBuffer
  constructor:(data) ->
    @data = data

class RWindow
  constructor:(data) ->
    @data = data

class RTabpage
  constructor:(data) ->
    @data = data

module.exports =

# TODO(levon): extract the VimGlobals from here
# probably by making this a class that handles all communication with neovim
attachToNeoVim: (connectTo)->
  socket2 = new net.Socket()
  socket2.connect(connectTo)
  socket2.on('error', (error) ->
    console.log 'error communicating (send message): ' + error
    socket2.destroy()
  )
  tmpsession = new Session()
  tmpsession.attach(socket2, socket2)
  types = []
  tmpsession.request('vim_get_api_info', [], (err, res) ->
    metadata = res[1]
    console.log(metadata)
    _.each([RBuffer, RWindow, RTabpage],
      ((constructor) ->
        types.push
          constructor: constructor
          code: metadata.types[constructor.name[1..]].id
          decode: (data) ->
            new constructor(data)
          encode: (obj) ->
            obj.data
      )
    )

    tmpsession.detach()
    socket = new net.Socket()
    socket.connect(connectTo)
    VimGlobals.session = new Session(types)
    VimGlobals.session.attach(socket, socket)
  )
