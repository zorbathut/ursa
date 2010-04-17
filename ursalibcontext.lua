
local lib = ursa.lib

local ul = {}
ursalibcontext = ul

-- it may seem like we should be chdir'ing when things are pushed or popped, but we actually live "natively" in the root directory. We only chdir when we need to.
local context_base = {prefix = "", absolute = lib.getcwd()}
local context_top = {current = context_base}
function ul.context_stack_push(chunk)
  --print("pushing stack", chunk.prefix, chunk.absolute)
  context_top = {current = chunk, up = context_top}
end
function ul.context_stack_pop(chunk)
  --print("popping stack")
  assert(context_top.current == chunk)
  context_top = context_top.up
end
function ul.context_stack_prefix()
  if context_top.current.prefix == "" then return "" end
  return context_top.current.prefix .. "/"
end
function ul.context_stack_chdir(func, ...)
  local cops = lib.getcwd()
  lib.chdir(context_top.current.absolute)
  current_print_prefix = context_top.current.prefix
  --print("CHDIR INTO", context_stack[#context_stack].absolute)
  local rp = lib.return_pack(func(...))
  current_print_prefix = ""
  --print("CHDIR EXIT")
  lib.chdir(cops)
  return lib.return_unpack(rp)
end
function ul.context_stack_chdir_native(...)
  ul.context_stack_push(context_base)
  local rp = lib.return_pack(ul.context_stack_chdir(...))
  ul.context_stack_pop(context_base)
  return lib.return_unpack(rp)
end
function ul.context_stack_get()
  return context_top.current
end

function ul.context_stack_snapshot_get()
  return context_top
end
function ul.context_stack_snapshot_put(top)
  context_top = top
end