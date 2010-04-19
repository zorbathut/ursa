
--[[ Prefixes:

#value
:command
!literal
@absolute
#@valueabsolute

]]

--[[ Thinkin' about parallel builds.

First off, we need some kind of a Parallel Build Manager, I feel. This is just going to be grim otherwise.

Any function that can halt on tree evaluation - ursa.build and ursa.token, I believe - ends up shelling into the parallel build manager to resolve shit. The parallel build manager effectively halts and loops until it's done, and everything from there is done within coroutines so it can be paused.

Meanwhile, ursa.system (do we have ursa.system? we should have a serious ursa.system, I think) will coroutine.yield() with some appropriate check-to-see-if-we're-done token returned. That goes back to the build manager.

Build manager:

* Keep a pool of "ready coroutines"
* Run a coroutine
* Coroutine returns either "sleeping" or "running". If it's running, it's counted as taking a slot. If it's sleeping, it's not.
  * Coroutine does a few complicated things, but if it ends up blocking on something that isn't yet completed, it goes into "sleep" mode and adds itself to that thing's "being-blocked-on" table. Once that thing finishes, it adds its being-blocked-on table back into the build manager's ready coroutine pool.
* If we're out of coroutine pool, and everything's finished running, then in theory we're done.

Wake/block:

Wake should add itself to the manager pool, which should just immediately start running it. How should this work? Add a coroutine.yield() between wake calls?

"wake" shouldn't block, but should return immediately.
"block", on the other hand, may block (obviously).

States:
sleeping (has not yet awoken, not in the build system)
processing (in the build system, not finished)
finished (block can return immediately)

How do we deal with circular dependencies?

Coroutine manager has to also deal with the context stack, which is a bit nasty. Make context stack immutable but also chain intelligently


function self:wake() do
  add_block_to_manager()
end

function self:block() do
  if state == "
  for(items) do
    item:wake()
    coroutine.yield()
  end

  for(items) do
    item:block()
  end

  if needs_to_be_processed then
    self:process()
  end
end

The goal here is to start processing as early as humanly possible. Anything that's woken may end up doing things even as the rest of the build system is waking up, and that's totally OK.

So, steps to make this work:

* Modify context stack to do chaining so we can take advantage of garbage collection properly
* Change wake to add coroutine, change block to deal properly too, then do the whole process-manager thing
* Make it parallel

select() shit - use fileno() to make things work maybe

Alright how should the C API work?

fcntl(sockfd, F_SETFL, O_NONBLOCK);

-- Spawn a new process, return a handle
-- Given a set of handles, return the set that is ready to read
-- Given a handle, read a chunk
-- Given a handle, close it

]]

local tree_tree = {}
local tree_base = nil
local tree_roots = {}
local tree_static = {}
local tree_modified = {}
local tree_modified_forced = {}

local function tree_push(item)
  if not tree_base then table.insert(tree_roots, item) end
  tree_base = {content = item, up = tree_base}
  if not tree_tree[item] then tree_tree[item] = {} end
end
local function tree_pop(item)
  tree_base = tree_base.up
end
local function tree_top()
  return tree_base and tree_base.content
end

function tree_snapshot_get()
  return tree_base
end
function tree_snapshot_put(top)
  tree_base = top
end



require "md5"

ursa = {}

local lib = {}
ursa.lib = lib
require "ursalibc"
for k, v in pairs(ursalibc) do lib[k] = v end
require "ursaliblua"
for k, v in pairs(ursaliblua) do lib[k] = v end
require "ursalibcontext"
for k, v in pairs(ursalibcontext) do lib[k] = v end
ursalibc = nil
ursaliblua = nil
ursalibcontext = nil
ursa.lib = nil

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

--[[ ===============================================================

COROUTINE MANAGER MODULE

==================================================================]]

-- The manager has a concept of a "state", which includes mostly opaque data
--


local manager_coroutines = {}
local manager_current_stack = {}

local manager_handles = {}
local manager_live = {}

-- wrap a coro and return its state
local function manager_wrap(coro, nocoro)
  assert(coro)
  if not nocoro then
    coro = coroutine.wrap(coro)
  end
  return {coro = coro, tree = tree_snapshot_get(), context = lib.context_stack_snapshot_get()}
end

local manager_max_processes = 6

local function manager_execute(cc)
  assert(cc)
  tree_snapshot_put(cc.tree)
  lib.context_stack_snapshot_put(cc.context)
  table.insert(manager_current_stack, cc.coro)
  cc.coro()
  assert(table.remove(manager_current_stack) == cc.coro)
end

local last_status = 0

local manager_inside
local function manager_begin(coro)
  if not manager_inside then
    local tree, context = tree_snapshot_get(), lib.context_stack_snapshot_get()
    manager_inside = true
    
    table.insert(manager_coroutines, manager_wrap(coro))
    
    -- process the coroutines until they're all done
    while #manager_coroutines > 0 or #manager_handles > 0 do
      if last_status < os.time() - 5 then
        last_status = os.time() - 5
        print("CORO STATUS:", #manager_handles, #manager_coroutines)
        for _, v in pairs(manager_live) do
          print("", v.command)
        end
      end
      
      if #manager_handles < manager_max_processes and #manager_coroutines > 0 then
        -- if we need to add a new process, then do so
        manager_execute(table.remove(manager_coroutines))
        -- it may or may not have added itself, we're okay with that
      else
        -- otherwise wait for an existing process to be ready
        local readies = lib.process_scan(manager_handles)
        for _, v in ipairs(readies) do
          manager_execute(manager_live[v])
          -- again, these might remove themselves from the current handles, we're totally A-OK with that
        end
      end
      -- loop back around until we're done
    end
    
    manager_inside = false
    tree_snapshot_put(tree)
    lib.context_stack_snapshot_put(context)
  else
    -- we're already inside the manager, so we're inside a coroutine (probably inside an ursa.token{} invocation.) let's just run our program and be done with ourselves
    coro()
  end
end

-- here's the coroutine adder
local function manager_add(state)
  table.insert(manager_coroutines, state)
end

-- here's how we generate our current state
local function manager_get_current_state()
  return manager_wrap(manager_current_stack[#manager_current_stack], true)
end

-- returns stdout, stderr, error code. currently asserts on failure, also trims whitespace and doesn't actually return stderr
function ursa.system(tex)
  local chunk = unpack(tex)
  print_status(chunk)
  --print("us in")
  
  local proc = lib.process_spawn(chunk)
  
  table.insert(manager_handles, proc)
  
  local rv = {}
  while true do
    if manager_inside then
      manager_live[proc] = manager_get_current_state()
      manager_live[proc].command = chunk
      coroutine.yield()
    else
      lib.process_scan({proc})
    end
    local str, eof = lib.process_read(proc)
    table.insert(rv, str)
    if eof then break end
  end
  
  local foundcount = 0
  for i = 1, #manager_handles do
    if manager_handles[i] == proc then
      table.remove(manager_handles, i)
      foundcount = foundcount + 1
    end
  end
  assert(foundcount == 1)
  manager_live[proc] = nil
  
  local status = lib.process_close(proc)
  assert(status == 0, "Execution failed")
  
  --print((table.concat(rv)), (table.concat(rv):match("^%s*(.-)%s*$")))
  --print(table.concat(rv):match("^%s*(.-)%s*$"), "", status)
  return table.concat(rv):match("^%s*(.-)%s*$"), "", status
end

--[[ ===============================================================

END COROUTINE MANAGER MODULE

==================================================================]]

local files = {}
local commands = {}

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
  return tostring(lib.context_stack_chdir_native(lib.mtime, filename) or math.random())  -- yes yes shut up. at least this way we'll almost certainly break
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
      sv, bs, bt = unpack(lib.persistence.load(dat))
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


local function make_raw_file(file)
  assert(file:sub(1, 1) ~= "#", "attempted to use undeclared token " .. file) -- not a token wannabe
  tree_static[file] = true

  local Node = {}
  Node.depended_on = {}
  Node.unused = true
  
  local function process_node(self)
    if not self.sig then
      self.unused = nil
      local fil = lib.context_stack_chdir_native(sig_file, file, true)
      assert(fil ~= "", "Couldn't locate raw file " .. file)
      self.sig = md5.sum(md5.sum(file) .. fil)
      
      if built_signatures[file] ~= self.sig then
        tree_modified[file] = true
      end
      
      built_signatures[file] = self.sig
    end
  end
  
  function Node:wake()
    -- we don't want to do this in block mode because the stack isn't sane in block mode
    -- 'course this doesn't work at all right now
    tree_tree[tree_top()][file] = true
  end
  function Node:block()
    process_node(self)
  end
  function Node:signature()
    self:block()
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

local function strip_relative_path(item)
  local new_item = item
  while true do
    local itex = new_item:gsub("[%w_]+/%.%./", "")
    if itex == new_item then break end
    new_item = itex
  end
  assert(not new_item:find("/%.%./"), "Path appears to be relative: " .. item .. " (converted to " .. new_item .. ")")
  assert(not new_item:find("/%./"), "Path appears to be relative: " .. item .. " (converted to " .. new_item .. ")")
  return new_item
end
local function make_standard_path(item)
  -- get rid of various relative paths
  local prefix = item:sub(1, 1)
  if prefix == "#" then
    local block = item:sub(2)
    if block:sub(1, 1) == "@" then
      return '#' .. block:sub(2)
    else
      return '#' .. lib.context_stack_prefix() .. block -- relative injection
    end
  elseif prefix == "!" then
    return item -- literal
  elseif prefix == "@" then
    return strip_relative_path(item:sub(2)) -- absolute path, strip off the prefix
  elseif prefix == ":" then
    assert(false) -- not supported
  elseif prefix == "." then
    assert(false, "Appears to be a relative path: " .. prefix)
  else
    return strip_relative_path(lib.context_stack_prefix() .. item)
  end
end
local function make_absolute_from_core(path)
  local prefix = path:sub(1, 1)
  if prefix == "#" then
    return "#@" .. path:sub(2)
  elseif prefix == "!" then
    assert(false)
    return item -- literal
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
    assert(ipct == 0, "Non-integer keys found in dependency table")
  elseif type(item) == "function" then
    if resolve_functions then
      recrunch(list, lib.context_stack_chdir(item), resolve_functions)
    end
  elseif item == nil then
  else
    assert(false)
  end
end

local function distill_dependencies(dependencies, ofilelist, resolve_functions, from)
  assert(from)
  
  local ifilelist = {}
  local literals = {}
  recrunch(ifilelist, dependencies, resolve_functions)
  for k in pairs(ifilelist) do
    assert(not ofilelist or not ofilelist[k])
    if k:sub(1, 1) == "!" then
      literals[k] = true
    else      
      if not files[k] then
        files[k] = make_raw_file(k)
      else
        files[k].depended_on[from] = true
      end
      ifilelist[k] = true
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
  Node.depended_on = {}
  
  local realfiles = {}
  local tokens = {}
  local tokcount = 0
  local tokit = nil
  local simpledests = {}
  for k in pairs(destfiles) do
    if k:sub(1, 1) ~= "#" then
      realfiles[k] = true
      table.insert(simpledests, relativize(k, lib.context_stack_prefix()))
    else
      tokens[k:sub(2)] = true
      tokcount = tokcount + 1
      tokit = k:sub(2)
    end
  end
  assert(tokcount < 2)
  
  Node.context = lib.context_stack_get()

  Node.state = "asleep"
  
  -- wake up, I'm gonna need you. get yourself ready to be processed and start crunching at some point in the future
  function Node:wake()
    if self.state == "asleep" then
      -- wakey wakey!
      manager_add(manager_wrap(function ()
        self:crunch()
      end))
      self.state = "working"
    elseif self.state == "working" or self.state == "finished" then
      -- guess it's awake
    else
      assert(false)
    end
  end
  
  function Node:crunch()
    assert(self.state == "working")
    
    if tree_top() then
      assert(tree_tree[tree_top()])
      tree_tree[tree_top()][sig] = true
    end
    if not tree_tree[sig] then tree_tree[sig] = {} end
    
    tree_push(sig)
    
    for k in pairs(distill_dependencies(dependencies, destfiles, true, sig)) do
      if not files[k] then
        print("Can't find", k, "from", sig)
        assert(false)
      end
      files[k]:wake()
    end
    
    for k in pairs(distill_dependencies(dependencies, destfiles, true, sig)) do
      self.sig = nil  -- I forget why this is needed, but I suspect it's important
      files[k]:block()
    end
    
    --print("PRESIG", sig, self:signature(), built_signatures[sig])
    if flags.always_rebuild or self:signature() ~= built_signatures[sig] then
      tree_modified[sig] = true
      if self:signature() == built_signatures[sig] then
        tree_modified_forced[sig] = true
      end
      self.sig = nil
      
      local simpledeps = {}
      for k in pairs(distill_dependencies(dependencies, destfiles, true, sig)) do
        if k:sub(1, 1) ~= "#" then
          table.insert(simpledeps, relativize(k, lib.context_stack_prefix())) -- grr
        end
      end
    
      if not flags.token then
        for k in pairs(realfiles) do
          os.remove(k)
          local path = k:match("(.*)/[^/]+")
          if path and not paths_made[path] then
            -- this segment is always based on the absolute root!
            local cmd = "mkdir -p -v " .. ursa.FRAGILE.parenthesize(path)
            print_status(cmd)
            lib.context_stack_chdir_native(os.execute, cmd)
            paths_made[path] = true
          end
        end
        
        --print("Activity on", sig, activity)
        if type(activity) == "string" then
          local rv = lib.context_stack_chdir(function (line) print_status(line) return os.execute(line) end, activity)
          if rv ~= 0 then
            for k in pairs(destfiles) do
              os.remove(k)
            end
            print("Program execution failed")
            assert(false)
          end
        elseif type(activity) == "function" then
          -- it's possible that we'll discover new unknown dependencies in this arbitrary function, so we make sure the stack is updated properly
          tree_push(sig)
          lib.context_stack_chdir(activity, simpledests, simpledeps)
          tree_pop(sig)
        elseif activity == nil then
        else
          assert(false) -- whups
        end
      else
        -- token
        assert(tokit)
        built_tokens[tokit] = nil
        
        if type(activity) == "string" then
          built_tokens[tokit] = lib.context_stack_chdir(ursa.system, {activity})
        elseif type(activity) == "function" then
          -- it's possible that we'll discover new unknown dependencies in this arbitrary function, so we make sure the stack is updated properly
          tree_push(sig)
          built_tokens[tokit] = lib.context_stack_chdir(activity, simpledests, simpledeps)
          tree_pop(sig)
        else
          assert(false) -- whups
        end
        
        assert(built_tokens[tokit], "Tried to build token " .. sig .. " but the function returned nil")
      end
    end
    
    -- make sure all the files were generated
    for k in pairs(destfiles) do
      if k:sub(1, 1) ~= "#" then
        assert(lib.context_stack_chdir_native(lib.mtime, k), "File " .. k .. " wasn't generated by the given build step.")
        if files[k].rewrite then files[k]:rewrite() end -- they were written to, one presumes.
      end
    end
    
    if not flags.no_save then
      --self.sig = nil
      --print("POSTSIG", sig, self:signature(), built_signatures[sig])
      built_signatures[sig] = self:signature()
    end
    
    tree_pop(sig)
    
    self.state = "finished"
    
    if self.to_be_awoken then
      for _, v in ipairs(self.to_be_awoken) do
        manager_add(v)
      end
    end
    self.to_be_awoken = nil
    
    -- now we return! if we're shelled from something we'll just go back to it, if we weren't then we'll get garbage collected after returning
  end
  
  function Node:block()  -- please return once you're done and yield/grind until then
    local did_something = false
    --print("blocking on", sig, self.state)
    
    if self.state == "asleep" then
      self:wake()
      self:block() -- yes yes this looks pretty silly. but it's actually exactly what we want - it'll loop back around into "working" mode, then dump itself in the wait queue
    end
    
    if self.state == "working" then
      if not self.to_be_awoken then self.to_be_awoken = {} end
      
      table.insert(self.to_be_awoken, manager_get_current_state())  -- we'll add this once this node is actually done
      coroutine.yield() -- snoooooore
    end
    
    assert(self.state == "finished")
  end
  
  function Node:signature()  -- what is your signature?
    if self.sig then return self.sig end
    
    local sch = {}
    if flags.token then
      table.insert(sch, md5.sum(lib.persistence.dump(built_tokens[tokit])))
    else
      for k in pairs(destfiles) do
        table.insert(sch, sig_file(k))
      end
    end
    
    if activity == nil then
      table.insert(sch, md5.sum(""))  -- "" is pretty much equivalent
    elseif type(activity) == "string" then
      table.insert(sch, md5.sum(activity))
    elseif type(activity) == "function" then
      table.insert(sch, md5.sum(string.dump(activity)))
    else
      assert(false)
    end
    
    local deps, literals = distill_dependencies(dependencies, destfiles, true, sig)
    
    for k in pairs(deps) do
      table.insert(sch, files[k]:signature())
    end
    for k in pairs(literals) do
      table.insert(sch, k)
    end
    
    table.sort(sch) -- heh heh. our table iteration has no guaranteed order, so we do this to guarantee an order. wheeee. technically this is slightly fragile and we should be doing this only in each "group", but, well, right now we're not.
    self.sig = md5.sum(table.concat(sch, "\0"))
    
    return self.sig
  end
  
  local function wrap(func)
    return function (...)
      lib.context_stack_push(Node.context)
      local rv = lib.return_pack(func(...))
      assert(lib.context_stack_get() == Node.context)
      lib.context_stack_pop(Node.context)
      return lib.return_unpack(rv)
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
  
  if type(activity) == "table" then
    dependencies = {dependencies, activity.depends}
    activity = activity.run
  end
  
  local ofilelist = {}
  local ofileabs = {}
  
  recrunch(ofilelist, destination, true)
    
  if type(destination) ~= "string" then
    local fill = {}
    for k in pairs(ofilelist) do
      table.insert(fill, k)
    end
    table.sort(fill)
    destination = "{" .. table.concat(fill, "; ") .. "}"
  end
  
  local found_ofile = false
  for k in pairs(ofilelist) do
    --print("yoop", k)
    if files[k] then
      if files[k].unused then
        files[k] = nil -- woop
      else
        print("error when trying to create", destination)
        print("", "output file " .. k .. " already defined")
        print("", "static:", files[k].static)
        print("", "unused:", files[k].unused)
        print("", "depended on by:")
        for v in pairs(files[k].depended_on) do
          print("", "", v)
        end
        assert(false)
      end
    end
    found_ofile = true
    
    table.insert(ofileabs, make_absolute_from_core(k))
  end
  assert(found_ofile, "no output files found?")
  
  distill_dependencies(dependencies, ofilelist, false, destination) -- we need to run this because we need to resolve the dependencies and ensure that they exist
  
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
  
  if type(activity) == "table" then
    dependencies = {dependencies, activity.depends}
    activity = activity.run
  end
  
  local spath = make_standard_path("#" .. destination)
  distill_dependencies(dependencies, nil, false, spath)
  
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
local ubhackery
function ursa.token(param)
  local tok = unpack(param)
  if tok:sub(1, 1) ~= "#" then tok = "#" .. tok end
  tok = make_standard_path(tok)
  local tokp = tok:sub(2)
  
  assert(files[tok], "Tried to resolve undefined token " .. tok)
  
  if param.default then
    if not built_tokens[tokp] then
      return param.default
    end
  elseif not built_tokens[tokp] then
    -- replaced to make parallel building work better, hopefully
    ubhackery({tok}, true)
    -- we call wake() to generate all the proper tree data, then block() to actually generate stuff. not . . . entirely happy about this? figure out better semantics later, wake/block doesn't quite do what I intended
    --files[tok]:wake()
    --files[tok]:block()
    assert(built_tokens[tokp], "didn't build " .. tok)
  end
  
  return built_tokens[tokp]
end

local command_default = {} -- opaque unique token
local command_default = "(((default build command)))" -- okay it's less unique right now

function ursa.command(param)
  local destination, dependencies, activity = unpack(param)
  
  --print("Making command:", destination, dependencies, activity)
  
  distill_dependencies(dependencies, nil, false, ":" .. tostring(destination))
  
  assert(not commands[destination])
  
  local node = make_node(":" .. tostring(destination), {}, dependencies, activity, {always_rebuild = true, no_save = true})
  commands[destination] = node
end

local in_build = false
local build_id = 1
function ursa.build(param, not_outer)
  local outer = not in_build and not not_outer
  
  local tid = "(build " .. build_id .. " {" .. tostring(param[1]) .. "})"
  build_id = build_id + 1
  tree_push(tid)
  
  if outer then
    in_build = true
  end
  
  if #param == 0 then
    param = {command_default}
  end
  
  local items = {}
  for _, v in ipairs(param) do
    local ite = commands[v] or files[v]
    assert(ite, v)
    table.insert(items, ite)
  end
  
  local function proc()
    local done = false
    manager_begin(function ()
      for _, v in ipairs(items) do
        v:wake()
      end
      for _, v in ipairs(items) do
        v:block()
      end
      done = true
    end)
    assert(done, "We probably have a circular dependency! That is bad, especially since Zorba has no bloody clue how to track this down")
  end
  
  if outer then
    local status, rv = xpcall(proc, function (err) return err .. "\n" .. lib.traceback_full() end)
    
    -- gotta return back to the correct context stack, or we might write our ursa files in the wrong place
    lib.context_stack_chdir_native(function ()
      lib.persistence.save(".ursa.cache", {serial_v, built_signatures, built_tokens})
      
      local cs = md5_file(".ursa.cache", true)
      local filcs = io.open(".ursa.cache.checksum", "wb")
      filcs:write(cs)
      filcs:close()
    end)
    
    if not status then
      print_status(rv)
      os.exit(1)
    end
    
    in_build = false
    
    -- print out that chart
    if true then
      local printed = {}
      local modified = {}
      local function recursive_modified(item)
        if modified[item] ~= nil then return modified[item] end
        
        local md = tree_modified[item]
        if not md and tree_tree[item] then for k in pairs(tree_tree[item]) do
          if recursive_modified(k) then
            md = true
            break
          end
        end end
        
        modified[item] = md
        return md
      end
      local function print_item(item, depth)
        if not recursive_modified(item) then return end
        
        local pref, suff = "", ""
        if tree_modified[item] then
          if tree_modified_forced[item] then
            if not printed[item] then
              pref, suff = "\027[35m\027[1m", "\027[0m"
            else
              pref, suff = "\027[35m", "\027[0m"
            end
          else
            if not printed[item] then
              pref, suff = "\027[31m\027[1m", "\027[0m"
            else
              pref, suff = "\027[31m", "\027[0m"
            end
          end
        else
          if printed[item] then
            pref, suff = "\027[30m\027[1m", "\027[0m"
          end
        end
        
        print_status(pref .. ("  "):rep(depth) .. item .. suff)
        
        if not printed[item] and tree_tree[item] then
          printed[item] = true
          for k in pairs(tree_tree[item]) do
            print_item(k, depth + 1)
          end
        end
      end
      for _, v in ipairs(tree_roots) do
        print_item(v, 0)
      end
    end
  else
    proc()
  end
  
  tree_pop(tid)
end
ubhackery = ursa.build

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
  local path, file, params = unpack(dat)
  local context = lib.context_stack_get()
  local absolute = lib.context_stack_chdir(function () lib.chdir(path) return lib.getcwd() end)
  local prefix = lib.context_stack_prefix() .. path
  
  --print("Embedding:", path, file, prefix, absolute)
  
  local uc, ub, ul, utc = ursa.command, ursa.build, ursa.list
  ursa.command = setmetatable({default = command_default}, {__call = function () end})
  function ursa.build() end
  function ursa.list() assert(false) end
  local stack = {prefix = prefix, absolute = absolute}
  lib.context_stack_push(stack)
  local rv = lib.return_pack(lib.context_stack_chdir(function ()
    local d, e = loadfile(file)
    if not d then
      error(e)
    end
    return d(unpack(params or {}))
  end))
  lib.context_stack_pop(stack)
  ursa.command, ursa.build, ursa.list = uc, ub, ul
  --print("Ending embed")
  
  return lib.return_unpack(rv)
end

local function recurse(item, writ)
  for _, v in ipairs(item) do
    if type(v) == "string" then
      table.insert(writ, v)
    elseif type(v) == "table" then
      recurse(v, writ)
    else
      assert(false)
    end
  end
end
function ursa.absolute_from(dat)
  local path = unpack(dat)
  
  if type(path) == "table" then
    local writ = {}
    recurse(path, writ)
    
    for k, v in ipairs(writ) do
      writ[k] = ursa.absolute_from{v}
    end
    
    return writ
  elseif type(path) == "string" then
    local pref = path:sub(1, 1)
    if pref == "#" then
      return make_absolute_from_core("#" .. lib.context_stack_prefix() .. path:sub(2))
    else
      return make_absolute_from_core(lib.context_stack_prefix() .. path)
    end
  else
    assert(false)
  end
end
function ursa.relative_from(dat)
  local path = unpack(dat)
  
  if type(path) == "table" then
    local writ = {}
    recurse(path, writ)
    
    for k, v in ipairs(writ) do
      writ[k] = ursa.relative_from{v}
    end
    
    return writ
  elseif type(path) == "string" then
    return relativize(make_standard_path(path), lib.context_stack_prefix())
  else
    assert(false)
  end
end

ursa.gen = {lib = lib, print = print, print_status = print_status}

local params = {
  rule = {3},
  token = {1, default = true},
  token_rule = {3, always_rebuild = true},
  command = {3},
  build = {1e10}, -- technically infinite
  embed = {3},
  absolute_from = {1},
  relative_from = {1},
  system = {1},
}

function ursa.gen.wrap_funcs(chunk, params)
  assert(chunk)
  assert(params)
  for k, v in pairs(chunk) do
    if type(v) == "function" then
      assert(params[k], "Missing function parameter data for " .. k)
      local templ = params[k]
      ursa[k] = function (block, ...)
        assert(select('#', ...) == 0, "Positional data for " .. k)
        assert(type(block) == "table", "Not a table for call to " .. k)
        assert(table.maxn(block) <= templ[1], string.format("%d parameters for call %s (maximum is %d)", table.maxn(block), k, templ[1]))
        for tk in pairs(block) do
          if type(tk) ~= "number" then
            assert(templ[tk], "Unknown parameter " .. tk .. " in function " .. k)
          end
        end
        return v(block)
      end
    end
  end
end
ursa.gen.wrap_funcs(ursa, params)

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


ursa.DEBUG = {}
function ursa.DEBUG.dbgamount()
  local ct = 0
  for _ in pairs(files) do
    ct = ct + 1
  end
  print(ct, "files")
end
