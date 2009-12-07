
#include "lua.h"
#include "lauxlib.h"


static int ursalib_system(lua_State *L) {
  FILE *fil = popen(luaL_checkstring(L, 1), "rb");
  
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  
  while(1) {
    char buff[4096];
    int siz = fread(buff, 1, sizeof(buff), fil);
    luaL_addlstring(&b, buff, siz);
    if(siz != sizeof(buff))
      break;
  }
  
  lua_pushinteger(L, pclose(fil));
  luaL_pushresult(&b);

  return 2;
}

LUALIB_API int luaopen_ursalib(lua_State *L)
{
  const luaL_reg ursil[] = {
    {"system", ursalib_system},
    {NULL, NULL}
  };

  luaL_register(L, "ursalib", ursil);

  return 0;
}
