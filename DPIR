--[[
Pushes dynamic PIR triggers via internal sockets.

Tag required objects with the "DPIR" keyword and this script will run whenever one of those objects change.
--]]

logging = false

-- Send an event that a dynamic PIR triggered
if event.getvalue() ~= 0 then
  require('socket').udp():sendto(event.dst, '127.0.0.1', 5431)
  if logging then log('Trigger message for '..event.dst) end
end
