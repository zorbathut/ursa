
local ul, print, print_status = ursa.gen.ul, ursa.gen.print, ursa.gen.print_status

function ursa.util.system(tex)
  local chunk = unpack(tex)
  print_status(chunk)
  --print("us in")
  local str, rv = ul.system(chunk)
  --print("us out")
  assert(rv == 0)
  str = str:match("^%s*(.-)%s*$")
  assert(str)
  return str
end

function ursa.util.token_deferred(chunk)
  local func = function () return ursa.token(chunk) end
  if chunk.default then
    return func
  else
    return {"#" .. chunk[1], func}
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
    str = str:gsub("$TARGETS", ursa.FRAGILE.parenthesize(dests))
    str = str:gsub("$TARGET", ursa.FRAGILE.parenthesize(dests and dests[1]))
    str = str:gsub("$SOURCES", ursa.FRAGILE.parenthesize(outdeps))
    str = str:gsub("$SOURCE", ursa.FRAGILE.parenthesize(deps and deps[1]))
    str = str:gsub("#([%w_]+)", function (param) return ursa.token{param} end)
    
    return ursa.util.system{str}
  end, depends = "!" .. str, tokz}
end

function ursa.util.once(st)
  local func = unpack(st)
  local touched = false
  local rv
  return function(...)
    if not touched then
      rv = func(...)
      touched = true
    end
    
    return rv
  end
end

ursa.gen.wrap_funcs(ursa.util)
