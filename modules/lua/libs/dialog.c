/*****************************************************************************
 * dialog.c: Functions to create interface dialogs from Lua extensions
 *****************************************************************************
 * Copyright (C) 2009-2010 VideoLAN and authors
 * $Id$
 *
 * Authors: Jean-Philippe André < jpeg # videolan.org >
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_dialog.h>
#include <vlc_extensions.h>

#include "../vlc.h"
#include "../libs.h"
#include "../extension.h"

#include "assert.h"

/*****************************************************************************
 *
 *****************************************************************************/

/* Dialog functions */
static int vlclua_dialog_create( lua_State *L );
static int vlclua_dialog_delete( lua_State *L );
static int vlclua_dialog_show( lua_State *L );
static int vlclua_dialog_hide( lua_State *L );
static int vlclua_dialog_set_title( lua_State *L );
static int vlclua_dialog_update( lua_State *L );
static int vlclua_dialog_set_size( lua_State *L );
static void lua_SetDialogUpdate( lua_State *L, int flag );
static int lua_GetDialogUpdate( lua_State *L );
int lua_DialogFlush( lua_State *L );

static int vlclua_dialog_add_button( lua_State *L );
static int vlclua_dialog_add_label( lua_State *L );
static int vlclua_dialog_add_html( lua_State *L );
static int vlclua_dialog_add_text_inner( lua_State *L, int );
static inline int vlclua_dialog_add_text_input( lua_State *L )
{
    return vlclua_dialog_add_text_inner( L, EXTENSION_WIDGET_TEXT_FIELD );
}
static inline int vlclua_dialog_add_password( lua_State *L )
{
    return vlclua_dialog_add_text_inner( L, EXTENSION_WIDGET_PASSWORD );
}
static inline int vlclua_dialog_add_html( lua_State *L )
{
    return vlclua_dialog_add_text_inner( L, EXTENSION_WIDGET_HTML );
}
static int vlclua_dialog_add_check_box( lua_State *L );
static int vlclua_dialog_add_list( lua_State *L );
static int vlclua_dialog_add_dropdown( lua_State *L );
static int vlclua_dialog_add_image( lua_State *L );
static int vlclua_dialog_add_spin_icon( lua_State *L );
static int vlclua_create_widget_inner( lua_State *L, int i_args,
                                       extension_widget_t *p_widget);

static int vlclua_dialog_delete_widget( lua_State *L );

/* Widget methods */
static int vlclua_widget_set_text( lua_State *L );
static int vlclua_widget_get_text( lua_State *L );
static int vlclua_widget_set_checked( lua_State *L );
static int vlclua_widget_get_checked( lua_State *L );
static int vlclua_widget_add_value( lua_State *L );
static int vlclua_widget_get_value( lua_State *L );
static int vlclua_widget_set_value( lua_State *L );
static int vlclua_widget_clear( lua_State *L );
static int vlclua_widget_get_selection( lua_State *L );
static int vlclua_widget_animate( lua_State *L );
static int vlclua_widget_stop( lua_State *L );

/* Helpers */
static void AddWidget( extension_dialog_t *p_dialog,
                       extension_widget_t *p_widget );
static int DeleteWidget( extension_dialog_t *p_dialog,
                         extension_widget_t *p_widget );

static const luaL_Reg vlclua_dialog_reg[] = {
    { "show", vlclua_dialog_show },
    { "hide", vlclua_dialog_hide },
    { "delete", vlclua_dialog_delete },
    { "set_title", vlclua_dialog_set_title },
    { "set_size", vlclua_dialog_set_size },
    { "update", vlclua_dialog_update },

    { "add_button", vlclua_dialog_add_button },
    { "add_label", vlclua_dialog_add_label },
    { "add_html", vlclua_dialog_add_html },
    { "add_text_input", vlclua_dialog_add_text_input },
    { "add_password", vlclua_dialog_add_password },
    { "add_check_box", vlclua_dialog_add_check_box },
    { "add_dropdown", vlclua_dialog_add_dropdown },
    { "add_list", vlclua_dialog_add_list },
    { "add_image", vlclua_dialog_add_image },
    { "add_spin_icon", vlclua_dialog_add_spin_icon },

    { "del_widget", vlclua_dialog_delete_widget },
    { NULL, NULL }
};

static const luaL_Reg vlclua_widget_reg[] = {
    { "set_text", vlclua_widget_set_text },
    { "get_text", vlclua_widget_get_text },
    { "set_checked", vlclua_widget_set_checked },
    { "get_checked", vlclua_widget_get_checked },
    { "add_value", vlclua_widget_add_value },
    { "get_value", vlclua_widget_get_value },
    { "set_value", vlclua_widget_set_value },
    { "clear", vlclua_widget_clear },
    { "get_selection", vlclua_widget_get_selection },
    { "animate", vlclua_widget_animate },
    { "stop", vlclua_widget_stop },
    { NULL, NULL }
};

/** Private static variable used for the registry index */
static const char key_opaque = 'A',
                  key_update = 'B';

/**
 * Open dialog library for Lua
 * @param L lua_State
 * @param opaque Object associated to this lua state
 * @note opaque will be p_ext for extensions, p_sd for service discoveries
 **/
void luaopen_dialog( lua_State *L, void *opaque )
{
    lua_getglobal( L, "vlc" );
    lua_pushcfunction( L, vlclua_dialog_create );
    lua_setfield( L, -2, "dialog" );

    /* Add a private pointer (opaque) in the registry
     * The &key pointer is used to have a unique entry in the registry
     */
    lua_pushlightuserdata( L, (void*) &key_opaque );
    lua_pushlightuserdata( L, opaque );
    lua_settable( L, LUA_REGISTRYINDEX );

    /* Add private data: dialog update flag */
    lua_SetDialogUpdate( L, 0 );
}

static int vlclua_dialog_create( lua_State *L )
{
    if( !lua_isstring( L, 1 ) )
        return luaL_error( L, "vlc.dialog() usage: (title)" );
    const char *psz_title = luaL_checkstring( L, 1 );

    vlc_object_t *p_this = vlclua_get_this( L );

    extension_dialog_t *p_dlg = calloc( 1, sizeof( extension_dialog_t ) );
    if( !p_dlg )
        return 0; // luaL_error( L, "Out Of Memory" );

    lua_getglobal( L, "vlc" );
    lua_getfield( L, -1, "__dialog" );
    if( lua_topointer( L, lua_gettop( L ) ) != NULL )
    {
        free( p_dlg );
        return luaL_error( L, "Only one dialog allowed per extension!" );
    }

    p_dlg->p_object = p_this;
    p_dlg->psz_title = strdup( psz_title );
    p_dlg->b_kill = false;
    ARRAY_INIT( p_dlg->widgets );

    /* Read the opaque value stored while loading the dialog library */
    lua_pushlightuserdata( L, (void*) &key_opaque );
    lua_gettable( L, LUA_REGISTRYINDEX );
    p_dlg->p_sys = (void*) lua_topointer( L, -1 ); // "const" discarded
    lua_pop( L, 1 );

    vlc_mutex_init( &p_dlg->lock );
    vlc_cond_init( &p_dlg->cond );

    /** @todo Use the registry instead of __dialog,
        so that the user can't tamper with it */

    lua_getglobal( L, "vlc" );
    lua_pushlightuserdata( L, p_dlg );
    lua_setfield( L, -2, "__dialog" );
    lua_pop( L, 1 );

    extension_dialog_t **pp_dlg = lua_newuserdata( L, sizeof( extension_dialog_t* ) );
    *pp_dlg = p_dlg;

    if( luaL_newmetatable( L, "dialog" ) )
    {
        lua_newtable( L );
        luaL_register( L, NULL, vlclua_dialog_reg );
        lua_setfield( L, -2, "__index" );
        lua_pushcfunction( L, vlclua_dialog_delete );
        lua_setfield( L, -2, "__gc" );
    }

    lua_setmetatable( L, -2 );

    msg_Dbg( p_this, "Creating dialog '%s'", psz_title );
    lua_SetDialogUpdate( L, 0 );

    return 1;
}

static int vlclua_dialog_delete( lua_State *L )
{
    vlc_object_t *p_mgr = vlclua_get_this( L );

    /* Get dialog descriptor */
    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );

    if( !pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );

    /* This is also the __gc metamethod: a script that deleted its dialog
     * itself -- the sane way, rather than leaving a finalizer to block on
     * the interface at some random allocation -- must not raise here when
     * the garbage collector finally gets to the value. */
    if( !*pp_dlg )
        return 0;

    extension_dialog_t *p_dlg = *pp_dlg;
    *pp_dlg = NULL;

    /* Remove private __dialog field */
    lua_getglobal( L, "vlc" );
    lua_pushnil( L );
    lua_setfield( L, -2, "__dialog" );

    assert( !p_dlg->b_kill );

    /* Immediately deleting the dialog */
    msg_Dbg( p_mgr, "Deleting dialog '%s'", p_dlg->psz_title );
    p_dlg->b_kill = true;
    lua_SetDialogUpdate( L, 0 ); // Reset the update flag

    /* On the way out, the interface is already waiting for this thread to
     * end -- an interface that closes its windows on the main thread would
     * have to answer us from a thread that is busy joining us. Leave the
     * window to the interface's own teardown instead of asking. */
    extension_t *p_ext = p_dlg->p_sys;
    bool b_exiting = false;
    if( p_ext != NULL && p_ext->p_sys != NULL )
    {
        vlc_mutex_lock( &p_ext->p_sys->command_lock );
        b_exiting = p_ext->p_sys->b_exiting;
        vlc_mutex_unlock( &p_ext->p_sys->command_lock );
    }
    if( b_exiting )
    {
        msg_Dbg( p_mgr, "extension is exiting: leaving dialog '%s' to the "
                 "interface", p_dlg->psz_title );
        return 1;
    }

    vlc_ext_dialog_update( p_mgr, p_dlg );

    /* After vlc_ext_dialog_update, the UI thread must take the lock asap and
     * then signal us when it's done deleting the dialog.
     *
     * Bounded, because at shutdown the interface may already be waiting on
     * this very thread to finish -- its main thread joins us while we ask
     * it to close a window, and neither side can move. That deadlock used
     * to leave an application that could not be quit at all. Waiting a
     * couple of seconds and walking away costs one leaked descriptor in a
     * process that is exiting anyway; freeing it would leave the interface
     * holding a dangling pointer.
     */
    msg_Dbg( p_mgr, "Waiting for the dialog to be deleted..." );
    mtime_t deadline = mdate() + 2 * CLOCK_FREQ;
    bool b_destroyed = true;
    vlc_mutex_lock( &p_dlg->lock );
    while( p_dlg->p_sys_intf != NULL )
    {
        if( vlc_cond_timedwait( &p_dlg->cond, &p_dlg->lock, deadline ) != 0 )
        {
            b_destroyed = false;
            break;
        }
    }
    vlc_mutex_unlock( &p_dlg->lock );

    if( !b_destroyed )
    {
        msg_Warn( p_mgr, "the interface never destroyed dialog '%s': "
                  "leaving it behind rather than hanging", p_dlg->psz_title );
        return 1;
    }

    free( p_dlg->psz_title );
    p_dlg->psz_title = NULL;

    /* Destroy widgets */
    extension_widget_t *p_widget;
    FOREACH_ARRAY( p_widget, p_dlg->widgets )
    {
        if( !p_widget )
            continue;
        free( p_widget->psz_text );

        /* Free data */
        struct extension_widget_value_t *p_value, *p_next;
        for( p_value = p_widget->p_values; p_value != NULL; p_value = p_next )
        {
            p_next = p_value->p_next;
            free( p_value->psz_text );
            free( p_value );
        }
        free( p_widget );
    }
    FOREACH_END()

    ARRAY_RESET( p_dlg->widgets );

    /* Note: At this point, the UI must not use these resources */
    vlc_mutex_destroy( &p_dlg->lock );
    vlc_cond_destroy( &p_dlg->cond );
    free( p_dlg );

    return 1;
}

/** Show the dialog */
static int vlclua_dialog_show( lua_State *L )
{
    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );
    if( !pp_dlg || !*pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );
    extension_dialog_t *p_dlg = *pp_dlg;

    p_dlg->b_hide = false;
    lua_SetDialogUpdate( L, 1 );

    return 1;
}

/** Hide the dialog */
static int vlclua_dialog_hide( lua_State *L )
{
    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );
    if( !pp_dlg || !*pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );
    extension_dialog_t *p_dlg = *pp_dlg;

    p_dlg->b_hide = true;
    lua_SetDialogUpdate( L, 1 );

    return 1;
}


/** Set the dialog's title */
static int vlclua_dialog_set_title( lua_State *L )
{
    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );
    if( !pp_dlg || !*pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );
    extension_dialog_t *p_dlg = *pp_dlg;

    vlc_mutex_lock( &p_dlg->lock );

    const char *psz_title = luaL_checkstring( L, 2 );
    free( p_dlg->psz_title );
    p_dlg->psz_title = strdup( psz_title );

    vlc_mutex_unlock( &p_dlg->lock );

    lua_SetDialogUpdate( L, 1 );

    return 1;
}

/** Update the dialog immediately */
/**
 * Ask for a minimum dialog size: set_size( width, height )
 * Either value may be 0 to leave that axis to the interface. The size is a
 * hint the interface may enlarge, never a fixed geometry.
 **/
static int vlclua_dialog_set_size( lua_State *L )
{
    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );
    if( !pp_dlg || !*pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );
    extension_dialog_t *p_dlg = *pp_dlg;

    int i_width = luaL_checkint( L, 2 );
    int i_height = luaL_optint( L, 3, 0 );

    vlc_mutex_lock( &p_dlg->lock );
    p_dlg->i_width = i_width > 0 ? i_width : 0;
    p_dlg->i_height = i_height > 0 ? i_height : 0;
    vlc_mutex_unlock( &p_dlg->lock );

    lua_SetDialogUpdate( L, 1 );

    return 1;
}

static int vlclua_dialog_update( lua_State *L )
{
    vlc_object_t *p_mgr = vlclua_get_this( L );

    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );
    if( !pp_dlg || !*pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );
    extension_dialog_t *p_dlg = *pp_dlg;

    // Updating dialog immediately
    vlc_ext_dialog_update( p_mgr, p_dlg );

    // Reset update flag
    lua_SetDialogUpdate( L, 0 );

    return 1;
}

static void lua_SetDialogUpdate( lua_State *L, int flag )
{
    /* Set entry in the Lua registry */
    lua_pushlightuserdata( L, (void*) &key_update );
    lua_pushinteger( L, flag );
    lua_settable( L, LUA_REGISTRYINDEX );
}

static int lua_GetDialogUpdate( lua_State *L )
{
    /* Read entry in the Lua registry */
    lua_pushlightuserdata( L, (void*) &key_update );
    lua_gettable( L, LUA_REGISTRYINDEX );
    return luaL_checkint( L, -1 );
}

/** Manually update a dialog
 * This can be called after a lua_pcall
 * @return SUCCESS if there is no dialog or the update was successful
 * @todo If there can be multiple dialogs, this function will have to
 * be fixed (lookup for dialog)
 */
int lua_DialogFlush( lua_State *L )
{
    lua_getglobal( L, "vlc" );
    lua_getfield( L, -1, "__dialog" );
    extension_dialog_t *p_dlg = ( extension_dialog_t* )lua_topointer( L, -1 );

    if( !p_dlg )
        return VLC_SUCCESS;

    int i_ret = VLC_SUCCESS;
    if( lua_GetDialogUpdate( L ) )
    {
        i_ret = vlc_ext_dialog_update( vlclua_get_this( L ), p_dlg );
        lua_SetDialogUpdate( L, 0 );
    }

    return i_ret;
}

/**
 * Create a button: add_button
 * Arguments: text, function (as string)
 * Qt: QPushButton
 **/
static int vlclua_dialog_add_button( lua_State *L )
{
    /* Verify arguments */
    if( !lua_isstring( L, 2 ) || !lua_isfunction( L, 3 ) )
        return luaL_error( L, "dialog:add_button usage: (text, func)" );

    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = EXTENSION_WIDGET_BUTTON;
    p_widget->psz_text = strdup( luaL_checkstring( L, 2 ) );
    lua_settop( L, 10 );
    lua_pushlightuserdata( L, p_widget );
    lua_pushvalue( L, 3 );
    lua_settable( L, LUA_REGISTRYINDEX );
    p_widget->p_sys = NULL;

    return vlclua_create_widget_inner( L, 2, p_widget );
}

/**
 * Create a text label: add_label
 * Arguments: text
 * Qt: QLabel
 **/
static int vlclua_dialog_add_label( lua_State *L )
{
    /* Verify arguments */
    if( !lua_isstring( L, 2 ) )
        return luaL_error( L, "dialog:add_label usage: (text)" );
    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = EXTENSION_WIDGET_LABEL;
    p_widget->psz_text = strdup( luaL_checkstring( L, 2 ) );

    return vlclua_create_widget_inner( L, 1, p_widget );
}

/**
 * Create a text area: add_html, add_text_input, add_password
 * Arguments: text (may be nil), then the grid coordinates and an optional
 * function called when the user validates the field (Enter)
 * Qt: QLineEdit (Text/Password) or QTextArea (HTML)
 **/
static int vlclua_dialog_add_text_inner( lua_State *L, int i_type )
{
    /* Verify arguments */
    if( !lua_isstring( L, 2 ) && !lua_isnil( L, 2 ) )
        return luaL_error( L, "dialog:add_text_input usage: (text = nil)" );

    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = i_type;
    if( !lua_isnil( L, 2 ) )
        p_widget->psz_text = strdup( luaL_checkstring( L, 2 ) );

    /* add_text_input( text, col, row, hspan, vspan [, validate [, change]] ):
     * with two interactions the registry entry becomes a table of named
     * functions, the same shape a list uses. "change" fires as the user
     * types, coalesced by the command queue -- a script can filter a list
     * from a search box without a button, and a slow machine simply runs
     * the callback fewer times. */
    bool b_validate = lua_gettop( L ) >= 7 && lua_isfunction( L, 7 );
    bool b_change = lua_gettop( L ) >= 8 && lua_isfunction( L, 8 );

    if( b_change )
    {
        lua_pushlightuserdata( L, p_widget );
        lua_newtable( L );
        if( b_validate )
        {
            lua_pushvalue( L, 7 );
            lua_setfield( L, -2, "click" );
        }
        lua_pushvalue( L, 8 );
        lua_setfield( L, -2, "select" );
        lua_settable( L, LUA_REGISTRYINDEX );
    }
    else if( b_validate )
    {
        lua_pushlightuserdata( L, p_widget );
        lua_pushvalue( L, 7 );
        lua_settable( L, LUA_REGISTRYINDEX );
    }

    return vlclua_create_widget_inner( L, 1, p_widget );
}

/**
 * Create a checkable box: add_check_box
 * Arguments: text, checked (as bool)
 * Qt: QCheckBox
 **/
static int vlclua_dialog_add_check_box( lua_State *L )
{
    /* Verify arguments */
    if( !lua_isstring( L, 2 ) )
        return luaL_error( L, "dialog:add_check_box usage: (text, checked)" );

    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = EXTENSION_WIDGET_CHECK_BOX;
    p_widget->psz_text = strdup( luaL_checkstring( L, 2 ) );
    p_widget->b_checked = lua_toboolean( L, 3 );

    return vlclua_create_widget_inner( L, 2, p_widget );
}

/**
 * Create a drop-down list (non editable)
 * Arguments: (none)
 * Qt: QComboBox
 * @todo make it editable?
 **/
static int vlclua_dialog_add_dropdown( lua_State *L )
{
    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = EXTENSION_WIDGET_DROPDOWN;

    /* add_dropdown( col, row, hspan, vspan [, on_change] ): stored under
     * the same "select" name a list uses, so both go through the one
     * selection-changed path. */
    if( lua_gettop( L ) >= 6 && lua_isfunction( L, 6 ) )
    {
        lua_pushlightuserdata( L, p_widget );
        lua_newtable( L );
        lua_pushvalue( L, 6 );
        lua_setfield( L, -2, "select" );
        lua_settable( L, LUA_REGISTRYINDEX );
    }

    return vlclua_create_widget_inner( L, 0, p_widget );
}

/**
 * Create a list panel (multiple selection)
 * Arguments: (none), or after the grid coordinates an optional function
 * called when a row is activated (double-clicked)
 * Qt: QListWidget
 **/
static int vlclua_dialog_add_list( lua_State *L )
{
    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = EXTENSION_WIDGET_LIST;

    /* add_list( col, row, hspan, vspan [, activate [, select]] ): a list has
     * two interactions, so the registry entry is a table of named functions
     * rather than the bare function a button stores. */
    if( ( lua_gettop( L ) >= 6 && lua_isfunction( L, 6 ) )
     || ( lua_gettop( L ) >= 7 && lua_isfunction( L, 7 ) ) )
    {
        lua_pushlightuserdata( L, p_widget );
        lua_newtable( L );
        if( lua_isfunction( L, 6 ) )
        {
            lua_pushvalue( L, 6 );
            lua_setfield( L, -2, "click" );
        }
        if( lua_isfunction( L, 7 ) )
        {
            lua_pushvalue( L, 7 );
            lua_setfield( L, -2, "select" );
        }
        lua_settable( L, LUA_REGISTRYINDEX );
    }

    return vlclua_create_widget_inner( L, 0, p_widget );
}

/**
 * Create an image label
 * Arguments: (string) url
 * Qt: QLabel with setPixmap( QPixmap& )
 **/
static int vlclua_dialog_add_image( lua_State *L )
{
    /* Verify arguments */
    if( !lua_isstring( L, 2 ) )
        return luaL_error( L, "dialog:add_image usage: (filename)" );

    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = EXTENSION_WIDGET_IMAGE;
    p_widget->psz_text = strdup( luaL_checkstring( L, 2 ) );

    return vlclua_create_widget_inner( L, 1, p_widget );
}

/**
 * Create a spinning icon
 * Arguments: (int) loop count to play: 0 means stopped, -1 means infinite.
 * Qt: SpinningIcon (custom widget)
 **/
static int vlclua_dialog_add_spin_icon( lua_State *L )
{
    /* Verify arguments */
    if( !lua_isstring( L, 2 ) )
        return luaL_error( L, "dialog:add_image usage: (filename)" );

    extension_widget_t *p_widget = calloc( 1, sizeof( extension_widget_t ) );
    p_widget->type = EXTENSION_WIDGET_SPIN_ICON;

    return vlclua_create_widget_inner( L, 0, p_widget );
}

/**
 * Internal helper to finalize the creation of a widget
 * @param L Lua State
 * @param i_args Number of arguments before "row" (0 or more)
 * @param p_widget The widget to add
 **/
static int vlclua_create_widget_inner( lua_State *L, int i_args,
                                       extension_widget_t *p_widget )
{
    int arg = i_args + 2;

    /* Get dialog */
    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );
    if( !pp_dlg || !*pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );
    extension_dialog_t *p_dlg = *pp_dlg;

    /* Set parent dialog */
    p_widget->p_dialog = p_dlg;

    /* Set common arguments: col, row, hspan, vspan, width, height */
    if( lua_isnumber( L, arg ) )
        p_widget->i_column = luaL_checkint( L, arg );
    else goto end_of_args;
    if( lua_isnumber( L, ++arg ) )
        p_widget->i_row = luaL_checkint( L, arg );
    else goto end_of_args;
    if( lua_isnumber( L, ++arg ) )
        p_widget->i_horiz_span = luaL_checkint( L, arg );
    else goto end_of_args;
    if( lua_isnumber( L, ++arg ) )
        p_widget->i_vert_span = luaL_checkint( L, arg );
    else goto end_of_args;
    if( lua_isnumber( L, ++arg ) )
        p_widget->i_width = luaL_checkint( L, arg );
    else goto end_of_args;
    if( lua_isnumber( L, ++arg ) )
        p_widget->i_height = luaL_checkint( L, arg );
    else goto end_of_args;

end_of_args:
    vlc_mutex_lock( &p_dlg->lock );

    /* Add the widget to the dialog descriptor */
    AddWidget( p_dlg, p_widget );

    vlc_mutex_unlock( &p_dlg->lock );

    /* Create meta table */
    extension_widget_t **pp_widget = lua_newuserdata( L, sizeof( extension_widget_t* ) );
    *pp_widget = p_widget;
    if( luaL_newmetatable( L, "widget" ) )
    {
        lua_newtable( L );
        luaL_register( L, NULL, vlclua_widget_reg );
        lua_setfield( L, -2, "__index" );
    }
    lua_setmetatable( L, -2 );

    lua_SetDialogUpdate( L, 1 );

    return 1;
}

static int vlclua_widget_set_text( lua_State *L )
{
    /* Get dialog */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    /* Verify arguments */
    if( !lua_isstring( L, 2 ) )
        return luaL_error( L, "widget:set_text usage: (text)" );

    /* Verify widget type */
    switch( p_widget->type )
    {
        case EXTENSION_WIDGET_LABEL:
        case EXTENSION_WIDGET_BUTTON:
        case EXTENSION_WIDGET_HTML:
        case EXTENSION_WIDGET_TEXT_FIELD:
        case EXTENSION_WIDGET_PASSWORD:
        case EXTENSION_WIDGET_DROPDOWN:
        case EXTENSION_WIDGET_CHECK_BOX:
        case EXTENSION_WIDGET_LIST:
            /* on a list the text carries the tab-separated column headers */
            break;
        case EXTENSION_WIDGET_IMAGE:
        default:
            return luaL_error( L, "method set_text not valid for this widget" );
    }

    vlc_mutex_lock( &p_widget->p_dialog->lock );

    /* Update widget */
    p_widget->b_update = true;
    free( p_widget->psz_text );
    p_widget->psz_text = strdup( luaL_checkstring( L, 2 ) );

    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    lua_SetDialogUpdate( L, 1 );

    return 1;
}

static int vlclua_widget_get_text( lua_State *L )
{
    /* Get dialog */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    /* Verify widget type */
    switch( p_widget->type )
    {
        case EXTENSION_WIDGET_LABEL:
        case EXTENSION_WIDGET_BUTTON:
        case EXTENSION_WIDGET_HTML:
        case EXTENSION_WIDGET_TEXT_FIELD:
        case EXTENSION_WIDGET_PASSWORD:
        case EXTENSION_WIDGET_DROPDOWN:
        case EXTENSION_WIDGET_CHECK_BOX:
            break;
        case EXTENSION_WIDGET_LIST:
        case EXTENSION_WIDGET_IMAGE:
        default:
            return luaL_error( L, "method get_text not valid for this widget" );
    }

    extension_dialog_t *p_dlg = p_widget->p_dialog;
    vlc_mutex_lock( &p_dlg->lock );

    char *psz_text = NULL;
    if( p_widget->psz_text )
        psz_text = strdup( p_widget->psz_text );
    vlc_mutex_unlock( &p_dlg->lock );

    lua_pushstring( L, psz_text );

    free( psz_text );
    return 1;
}

static int vlclua_widget_get_checked( lua_State *L )
{
    /* Get widget */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_CHECK_BOX )
        return luaL_error( L, "method get_checked not valid for this widget" );

    vlc_mutex_lock( &p_widget->p_dialog->lock );
    lua_pushboolean( L, p_widget->b_checked );
    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    return 1;
}

static int vlclua_widget_add_value( lua_State *L )
{
    /* Get widget */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_DROPDOWN
        && p_widget->type != EXTENSION_WIDGET_LIST )
        return luaL_error( L, "method add_value not valid for this widget" );

    if( !lua_isstring( L, 2 ) )
        return luaL_error( L, "widget:add_value usage: (text, id = 0)" );

    struct extension_widget_value_t *p_value,
        *p_new_value = calloc( 1, sizeof( struct extension_widget_value_t ) );
    p_new_value->psz_text = strdup( luaL_checkstring( L, 2 ) );
    p_new_value->i_id = lua_tointeger( L, 3 );

    vlc_mutex_lock( &p_widget->p_dialog->lock );

    if( !p_widget->p_values )
    {
        p_widget->p_values = p_new_value;
        if( p_widget->type == EXTENSION_WIDGET_DROPDOWN )
            p_new_value->b_selected = true;
    }
    else
    {
        for( p_value = p_widget->p_values;
             p_value->p_next != NULL;
             p_value = p_value->p_next )
        { /* Do nothing, iterate to find the end */ }
        p_value->p_next = p_new_value;
    }

    p_widget->b_update = true;
    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    lua_SetDialogUpdate( L, 1 );

    return 1;
}

static int vlclua_widget_get_value( lua_State *L )
{
    /* Get widget */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_DROPDOWN )
        return luaL_error( L, "method get_value not valid for this widget" );

    vlc_mutex_lock( &p_widget->p_dialog->lock );

    struct extension_widget_value_t *p_value;
    for( p_value = p_widget->p_values;
         p_value != NULL;
         p_value = p_value->p_next )
    {
        if( p_value->b_selected )
        {
            lua_pushinteger( L, p_value->i_id );
            lua_pushstring( L, p_value->psz_text );
            vlc_mutex_unlock( &p_widget->p_dialog->lock );
            return 2;
        }
    }

    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    lua_pushinteger( L, -1 );
    lua_pushnil( L );
    return 2;
}

/**
 * Choose which entry of a drop-down is shown, by the id given to
 * add_value. Without it a script has to add its entries in the order it
 * wants them read, since a drop-down opens on its first one -- which
 * makes a list that should read low to high impossible to write.
 */
static int vlclua_widget_set_value( lua_State *L )
{
    /* Get widget */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_DROPDOWN )
        return luaL_error( L, "method set_value not valid for this widget" );

    int i_id = luaL_checkint( L, 2 );
    bool b_found = false;

    vlc_mutex_lock( &p_widget->p_dialog->lock );
    for( struct extension_widget_value_t *p_value = p_widget->p_values;
         p_value != NULL;
         p_value = p_value->p_next )
    {
        p_value->b_selected = ( p_value->i_id == i_id );
        if( p_value->b_selected )
            b_found = true;
    }
    p_widget->b_update = true;
    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    lua_SetDialogUpdate( L, 1 );
    lua_pushboolean( L, b_found );
    return 1;
}

static int vlclua_widget_clear( lua_State *L )
{
    /* Get widget */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_DROPDOWN
        && p_widget->type != EXTENSION_WIDGET_LIST )
        return luaL_error( L, "method clear not valid for this widget" );

    struct extension_widget_value_t *p_value, *p_next;

    vlc_mutex_lock( &p_widget->p_dialog->lock );

    for( p_value = p_widget->p_values;
         p_value != NULL;
         p_value = p_next )
    {
        p_next = p_value->p_next;
        free( p_value->psz_text );
        free( p_value );
    }

    p_widget->p_values = NULL;
    p_widget->b_update = true;

    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    lua_SetDialogUpdate( L, 1 );

    return 1;
}

static int vlclua_widget_get_selection( lua_State *L )
{
    /* Get widget */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_LIST )
        return luaL_error( L, "method get_selection not valid for this widget" );

    /* Create empty table */
    lua_newtable( L );

    vlc_mutex_lock( &p_widget->p_dialog->lock );

    struct extension_widget_value_t *p_value;
    for( p_value = p_widget->p_values;
         p_value != NULL;
         p_value = p_value->p_next )
    {
        if( p_value->b_selected )
        {
            lua_pushinteger( L, p_value->i_id );
            lua_pushstring( L, p_value->psz_text );
            lua_settable( L, -3 );
        }
    }

    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    return 1;
}

static int vlclua_widget_set_checked( lua_State *L )
{
    /* Get dialog */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_CHECK_BOX )
        return luaL_error( L, "method set_checked not valid for this widget" );

    /* Verify arguments */
    if( !lua_isboolean( L, 2 ) )
        return luaL_error( L, "widget:set_checked usage: (bool)" );

    vlc_mutex_lock( &p_widget->p_dialog->lock );

    bool b_old_check = p_widget->b_checked;
    p_widget->b_checked = lua_toboolean( L, 2 );

    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    if( b_old_check != p_widget->b_checked )
    {
        /* Signal interface of the change */
        p_widget->b_update = true;
        lua_SetDialogUpdate( L, 1 );
    }

    return 1;
}

static int vlclua_widget_animate( lua_State *L )
{
    /* Get dialog */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_SPIN_ICON )
        return luaL_error( L, "method animate not valid for this widget" );

    /* Verify arguments */
    vlc_mutex_lock( &p_widget->p_dialog->lock );
    if( !lua_isnumber( L, 2 ) )
        p_widget->i_spin_loops = -1;
    else
        p_widget->i_spin_loops = lua_tointeger( L, 2 );
    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    /* Signal interface of the change */
    p_widget->b_update = true;
    lua_SetDialogUpdate( L, 1 );

    return 1;
}

static int vlclua_widget_stop( lua_State *L )
{
    /* Get dialog */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 1, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    if( p_widget->type != EXTENSION_WIDGET_SPIN_ICON )
        return luaL_error( L, "method stop not valid for this widget" );

    vlc_mutex_lock( &p_widget->p_dialog->lock );

    bool b_needs_update = p_widget->i_spin_loops != 0;
    p_widget->i_spin_loops = 0;

    vlc_mutex_unlock( &p_widget->p_dialog->lock );

    if( b_needs_update )
    {
        /* Signal interface of the change */
        p_widget->b_update = true;
        lua_SetDialogUpdate( L, 1 );
    }

    return 1;
}

/**
 * Delete a widget from a dialog
 * Remove it from the list once it has been safely destroyed by the interface
 * @note This will always update the dialog
 **/
static int vlclua_dialog_delete_widget( lua_State *L )
{
    /* Get dialog */
    extension_dialog_t **pp_dlg =
            (extension_dialog_t**) luaL_checkudata( L, 1, "dialog" );
    if( !pp_dlg || !*pp_dlg )
        return luaL_error( L, "Can't get pointer to dialog" );
    extension_dialog_t *p_dlg = *pp_dlg;

    /* Get widget */
    if( !lua_isuserdata( L, 2 ) )
        return luaL_error( L, "Argument to del_widget is not a widget" );

    /* Get dialog */
    extension_widget_t **pp_widget =
            (extension_widget_t **) luaL_checkudata( L, 2, "widget" );
    if( !pp_widget || !*pp_widget )
        return luaL_error( L, "Can't get pointer to widget" );
    extension_widget_t *p_widget = *pp_widget;

    /* Delete widget */
    *pp_widget = NULL;
    if( p_widget->type == EXTENSION_WIDGET_BUTTON )
    {
        /* Remove button action from registry */
        lua_pushlightuserdata( L, p_widget );
        lua_pushnil( L );
        lua_settable( L, LUA_REGISTRYINDEX );
    }

    vlc_object_t *p_mgr = vlclua_get_this( L );

    p_widget->b_kill = true;

    lua_SetDialogUpdate( L, 0 ); // Reset update flag
    int i_ret = vlc_ext_dialog_update( p_mgr, p_dlg );

    if( i_ret != VLC_SUCCESS )
    {
        return luaL_error( L, "Could not delete widget" );
    }

    vlc_mutex_lock( &p_dlg->lock );

    /* Same remarks as for dialog delete.
     * If the dialog is deleted or about to be deleted, then there is no
     * need to wait on this particular widget that already doesn't exist
     * anymore in the UI */
    while( p_widget->p_sys_intf != NULL && !p_dlg->b_kill
           && p_dlg->p_sys_intf != NULL )
    {
        vlc_cond_wait( &p_dlg->cond, &p_dlg->lock );
    }

    i_ret = DeleteWidget( p_dlg, p_widget );

    vlc_mutex_unlock( &p_dlg->lock );

    if( i_ret != VLC_SUCCESS )
    {
        return luaL_error( L, "Could not remove widget from list" );
    }

    return 1;
}


/*
 * Below this line, no Lua specific code.
 * Extension helpers.
 */


/**
 * Add a widget to the widget list of a dialog
 * @note Must be entered with lock on dialog
 **/
static void AddWidget( extension_dialog_t *p_dialog,
                       extension_widget_t *p_widget )
{
    ARRAY_APPEND( p_dialog->widgets, p_widget );
}

/**
 * Remove a widget from the widget list of a dialog
 * @note The widget MUST have been safely killed before
 * @note Must be entered with lock on dialog
 **/
static int DeleteWidget( extension_dialog_t *p_dialog,
                         extension_widget_t *p_widget )
{
    int pos = -1;
    bool found = false;
    extension_widget_t *p_iter;
    FOREACH_ARRAY( p_iter, p_dialog->widgets )
    {
        pos++;
        if( p_iter == p_widget )
        {
            found = true;
            break;
        }
    }
    FOREACH_END()

    if( !found )
        return VLC_EGENERIC;

    ARRAY_REMOVE( p_dialog->widgets, pos );

    /* Now free the data */
    free( p_widget->p_sys );
    struct extension_widget_value_t *p_value = p_widget->p_values;
    while( p_value )
    {
        free( p_value->psz_text );
        struct extension_widget_value_t *old = p_value;
        p_value = p_value->p_next;
        free( old );
    }
    free( p_widget->psz_text );
    free( p_widget );

    return VLC_SUCCESS;
}
