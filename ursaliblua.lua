
ursaliblua = {}

local keywords = {
  'break', 'do', 'end', 'else',
  'elseif', 'function', 'if', 'local',
  'nil', 'not', 'or', 'repeat',
  'return', 'then', 'until', 'while', 'in'
}
for _, v in ipairs(keywords) do
  keywords[v] = true
end

local persistence

persistence =
{
  dump = function(item)
    local stix = {}
    function stix:write(txt)
      table.insert(self, txt)
      for i = #self - 1, 1, -1 do
        if string.len(self[i]) > string.len(self[i + 1]) then break end
        self[i] = self[i] .. table.remove(self, i + 1)
      end
    end
    persistence.write(stix, item, 0)
    return table.concat(stix)
  end;
  
	save = function (filename, item)
    local f = io.open(filename, "wb")
    assert(f)
    persistence.write(f, item, 0);
    f:write("\n");
    f:close()
	end;
	
	load = function (data)
		local f = loadstring("return " .. data);
		assert(f)
    return f();
	end;
	
	write = function (f, item, level)
		local t = type(item);
		persistence.writers[t](f, item, level);
	end;
	
	writeIndent = function (f, level)
		for i = 1, level do
			f:write("\t");
		end;
	end;
	
	writers = {
		["nil"] = function (f, item, level)
				f:write("nil");
			end;
		["number"] = function (f, item, level)
				f:write(tostring(item));
			end;
		["string"] = function (f, item, level)
				f:write(string.format("%q", item));
			end;
		["boolean"] = function (f, item, level)
				if item then
					f:write("true");
				else
					f:write("false");
				end
			end;
		["table"] = function (f, item, level)
				f:write("{\n");
        
        local first = true
        local hit = {}
        
        persistence.writeIndent(f, level+1);
        
        for k, v in ipairs(item) do
          hit[k] = true
          if not first then
            f:write(", ")
          end
          
          persistence.write(f, v, level+1)
          first = false
        end
        
        local order = {}
        for k, v in pairs(item) do
          if not hit[k] then table.insert(order, k) end
        end
        
        table.sort(order, function (a, b)
          if type(a) == type(b) then return a < b end
          return type(a) < type(b)
        end)
        
        for _, v in pairs(order) do
          if not first then f:write(",\n") end
          first = false
          persistence.writeIndent(f, level+1);
          
          if type(v) == "string" and v:match("^[a-zA-Z_][a-zA-Z0-9_]*$") and not keywords[v] then
            f:write(v)
          else
            f:write("[");
            persistence.write(f, v, level+1);
            f:write("]");
          end
          f:write(" = ");
          
          persistence.write(f, item[v], level+1);
        end
        f:write("\n")
        persistence.writeIndent(f, level);
        
				f:write("}");
			end;
		["function"] = function (f, item, level)
				-- Does only work for "normal" functions, not those
				-- with upvalues or c functions
				local dInfo = debug.getinfo(item, "uS");
				if dInfo.nups > 0 then
					f:write("nil -- functions with upvalue not supported\n");
				elseif dInfo.what ~= "Lua" then
					f:write("nil -- function is not a lua function\n");
				else
					local r, s = pcall(string.dump,item);
					if r then
						f:write(string.format("loadstring(%q)", s));
					else
						f:write("nil -- function could not be dumped\n");
					end
				end
			end;
		["thread"] = function (f, item, level)
				f:write("nil --thread\n");
			end;
		["userdata"] = function (f, item, level)
				f:write("nil --userdata\n");
			end;
	}
}

ursaliblua.persistence = persistence
