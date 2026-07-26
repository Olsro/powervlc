#ifndef _COMPAT_AVAILABILITY_H
#define _COMPAT_AVAILABILITY_H
/* Shim for pre-10.5 SDKs: Availability.h first shipped with the 10.5 SDK.
   Provides only AvailabilityMacros; __MAC_10_x stay undefined so version-
   gated blocks take their legacy fallback path. */
#include <AvailabilityMacros.h>
#endif
