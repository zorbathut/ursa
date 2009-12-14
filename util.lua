
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
  return function () return ursa.token(chunk) end
end

function ursa.util.clean()
  for k in ursa.list{} do
    if k:sub(1, 1) == '#' then
      print_status("clearing " .. k)
      ursa.token.clear{k:sub(2)}
    else
      print_status("removing " .. k)
      os.remove(k)
    end
  end
end

function ursa.util.system_template(st)
  local str = unpack(st)
  return function(dests, deps)
    if str:find("$TARGET") and not str:find("$TARGETS") then assert(#dests == 1) end
    if str:find("$SOURCE") and not str:find("$SOURCES") then assert(#deps == 1) end
    
    return ursa.util.system{str:gsub("$TARGETS", table.concat(dests, " ")):gsub("$TARGET", dests[1]):gsub("$SOURCES", table.concat(deps, " ")):gsub("$SOURCE", deps[1])}
  end
end

ursa.gen.wrap_funcs(ursa.util)
