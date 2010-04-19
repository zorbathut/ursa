
#include "lua.h"
#include "lauxlib.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <fcntl.h>
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

// Spawn a new process, return a handle
static int ursalib_process_spawn(lua_State *L) {
  FILE *fil;
  void *dat;
  int fd;
  int rv;
  
  fil = popen(luaL_checkstring(L, 1), "r");
  if(!fil) {
    luaL_error(L, "failure to popen, world collapsing in flames");
  }
  
  dat = lua_newuserdata(L, sizeof(fil));
  *(FILE**)dat = fil;
  
  fd = fileno(fil);
  if(fd == -1) {
    luaL_error(L, "failure to get fd, world collapsing in flames");
  }
  
  rv = fcntl(fd, F_SETFL, O_NONBLOCK);
  if(rv == -1) {
    luaL_error(L, "failure to set nonblock, world collapsing in flames");
  }
  
  return 1;
}

// Given a set of handles, return the set that is ready to read
static int ursalib_process_scan(lua_State *L) {
  int ct;
  void *ud;
  FILE *fil;
  int filno;
  int i;
  int tfd;
  int mx = 0;
  fd_set fdset_read;
  
  FD_ZERO(&fdset_read);
  
  luaL_checktype(L, 1, LUA_TTABLE);
  
  ct = lua_objlen(L, 1);
  for(i = 1; i <= ct; i++) {
    lua_pushnumber(L, i);
    lua_pushnumber(L, i);
    lua_gettable(L, 1);
    ud = lua_touserdata(L, -1);
    lua_pop(L, 2);
    
    fil = *(FILE**)ud;
    filno = fileno(fil);
    FD_SET(filno, &fdset_read);
    if(filno > mx)
      mx = filno;
  }
  
  select(mx + 1, &fdset_read, NULL, NULL, NULL);
  
  lua_newtable(L);
  for(i = 1; i <= ct; i++) {
    lua_pushnumber(L, i);
    lua_pushnumber(L, i);
    lua_gettable(L, 1);
    ud = lua_touserdata(L, -1);
    
    fil = *(FILE**)ud;
    filno = fileno(fil);
    
    if(FD_ISSET(filno, &fdset_read)) {
      lua_settable(L, 2);
    } else {
      lua_pop(L, 2);
    }
  }
  
  return 1;
}

char bufr[16384];

// Given a handle, read a chunk
static int ursalib_process_read(lua_State *L) {
  void *ud;
  FILE *fil;
  int len;
  
  ud = lua_touserdata(L, 1);
  if(!ud) {
    luaL_error(L, "omg no userdata");
  }
  fil = *(FILE**)ud;
  if(!fil) {
    luaL_error(L, "omg no fil");
  }
  
  //printf("recv\n");
  //len = recv(filno, bufr, sizeof(bufr), 0); // msg_dontwait?
  len = fread(bufr, 1, sizeof(bufr), fil);
  if(len == -1) {
    perror("wut wut");
    luaL_error(L, "omg something went wrong");
  }
  //printf("recve %d\n", len);
  
  lua_pushlstring(L, bufr, len);
  lua_pushboolean(L, feof(fil));
  return 2;
}
  
// Given a handle, close it
static int ursalib_process_close(lua_State *L) {
  void *ud;
  FILE *fil;
  ud = lua_touserdata(L, -1);
  fil = *(FILE**)ud;
  lua_pushinteger(L, pclose(fil));
  return 1;
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
    
    {"process_spawn", ursalib_process_spawn},
    {"process_scan", ursalib_process_scan},
    {"process_read", ursalib_process_read},
    {"process_close", ursalib_process_close},
    {NULL, NULL}
  };

  luaL_register(L, "ursalibc", ursil);

  return 0;
}
