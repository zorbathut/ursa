package = "Ursa"
version = "0.0.0-1"
source = {
  url = "http://..." -- no
}
description = {
  summary = "none",
  detailed = "none",
  homepage = "none",
  license = "BSD",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  
  modules = {
    ursa = "ursa.lua",
    ["ursa.util"] = "util.lua",
    
    ursaliblua = "ursaliblua.lua",
    ursalibcontext = "ursalibcontext.lua",
    
    ursalibc = "ursalib.c",
  },
}
