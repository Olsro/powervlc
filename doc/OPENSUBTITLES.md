# Online subtitles

Choose **Subtitles → Find Subtitles Online…**, or the same command in the
video context menu. PowerVLC opens its bundled PowerVLSub extension and
searches for the current video in your preferred languages.

Automatic search tries the OpenSubtitles file hash first, then the filename
with its year or season/episode information. Hashing is limited to local
file URLs and reads the first and last 64 KiB, including for files larger
than 4 GiB on 32-bit systems. Network streams use their title instead.
The search field and method selector also allow a custom name or hash-only
search. **Advanced…** adds year, season, episode and IMDb fields. Results can
be sorted by relevance, download count or rating and filtered by translation
provenance. Selecting a result shows its rating, votes, downloads, frame rate,
uploader and upload date when the service supplies them.

The **Settings…** button configures:

- Up to three languages in priority order, selected by name. The list is
  refreshed from OpenSubtitles and cached for 30 days; an embedded list remains
  available offline. The initial language follows PowerVLC's interface language.
- An optional OpenSubtitles.com username and password. **Remember my account
  securely** uses VLC's keystore. If secure storage is unavailable, the
  password stays in memory and the settings window explains this. **Test
  account** checks the credentials and displays the account level, download
  allowance and reset time when available.
- An optional save folder. With no folder selected, subtitles are saved next
  to the video, falling back to PowerVLC's `subtitles` cache directory if
  that location is unwritable. Existing files are never overwritten.
- A download behavior: save and activate, or load temporarily from PowerVLC's
  cache. **Save in…** writes an individual result to a folder chosen at download
  time without activating it.
- Optional OpenSubtitles filename analysis when local hash and title searches
  find nothing. Only the basename is sent, never its directory; the parsed
  metadata is cached for seven days. This option is disabled initially.
- Filters for AI and machine translations. Machine translations are hidden
  initially and both filters remain available in the search window.
- An optional personal API key. Otherwise the bundled PowerVLC application
  key is used; ordinary users do not need to obtain a developer key.

Download quotas are imposed by OpenSubtitles. The remaining allowance is
shown after a download, and authentication, quota and connection errors are
reported separately. Downloading is always an explicit action: opening a
video alone does not consume a download.

The extension uses PowerVLC's HTTP/TLS implementation and bundled certificate
store. It does not require a system curl, browser, Python, geolocation or a
separate update mechanism. Only the hash, search terms, selected language(s),
an optional basename for filename analysis and any supplied account credentials
are sent to OpenSubtitles; the video itself is never uploaded.

## Development and validation

The extension is in `share/lua/extensions/PowerVLSub.lua` and the REST
implementation is in `share/lua/modules/pvlc_opensubtitles.lua`;
`application_key` identifies PowerVLC's registered API consumer. User account
credentials and personal keys are stored separately in the keystore, not in
the JSON preferences file. UI catalogues are under
`share/lua/i18n/opensubtitles/` with English fallback.

Run `sh test/check_opensubtitles.sh` for offline regression coverage of
hashing, metadata extraction, result ordering, authentication, quota errors,
safe file creation and extension callbacks. Run
`sh test/check_lua_extensions.sh` to verify discovery in VLC's restricted
extension scanner. No API access or account is needed for these tests.

Live validation should use a separate test application/profile and a
temporary subtitle folder. Verify a local file larger than 4 GiB, hash/name
fallback, downloading and track activation. Test account login with a real
account when available; mocked tests cover token expiry and login errors.
