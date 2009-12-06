
#include "lua.h"
#include "lauxlib.h"


static int ursalib_unlink(lua_State *L) {
  unlink(luaL_checkstring(L, 1));
  return 0;
}

LUALIB_API int luaopen_ursalib(lua_State *L)
{
  const luaL_reg ursil[] = {
    {"unlink", ursalib_unlink},
    {NULL, NULL}
  };

  luaL_register(L, "ursalib", ursil);

  return 0;
}
