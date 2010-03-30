
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
  int rv = lstat(st, &stt);
  if(rv == -1) return 0;
  lua_pushinteger(L, stt.st_mtime);
  return 1;
}

static int ursalib_chmod_get(lua_State *L) {
  const char *st = luaL_checklstring(L, 1, NULL);
  struct stat stt;
  int rv = stat(st, &stt);
  if(rv == -1) return 0;
  lua_pushinteger(L, stt.st_mode & 0777);
  return 1;
}

static int ursalib_chmod_set(lua_State *L) {
  const char *st = luaL_checklstring(L, 1, NULL);
  chmod(st, luaL_checkint(L, 2));
  return 0;
}

#define LEVELS1	10000	/* size of the first part of the stack */
#define LEVELS2	10000	/* size of the second part of the stack */

static lua_State *getthread (lua_State *L, int *arg) {
  if (lua_isthread(L, 1)) {
    *arg = 1;
    return lua_tothread(L, 1);
  }
  else {
    *arg = 0;
    return L;
  }
}
static int ursalib_traceback_full(lua_State *L) {
  int level;
  int firstpart = 1;  /* still before eventual `...' */
  int arg;
  lua_State *L1 = getthread(L, &arg);
  lua_Debug ar;
  if (lua_isnumber(L, arg+2)) {
    level = (int)lua_tointeger(L, arg+2);
    lua_pop(L, 1);
  }
  else
    level = (L == L1) ? 1 : 0;  /* level 0 may be this own function */
  if (lua_gettop(L) == arg)
    lua_pushliteral(L, "");
  else if (!lua_isstring(L, arg+1)) return 1;  /* message is not a string */
  else lua_pushliteral(L, "\n");
  lua_pushliteral(L, "stack traceback:");
  while (lua_getstack(L1, level++, &ar)) {
    if (level > LEVELS1 && firstpart) {
      /* no more than `LEVELS2' more levels? */
      if (!lua_getstack(L1, level+LEVELS2, &ar))
        level--;  /* keep going */
      else {
        lua_pushliteral(L, "\n\t...");  /* too many levels */
        while (lua_getstack(L1, level+LEVELS2, &ar))  /* find last levels */
          level++;
      }
      firstpart = 0;
      continue;
    }
    lua_pushliteral(L, "\n\t");
    lua_getinfo(L1, "Snl", &ar);
    lua_pushfstring(L, "%s:", ar.short_src);
    if (ar.currentline > 0)
      lua_pushfstring(L, "%d:", ar.currentline);
    if (*ar.namewhat != '\0')  /* is there a name? */
        lua_pushfstring(L, " in function " LUA_QS, ar.name);
    else {
      if (*ar.what == 'm')  /* main? */
        lua_pushfstring(L, " in main chunk");
      else if (*ar.what == 'C' || *ar.what == 't')
        lua_pushliteral(L, " ?");  /* C function or tail call */
      else
        lua_pushfstring(L, " in function <%s:%d>",
                           ar.short_src, ar.linedefined);
    }
    lua_concat(L, lua_gettop(L) - arg);
  }
  lua_concat(L, lua_gettop(L) - arg);
  return 1;
}

LUALIB_API int luaopen_ursalibc(lua_State *L)
{
  const luaL_reg ursil[] = {
    {"system", ursalib_system},
    {"getcwd", ursalib_getcwd},
    {"chdir", ursalib_chdir},
    {"mtime", ursalib_mtime},
    {"chmod_get", ursalib_chmod_get},
    {"chmod_set", ursalib_chmod_set},
    {"traceback_full", ursalib_traceback_full},
    {NULL, NULL}
  };

  luaL_register(L, "ursalibc", ursil);

  return 0;
}
