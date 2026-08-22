/*
 * Downloader.hpp
 *****************************************************************************
 * Copyright (C) 2015 - VideoLAN Authors
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "Downloader.hpp"

#include <vlc_threads.h>
#include <vlc_atomic.h>

using namespace adaptive::http;

Downloader::Downloader()
{
    vlc_mutex_init(&lock);
    vlc_cond_init(&waitcond);
    vlc_cond_init(&updatedcond);
    killed = false;
    thread_handle_valid = false;
    current = nullptr;
    cancel_current = false;
}

bool Downloader::start()
{
    /* The downloader works ahead into a bounded buffer.  Giving it input
     * priority makes TLS decryption of a freshly arrived HLS segment run in
     * the same fixed-priority band as the video output on Darwin.  On a
     * single-core G4 that burst can hold the CPU for several frame periods,
     * even though decoded pictures are already queued well ahead of their
     * deadlines.  Keep network prefetch in the normal time-sharing class so
     * the output thread can retain punctual presentation.  Other systems do
     * not use Darwin's fixed-priority mapping and retain the existing input
     * priority. */
#ifdef __APPLE__
    const int priority = VLC_THREAD_PRIORITY_LOW;
#else
    const int priority = VLC_THREAD_PRIORITY_INPUT;
#endif
    if(!thread_handle_valid &&
       vlc_clone(&thread_handle, downloaderThread,
                 static_cast<void *>(this), priority))
    {
        return false;
    }
    thread_handle_valid = true;
    return true;
}

Downloader::~Downloader()
{
    vlc_mutex_lock( &lock );
    killed = true;
    vlc_cond_signal(&waitcond);
    vlc_mutex_unlock( &lock );

    if(thread_handle_valid)
        vlc_join(thread_handle, nullptr);
    vlc_mutex_destroy(&lock);
    vlc_cond_destroy(&waitcond);
}
void Downloader::schedule(HTTPChunkBufferedSource *source)
{
    vlc_mutex_lock(&lock);
    source->hold();
    chunks.push_back(source);
    vlc_cond_signal(&waitcond);
    vlc_mutex_unlock(&lock);
}

void Downloader::cancel(HTTPChunkBufferedSource *source)
{
    vlc_mutex_lock(&lock);
    while (current == source)
    {
        cancel_current = true;
        vlc_cond_wait(&updatedcond, &lock);
    }

    if(!source->isDone())
    {
        chunks.remove(source);
        source->release();
    }
    vlc_mutex_unlock(&lock);
}

void * Downloader::downloaderThread(void *opaque)
{
    Downloader *instance = static_cast<Downloader *>(opaque);
    instance->Run();
    return nullptr;
}

void Downloader::Run()
{
    vlc_mutex_lock(&lock);
    while(1)
    {
        while(chunks.empty() && !killed)
            vlc_cond_wait(&waitcond, &lock);

        if(killed)
            break;

        current = chunks.front();
        vlc_mutex_unlock(&lock);
        current->bufferize(HTTPChunkSource::CHUNK_SIZE);
        vlc_mutex_lock(&lock);
        if(current->isDone() || cancel_current)
        {
            chunks.pop_front();
            current->release();
        }
        cancel_current = false;
        current = nullptr;
        vlc_cond_signal(&updatedcond);
    }
    vlc_mutex_unlock(&lock);
}
