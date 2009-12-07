
#include "lua.h"
#include "lauxlib.h"


static int ursalib_system(lua_State *L) {
  FILE *fil = popen(luaL_checkstring(L, 1), "rb");
  
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  
  while(1) {
    char *buff = luaL_prepbuffer(&b);
    int siz = fread(buff, 1, LUAL_BUFFERSIZE, fil);
    luaL_addsize(&b, siz);
    if(siz != LUAL_BUFFERSIZE)
      break;
  }
  
  luaL_pushresult(&b);
  lua_pushinteger(L, pclose(fil));

  return 2;
}

LUALIB_API int luaopen_ursalibc(lua_State *L)
{
  const luaL_reg ursil[] = {
    {"system", ursalib_system},
    {NULL, NULL}
  };

  luaL_register(L, "ursalibc", ursil);

  return 0;
}
