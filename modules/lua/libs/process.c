/*****************************************************************************
 * process.c: asynchronous child processes for Lua extensions
 *****************************************************************************
 * Copyright (C) 2026 the PowerVLC team
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************
 *
 * The ordinary Lua os.execute/io.popen functions go through a shell and either
 * block the extension thread or require fragile platform-specific quoting.
 * This deliberately small binding launches an argv vector directly, redirects
 * both output streams to a caller-owned file, and lets a script poll it from
 * vlc.timer().  No reader thread, pipe buffer or callback crosses into Lua.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <vlc_common.h>

#include "../vlc.h"
#include "../libs.h"

typedef struct vlclua_detached_process vlclua_detached_process_t;

#if defined(_WIN32)

# include <vlc_charset.h>
# include <windows.h>

typedef struct
{
    HANDLE process;
    HANDLE job;
    DWORD pid;
    bool detached;
    bool done;
    int code;
    vlclua_detached_process_t *tracked;
} vlclua_process_t;

struct vlclua_detached_process
{
    vlclua_detached_process_t *next;
    HANDLE process;
    DWORD pid;
};

static vlc_mutex_t detached_lock = VLC_STATIC_MUTEX;
static vlclua_detached_process_t *detached_processes;

static int ProcessTrackDetached( vlclua_process_t *process )
{
    vlclua_detached_process_t *tracked = malloc( sizeof( *tracked ) );
    if( tracked == NULL )
        return ERROR_NOT_ENOUGH_MEMORY;

    if( !DuplicateHandle( GetCurrentProcess(), process->process,
                          GetCurrentProcess(), &tracked->process,
                          0, FALSE, DUPLICATE_SAME_ACCESS ) )
    {
        int error = GetLastError();
        free( tracked );
        return error;
    }
    tracked->pid = process->pid;

    vlc_mutex_lock( &detached_lock );
    tracked->next = detached_processes;
    detached_processes = tracked;
    process->tracked = tracked;
    vlc_mutex_unlock( &detached_lock );
    return 0;
}

static void ProcessUntrackDetached( vlclua_process_t *process )
{
    vlclua_detached_process_t *tracked = process->tracked;
    if( tracked == NULL )
        return;

    vlc_mutex_lock( &detached_lock );
    vlclua_detached_process_t **cursor = &detached_processes;
    while( *cursor != NULL && *cursor != tracked )
        cursor = &( *cursor )->next;
    if( *cursor == tracked )
        *cursor = tracked->next;
    process->tracked = NULL;
    vlc_mutex_unlock( &detached_lock );

    CloseHandle( tracked->process );
    free( tracked );
}

/* Quote one argument according to CommandLineToArgvW's rules.  CreateProcess
 * receives one command-line string even though Lua supplied a real argv, so
 * this is the one place where the vector has to be serialized again. */
static char *Win32CommandLine( char **argv, size_t argc )
{
    size_t size = 1;
    for( size_t i = 0; i < argc; ++i )
    {
        size_t len = strlen( argv[i] );
        if( len > (SIZE_MAX - size - 4) / 2 )
            return NULL;
        size += len * 2 + 4;
    }

    char *line = malloc( size );
    if( line == NULL )
        return NULL;
    char *out = line;

    for( size_t i = 0; i < argc; ++i )
    {
        if( i != 0 )
            *out++ = ' ';
        *out++ = '"';

        const char *in = argv[i];
        size_t slashes = 0;
        for( ;; )
        {
            if( *in == '\\' )
            {
                ++slashes;
                ++in;
                continue;
            }

            if( *in == '"' )
            {
                for( size_t j = 0; j < slashes * 2 + 1; ++j )
                    *out++ = '\\';
                *out++ = *in++;
                slashes = 0;
                continue;
            }

            if( *in == '\0' )
            {
                for( size_t j = 0; j < slashes * 2; ++j )
                    *out++ = '\\';
                break;
            }

            for( size_t j = 0; j < slashes; ++j )
                *out++ = '\\';
            slashes = 0;
            *out++ = *in++;
        }
        *out++ = '"';
    }
    *out = '\0';
    return line;
}

static int ProcessSpawn( vlclua_process_t *process, char **argv, size_t argc,
                         const char *output, bool detached )
{
    int error = ERROR_NOT_ENOUGH_MEMORY;
    char *line = Win32CommandLine( argv, argc );
    wchar_t *wline = line != NULL ? ToWide( line ) : NULL;
    wchar_t *woutput = ToWide( output );
    free( line );
    if( wline == NULL || woutput == NULL )
        goto out;

    SECURITY_ATTRIBUTES security = {
        .nLength = sizeof( security ),
        .lpSecurityDescriptor = NULL,
        .bInheritHandle = TRUE,
    };
    HANDLE out_handle = CreateFileW( woutput, GENERIC_WRITE,
                                     FILE_SHARE_READ | FILE_SHARE_WRITE,
                                     &security, CREATE_ALWAYS,
                                     FILE_ATTRIBUTE_NORMAL, NULL );
    if( out_handle == INVALID_HANDLE_VALUE )
    {
        error = GetLastError();
        goto out;
    }

    HANDLE input = CreateFileW( L"NUL", GENERIC_READ,
                                FILE_SHARE_READ | FILE_SHARE_WRITE,
                                &security, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL, NULL );
    if( input == INVALID_HANDLE_VALUE )
    {
        error = GetLastError();
        CloseHandle( out_handle );
        goto out;
    }

    STARTUPINFOW startup;
    memset( &startup, 0, sizeof( startup ) );
    startup.cb = sizeof( startup );
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = input;
    startup.hStdOutput = out_handle;
    startup.hStdError = out_handle;

    PROCESS_INFORMATION info;
    memset( &info, 0, sizeof( info ) );
    if( !CreateProcessW( NULL, wline, NULL, NULL, TRUE,
                         CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
                                          | CREATE_SUSPENDED,
                         NULL, NULL, &startup, &info ) )
        error = GetLastError();
    else
    {
        /* Keep ffmpeg and any other helper in the same cancellable unit. On
         * pre-Windows-8 systems a PowerVLC process already inside a job may
         * reject nesting; in that case cancellation still covers yt-dlp. */
        HANDLE job = detached ? NULL : CreateJobObjectW( NULL, NULL );
        if( job != NULL )
        {
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
            memset( &limits, 0, sizeof( limits ) );
            limits.BasicLimitInformation.LimitFlags =
                JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if( !SetInformationJobObject( job, JobObjectExtendedLimitInformation,
                                          &limits, sizeof( limits ) )
             || !AssignProcessToJobObject( job, info.hProcess ) )
            {
                CloseHandle( job );
                job = NULL;
            }
        }
        process->process = info.hProcess;
        process->job = job;
        process->pid = info.dwProcessId;
        process->detached = detached;
        process->done = false;
        process->code = 0;
        ResumeThread( info.hThread );
        CloseHandle( info.hThread );
        error = 0;
    }
    CloseHandle( input );
    CloseHandle( out_handle );

out:
    free( wline );
    free( woutput );
    return error;
}

static bool ProcessUpdate( vlclua_process_t *process )
{
    if( process->done )
        return false;

    DWORD wait = WaitForSingleObject( process->process, 0 );
    if( wait == WAIT_TIMEOUT )
        return true;

    DWORD code = (DWORD)-1;
    if( wait == WAIT_OBJECT_0 )
        GetExitCodeProcess( process->process, &code );
    process->code = code > INT_MAX ? -1 : (int)code;
    process->done = true;
    ProcessUntrackDetached( process );
    return false;
}

static void ProcessCancel( vlclua_process_t *process, bool force )
{
    (void)force;
    if( ProcessUpdate( process ) )
    {
        if( process->job != NULL )
            TerminateJobObject( process->job, 130 );
        else
            TerminateProcess( process->process, 130 );
    }
}

static void ProcessClose( vlclua_process_t *process )
{
    if( process->process == NULL )
        return;
    if( process->detached )
    {
        ProcessUpdate( process );
        CloseHandle( process->process );
        process->process = NULL;
        return;
    }
    ProcessCancel( process, true );
    if( !process->done )
    {
        WaitForSingleObject( process->process, 2000 );
        ProcessUpdate( process );
    }
    if( process->job != NULL )
    {
        CloseHandle( process->job );
        process->job = NULL;
    }
    CloseHandle( process->process );
    process->process = NULL;
}

#else /* POSIX */

# include <signal.h>
# include <sys/types.h>
# include <sys/wait.h>
# include <unistd.h>

#ifndef _POSIX_SPAWN
# define _POSIX_SPAWN (-1)
#endif
#if (_POSIX_SPAWN >= 0)
# include <spawn.h>
# ifdef __APPLE__
#  include <crt_externs.h>
#  define VLC_PROCESS_ENVIRON (*_NSGetEnviron())
# else
extern char **environ;
#  define VLC_PROCESS_ENVIRON environ
# endif
#endif

#include <vlc_fs.h>

typedef struct
{
    pid_t pid;
    bool grouped;
    bool detached;
    bool done;
    int code;
    vlclua_detached_process_t *tracked;
} vlclua_process_t;

struct vlclua_detached_process
{
    vlclua_detached_process_t *next;
    pid_t pid;
    bool grouped;
};

static vlc_mutex_t detached_lock = VLC_STATIC_MUTEX;
static vlclua_detached_process_t *detached_processes;

static int ProcessTrackDetached( vlclua_process_t *process )
{
    vlclua_detached_process_t *tracked = malloc( sizeof( *tracked ) );
    if( tracked == NULL )
        return ENOMEM;
    tracked->pid = process->pid;
    tracked->grouped = process->grouped;

    vlc_mutex_lock( &detached_lock );
    tracked->next = detached_processes;
    detached_processes = tracked;
    process->tracked = tracked;
    vlc_mutex_unlock( &detached_lock );
    return 0;
}

static void ProcessUntrackDetached( vlclua_process_t *process )
{
    vlclua_detached_process_t *tracked = process->tracked;
    if( tracked == NULL )
        return;

    vlc_mutex_lock( &detached_lock );
    vlclua_detached_process_t **cursor = &detached_processes;
    while( *cursor != NULL && *cursor != tracked )
        cursor = &( *cursor )->next;
    if( *cursor == tracked )
        *cursor = tracked->next;
    process->tracked = NULL;
    vlc_mutex_unlock( &detached_lock );
    free( tracked );
}

static int ProcessSpawn( vlclua_process_t *process, char **argv, size_t argc,
                         const char *output, bool detached )
{
    (void)argc;
    int output_fd = vlc_open( output, O_WRONLY | O_CREAT | O_TRUNC, 0600 );
    if( output_fd < 0 )
        return errno;

    pid_t pid = -1;
    int error = 0;
    bool grouped = false;

#if (_POSIX_SPAWN >= 0)
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attr;
    if( (error = posix_spawn_file_actions_init( &actions )) != 0 )
        goto out;
    if( (error = posix_spawn_file_actions_addopen( &actions, STDIN_FILENO,
                                                   "/dev/null", O_RDONLY,
                                                   0644 )) != 0
     || (error = posix_spawn_file_actions_adddup2( &actions, output_fd,
                                                   STDOUT_FILENO )) != 0
     || (error = posix_spawn_file_actions_adddup2( &actions, output_fd,
                                                   STDERR_FILENO )) != 0 )
    {
        posix_spawn_file_actions_destroy( &actions );
        goto out;
    }

    if( (error = posix_spawnattr_init( &attr )) != 0 )
    {
        posix_spawn_file_actions_destroy( &actions );
        goto out;
    }

    short flags = POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK;
    sigset_t empty, defaults;
    sigemptyset( &empty );
    sigemptyset( &defaults );
    sigaddset( &defaults, SIGPIPE );
    posix_spawnattr_setsigmask( &attr, &empty );
    posix_spawnattr_setsigdefault( &attr, &defaults );
#ifdef POSIX_SPAWN_SETPGROUP
    if( posix_spawnattr_setpgroup( &attr, 0 ) == 0 )
    {
        flags |= POSIX_SPAWN_SETPGROUP;
        grouped = true;
    }
#endif
    posix_spawnattr_setflags( &attr, flags );
    error = posix_spawnp( &pid, argv[0], &actions, &attr, argv,
                          VLC_PROCESS_ENVIRON );
    posix_spawnattr_destroy( &attr );
    posix_spawn_file_actions_destroy( &actions );
#else
    pid = fork();
    if( pid < 0 )
        error = errno;
    else if( pid == 0 )
    {
        setpgid( 0, 0 );
        int input = open( "/dev/null", O_RDONLY );
        if( input >= 0 )
            dup2( input, STDIN_FILENO );
        dup2( output_fd, STDOUT_FILENO );
        dup2( output_fd, STDERR_FILENO );
        execvp( argv[0], argv );
        _exit( 127 );
    }
    else
        grouped = true;
#endif

#if (_POSIX_SPAWN >= 0)
out:
#endif
    vlc_close( output_fd );
    if( error != 0 )
        return error;

    process->pid = pid;
    process->grouped = grouped;
    process->detached = detached;
    process->done = false;
    process->code = 0;
    return 0;
}

static bool ProcessUpdate( vlclua_process_t *process )
{
    if( process->done )
        return false;

    int status;
    pid_t value;
    do
        value = waitpid( process->pid, &status, WNOHANG );
    while( value < 0 && errno == EINTR );

    if( value == 0 )
        return true;

    if( value < 0 )
        process->code = -1;
    else if( WIFEXITED( status ) )
        process->code = WEXITSTATUS( status );
    else if( WIFSIGNALED( status ) )
        process->code = 128 + WTERMSIG( status );
    else
        return true;
    process->done = true;
    ProcessUntrackDetached( process );
    return false;
}

static void ProcessSignal( vlclua_process_t *process, int signal_ )
{
    if( process->grouped && kill( -process->pid, signal_ ) == 0 )
        return;
    kill( process->pid, signal_ );
}

static void ProcessCancel( vlclua_process_t *process, bool force )
{
    if( ProcessUpdate( process ) )
        ProcessSignal( process, force ? SIGKILL : SIGTERM );
}

static void ProcessClose( vlclua_process_t *process )
{
    if( process->pid <= 0 || process->done )
        return;

    /* A detached long-running service is deliberately left alive when its
     * Lua extension closes. If it already exited, ProcessUpdate reaps it. */
    if( process->detached )
    {
        ProcessUpdate( process );
        return;
    }

    /* A collected handle must not leave a zombie behind. SIGKILL makes the
     * blocking reap bounded to the scheduler, and this path normally only
     * runs while the whole extension state is being torn down. */
    ProcessCancel( process, true );
    int status;
    while( waitpid( process->pid, &status, 0 ) < 0 && errno == EINTR )
        ;
    process->done = true;
}

#endif

void vlclua_process_cleanup_detached( void )
{
    vlc_mutex_lock( &detached_lock );
    vlclua_detached_process_t *tracked = detached_processes;
    detached_processes = NULL;
    vlc_mutex_unlock( &detached_lock );

    while( tracked != NULL )
    {
        vlclua_detached_process_t *next = tracked->next;
#if defined(_WIN32)
        if( WaitForSingleObject( tracked->process, 0 ) == WAIT_TIMEOUT )
            TerminateProcess( tracked->process, 130 );
        WaitForSingleObject( tracked->process, 2000 );
        CloseHandle( tracked->process );
#else
        int status;
        pid_t value;
        do
            value = waitpid( tracked->pid, &status, WNOHANG );
        while( value < 0 && errno == EINTR );
        if( value == 0 )
        {
            if( !tracked->grouped || kill( -tracked->pid, SIGTERM ) != 0 )
                kill( tracked->pid, SIGTERM );
            for( unsigned i = 0; i < 20; ++i )
            {
                msleep( VLC_TICK_FROM_MS( 50 ) );
                do
                    value = waitpid( tracked->pid, &status, WNOHANG );
                while( value < 0 && errno == EINTR );
                if( value != 0 )
                    break;
            }
            if( value == 0 )
            {
                if( !tracked->grouped || kill( -tracked->pid, SIGKILL ) != 0 )
                    kill( tracked->pid, SIGKILL );
                while( waitpid( tracked->pid, &status, 0 ) < 0 && errno == EINTR )
                    ;
            }
        }
#endif
        free( tracked );
        tracked = next;
    }
}

/*****************************************************************************
 * Lua binding
 *****************************************************************************/

static vlclua_process_t *CheckProcess( lua_State *L )
{
    return luaL_checkudata( L, 1, "vlc_process" );
}

static int vlclua_process_status( lua_State *L )
{
    vlclua_process_t *process = CheckProcess( L );
    bool running = ProcessUpdate( process );
    lua_pushboolean( L, running );
    if( running )
        return 1;
    lua_pushinteger( L, process->code );
    return 2;
}

static int vlclua_process_cancel( lua_State *L )
{
    vlclua_process_t *process = CheckProcess( L );
    bool was_running = ProcessUpdate( process );
    if( was_running )
        ProcessCancel( process, false );
    lua_pushboolean( L, was_running );
    return 1;
}

static int vlclua_process_pid( lua_State *L )
{
    vlclua_process_t *process = CheckProcess( L );
    lua_pushnumber( L, (lua_Number)process->pid );
    return 1;
}

static int vlclua_process_gc( lua_State *L )
{
    ProcessClose( CheckProcess( L ) );
    return 0;
}

static const luaL_Reg vlclua_process_methods[] = {
    { "status", vlclua_process_status },
    { "cancel", vlclua_process_cancel },
    { "pid", vlclua_process_pid },
    { "close", vlclua_process_gc },
    { NULL, NULL },
};

/* vlc.process.start({ executable, arg1, ... }, output_path [, detached])
 *
 * Returns a process handle, or nil plus an error. stdout and stderr share the
 * output file, which is truncated before the child starts. A detached child
 * is not killed when the Lua handle is collected. */
static int vlclua_process_start( lua_State *L )
{
    luaL_checktype( L, 1, LUA_TTABLE );
    const char *output = luaL_checkstring( L, 2 );
    bool detached = lua_toboolean( L, 3 );
    size_t argc = lua_objlen( L, 1 );
    if( argc == 0 || argc > 512 )
        return luaL_error( L, "process argv must contain 1 to 512 strings" );

    char **argv = calloc( argc + 1, sizeof( *argv ) );
    if( argv == NULL )
        return luaL_error( L, "out of memory" );

    for( size_t i = 0; i < argc; ++i )
    {
        lua_rawgeti( L, 1, i + 1 );
        if( !lua_isstring( L, -1 ) )
        {
            lua_pop( L, 1 );
            free( argv );
            return luaL_error( L, "process argv entries must be strings" );
        }
        argv[i] = (char *)lua_tostring( L, -1 );
        lua_pop( L, 1 );
    }

    vlclua_process_t *process = lua_newuserdata( L, sizeof( *process ) );
    memset( process, 0, sizeof( *process ) );
    int error = ProcessSpawn( process, argv, argc, output, detached );
    free( argv );
    if( error == 0 && detached )
    {
        error = ProcessTrackDetached( process );
        if( error != 0 )
        {
            process->detached = false;
            ProcessClose( process );
        }
    }
    if( error != 0 )
    {
        lua_pop( L, 1 );
        lua_pushnil( L );
#if defined(_WIN32)
        lua_pushfstring( L, "cannot start process (Windows error %d)", error );
#else
        lua_pushfstring( L, "cannot start process: %s", strerror( error ) );
#endif
        return 2;
    }

    if( luaL_newmetatable( L, "vlc_process" ) )
    {
        lua_newtable( L );
        luaL_register( L, NULL, vlclua_process_methods );
        lua_setfield( L, -2, "__index" );
        lua_pushcfunction( L, vlclua_process_gc );
        lua_setfield( L, -2, "__gc" );
    }
    lua_setmetatable( L, -2 );
    return 1;
}

static const luaL_Reg vlclua_process_reg[] = {
    { "start", vlclua_process_start },
    { NULL, NULL },
};

void luaopen_process( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_process_reg );
    lua_setfield( L, -2, "process" );
}
