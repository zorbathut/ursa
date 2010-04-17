
local lib = ursa.lib

local ul = {}
ursalibcontext = ul

-- it may seem like we should be chdir'ing when things are pushed or popped, but we actually live "natively" in the root directory. We only chdir when we need to.
local context_stack = {{prefix = "", absolute = lib.getcwd()}}
function ul.context_stack_push(chunk)
  --print("pushing stack", chunk.prefix, chunk.absolute)
  table.insert(context_stack, chunk)
end
function ul.context_stack_pop(chunk)
  --print("popping stack")
  assert(context_stack[#context_stack] == chunk)
  table.remove(context_stack)
end
function ul.context_stack_prefix()
  if context_stack[#context_stack].prefix == "" then return "" end
  return context_stack[#context_stack].prefix .. "/"
end
function ul.context_stack_chdir(func, ...)
  local cops = lib.getcwd()
  lib.chdir(context_stack[#context_stack].absolute)
  current_print_prefix = context_stack[#context_stack].prefix
  --print("CHDIR INTO", context_stack[#context_stack].absolute)
  local rp = lib.return_pack(func(...))
  current_print_prefix = ""
  --print("CHDIR EXIT")
  lib.chdir(cops)
  return lib.return_unpack(rp)
end
function ul.context_stack_chdir_native(...)
  ul.context_stack_push(context_stack[1])
  local rp = lib.return_pack(ul.context_stack_chdir(...))
  ul.context_stack_pop(context_stack[1])
  return lib.return_unpack(rp)
end
function ul.context_stack_get()
  return context_stack[#context_stack]
end
