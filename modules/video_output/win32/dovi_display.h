/*****************************************************************************
 * dovi_display.h: native Windows Dolby Vision display transport
 *****************************************************************************/

#ifndef VLC_WIN32_DOVI_DISPLAY_H
#define VLC_WIN32_DOVI_DISPLAY_H

#include <vlc_common.h>

typedef struct win32_dovi_display win32_dovi_display_t;

win32_dovi_display_t *Win32DoviDisplay_Enable(vlc_object_t *, HWND);
void Win32DoviDisplay_Restore(vlc_object_t *, win32_dovi_display_t *);

#endif
