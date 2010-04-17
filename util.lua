
local lib, print, print_status = ursa.gen.lib, ursa.gen.print, ursa.gen.print_status

function ursa.util.system(tex)
  local chunk = unpack(tex)
  print_status(chunk)
  --print("us in")
  local str, rv = lib.system(chunk)
  --print("us out")
  assert(rv == 0, "Execution failed")
  str = str:match("^%s*(.-)%s*$")
  assert(str)
  return str
end

-- turns out this is a surprisingly subtle function, though this really, really shouldn't be surprising anyone
function ursa.util.token_deferred(chunk)
  assert(chunk[1])
  
  local ab = ursa.absolute_from{"#" .. chunk[1]}
  assert(type(ab) == "string")
  assert(ab:sub(1, 2) == "#@")
  
  local cdep = {}
  for k, v in pairs(chunk) do
    cdep[k] = v
  end
  cdep[1] = ab
  
  local func = function ()
    return ursa.token(cdep)
  end
  if chunk.default then
    return func
  else
    return {ab, func}
  end
end

function ursa.util.clean()
  for k in ursa.FRAGILE.list{} do
    if k:sub(1, 1) == '#' then
      print_status("clearing " .. k)
      ursa.FRAGILE.token_clear{k:sub(2)}
    else
      print_status("removing " .. k)
      os.remove(k)
    end
  end
end

function ursa.util.system_template(st)
  local str = unpack(st)
  
  local tokz = {}
  
  for tok in str:gmatch("(#[%w_]+)") do
    table.insert(tokz, tok)
  end
  if #tokz == 0 then tokz = nil end
  
  return {run = function(dests, deps)
    if str:find("$TARGET") and not str:find("$TARGETS") then assert(#dests == 1) end
    if str:find("$SOURCE") and not str:find("$SOURCES") then assert(#deps == 1) end
    
    local outdeps = {}
    for _, v in pairs(deps) do
      if v:sub(1, 1) ~= "#" then
        table.insert(outdeps, v)
      end
    end
    
    local stpass = str
    --print(str)
    str = str:gsub("$TARGETS", ursa.FRAGILE.parenthesize(dests))
    str = str:gsub("$TARGET", ursa.FRAGILE.parenthesize(dests and dests[1]))
    str = str:gsub("$SOURCES", ursa.FRAGILE.parenthesize(outdeps))
    str = str:gsub("$SOURCE", ursa.FRAGILE.parenthesize(deps and deps[1]))
    --print(str)
    str = str:gsub("#([%w_]+)", function (param) return ursa.token{param} end)
    
    return ursa.util.system{str}
  end, depends = {"!" .. str, tokz}}
end

function ursa.util.copy()
  return function(dests, deps)
    assert(#dests == 1)
    assert(#deps == 1)
    
    print("Copying", deps[1], dests[1])
    
    local i = io.open(deps[1], "rb")
    local o = io.open(dests[1], "wb")
    
    local size = 2^15
    while true do
      local block = i:read(size)
      if not block then break end
      o:write(block)
    end
    
    i:close()
    o:close()
    
    lib.chmod_set(dests[1], lib.chmod_get(deps[1]))
  end
  --return ursa.util.system_template{"cp $SOURCE $TARGET"}  -- this may be reimplemented later
end

local params = {
  system = {1},
  token_deferred = {1, default = true},
  system_template = {1},
  clean = {0}, -- I'm actually not sure how this even works
  copy = {0},
}

ursa.gen.wrap_funcs(ursa.util, params)
