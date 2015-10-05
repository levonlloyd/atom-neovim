_ = require 'underscore-plus'

module.exports =
    normalize_filename: (filename) ->
      if filename
        filename = filename.split('\\').join('/')
      return filename

    buf2str: (buffer) ->
      #_.map(buffer, String.fromCharCode).join('')
      if not buffer
          return ''
      res = ''
      i = 0
      while i < buffer.length
        res = res + String.fromCharCode(buffer[i])
        i++
      res

