
#include "lua.h"
#include "lauxlib.h"


static int ursalib_system(lua_State *L) {
  //printf("ULS 1\n");
  FILE *fil = popen(luaL_checkstring(L, 1), "rb");
  //printf("ULS 2\n");
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  //printf("ULS 3\n");
  while(1) {
    char *buff = luaL_prepbuffer(&b);
    //printf("ULS 4\n");
    int siz = fread(buff, 1, LUAL_BUFFERSIZE, fil);
    //printf("ULS 5\n");
    luaL_addsize(&b, siz);
    //printf("ULS 6\n");
    if(siz != LUAL_BUFFERSIZE)
      break;
  }
  //printf("ULS 7\n");
  luaL_pushresult(&b);
  //printf("ULS 8\n");
  lua_pushinteger(L, pclose(fil));
  //printf("ULS 9\n");

  return 2;
}

static int ursalib_getcwd(lua_State *L) {
  char bf[2048];
  if(getcwd(bf, sizeof(bf)) != bf) {
    luaL_error(L, "couldn't get cwd for some wacky reason");
  }
  lua_pushstring(L, bf);
  return 1;
}

static int ursalib_chdir(lua_State *L) {
  const char *st = luaL_checklstring(L, 1, NULL);
  if(!st) {
    luaL_error(L, "chdir failure, man, I don't know");
  }
  chdir(st);
  return 0;
}

LUALIB_API int luaopen_ursalibc(lua_State *L)
{
  const luaL_reg ursil[] = {
    {"system", ursalib_system},
    {"getcwd", ursalib_getcwd},
    {"chdir", ursalib_chdir},
    {NULL, NULL}
  };

  luaL_register(L, "ursalibc", ursil);

  return 0;
}
