
#include "lua.h"
#include "lauxlib.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

static int ursalib_system(lua_State *L) {
  
  FILE *fil = popen(luaL_checkstring(L, 1), "r");
  if(!fil) {
    luaL_error(L, "failure to popen, world collapsing in flames");
  }

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

static int ursalib_getcwd(lua_State *L) {
  char bf[2048];
  if(!getcwd(bf, sizeof(bf))) {
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

static int ursalib_mtime(lua_State *L) {
  const char *st = luaL_checklstring(L, 1, NULL);
  struct stat stt;
  int rv = stat(st, &stt);
  if(rv == -1) return 0;
  lua_pushinteger(L, stt.st_mtime);
  return 1;
}

LUALIB_API int luaopen_ursalibc(lua_State *L)
{
  const luaL_reg ursil[] = {
    {"system", ursalib_system},
    {"getcwd", ursalib_getcwd},
    {"chdir", ursalib_chdir},
    {"mtime", ursalib_mtime},
    {NULL, NULL}
  };

  luaL_register(L, "ursalibc", ursil);

  return 0;
}
