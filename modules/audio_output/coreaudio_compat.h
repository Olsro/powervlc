/*****************************************************************************
 * coreaudio_compat.h: the AudioObject* property API on Mac OS X 10.3
 *****************************************************************************
 * CoreAudio's AudioObject abstraction (AudioObjectGetPropertyData() and
 * friends) arrived with Mac OS X 10.4. Below that deployment target the SDK
 * weak-imports the whole family, so on a 10.3 system every one of them
 * resolves to NULL and calling one jumps to 0.
 *
 * Everything those functions do was already reachable through the per-class
 * calls of 10.0/10.1 -- AudioHardwareGetProperty() for the system object,
 * AudioDeviceGetProperty() for a device, AudioStreamGetProperty() for a
 * stream -- which are still present (deprecated) up to 10.6. This header maps
 * the modern call onto the old one when, and only when, the modern symbol is
 * missing, so a single code path serves 10.3 through 10.15+.
 *
 * The AudioObjectPropertyAddress fields map as follows:
 *   mScope   == kAudioDevicePropertyScopeInput -> isInput = TRUE
 *   mElement                                   -> inChannel (0 = master)
 *   mSelector                                  -> inPropertyID
 * and the object class is derived from the selector, since the old API needs
 * to be told which one it is talking to.
 *
 * KNOWN LIMITATION on 10.3 only: property listeners are not installed. The
 * old callback signatures differ from AudioObjectPropertyListenerProc, so
 * relaying them would need a trampoline registry. The listeners auhal
 * installs are all hot-plug notifications (device list, default device,
 * stream format); without them the device list is simply not refreshed while
 * VLC runs. Every Mac that stops at 10.3 has one built-in output.
 *****************************************************************************/

#ifndef VLC_COREAUDIO_COMPAT_H
#define VLC_COREAUDIO_COMPAT_H

#include <CoreAudio/CoreAudio.h>

/* Selectors that address a stream object rather than a device. */
static inline bool
vlc_ca_selector_is_stream(AudioObjectPropertySelector sel)
{
    return sel == kAudioStreamPropertyPhysicalFormat
        || sel == kAudioStreamPropertyAvailablePhysicalFormats
        || sel == kAudioStreamPropertyVirtualFormat
        || sel == kAudioStreamPropertyAvailableVirtualFormats
        || sel == kAudioStreamPropertyDirection;
}

static inline Boolean
vlc_ca_is_input(const AudioObjectPropertyAddress *addr)
{
    return addr->mScope == kAudioDevicePropertyScopeInput ? TRUE : FALSE;
}

static inline OSStatus
vlc_AudioObjectGetPropertyDataSize(AudioObjectID id,
                                   const AudioObjectPropertyAddress *addr,
                                   UInt32 qualifier_size,
                                   const void *qualifier, UInt32 *out_size)
{
    /* Taken through a variable rather than compared directly: on the 10.4+
     * builds the symbol is not weak and GCC would warn that its address is
     * always true. */
    OSStatus (*get_size)(AudioObjectID, const AudioObjectPropertyAddress *,
                         UInt32, const void *, UInt32 *) =
        AudioObjectGetPropertyDataSize;

    if (get_size != NULL)
        return get_size(id, addr, qualifier_size, qualifier, out_size);

    if (id == kAudioObjectSystemObject)
        return AudioHardwareGetPropertyInfo(addr->mSelector, out_size, NULL);

    if (vlc_ca_selector_is_stream(addr->mSelector))
        return AudioStreamGetPropertyInfo(id, addr->mElement, addr->mSelector,
                                          out_size, NULL);

    return AudioDeviceGetPropertyInfo(id, addr->mElement,
                                      vlc_ca_is_input(addr), addr->mSelector,
                                      out_size, NULL);
}

static inline OSStatus
vlc_AudioObjectGetPropertyData(AudioObjectID id,
                               const AudioObjectPropertyAddress *addr,
                               UInt32 qualifier_size, const void *qualifier,
                               UInt32 *io_size, void *out_data)
{
    OSStatus (*get_data)(AudioObjectID, const AudioObjectPropertyAddress *,
                         UInt32, const void *, UInt32 *, void *) =
        AudioObjectGetPropertyData;

    if (get_data != NULL)
        return get_data(id, addr, qualifier_size, qualifier, io_size,
                        out_data);

    if (id == kAudioObjectSystemObject)
        return AudioHardwareGetProperty(addr->mSelector, io_size, out_data);

    if (vlc_ca_selector_is_stream(addr->mSelector))
        return AudioStreamGetProperty(id, addr->mElement, addr->mSelector,
                                      io_size, out_data);

    /* kAudioObjectPropertyName is the 10.4 name of what the device class has
     * always called kAudioDevicePropertyDeviceNameCFString (same selector). */
    return AudioDeviceGetProperty(id, addr->mElement, vlc_ca_is_input(addr),
                                  addr->mSelector, io_size, out_data);
}

static inline OSStatus
vlc_AudioObjectSetPropertyData(AudioObjectID id,
                               const AudioObjectPropertyAddress *addr,
                               UInt32 qualifier_size, const void *qualifier,
                               UInt32 size, const void *data)
{
    OSStatus (*set_data)(AudioObjectID, const AudioObjectPropertyAddress *,
                         UInt32, const void *, UInt32, const void *) =
        AudioObjectSetPropertyData;

    if (set_data != NULL)
        return set_data(id, addr, qualifier_size, qualifier, size, data);

    if (id == kAudioObjectSystemObject)
    {
        /* kAudioHardwarePropertyRunLoop is a 10.4 concept: before that,
         * CoreAudio always ran its notifications on its own thread, which is
         * exactly what setting it to NULL asks for. Accept and ignore. */
        if (addr->mSelector == kAudioHardwarePropertyRunLoop)
            return noErr;
        return AudioHardwareSetProperty(addr->mSelector, size, (void *)data);
    }

    if (vlc_ca_selector_is_stream(addr->mSelector))
        return AudioStreamSetProperty(id, NULL, addr->mElement,
                                      addr->mSelector, size, data);

    return AudioDeviceSetProperty(id, NULL, addr->mElement,
                                  vlc_ca_is_input(addr), addr->mSelector,
                                  size, data);
}

static inline Boolean
vlc_AudioObjectHasProperty(AudioObjectID id,
                           const AudioObjectPropertyAddress *addr)
{
    Boolean (*has_prop)(AudioObjectID, const AudioObjectPropertyAddress *) =
        AudioObjectHasProperty;

    if (has_prop != NULL)
        return has_prop(id, addr);

    UInt32 size;
    return vlc_AudioObjectGetPropertyDataSize(id, addr, 0, NULL, &size)
           == noErr ? TRUE : FALSE;
}

static inline OSStatus
vlc_AudioObjectIsPropertySettable(AudioObjectID id,
                                  const AudioObjectPropertyAddress *addr,
                                  Boolean *out_settable)
{
    OSStatus (*is_settable)(AudioObjectID, const AudioObjectPropertyAddress *,
                            Boolean *) = AudioObjectIsPropertySettable;

    if (is_settable != NULL)
        return is_settable(id, addr, out_settable);

    UInt32 size;
    if (id == kAudioObjectSystemObject)
        return AudioHardwareGetPropertyInfo(addr->mSelector, &size,
                                            out_settable);

    if (vlc_ca_selector_is_stream(addr->mSelector))
        return AudioStreamGetPropertyInfo(id, addr->mElement, addr->mSelector,
                                          &size, out_settable);

    return AudioDeviceGetPropertyInfo(id, addr->mElement,
                                      vlc_ca_is_input(addr), addr->mSelector,
                                      &size, out_settable);
}

static inline OSStatus
vlc_AudioObjectAddPropertyListener(AudioObjectID id,
                                   const AudioObjectPropertyAddress *addr,
                                   AudioObjectPropertyListenerProc listener,
                                   void *data)
{
    OSStatus (*add_listener)(AudioObjectID,
                             const AudioObjectPropertyAddress *,
                             AudioObjectPropertyListenerProc, void *) =
        AudioObjectAddPropertyListener;

    if (add_listener != NULL)
        return add_listener(id, addr, listener, data);

    /* See the KNOWN LIMITATION at the top: no hot-plug notifications on 10.3.
     * Reported as success so that the caller does not treat a machine without
     * removable audio devices as a failure to open the output. */
    (void) id; (void) addr; (void) listener; (void) data;
    return noErr;
}

static inline OSStatus
vlc_AudioObjectRemovePropertyListener(AudioObjectID id,
                                      const AudioObjectPropertyAddress *addr,
                                      AudioObjectPropertyListenerProc listener,
                                      void *data)
{
    OSStatus (*remove_listener)(AudioObjectID,
                                const AudioObjectPropertyAddress *,
                                AudioObjectPropertyListenerProc, void *) =
        AudioObjectRemovePropertyListener;

    if (remove_listener != NULL)
        return remove_listener(id, addr, listener, data);

    (void) id; (void) addr; (void) listener; (void) data;
    return noErr;
}

#endif /* VLC_COREAUDIO_COMPAT_H */
