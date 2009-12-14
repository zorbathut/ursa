
print("req md5 wat")
require "md5"
print("hoohah")

require "ursalibc"
require "ursaliblua"

local ul = {}
for k, v in pairs(ursalibc) do ul[k] = v end
for k, v in pairs(ursaliblua) do ul[k] = v end
ursalibc = nil
ursaliblua = nil

local print_raw = print

local current_print_prefix = ""
local function print_status(...)
  if current_print_prefix ~= "" then
    print(current_print_prefix, ...)
  else
    print(...)
  end
end

local function print(...)
  print_raw("ursadbg", ...)
end

local function garbaj()
  print("testing garbaj")
  collectgarbage("collect")
  print("testing garbaj complete")
end

local files = {}
local commands = {}

ursa = {}
ursa.util = {}

local function md5_file(filename, hexa)
  local file = io.open(filename, "rb")
  if not file then return "" end
  local dat = file:read("*a")
  assert(dat, filename, #filename)
  file:close()
  --print("yoop")
  collectgarbage("collect")
  --print("yarp")
  
  local rv = hexa and md5.sumhexa(dat) or md5.sum(dat)
  --garbaj()
  return rv
end

local paths_made = {}

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

-- wish there were a better way to do this
local function return_pack(...)
  return {..., n = select('#', ...)}
end
local function return_unpack(item)
  return unpack(item, item.n)
end

-- it may seem like we should be chdir'ing when things are pushed or popped, but we actually live "natively" in the root directory. We only chdir when we need to.
local context_stack = {{prefix = "", absolute = ul.getcwd()}}
local function context_stack_push(chunk)
  --print("pushing stack", chunk.prefix, chunk.absolute)
  table.insert(context_stack, chunk)
end
local function context_stack_pop()
  --print("popping stack")
  table.remove(context_stack)
end
local function context_stack_prefix()
  if context_stack[#context_stack].prefix == "" then return "" end
  return context_stack[#context_stack].prefix .. "/"
end
local function context_stack_chdir(func, ...)
  local cops = ul.getcwd()
  ul.chdir(context_stack[#context_stack].absolute)
  current_print_prefix = context_stack[#context_stack].prefix
  --print("CHDIR INTO", context_stack[#context_stack].absolute)
  local rp = return_pack(func(...))
  current_print_prefix = ""
  --print("CHDIR EXIT")
  ul.chdir(cops)
  return return_unpack(rp)
end
local function context_stack_get()
  return context_stack[#context_stack]
end


local function make_raw_file(file)
  assert(file:sub(1, 1) ~= "#") -- not a token wannabe

  local Node = {}
  
  function Node:wake()
    --print("rwak a")
    if not self.sig then
      --print("rwak ba")
      context_stack_push(context_stack[1])
      --print("rwak bb")
      local fil = context_stack_chdir(md5_file, file, true)
      --print("rwak bc")
      context_stack_pop()
      --print("rwak c")
      assert(fil ~= "", "Couldn't locate raw file " .. file .. " in context " .. ul.getcwd())
      --print("rwak d")
      self.sig = md5.sum(md5.sum(file) .. fil)
      --print("rwak e")
    end
    --print("rwak f")
  end
  Node.block = Node.wake
  function Node:signature()
    self:wake()
    return self.sig
  end
  Node.static = true
  
  return Node
end

local function recrunch(list, item, resolve_functions)
  if type(item) == "string" then
    list[context_stack_prefix() .. item] = true
  elseif type(item) == "table" then
    local ipct = 0
    for _, v in ipairs(item) do
      recrunch(list, v)
      ipct = ipct + 1
    end
    for _, v in pairs(item) do
      ipct = ipct - 1
    end
    assert(ipct == 0)
  elseif type(item) == "function" then
    if resolve_functions then
      recrunch(list, context_stack_chdir(item))
    end
  elseif item == nil then
  else
    assert(false)
  end
end

local function distill_dependencies(dependencies, ofilelist, resolve_functions)
  local ifilelist = {}
  recrunch(ifilelist, dependencies, resolve_functions)
  for k in pairs(ifilelist) do
    assert(not ofilelist or not ofilelist[k])
    if not files[k] then
      files[k] = make_raw_file(k)
    end
  end
  return ifilelist
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
  local simpledests = {}
  for k in pairs(destfiles) do
    if k:sub(1, 1) ~= "#" then
      realfiles[k] = true
      table.insert(simpledests, k)
    else
      tokens[k:sub(2)] = true
      tokcount = tokcount + 1
      tokit = k:sub(2)
    end
  end
  assert(tokcount < 2)
  
  Node.context = context_stack_get()

  Node.state = "asleep"
  function Node:wake()  -- wake up, I'm gonna need you. get yourself ready to be processed and start crunching
    --print("wi a")
    if self.state == "asleep" then
      self.state = "working"
      
      --print("wi b")
      for k in pairs(distill_dependencies(dependencies, destfiles, true)) do
        --print("wi c")
        files[k]:wake()
        --print("wi d")
      end
      --print("wi e")
      if not flags.always_rebuild and self:signature() == built_signatures[sig] then
        --print("marking as finished")
        self.state = "finished"
      else
        -- add self to production queue
      end
      --print("wi f")
    end
    --print("wi g")
  end
  function Node:block()  -- please return once you're done and yield/grind until then
    local did_something = false
    
    if self.state == "asleep" then
      self:wake()
    end
    
    if self.state == "working" then
      --print("Blocking on ", sig)
      for k in pairs(distill_dependencies(dependencies, destfiles, true)) do
        self.sig = nil
        files[k]:block()
      end
      
      self.sig = nil
      
      local simpledeps = {}
      do
        local depp = distill_dependencies(dependencies, destfiles, true)
        for k in pairs(depp) do
          table.insert(simpledeps, k) -- grr
        end
      end
    
      if not flags.token then
        for k in pairs(realfiles) do
          os.remove(k)
          local path = k:match("(.*)/[^/]+")
          if path and not paths_made[path] then
            local cmd = "mkdir -p -v " .. path
            print_status(cmd)
            os.execute(cmd)
            paths_made[path] = true
          end
        end
        
        --print("Activity on", sig, activity)
        if type(activity) == "string" then
          local rv = context_stack_chdir(function (line) print_status(line) return os.execute(line) end, activity)
          if rv ~= 0 then
            for k in pairs(destfiles) do
              os.remove(k)
            end
            assert(false)
          end
        elseif type(activity) == "function" then
          context_stack_chdir(activity, simpledests, simpledeps)
        elseif activity == nil then
        else
          assert(false) -- whups
        end
        
        -- make sure all the files were generated
        for k in pairs(destfiles) do
          if k:sub(1, 1) ~= "#" then
            local check = io.open(k, "r")
            assert(check, "File " .. k .. " wasn't generated by the given build step.")
            check:close()
          end
        end
      else
        -- token
        assert(tokit)
        built_tokens[tokit] = nil
        
        if type(activity) == "string" then
          built_tokens[tokit] = context_stack_chdir(ursa.util.system, {activity})
        elseif type(activity) == "function" then
          built_tokens[tokit] = context_stack_chdir(activity, simpledests, simpledeps)
        else
          assert(false) -- whups
        end
        
        assert(built_tokens[tokit])
      end
      
      self.state = "finished"
      
      if not flags.no_save then
        built_signatures[sig] = self:signature()
      end
    end
    
    assert(self.state == "finished")
  end
  function Node:signature()  -- what is your signature?
    if self.sig then return self.sig end
    
    local sch = {}
    if flags.token then
      --print("token sig is", tokit, built_tokens[tokit])
      --print("ts 0")
      table.insert(sch, md5.sum(ul.persistence.dump(built_tokens[tokit])))
      --print("ts a")
    else
      for k in pairs(destfiles) do
        table.insert(sch, md5_file(k))
      end
    end
    --print("ts b")
    if activity == nil then
      --print("ts c")
      table.insert(sch, md5.sum(""))  -- "" is pretty much equivalent
      --print("ts d")
    elseif type(activity) == "string" then
      --print("ts e")
      table.insert(sch, md5.sum(activity))
      --print("ts f")
    elseif type(activity) == "function" then
      --print("ts g")
      table.insert(sch, md5.sum(string.dump(activity)))
      --print("ts h")
    else
      assert(false)
    end
    --print("ts i")
    for k in pairs(distill_dependencies(dependencies, destfiles, true)) do
      --print("ts j")
      table.insert(sch, files[k]:signature())
      --print("ts k")
    end
    --print("ts l")
    table.sort(sch) -- heh heh. our table iteration has no guaranteed order, so we do this to guarantee an order. wheeee. technically this is slightly fragile and we should be doing this only in each "group", but, well, right now we're not.
    --print("ts m")
    self.sig = md5.sum(table.concat(sch, "\0"))
    --print("ts n")
    
    return self.sig
  end
  
  local function wrap(func)
    return function (...)
      context_stack_push(Node.context)
      local rv = return_pack(func(...))
      assert(context_stack_get() == Node.context)
      context_stack_pop()
      return return_unpack(rv)
    end
  end
  
  Node.wake = wrap(Node.wake)
  Node.block = wrap(Node.block)
  Node.signature = wrap(Node.signature)
  
  return Node -- this may become a RAM issue, it may be better to embed the data in the Node and not do upvalues
end

function ursa.rule(param)
  local destination, dependencies, activity = unpack(param)
  print("Making rule:", destination, dependencies, activity)
  
  local ofilelist = {}
  
  recrunch(ofilelist, destination, true)
  
  local found_ofile = false
  for k in pairs(ofilelist) do
    --print("yoop", k)
    assert(not files[k])
    found_ofile = true
  end
  assert(found_ofile, "no output files found?")
  
  distill_dependencies(dependencies, ofilelist, false)
  
  local node = make_node(destination, ofilelist, dependencies, activity)
  for k in pairs(ofilelist) do
    assert(not files[k]) -- we already tried this
    files[k] = node
  end
end

function ursa.token_rule(param)
  local destination, dependencies, activity = unpack(param)
  print("Making token:", destination, dependencies, activity)
  
  distill_dependencies(dependencies, nil, false)
  
  local node = make_node("#" .. destination, {["#" .. destination] = true}, dependencies, activity, {token = true})
  
  assert(not files["#" .. destination]) -- we already tried this
  files["#" .. destination] = node
end
function ursa.token(param)
  local tok = unpack(param)
  assert(files["#" .. tok])
  
  if param.default then
    if not built_tokens[tok] then
      return param.default
    end
  else
    files["#" .. tok]:block()
    assert(built_tokens[tok], "didn't build " .. tok)
  end
  
  return built_tokens[tok]
end

local command_default = {} -- opaque unique token

function ursa.command(param)
  local destination, dependencies, activity = unpack(param)
  
  print("Making command:", destination, dependencies, activity)
  
  distill_dependencies(dependencies, nil, false)
  
  assert(not commands[destination])
  
  local node = make_node(":" .. tostring(destination), {}, dependencies, activity, {always_rebuild = true, no_save = true})
  commands[destination] = node
end

function ursa.build(param)
--print("sb")
  if #param == 0 then
    param = {command_default}
  end
  
  local status, rv = xpcall(function ()
    --print("ip")
    for _, v in ipairs(param) do
      assert(commands[v], v)
      --print("wakein")
      commands[v]:wake()
      --print("wakeout")
    end
    for _, v in ipairs(param) do
      assert(commands[v])
      --print("blockin")
      commands[v]:block()
      --print("blockout")
    end
    --print("ip done")
  end, function (err) return err .. "\n" .. debug.traceback() end)
  
  --print("sav")
  ul.persistence.save(".ursa.cache", {serial_v, built_signatures, built_tokens})
  
  local cs = md5_file(".ursa.cache", true)
  local filcs = io.open(".ursa.cache.checksum", "wb")
  filcs:write(cs)
  filcs:close()
  
  if not status then
    print_status(rv)
    os.exit(1)
  end
end

-- returns an iterator to list all generated files
function ursa.list()
  return coroutine.wrap(function ()
    local cp = nil
    while true do
      local nd
      cp, nd = next(files, cp)
      if not cp then break end
      if not nd.static then
        coroutine.yield(cp)
      end
    end
  end)
end

function ursa.token_clear(tok)
  local toki = unpack(tok)
  built_tokens[toki] = nil
end

function ursa.embed(dat)
  local path, file = unpack(dat)
  local context = context_stack_get()
  local absolute = context_stack_chdir(function () ul.chdir(path) return ul.getcwd() end)
  local prefix = context_stack_prefix() .. path
  
  print("Embedding:", path, file, prefix, absolute)
  
  local uc, ub, ul, utc = ursa.command, ursa.build, ursa.list, ursa.token.clear
  ursa.command = setmetatable({default = command_default,}, {__call = function () end})
  function ursa.build() end
  function ursa.list() assert(false) end
  function ursa.token.clear() assert(false) end
  context_stack_push({prefix = prefix, absolute = absolute})
  context_stack_chdir(function ()
    loadfile(file)()
  end)
  context_stack_pop()
  ursa.command, ursa.build, ursa.list, ursa.token.clear = uc, ub, ul, utc
  print("Ending embed")
end

ursa.gen = {ul = ul, print = print, print_status = print_status}

function ursa.gen.wrap_funcs(chunk)
  for k, v in pairs(chunk) do
    if type(v) == "function" then
      ursa[k] = function (block, ...)
        assert(select('#', ...) == 0)
        assert(type(block) == "table")
        return v(block)
      end
    end
  end
end
ursa.gen.wrap_funcs(ursa)

local uc = ursa.command
ursa.command = setmetatable({
  default = command_default,
}, {
  __call = function(_, ...) return uc(...) end
})

local token_clear = ursa.token_clear
local token_rule = ursa.token_rule
local token_value = ursa.token

ursa.token = setmetatable({
  rule = token_rule,
  clear = token_clear,
}, {
  __call = function(_, ...) return token_value(...) end
})


require "ursa.util"

ursa.gen = nil
