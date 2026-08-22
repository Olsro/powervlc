/*
 * Chunk.cpp
 *****************************************************************************
 * Copyright (C) 2010 - 2011 Klagenfurt University
 *
 * Created on: Aug 10, 2010
 * Authors: Christopher Mueller <christopher.mueller@itec.uni-klu.ac.at>
 *          Christian Timmerer  <christian.timmerer@itec.uni-klu.ac.at>
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

#include "Chunk.h"
#include "HTTPConnection.hpp"
#include "HTTPConnectionManager.h"
#include "Downloader.hpp"

#include <vlc_common.h>
#include <vlc_block.h>

#include <algorithm>

using namespace adaptive::http;

static std::string EmptyStr = "";

AbstractChunkSource::AbstractChunkSource(ChunkType t, const BytesRange &range)
{
    type = t;
    contentLength = 0;
    requeststatus = RequestStatus::Success;
    bytesRange = range;
    if(bytesRange.isValid() && bytesRange.getEndByte())
        contentLength = bytesRange.getEndByte() - bytesRange.getStartByte();
}

AbstractChunkSource::~AbstractChunkSource()
{

}

const BytesRange & AbstractChunkSource::getBytesRange() const
{
    return bytesRange;
}

const std::string & AbstractChunkSource::getContentType() const
{
    return EmptyStr;
}

RequestStatus AbstractChunkSource::getRequestStatus() const
{
    return requeststatus;
}

const StorageID & AbstractChunkSource::getStorageID() const
{
    return storeid;
}

ChunkType AbstractChunkSource::getChunkType() const
{
    return type;
}

AbstractChunk::AbstractChunk(AbstractChunkSource *source_)
{
    bytesRead = 0;
    source = source_;
}

AbstractChunk::~AbstractChunk()
{
    source->recycle();
}

const std::string & AbstractChunk::getContentType() const
{
    return source->getContentType();
}

RequestStatus AbstractChunk::getRequestStatus() const
{
    return source->getRequestStatus();
}

size_t AbstractChunk::getBytesRead() const
{
    return this->bytesRead;
}

uint64_t AbstractChunk::getStartByteInFile() const
{
    if(!source || !source->getBytesRange().isValid())
        return 0;

    return source->getBytesRange().getStartByte();
}

block_t * AbstractChunk::doRead(size_t size, bool b_block)
{
    if(!source)
        return nullptr;

    block_t *block = (b_block) ? source->readBlock() : source->read(size);
    if(block)
    {
        if(bytesRead == 0)
            block->i_flags |= BLOCK_FLAG_HEADER;
        bytesRead += block->i_buffer;
        onDownload(&block);
        block->i_flags &= ~BLOCK_FLAG_HEADER;
    }

    return block;
}

bool AbstractChunk::hasMoreData() const
{
    return source->hasMoreData();
}

block_t * AbstractChunk::readBlock()
{
    return doRead(0, true);
}

block_t * AbstractChunk::read(size_t size)
{
    return doRead(size, false);
}

HTTPChunkSource::HTTPChunkSource(const std::string& url, AbstractConnectionManager *manager,
                                 const adaptive::ID &id, ChunkType t, const BytesRange &range,
                                 bool access) :
    AbstractChunkSource(t, range),
    connection   (nullptr),
    connManager  (manager),
    consumed     (0),
    requestRange (range)
{
    vlc_mutex_init(&lock);
    prepared = false;
    eof = false;
    sourceid = id;
    setUseAccess(access);
    setIdentifier(url, range);
    if(!init(url))
        eof = true;
}

HTTPChunkSource::~HTTPChunkSource()
{
    if(connection)
        connection->setUsed(false);
    vlc_mutex_destroy(&lock);
}

bool HTTPChunkSource::init(const std::string &url)
{
    vlc_mutex_locker locker(&lock);
    params = ConnectionParams(url);
    params.setUseAccess(usesAccess());

    if(params.getScheme() != "http" && params.getScheme() != "https")
        return false;

    if(params.getPath().empty() || params.getHostname().empty())
        return false;

    return true;
}

bool HTTPChunkSource::hasMoreData() const
{
    vlc_mutex_locker locker(&lock);
    if(eof)
        return false;
    else if(contentLength)
        return consumed < contentLength;
    else return true;
}

size_t HTTPChunkSource::getBytesRead() const
{
    return consumed;
}

block_t * HTTPChunkSource::read(size_t readsize)
{
    vlc_mutex_locker locker(&lock);
    if(!prepare())
    {
        eof = true;
        return nullptr;
    }

    if(consumed == contentLength && consumed > 0)
    {
        eof = true;
        return nullptr;
    }

    if(contentLength && readsize > contentLength - consumed)
        readsize = contentLength - consumed;

    block_t *p_block = block_Alloc(readsize);
    if(!p_block)
    {
        eof = true;
        return nullptr;
    }

    ssize_t ret = connection->read(p_block->p_buffer, readsize);
    if(ret < 0)
    {
        block_Release(p_block);
        p_block = nullptr;
        eof = true;
        downloadEndTime = mdate();
    }
    else
    {
        p_block->i_buffer = (size_t) ret;
        consumed += p_block->i_buffer;
        if((size_t)ret < readsize)
        {
            eof = true;
            downloadEndTime = mdate();
        }
        if(ret && connection->getBytesRead() &&
           downloadEndTime > requestStartTime && type == ChunkType::Segment)
        {
            connManager->updateDownloadRate(sourceid,
                                            connection->getBytesRead(),
                                            downloadEndTime - requestStartTime,
                                            downloadEndTime - responseTime);
        }
    }

    return p_block;
}

void HTTPChunkSource::recycle()
{
    delete this;
}

StorageID HTTPChunkSource::makeStorageID(const std::string &s, const BytesRange &r)
{
    return std::to_string(r.getStartByte())+ std::to_string(r.getEndByte()) + '@' + s;
}

const std::string & HTTPChunkSource::getContentType() const
{
    vlc_mutex_locker locker(&lock);
    if(connection)
        return connection->getContentType();
    else
        return EmptyStr;
}

void HTTPChunkSource::setIdentifier(const std::string &s, const BytesRange &r)
{
    storeid =  makeStorageID(s, r);
}

bool HTTPChunkSource::prepare()
{
    if(prepared)
        return true;

    if(!connManager)
        return false;

    ConnectionParams connparams = params; /* can be changed on 301 */

    requestStartTime = mdate();

    unsigned int i_redirects = 0;
    while(i_redirects++ < http::MAX_REDIRECTS)
    {
        if(!connection)
        {
            connection = connManager->getConnection(connparams);
            if(!connection)
                break;
        }

        requeststatus = connection->request(connparams.getPath(), requestRange);
        if(requeststatus != RequestStatus::Success)
        {
            if(requeststatus == RequestStatus::Redirection)
            {
                connparams = connection->getRedirection();
                connection->setUsed(false);
                connection = nullptr;
                if(!connparams.getUrl().empty())
                    continue;
            }
            break;
        }

        /* Because we don't know Chunk size at start, we need to get size
               from content length */
        contentLength = connection->getContentLength();
        prepared = true;
        responseTime = mdate();
        return true;
    }

    return false;
}

block_t * HTTPChunkSource::readBlock()
{
    return read(HTTPChunkSource::CHUNK_SIZE);
}

HTTPChunkBufferedSource::HTTPChunkBufferedSource(const std::string& url, AbstractConnectionManager *manager,
                                                 const adaptive::ID &sourceid,
                                                 ChunkType type, const BytesRange &range,
                                                 bool access) :
    HTTPChunkSource(url, manager, sourceid, type, range, access),
    p_head     (nullptr),
    pp_tail    (&p_head),
    p_read     (nullptr),
    inblockreadoffset (0),
    buffered     (0),
    totalContentLength (range.isValid() && range.getEndByte() > 0
                        ? range.getEndByte() - range.getStartByte() + 1 : 0),
    requestBufferedOffset (0),
    retryCount   (0),
    done         (false),
    eof          (false),
    held         (false)
{
    vlc_cond_init(&avail);
}

HTTPChunkBufferedSource::~HTTPChunkBufferedSource()
{
    /* cancel ourself if in queue */
    connManager->cancel(this);

    vlc_mutex_lock(&lock);
    done = true;
    while(held) /* wait release if not in queue but currently downloaded */
        vlc_cond_wait(&avail, &lock);

    if(p_head)
    {
        block_ChainRelease(p_head);
        p_head = nullptr;
        p_read = nullptr;
        pp_tail = &p_head;
    }
    buffered = 0;
    vlc_mutex_unlock(&lock);

    vlc_cond_destroy(&avail);
}

bool HTTPChunkBufferedSource::isDone() const
{
    vlc_mutex_locker locker( &lock );
    return done;
}

void HTTPChunkBufferedSource::hold()
{
    vlc_mutex_locker locker( &lock );
    held = true;
}

void HTTPChunkBufferedSource::release()
{
    vlc_mutex_locker locker( &lock );
    held = false;
    vlc_cond_signal(&avail);
}

/* A DASH representation is an independent byte-range stream.  Losing one
 * range must not turn that representation into a permanent EOF while the
 * other representations (typically audio) keep playing. */
bool HTTPChunkBufferedSource::resetForRetry(bool resume)
{
    static const unsigned maxRetries = 3;

    if(retryCount >= maxRetries)
        return false;

    if(resume)
    {
        if(!requestRange.isValid() || requestRange.getEndByte() == 0
         || buffered < requestBufferedOffset)
            return false;

        const size_t received = buffered - requestBufferedOffset;
        const size_t next = requestRange.getStartByte() + received;
        if(next > requestRange.getEndByte())
            return false;

        requestRange = BytesRange(next, requestRange.getEndByte());
    }

    retryCount++;
    if(connection)
    {
        connection->setUsed(false);
        connection = nullptr;
    }
    prepared = false;
    return true;
}

void HTTPChunkBufferedSource::bufferize(size_t readsize)
{
    vlc_mutex_lock(&lock);
    const bool startingRequest = !prepared;
    if(!prepare())
    {
        if(requeststatus == RequestStatus::TransientError && resetForRetry(false))
        {
            const unsigned attempt = retryCount;
            vlc_mutex_unlock(&lock);
            msleep(INT64_C(100000) * attempt);
            return;
        }

        done = true;
        eof = true;
        vlc_cond_signal(&avail);
        vlc_mutex_unlock(&lock);
        return;
    }

    if(startingRequest)
    {
        if(totalContentLength == 0)
            totalContentLength = buffered + contentLength;
        else
            contentLength = totalContentLength;
        requestBufferedOffset = buffered;
    }

    if(readsize < HTTPChunkSource::CHUNK_SIZE)
        readsize = HTTPChunkSource::CHUNK_SIZE;

    if(contentLength && readsize > contentLength - buffered)
        readsize = contentLength - buffered;

    vlc_mutex_unlock(&lock);

    block_t *p_block = block_Alloc(readsize);
    if(!p_block)
    {
        eof = true;
        return;
    }

    struct
    {
        size_t size;
        vlc_tick_t time;
        vlc_tick_t latency;
    } rate = {0,0,0};

    ssize_t ret = connection->read(p_block->p_buffer, readsize);
    if(ret <= 0)
    {
        block_Release(p_block);
        p_block = nullptr;
        vlc_mutex_lock(&lock);
        if(buffered < contentLength && resetForRetry(true))
        {
            requeststatus = RequestStatus::TransientError;
            const unsigned attempt = retryCount;
            vlc_mutex_unlock(&lock);
            msleep(INT64_C(100000) * attempt);
            return;
        }

        if(buffered < contentLength)
            requeststatus = RequestStatus::TransientError;
        done = true;
        downloadEndTime = mdate();
        rate.size = buffered;
        rate.time = downloadEndTime - requestStartTime;
        rate.latency = responseTime - requestStartTime;
        vlc_mutex_unlock(&lock);
    }
    else
    {
        p_block->i_buffer = (size_t) ret;
        vlc_mutex_lock(&lock);
        buffered += p_block->i_buffer;
        block_ChainLastAppend(&pp_tail, p_block);
        if(p_read == nullptr)
        {
            p_read = p_block;
            inblockreadoffset = 0;
        }
        if((size_t) ret < readsize)
        {
            if(buffered < contentLength && resetForRetry(true))
            {
                requeststatus = RequestStatus::TransientError;
                const unsigned attempt = retryCount;
                vlc_cond_signal(&avail);
                vlc_mutex_unlock(&lock);
                msleep(INT64_C(100000) * attempt);
                return;
            }

            if(buffered < contentLength)
                requeststatus = RequestStatus::TransientError;
            done = true;
            downloadEndTime = mdate();
            rate.size = buffered;
            rate.time = downloadEndTime - requestStartTime;
            rate.latency = responseTime - requestStartTime;
        }
        vlc_mutex_unlock(&lock);
    }

    /* A retry resets the per-request timing while "buffered" still covers the
     * whole segment.  Do not feed that mismatched sample to adaptation: it
     * would overestimate bandwidth immediately after network recovery. */
    if(rate.size && rate.time && retryCount == 0 && type == ChunkType::Segment)
    {
        connManager->updateDownloadRate(sourceid, rate.size,
                                        rate.time, rate.latency);
    }

    vlc_cond_signal(&avail);
}

bool HTTPChunkBufferedSource::hasMoreData() const
{
    vlc_mutex_locker locker( &lock );
    return !eof;
}

void HTTPChunkBufferedSource::recycle()
{
    p_read = p_head;
    inblockreadoffset = 0;
    consumed = 0;
    contentLength = buffered;
    connManager->recycleSource(this);
}

block_t * HTTPChunkBufferedSource::readBlock()
{
    block_t *p_block = nullptr;

    vlc_mutex_locker locker(&lock);

    while(!p_read && !done)
        vlc_cond_wait(&avail, &lock);

    if(!p_read && done)
    {
        if(!eof)
            p_block = block_Alloc(0);
        eof = true;
        return p_block;
    }

    /* dequeue */
    p_block = block_Duplicate(const_cast<block_t *>(p_read));
    consumed += p_block->i_buffer;
    p_read = p_read->p_next;
    inblockreadoffset = 0;
    if(p_read == nullptr && done)
        eof = true;

    return p_block;
}

block_t * HTTPChunkBufferedSource::read(size_t readsize)
{
    vlc_mutex_locker locker(&lock);

    while(readsize > (buffered - consumed) && !done)
        vlc_cond_wait(&avail, &lock);

    block_t *p_block = nullptr;
    if(!readsize || (buffered == consumed) || !(p_block = block_Alloc(readsize)) )
    {
        eof = true;
        return nullptr;
    }

    size_t copied = 0;
    while(buffered && readsize && p_read)
    {
        const size_t toconsume = std::min(p_read->i_buffer - inblockreadoffset, readsize);
        memcpy(&p_block->p_buffer[copied], &p_read->p_buffer[inblockreadoffset], toconsume);
        copied += toconsume;
        readsize -= toconsume;
        inblockreadoffset += toconsume;
        if(inblockreadoffset >= p_read->i_buffer)
        {
            p_read = p_read->p_next;
            inblockreadoffset = 0;
        }
    }

    consumed += copied;
    p_block->i_buffer = copied;

    if(copied < readsize)
        eof = true;

    return p_block;
}

HTTPChunk::HTTPChunk(const std::string &url, AbstractConnectionManager *manager,
                     const adaptive::ID &id, ChunkType type, const BytesRange &range):
    AbstractChunk(manager->makeSource(url, id, type, range))
{
    manager->start(source);
}

HTTPChunk::~HTTPChunk()
{

}

ProbeableChunk::ProbeableChunk(ChunkInterface *source)
{
    this->source = source;
    peekblock = nullptr;
}

ProbeableChunk::~ProbeableChunk()
{
    if(peekblock)
        block_Release(peekblock);
    delete source;
}

const std::string & ProbeableChunk::getContentType() const
{
    return source->getContentType();
}

RequestStatus ProbeableChunk::getRequestStatus() const
{
    return source->getRequestStatus();
}

block_t * ProbeableChunk::readBlock()
{
    if(peekblock == nullptr)
        return source->readBlock();
    block_t *b = peekblock;
    peekblock = nullptr;
    return b;
}

block_t * ProbeableChunk::read(size_t sz)
{
    if(peekblock == nullptr)
        return source->read(sz);
    if(sz < peekblock->i_buffer)
    {
        block_t *b = block_Alloc(sz);
        if(b)
        {
            memcpy(b->p_buffer, peekblock->p_buffer, sz);
            b->i_flags = peekblock->i_flags;
            peekblock->i_flags = 0;
            peekblock->p_buffer += sz;
            peekblock->i_buffer -= sz;
        }
        return b;
    }
    else
    {
        block_t *append = sz > peekblock->i_buffer ? source->read(sz - peekblock->i_buffer)
                                                   : nullptr;
        if(append)
        {
            peekblock = block_Realloc(peekblock, 0, sz);
            if(peekblock)
                memcpy(&peekblock->p_buffer[peekblock->i_buffer - append->i_buffer],
                       append->p_buffer, append->i_buffer);
            block_Release(append);
        }
        block_t *b = peekblock;
        peekblock = nullptr;
        return b;
    }
}

bool ProbeableChunk::hasMoreData() const
{
    return (peekblock || source->hasMoreData());
}

size_t ProbeableChunk::getBytesRead() const
{
    return source->getBytesRead() - (peekblock ? peekblock->i_buffer : 0);
}

size_t ProbeableChunk::peek(const uint8_t **pp)
{
    if(!peekblock)
        peekblock = source->readBlock();
    if(!peekblock)
        return 0;
    *pp = peekblock->p_buffer;
    return peekblock->i_buffer;
}
