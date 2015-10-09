util = require 'util'
VimGlobals = require './vim-globals'
VimUtils = require './vim-utils'

#This function changes the text between start and end changing the number
#of lines by delta. The change occurs directionaly from Atom -> Neovim.
#There is a bunch of bookkeeping to make sure the change is unidirectional.

neovim_set_text = (text, start, end, delta) ->
  debugger
  lines = text.split('\n')
  lines = lines[0..lines.length-2]
  cpos = VimGlobals.current_editor.getCursorScreenPosition()
  # The following three send calls collectively get the entire buffer from vim.
  # gets the name of the current buffer
  VimGlobals.session.sendMessage(['vim_get_current_buffer',[]],
    ((buf) ->
      # gets the number of lines in the current buffer
      VimGlobals.session.sendMessage(['buffer_line_count',[buf]],
        ((vim_cnt) ->

          # gets all the data for the buffer from vim as an array of lines
          VimGlobals.session.sendMessage(['buffer_get_line_slice', [buf, 0,
                                                          parseInt(vim_cnt),
                                                          true,
                                                          false]],
            ((vim_lines_r) ->
              vim_lines = []
              for line in vim_lines_r
                vim_lines.push line.binarySlice()
              l = []
              pos = 0
              for pos in [0..vim_lines.length + delta - 1]
                item = vim_lines[pos]
                if pos < start
                  if item
                    l.push(item)
                  else
                    l.push('')

                if pos >= start and pos <= end + delta
                  if lines[pos]
                    l.push(lines[pos])
                  else
                    l.push('')

                if pos > end + delta
                  if vim_lines[pos-delta]
                    l.push(vim_lines[pos-delta])
                  else
                    l.push('')

              send_data(buf,l,delta,-delta, cpos.row+1, cpos.column+1)
            )
          )
        )
      )
    )
  )

#This function sends the data and updates the the cursor location. It then
#calls a function to update the state to the syncing from Atom -> Neovim
#stops and the Neovim -> Atom change resumes.

send_data = (buf, l, delta, i, r, c) ->
  j = l.length + i
  lines = []
  l2 = []
  for item in l
    item2 = item.split('\\').join('\\\\')
    item2 = item2.split('"').join('\\"')
    l2.push '"'+item2+'"'

  lines.push('cal setline(1, ['+l2.join()+'])')
  lines.push('redraw!')

  while j > l.length
    lines.push(''+(j)+'d')
    j = j - 1
  lines.push('cal cursor('+r+','+c+')')
  console.log 'lines2',lines
  VimGlobals.internal_change = true
  VimGlobals.session.sendMessage(['vim_command', [lines.join(' | ')]],
                      update_state)

#This function redraws everything and updates the state to re-enable
#Neovim -> Atom syncing.

update_state = () ->
  VimGlobals.updating = false
  VimGlobals.internal_change = true
  VimGlobals.session.sendMessage(['vim_command',['redraw!']],
    (() ->
      VimGlobals.internal_change = false
    )
  )

module.exports =

#This function performs the "real update" from Atom -> Neovim. In case
#of Cmd-X, Cmd-V, etc.

    real_update : () ->
      if not VimGlobals.updating
        VimGlobals.updating = true

        curr_updates = VimGlobals.lupdates.slice(0)

        VimGlobals.lupdates = []
        if curr_updates.length > 0

          for item in curr_updates
            if item.uri is atom.workspace.getActiveTextEditor().getURI()
              neovim_set_text(item.text, item.start, item.end, item.delta)

