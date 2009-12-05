
require "luarocks.loader"
require "md5"
require "pluto"

local print_raw = print

local function print(...)
  print_raw("ursadbg", ...)
end

local files = {}
local commands = {}

ursa = {}
ursa.util = {}

local built_signatures = {}   -- no sig storage yet
do
  local cache = io.open(".ursa.cache", "rb")
  if cache then
    local dat = cache:read("*a")
    cache:close()
    built_signatures = pluto.unpersist({}, dat)
  end
end

local function md5_file(filename)
  --print("ma")
  local file = io.open(filename, "rb")
  --print("mb")
  if not file then return "" end
  --print("mc")
  local dat = file:read("*a")
  --print("md")
  file:close()
  --print("me")
  return md5.sum(dat)
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
      
      --print("working on ", sig)
      
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
        os.execute(activity)
      elseif type(activity) == "function" then
        activity()
      elseif activity == nil then
      else
        assert(false) -- whups
      end
      
      self.state = "finished"
      
      print("bsig")
      built_signatures[sig] = self:signature()
      print("dsig")
      print("Set sig", sig, built_signatures[sig])
    end
    
    assert(self.state == "finished")
  end
  function Node:signature()  -- what is your signature?
    --print("startsig")
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
    --print("d")
    self.sig = md5.sum(table.concat(sch, "\0"))
    
    --print("endsig")
    return self.sig
  end
  
  return Node -- this may become a RAM issue, it may be better to embed the data in the Node and not do upvalues
end

local function make_raw_file(file)
  local Node = {}
  
  function Node:wake()
    if not self.sig then
    print(file)
      self.sig = md5.sum(md5.sum(file) .. md5_file(file))
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
      recrunch_output(v)
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
    print("Adding node", k)
    files[k] = node
  end
end

ursa.command_default = {} -- opaque unique token

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
  print("build", param)
  if #param == 0 then
    param = {ursa.command_default}
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
end
