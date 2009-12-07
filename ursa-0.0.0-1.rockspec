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
  "md5 >= 1.1.0",
}
build = {
  type = "builtin",
  
  modules = {
    ursa = "ursa.lua",
    
    ursaliblua = "ursaliblua.lua",
    
    ursalibc = "ursalib.c",
  },
}
