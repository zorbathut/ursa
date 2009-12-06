
require "luarocks.loader"
require "md5"
require "pluto"
require "ursalib"

local ul = ursalib
ursalib = nil

local print_raw = print

local function print(...)
  print_raw("ursadbg", ...)
end

local files = {}
local commands = {}

ursa = {}
ursa.util = {}

local function md5_file(filename)
  local file = io.open(filename, "rb")
  if not file then return "" end
  local dat = file:read("*a")
  file:close()
  return md5.sum(dat)
end

local built_signatures = {}   -- no sig storage yet
do
  local uc_cs = io.open(".ursa.cache.checksum", "rb")
  local cache = io.open(".ursa.cache", "rb")
  if uc_cs and cache then
    local cs = uc_cs:read("*a")
    if md5_file(".ursa.cache") == cs then
      local dat = cache:read("*a")
      print("DECACHING")
      built_signatures = pluto.unpersist({}, dat)
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
      
      --print("Activity on", sig, activity)
      if type(activity) == "string" then
        print_raw(activity)
        local rv = os.execute(activity)
        if rv ~= 0 then
          for k in pairs(destfiles) do
            ul.unlink(k)
          end
          assert(false)
        end
      elseif type(activity) == "function" then
        activity()
      elseif activity == nil then
      else
        assert(false) -- whups
      end
      
      self.state = "finished"
      
      built_signatures[sig] = self:signature()
    end
    
    assert(self.state == "finished")
  end
  function Node:signature()  -- what is your signature?
    if self.sig then return self.sig end
    
    --print("a")
    local sch = {}
    for k in pairs(destfiles) do
      --print("md5f", k)
      table.insert(sch, md5_file(k))
      --print("md5fe")
    end
    --print("b")
    table.insert(sch, md5.sum(activity or ""))  -- "" is pretty much equivalent
    --print("c")
    for k in pairs(dependencies) do
      table.insert(sch, files[k]:signature())
    end
    self.sig = md5.sum(table.concat(sch, "\0"))
    
    return self.sig
  end
  
  return Node -- this may become a RAM issue, it may be better to embed the data in the Node and not do upvalues
end

local function make_raw_file(file)
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
  
  local fil = io.open(".ursa.cache", "wb")
  fil:write(pluto.persist({}, built_signatures))
  fil:close()
  
  local cs = md5_file(".ursa.cache")
  local filcs = io.open(".ursa.cache.checksum", "wb")
  filcs:write(cs)
  filcs:close()
end

for k, v in pairs(ursa) do
  if type(v) == "function" then
    ursa[k] = function (block, ...)
      assert(select('#', ...) == 0)
      return v(block)
    end
  end
end

local uc = ursa.command
ursa.command = setmetatable({
  default = command_default,
}, {
  __call = function(_, ...) return uc(...) end
})
