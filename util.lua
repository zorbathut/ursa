
local ul, print, print_raw = ursa.gen.ul, ursa.gen.print, ursa.gen.print_raw

function ursa.util.system(chunk)
  print_raw(chunk)
  local str, rv = ul.system(chunk)
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
      print_raw("clearing " .. k)
      ursa.token.clear{k:sub(2)}
    else
      print_raw("removing " .. k)
      os.remove(k)
    end
  end
end

ursa.gen.wrap_funcs(ursa.util)
