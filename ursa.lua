
require "luarocks.loader"
require "md5"
require "ursalibc"
require "ursaliblua"

local ul = {}
for k, v in pairs(ursalibc) do ul[k] = v end
for k, v in pairs(ursaliblua) do ul[k] = v end
ursalibc = nil
ursaliblua = nil

local print_raw = print

local function print(...)
  print_raw("ursadbg", ...)
end

local files = {}
local commands = {}

ursa = {}
ursa.util = {}

local function md5_file(filename, hexa)
  collectgarbage("collect")
  local file = io.open(filename, "rb")
  if not file then return "" end
  file:read("*a")
  local dat = file:read("*a")
  file:close()
  return hexa and md5.sumhexa(dat) or md5.sum(dat)
end

local built_signatures = {}   -- no sig storage yet
local built_tokens = {}
local serial_v = 1
do
  local uc_cs = io.open(".ursa.cache.checksum", "rb")
  local cache = io.open(".ursa.cache", "rb")
  if uc_cs and cache then
    local cs = uc_cs:read("*a")
    if md5_file(".ursa.cache", true) == cs then
      local dat = cache:read("*a")
      local pv, bs, bt
      sv, bs, bt = unpack(ul.persistence.load(dat))
      if sv == serial_v then
        built_signatures, built_tokens = bs, bt
      end
    else
      print("Corrupted cache?")
    end
  end
  
  if uc_cs then uc_cs:close() end
  if cache then cache:close() end
end

local function make_node(sig, destfiles, dependencies, activity, flags)
  if not flags then flags = {} end
  -- Node transition: "asleep", "working", "finished".
  -- Signatures are the combined md5 of three separate parts
  --  My file value/data value: if this changes, I have to be updated
  --  My command: if this changes, I have to be updated
  --  The signatures of everything I depend on, sorted in alphabetical order: if these change, I have to be updated
  -- We also have to store implicit dependencies for nodes, but these get thrown away if the node gets rebuilt
  local Node = {}
  
  local realfiles = {}
  local tokens = {}
  local tokcount = 0
  local tokit = nil
  for k in pairs(destfiles) do
    if k:sub(1, 1) ~= "#" then
      realfiles[k] = true
    else
      tokens[k:sub(2)] = true
      tokcount = tokcount + 1
      tokit = k:sub(2)
    end
  end
  assert(tokcount < 2)

  Node.state = "asleep"
  function Node:wake()  -- wake up, I'm gonna need you. get yourself ready to be processed and start crunching
    if self.state == "asleep" then
      self.state = "working"
      for k in pairs(dependencies) do
        files[k]:wake()
      end
      
      if not flags.always_rebuild and self:signature() == built_signatures[sig] then
        self.state = "finished"
      else
        -- add self to production queue
      end
    end
  end
  function Node:block()  -- please return once you're done and yield/grind until then
    if self.state == "asleep" then
      self:wake()
    end
    
    if self.state == "working" then
      --print("Blocking on ", sig)
      for k in pairs(dependencies) do
        self.sig = nil
        files[k]:block()
      end
      
      if not flags.token then
        for k in pairs(realfiles) do
          os.remove(k)
        end
        
        --print("Activity on", sig, activity)
        if type(activity) == "string" then
          print_raw(activity)
          local rv = os.execute(activity)
          if rv ~= 0 then
            for k in pairs(destfiles) do
              os.remove(k)
            end
            assert(false)
          end
        elseif type(activity) == "function" then
          activity()
        elseif activity == nil then
        else
          assert(false) -- whups
        end
        
        -- make sure all the files were generated
        for k in pairs(destfiles) do
          if k:sub(1, 1) ~= "#" then
            local check = io.open(k, "r")
            assert(check)
            check:close()
          end
        end
      else
        -- token
        assert(tokit)
        built_tokens[tokit] = nil
        
        if type(activity) == "string" then
          print_raw(activity)
          built_tokens[tokit] = ursa.util.system(activity)
        elseif type(activity) == "function" then
          built_tokens[tokit] = activity()
        else
          assert(false) -- whups
        end
        
        assert(built_tokens[tokit])
      end
      
      self.state = "finished"
      
      built_signatures[sig] = self:signature()
    end
    
    assert(self.state == "finished")
  end
  function Node:signature()  -- what is your signature?
    if self.sig then return self.sig end
    
    local sch = {}
    for k in pairs(destfiles) do
      table.insert(sch, md5_file(k))
    end
    table.insert(sch, md5.sum(activity or ""))  -- "" is pretty much equivalent
    for k in pairs(dependencies) do
      table.insert(sch, files[k]:signature())
    end
    self.sig = md5.sum(table.concat(sch, "\0"))
    
    return self.sig
  end
  
  return Node -- this may become a RAM issue, it may be better to embed the data in the Node and not do upvalues
end

local function make_raw_file(file)
  assert(file:sub(1, 1) ~= "#") -- not a token wannabe

  local Node = {}
  
  function Node:wake()
    if not self.sig then
      local fil = md5_file(file)
      assert(fil ~= "")
      self.sig = md5.sum(md5.sum(file) .. fil)
    end
  end
  Node.block = Node.wake
  function Node:signature()
    self:wake()
    return self.sig
  end
  
  return Node
end

local function recrunch(list, item)
  if type(item) == "string" then
    list[item] = true
  elseif type(item) == "table" then
    for _, v in ipairs(item) do
      recrunch(list, v)
    end
  elseif item == nil then
  else
    assert(false)
  end
end

function ursa.rule(param)
  local destination, dependencies, activity = unpack(param)
  print("Making rule:", destination, dependencies, activity)
  
  local ofilelist = {}
  local ifilelist = {}
  
  recrunch(ofilelist, destination)
  recrunch(ifilelist, dependencies)
  
  local found_ofile = false
  for k in pairs(ofilelist) do
    assert(not files[k])
    found_ofile = true
  end
  assert(found_ofile)
  
  for k in pairs(ifilelist) do
    assert(not ofilelist[k])
    if not files[k] then
      files[k] = make_raw_file(k)
    end
  end
  
  local node = make_node(destination, ofilelist, ifilelist, activity)
  for k in pairs(ofilelist) do
    assert(not files[k]) -- we already tried this
    files[k] = node
  end
end

function ursa.token(param)
  local destination, dependencies, activity = unpack(param)
  print("Making token:", destination, dependencies, activity)
  
  local ifilelist = {}
  
  recrunch(ifilelist, dependencies)
  
  for k in pairs(ifilelist) do
    assert(not ofilelist[k])
    if not files[k] then
      files[k] = make_raw_file(k)
    end
  end
  
  local node = make_node("#" .. destination, {["#" .. destination] = true}, ifilelist, activity, {token = true})
  
  assert(not files["#" .. destination]) -- we already tried this
  files["#" .. destination] = node
end
function ursa.value(param)
  local tok = unpack(param)
  assert(files["#" .. tok])
  
  files["#" .. tok]:block()
  assert(built_tokens[tok])
  
  return built_tokens[tok]
end

local command_default = {} -- opaque unique token

function ursa.command(param)
  local destination, dependencies, activity = unpack(param)
  
  local ifilelist = {}
  recrunch(ifilelist, dependencies)
  
  for k in pairs(ifilelist) do
    if not files[k] then
      files[k] = make_raw_file(k)
    end
  end
  
  assert(not commands[destination])
  
  local node = make_node(":" .. tostring(destination), {}, ifilelist, activity, {always_rebuild = true})
  commands[destination] = node
end

function ursa.build(param)
  if #param == 0 then
    param = {command_default}
  end
  
  for _, v in ipairs(param) do
    assert(commands[v], v)
    commands[v]:wake()
  end
  for _, v in ipairs(param) do
    assert(commands[v])
    commands[v]:block()
  end
  
  ul.persistence.save(".ursa.cache", {serial_v, built_signatures, built_tokens})
  
  local cs = md5_file(".ursa.cache", true)
  local filcs = io.open(".ursa.cache.checksum", "wb")
  filcs:write(cs)
  filcs:close()
end

local function wrap_funcs(chunk)
  for k, v in pairs(chunk) do
    if type(v) == "function" then
      ursa[k] = function (block, ...)
        assert(select('#', ...) == 0)
        return v(block)
      end
    end
  end
end
wrap_funcs(ursa)

local uc = ursa.command
ursa.command = setmetatable({
  default = command_default,
}, {
  __call = function(_, ...) return uc(...) end
})


function ursa.util.system(chunk)
  do return "" end
  local str, rv = ul.system(chunk)
  assert(rv == 0)
  return str
end

wrap_funcs(ursa.util)
