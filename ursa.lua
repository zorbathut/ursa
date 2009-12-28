
--[[ Prefixes:

#value
:command
!literal
@absolute
#@valueabsolute

]]

require "md5"

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
ursa.FRAGILE = {}


function ursa.FRAGILE.parenthesize(item)
  if type(item) == "table" then
    local tt = ""
    for _, v in pairs(item) do
      if tt ~= "" then
        tt = tt .. " " .. ursa.FRAGILE.parenthesize(v)
      else
        tt = ursa.FRAGILE.parenthesize(v)
      end
    end
    return tt
  elseif type(item) == "string" then
    if item:find('"') then assert(false) end -- bzzt
    if item:find("%s") then return '"' .. item .. '"' end
    return item
  elseif type(item) == "nil" then
    return ""
  end
end

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

local function sig_file(filename)
  return tostring(ul.mtime(filename) or math.random())  -- yes yes shut up. at least this way we'll almost certainly break
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
  assert(file:sub(1, 1) ~= "#", "attempted to use undefined token " .. file) -- not a token wannabe

  local Node = {}
  
  function Node:wake()
    --print("rwak a")
    if not self.sig then
      --print("rwak ba")
      context_stack_push(context_stack[1])
      --print("rwak bb")
      local fil = context_stack_chdir(sig_file, file, true)
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
  function Node:rewrite() -- this file is being changed
    self.sig = nil
  end
  Node.static = true
  
  return Node
end

-- path manipulations
-- assumes the file "orig" is relative to the denroot, returns an appropriate path from the "newhead" location
local function relativize(orig, newhead)
  local realorig = orig
  for stx in newhead:gmatch("[^/]+") do
    local top, rest = orig:match("^([^/]+)/(.*)")
    if top == stx then
      orig = rest
    else
      orig = "../" .. orig
    end
  end
  return orig
end

local function make_standard_path(item)
  -- get rid of various relative paths
  local new_item = item
  while true do
    local itex = new_item:gsub("[%w_]+/%.%./", "")
    if itex == new_item then break end
    new_item = itex
  end
  assert(not new_item:find("/%.%./"), "Path appears to be relative: " .. item .. " (converted to " .. new_item .. ")")
  assert(not new_item:find("/%./"), "Path appears to be relative: " .. item .. " (converted to " .. new_item .. ")")
  item = new_item
  
  local prefix = item:sub(1, 1)
  if prefix == "#" then
    local block = item:sub(2)
    if block:sub(1, 1) == "@" then
      return '#' .. block:sub(2)
    else
      return '#' .. context_stack_prefix() .. block -- relative injection
    end
  elseif prefix == "!" then
    return prefix -- literal
  elseif prefix == "@" then
    return item:sub(2) -- absolute path, strip off the prefix
  elseif prefix == ":" then
    assert(false) -- not supported
  elseif prefix == "." then
    assert(false) -- relative paths are evil
  else
    return context_stack_prefix() .. item
  end
end
local function make_absolute_from_core(path)
  local prefix = path:sub(1, 1)
  if prefix == "#" then
    return "#@" .. path:sub(2)
  elseif prefix == "!" then
    assert(false)
    return prefix -- literal
  elseif prefix == "@" then
    assert(false) -- what
  elseif prefix == ":" then
    assert(false) -- not supported
  elseif prefix == "." then
    assert(false) -- relative paths are evil
  else
    return "@" .. path
  end
end

local function recrunch(list, item, resolve_functions)
  if type(item) == "string" then
    list[make_standard_path(item)] = true
  elseif type(item) == "table" then
    local ipct = 0
    for _, v in ipairs(item) do
      recrunch(list, v, resolve_functions)
      ipct = ipct + 1
    end
    for _, v in pairs(item) do
      ipct = ipct - 1
    end
    assert(ipct == 0)
  elseif type(item) == "function" then
    if resolve_functions then
      recrunch(list, context_stack_chdir(item), resolve_functions)
    end
  elseif item == nil then
  else
    assert(false)
  end
end

local function distill_dependencies(dependencies, ofilelist, resolve_functions)
  local ifilelist = {}
  local literals = {}
  recrunch(ifilelist, dependencies, resolve_functions)
  for k in pairs(ifilelist) do
    assert(not ofilelist or not ofilelist[k])
    if not files[k] then
      if k:sub(1, 1) ~= "!" then
        files[k] = make_raw_file(k)
      else
        literals[k] = true
      end
    end
  end
  for k in pairs(literals) do
    ifilelist[k] = nil
  end
  return ifilelist, literals
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
      table.insert(simpledests, relativize(k, context_stack_prefix()))
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
    if self.state == "asleep" then
      self.state = "working"
      
      for k in pairs(distill_dependencies(dependencies, destfiles, true)) do
        files[k]:wake()
      end
      
      -- add self to production queue
      -- maybe not do it if everything downstream is truly finished?
    end
  end
  function Node:block()  -- please return once you're done and yield/grind until then
    local did_something = false
    --print("blocking on", sig, self.state)
    
    if self.state == "asleep" then
      self:wake()
    end
    
    if self.state == "working" then
      for k in pairs(distill_dependencies(dependencies, destfiles, true)) do
        self.sig = nil
        files[k]:block()
      end
      
      --print("PRESIG", sig, self:signature(), built_signatures[sig])
      if flags.always_rebuild or self:signature() ~= built_signatures[sig] then
        self.sig = nil
        
        local simpledeps = {}
        for k in pairs(distill_dependencies(dependencies, destfiles, true)) do
          table.insert(simpledeps, relativize(k, context_stack_prefix())) -- grr
        end
      
        if not flags.token then
          for k in pairs(realfiles) do
            os.remove(k)
            local path = k:match("(.*)/[^/]+")
            if path and not paths_made[path] then
              local cmd = "mkdir -p -v " .. ursa.FRAGILE.parenthesize(path)
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
              print("Program execution failed")
              assert(false)
            end
          elseif type(activity) == "function" then
            context_stack_chdir(activity, simpledests, simpledeps)
          elseif activity == nil then
          else
            assert(false) -- whups
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
      end
      
      -- make sure all the files were generated
      for k in pairs(destfiles) do
        if k:sub(1, 1) ~= "#" then
          assert(ul.mtime(k), "File " .. k .. " wasn't generated by the given build step.")
          if files[k].rewrite then files[k]:rewrite() end -- they were written to, one presumes.
        end
      end
      
      self.state = "finished"
      
      if not flags.no_save then
        --self.sig = nil
        --print("POSTSIG", sig, self:signature(), built_signatures[sig])
        built_signatures[sig] = self:signature()
      end
    end
    
    assert(self.state == "finished")
  end
  function Node:signature()  -- what is your signature?
    if self.sig then return self.sig end
    
    local sch = {}
    if flags.token then
      table.insert(sch, md5.sum(ul.persistence.dump(built_tokens[tokit])))
    else
      for k in pairs(destfiles) do
        --print(sig, "dfsig", sig_file(k))
        table.insert(sch, sig_file(k))
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
    local deps, literals = distill_dependencies(dependencies, destfiles, true)
    for k in pairs(deps) do
      --print(sig, "depsig", k, files[k]:signature())
      table.insert(sch, files[k]:signature())
    end
    for k in pairs(literals) do
      table.insert(sch, k)
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
  --print("Making rule:", destination, dependencies, activity)
  
  local ofilelist = {}
  local ofileabs = {}
  
  recrunch(ofilelist, destination, true)
  
  local found_ofile = false
  for k in pairs(ofilelist) do
    --print("yoop", k)
    assert(not files[k], "output file " .. k .. " already defined")
    found_ofile = true
    
    table.insert(ofileabs, make_absolute_from_core(k))
  end
  assert(found_ofile, "no output files found?")
  
  distill_dependencies(dependencies, ofilelist, false)
  
  if type(destination) ~= "string" then
    local fill = {}
    for k in pairs(ofilelist) do
      table.insert(fill, k)
    end
    table.sort(fill)
    destination = "{" .. table.concat(fill, "<--->") .. "}"
  end
  
  local node = make_node(destination, ofilelist, dependencies, activity, param)
  for k in pairs(ofilelist) do
    assert(not files[k]) -- we already tried this
    files[k] = node
  end
  
  return ofileabs
end

function ursa.token_rule(param)
  local destination, dependencies, activity = unpack(param)
  --print("Making token:", destination, dependencies, activity)
  
  distill_dependencies(dependencies, nil, false)
  
  local spath = make_standard_path("#" .. destination)
  
  local node = make_node(spath, {[spath] = true}, dependencies, activity, setmetatable({token = true}, {__index = param}))
  
  if files[spath] then
    if files[spath].static then
      assert(false, spath .. " used before it was defined. Re-order your definitions!")
    else
      assert(false, spath .. " defined multiple times.")
    end
  end
  
  files[spath] = node
  
  return make_absolute_from_core(spath)
end
function ursa.token(param)
  local tok = unpack(param)
  tok = make_standard_path("#" .. tok)
  local tokp = tok:sub(2)
  
  assert(files[tok])
  
  if param.default then
    if not built_tokens[tokp] then
      return param.default
    end
  else
    files[tok]:block()
    assert(built_tokens[tokp], "didn't build " .. tok)
  end
  
  return built_tokens[tokp]
end

local command_default = {} -- opaque unique token

function ursa.command(param)
  local destination, dependencies, activity = unpack(param)
  
  --print("Making command:", destination, dependencies, activity)
  
  distill_dependencies(dependencies, nil, false)
  
  assert(not commands[destination])
  
  local node = make_node(":" .. tostring(destination), {}, dependencies, activity, {always_rebuild = true, no_save = true})
  commands[destination] = node
end

function ursa.build(param)
  if #param == 0 then
    param = {command_default}
  end
  
  local items = {}
  for _, v in ipairs(param) do
    local ite = commands[v] or files[v]
    assert(ite, v)
    table.insert(items, ite)
  end
  
  local status, rv = xpcall(function ()
    for _, v in ipairs(items) do
      v:wake()
    end
    for _, v in ipairs(items) do
      v:block()
    end
    print("build complete")
  end, function (err) return err .. "\n" .. debug.traceback() end)
  
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
function ursa.FRAGILE.list()
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

function ursa.FRAGILE.token_clear(tok)
  local toki = unpack(tok)
  built_tokens[toki] = nil
end

function ursa.embed(dat)
  local path, file = unpack(dat)
  local context = context_stack_get()
  local absolute = context_stack_chdir(function () ul.chdir(path) return ul.getcwd() end)
  local prefix = context_stack_prefix() .. path
  
  --print("Embedding:", path, file, prefix, absolute)
  
  local uc, ub, ul, utc = ursa.command, ursa.build, ursa.list
  ursa.command = setmetatable({default = command_default}, {__call = function () end})
  function ursa.build() end
  function ursa.list() assert(false) end
  context_stack_push({prefix = prefix, absolute = absolute})
  local rv = return_pack(context_stack_chdir(function ()
    local d, e = loadfile(file)
    if not d then
      error(e)
    end
    return d()
  end))
  context_stack_pop()
  ursa.command, ursa.build, ursa.list = uc, ub, ul
  --print("Ending embed")
  
  return return_unpack(rv)
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

local token_rule = ursa.token_rule
local token_value = ursa.token

ursa.token = setmetatable({
  rule = token_rule,
}, {
  __call = function(_, ...) return token_value(...) end
})


require "ursa.util"

ursa.gen = nil
