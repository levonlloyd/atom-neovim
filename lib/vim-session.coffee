_ = require 'underscore-plus'
Q = require 'q'
net = require 'net'
util = require 'util'
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

exports.NeoVimSession =
class NeoVimSession
  session: null

  constructor: (connectTo)->
    socket2 = new net.Socket()
    socket2.connect(connectTo)
    socket2.on('error', (error) ->
      console.log 'error communicating (send message): ' + error
      socket2.destroy()
    )
    tmpsession = new Session()
    tmpsession.attach(socket2, socket2)
    types = []
    deferred = Q.defer()
    tmpsession.request('vim_get_api_info', [], (err, res) ->
      metadata = res[1]
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
      session = new Session(types)
      session.attach(socket, socket)
      deferred.resolve(session)
    )
    @session = deferred.promise

  subscribe: (eventHandler) ->
    @session.then (s) ->
      s.on('notification', eventHandler.handleEvent)

  sendMessage: (message) ->

    # TODO(levon): is the try catch necessary?  seems not
    # TODO(levon): return a future instead of taking a function
    try
      if message[0] and message[1]
        console.log("MESSAGE 1: " + message[0])
        console.log(message[1])
        deferred = Q.defer()
        @session.then (s) ->
          s.request(message[0], message[1], (err, res) ->
            console.log("RES: " + res)
            console.log(err)
            if typeof(res) is 'number'
              deferred.resolve(util.inspect(res))
            else
              deferred.resolve(res)
          )
          return deferred.promise
    catch err
      console.log 'error in neovim_send_message '+err
      console.log 'm1:',message[0]
      console.log 'm2:',message[1]
