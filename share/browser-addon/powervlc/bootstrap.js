/* PowerVLC browser companion -- bootstrap.js
 *
 * Two halves, both about the same thing: the browser and the player are
 * on the same machine and should not have to ignore each other.
 *
 * 1. Play in PowerVLC
 *    When a page carries a video or an audio stream the player can read
 *    on its own -- a plain file or a playlist, not a Media Source fed by
 *    the page -- offer a button that hands it over, and put "Send to
 *    PowerVLC" in the right-click menu over any video, audio or link.
 *    Old hardware plays a 720p file perfectly well through PowerVLC and
 *    not at all through a browser that has to decode it in JavaScript.
 *
 * 2. Read this page for the player
 *    Sites increasingly put a proof of work or a captcha in front of
 *    every page. PowerVLC does not solve those: the person at the machine
 *    does, in their own browser, and the tab that passed the check then
 *    reads pages on the player's behalf. On a current browser a
 *    bookmarklet is enough to put that relay script on the page.
 *
 *    It is not enough here. Until Firefox 69 a bookmarklet counted as
 *    inline script, so a page carrying "script-src 'self'" refused to run
 *    it, silently -- clicking the bookmark did nothing at all, with one
 *    line in a console nobody opens. Every browser these machines can run
 *    is older than that: TenFourFox is Gecko 45, PowerFox 52. A chrome
 *    script is subject to no page policy, so this puts the script there
 *    itself. The protocol, the slicing and the page handover all stay in
 *    PowerVLC, where they were written and tested; this add-on fetches
 *    that script rather than carrying a copy that would drift.
 *
 * It talks to nothing but the player, on the loopback interface, and runs
 * the relay on the one site PowerVLC named -- nowhere else.
 */

const { classes: Cc, interfaces: Ci, utils: Cu } = Components;
Cu.import("resource://gre/modules/Services.jsm");

const PREF_BASE   = "extensions.powervlc.base";
const PREF_ORIGIN = "extensions.powervlc.origin";

/* The player is asked for by identity, not by path: LaunchServices knows
 * where it is, and hands the address to the copy already running rather
 * than starting a second one. */
const PLAYER_BUNDLE = "com.github.PowerVLC";

/* Media the page builds itself, segment by segment, out of a MediaSource:
 * there is no address to hand over, so there is nothing to offer.
 * javascript: is in there for the context menu, where a link is whatever
 * the page made it. */
const NO_HANDOVER = /^(blob:|mediasource:|data:|javascript:)/i;

/* The context menu item, by id, so that it can be found again and taken
 * out: an add-on that installs without a restart has to uninstall without
 * one too, and a menu item left behind would outlive it. */
const MENU_ID = "pvlc-context-send";

/* PowerVLC's local page: http://127.0.0.1:<port>/<secret> */
var gBase = null;
/* the one site the relay is for, e.g. https://inv.nadeko.net */
var gOrigin = null;
/* the relay script, as PowerVLC serves it */
var gScript = null;

function log(msg) {
  Services.console.logStringMessage("PowerVLC: " + msg);
}

function getPref(name) {
  try {
    if (Services.prefs.prefHasUserValue(name))
      return Services.prefs.getCharPref(name);
  } catch (e) {}
  return null;
}

function setPref(name, value) {
  try {
    if (value === null)
      Services.prefs.clearUserPref(name);
    else
      Services.prefs.setCharPref(name, value);
  } catch (e) {}
}

function originOf(href) {
  var m = String(href).match(/^(https?:\/\/[^\/]+)/);
  return m ? m[1] : null;
}

function forEachBrowserWindow(fn) {
  try {
    var e = Services.wm.getEnumerator("navigator:browser");
    while (e.hasMoreElements()) fn(e.getNext());
  } catch (err) {}
}

/* Every content window currently open. Nothing here runs with e10s --
 * these builds are all single-process -- so the content window is right
 * there on the browser element. */
function forEachTab(fn) {
  forEachBrowserWindow(function (win) {
    var tabs = win.gBrowser;
    if (!tabs || !tabs.browsers) return;
    for (var i = 0; i < tabs.browsers.length; i++) {
      try {
        var cw = tabs.browsers[i].contentWindow;
        if (cw) fn(cw);
      } catch (err) {}
    }
  });
}

/*****************************************************************************
 * Play in PowerVLC
 *****************************************************************************/

/* French if the browser is in French, English otherwise: two strings do
 * not warrant a locale bundle, and getting them wrong costs a shrug. */
function lang() {
  var l = "en";
  try { l = Services.prefs.getCharPref("general.useragent.locale"); } catch (e) {}
  return (String(l).indexOf("fr") === 0) ? "fr" : "en";
}

function label(name) {
  var s = {
    en: { play: "Play in PowerVLC", hide: "Hide", sent: "Sent to PowerVLC",
          nope: "PowerVLC could not be started",
          send: "Send to PowerVLC" },
    /* \u escapes on purpose: a bootstrap script is not always read as
       UTF-8, and a mangled accent is a bug report nobody can reproduce */
    fr: { play: "Lire dans PowerVLC", hide: "Masquer",
          sent: "Envoy\u00E9 \u00E0 PowerVLC",
          nope: "PowerVLC n\u2019a pas pu d\u00E9marrer",
          send: "Transf\u00E9rer vers PowerVLC" }
  };
  return s[lang()][name];
}

/* Hands an address to the player. LaunchServices opens it with the copy
 * that is already running, so this adds to the playlist of the session
 * the user has in front of them rather than starting another one. */
function playInPlayer(url) {
  try {
    var open = Cc["@mozilla.org/file/local;1"]
                 .createInstance(Ci.nsILocalFile);
    open.initWithPath("/usr/bin/open");
    if (!open.exists()) return false;

    var proc = Cc["@mozilla.org/process/util;1"]
                 .createInstance(Ci.nsIProcess);
    proc.init(open);
    var args = ["-b", PLAYER_BUNDLE, url];
    proc.run(false, args, args.length);
    return true;
  } catch (e) {
    log("could not hand " + url + " over: " + e);
    return false;
  }
}

/* The address of something the player can read by itself.
 *
 * currentSrc, not src: a <video> with <source> children has no src at
 * all, and currentSrc is the one the browser settled on. Anything the
 * page assembles in memory is skipped -- see NO_HANDOVER. */
function mediaAddress(win) {
  try {
    var doc = win.document;
    var type = String(doc.contentType || "");
    /* the page is the media: an .mp4 or an .m3u8 opened on its own */
    if (/^(video|audio)\//.test(type)
     || /mpegurl|dash\+xml|ogg|matroska/.test(type))
      return String(win.location.href);

    var media = doc.getElementsByTagName("video");
    var lists = [media, doc.getElementsByTagName("audio")];
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var el = lists[l][i];
        var url = el.currentSrc || el.src || "";
        if (!url) {
          var src = el.getElementsByTagName("source");
          if (src.length) url = src[0].src || "";
        }
        if (url && !NO_HANDOVER.test(url)) return String(url);
      }
    }
  } catch (e) {}
  return null;
}

/* The button is built here rather than by a script on the page: a page
 * that forbids inline script would refuse that one too, and this has to
 * work on exactly those pages. Everything is set through .style, which no
 * policy governs, and the click is handled by this code. */
function offer(win, url) {
  var doc = win.document;
  if (!doc.body) return;

  var box = doc.getElementById("pvlcplay");
  if (box) {                       /* already offered: keep it current */
    box.__pvlcUrl = url;
    return;
  }

  box = doc.createElement("div");
  box.id = "pvlcplay";
  box.style.cssText = "position:fixed;z-index:2147483646;right:12px;"
    + "bottom:12px;background:#c1272d;color:#fff;font:13px sans-serif;"
    + "border-radius:6px;box-shadow:0 1px 6px rgba(0,0,0,.4);"
    + "padding:0;display:flex;align-items:stretch;overflow:hidden";
  box.__pvlcUrl = url;

  var play = doc.createElement("span");
  play.textContent = "\u25B6 " + label("play");
  play.style.cssText = "padding:8px 12px;cursor:pointer";
  play.addEventListener("click", function () {
    var ok = playInPlayer(box.__pvlcUrl);
    play.textContent = ok ? label("sent") : label("nope");
    if (ok) win.setTimeout(function () { hide(); }, 2000);
  }, false);

  var close = doc.createElement("span");
  close.textContent = "\u00D7";
  close.title = label("hide");
  close.style.cssText = "padding:8px 10px;cursor:pointer;"
    + "background:rgba(0,0,0,.18)";
  close.addEventListener("click", function () { hide(); }, false);

  function hide() {
    try { box.parentNode.removeChild(box); } catch (e) {}
    /* dismissed for this page: do not put it back on the next scan */
    try { win.__pvlcNoOffer = true; } catch (e) {}
  }

  box.appendChild(play);
  box.appendChild(close);
  doc.body.appendChild(box);
}

/* Players insert their <video> when they feel like it, so looking once at
 * DOMContentLoaded finds nothing on half the sites. Look again when the
 * page starts loading media, and a couple of times on a timer for the
 * ones that do neither. */
function watchForMedia(win) {
  function scan() {
    try {
      if (win.closed || win.__pvlcNoOffer) return;
      var url = mediaAddress(win);
      if (url) offer(win, url);
    } catch (e) {}
  }

  try {
    win.document.addEventListener("loadstart", scan, true);
    win.document.addEventListener("durationchange", scan, true);
    win.setTimeout(scan, 1500);
    win.setTimeout(scan, 5000);
  } catch (e) {}
  scan();
}

/*****************************************************************************
 * Right-click: send to PowerVLC
 *****************************************************************************/

/* What the click was on. gContextMenu is the browser's own summary of it,
 * built just before the menu opens, and it has already done the work of
 * following a <video> back to the address it plays -- currentSrc, poster
 * and <source> children included.
 *
 * The fallback below matters all the same: an add-on that only ever worked
 * through gContextMenu would go quiet the day a build stops setting it,
 * and a menu item that is simply never there is not something a user
 * reports usefully. */
function contextTarget(win) {
  var url = null;

  try {
    var cm = win.gContextMenu;
    if (cm) {
      if ((cm.onVideo || cm.onAudio) && cm.mediaURL) url = cm.mediaURL;
      else if (cm.onLink && cm.linkURL) url = cm.linkURL;
    }
  } catch (e) {}

  if (!url) {
    try {
      var node = win.document.popupNode;
      while (node && node.nodeType === 1) {
        var name = String(node.localName || "").toLowerCase();
        if (name === "video" || name === "audio") {
          url = node.currentSrc || node.src || "";
          if (!url) {
            var src = node.getElementsByTagName("source");
            if (src.length) url = src[0].src || "";
          }
          break;
        }
        if (name === "a" && node.href) { url = String(node.href); break; }
        node = node.parentNode;
      }
    } catch (e) {}
  }

  if (!url || NO_HANDOVER.test(url)) return null;
  return String(url);
}

/* One item per browser window, put there by hand: a bootstrapped add-on
 * has no overlay, and the window it is added to may not exist yet. */
function addMenu(win) {
  var doc = win.document;
  if (doc.getElementById(MENU_ID)) return;

  var popup = doc.getElementById("contentAreaContextMenu");
  if (!popup) return;

  var item = doc.createElement("menuitem");
  item.setAttribute("id", MENU_ID);
  item.setAttribute("label", label("send"));
  item.addEventListener("command", function () {
    var url = contextTarget(win);
    if (!url) return;
    if (!playInPlayer(url)) {
      try { Services.prompt.alert(win, "PowerVLC", label("nope")); }
      catch (e) {}
    }
  }, false);

  /* Shown only when the click was on something that can be handed over --
   * an item that is always there and does nothing half the time is worse
   * than no item. */
  var showing = function () {
    try { item.hidden = !contextTarget(win); } catch (e) {}
  };
  popup.addEventListener("popupshowing", showing, false);

  popup.appendChild(item);
  win.__pvlcShowing = showing;
}

function removeMenu(win) {
  try {
    var doc = win.document;
    var item = doc.getElementById(MENU_ID);
    var popup = doc.getElementById("contentAreaContextMenu");
    if (popup && win.__pvlcShowing)
      popup.removeEventListener("popupshowing", win.__pvlcShowing, false);
    win.__pvlcShowing = null;
    if (item && item.parentNode) item.parentNode.removeChild(item);
  } catch (e) {}
}

/* Windows opened later get the item too. */
var windowListener = {
  onOpenWindow: function (xulWindow) {
    var win = xulWindow.QueryInterface(Ci.nsIInterfaceRequestor)
                       .getInterface(Ci.nsIDOMWindow);
    win.addEventListener("load", function loaded() {
      win.removeEventListener("load", loaded, false);
      try {
        if (win.document.documentElement.getAttribute("windowtype")
              === "navigator:browser")
          addMenu(win);
      } catch (e) {}
    }, false);
  },
  onCloseWindow: function () {},
  onWindowTitleChange: function () {}
};

/*****************************************************************************
 * Read this page for the player
 *****************************************************************************/

/* PowerVLC serves the relay script itself, so that the script and the
 * player that talks to it can never be two different versions. A chrome
 * request is not bound by the same-origin rule, which is the whole point
 * of doing this here rather than on the page. */
function fetchScript(after) {
  if (!gBase) return;
  var url = gBase + "/inject.js";
  var x = Cc["@mozilla.org/xmlextras/xmlhttprequest;1"]
            .createInstance(Ci.nsIXMLHttpRequest);
  try {
    x.open("GET", url, true);
  } catch (e) {
    return;
  }
  x.onreadystatechange = function () {
    if (x.readyState != 4) return;
    if (x.status == 200 && x.responseText) {
      gScript = x.responseText;
      if (after) after();
    } else {
      /* The player is gone, or this is a stale address from a previous
       * run: forget it rather than keep asking. */
      gScript = null;
      gBase = null;
      setPref(PREF_BASE, null);
    }
  };
  try { x.send(null); } catch (e) {}
}

/* The relay talks to PowerVLC's page by postMessage. It finds that page
 * on its own through window.opener when the tab was opened from there,
 * but the page may just as well have been opened by hand, in another
 * window entirely -- so hand it the reference. Chrome code may hold a
 * window from any origin; the page only ever gets to postMessage to it. */
function findPlayerWindow() {
  if (!gBase) return null;
  var found = null;
  forEachTab(function (cw) {
    if (!found && String(cw.location.href).indexOf(gBase) === 0) found = cw;
  });
  return found;
}

/* Runs the relay script with the page's own principal, but compiled from
 * here: that is what the page's Content-Security-Policy cannot reach, and
 * it is the single reason this add-on exists. */
function inject(win) {
  if (!gScript) return;
  try {
    if (win.document.getElementById("pvlcmsg")) return; /* already there */
    var sandbox = Cu.Sandbox(win, { sandboxPrototype: win,
                                    wantXrays: false });
    var player = findPlayerWindow();
    if (player) sandbox.__pvlcw = player;
    /* Tells the script it is running because the add-on put it there, not
     * because somebody clicked the bookmark. A click means "hand this page
     * over", and the script stops the page's player straight away; being
     * injected means nothing of the sort -- it runs on every page of the
     * site, including one the user is watching in the browser. */
    sandbox.__pvlcauto = true;
    Cu.evalInSandbox(gScript, sandbox);
  } catch (e) {
    log("could not run the relay on " + win.location.host + ": " + e);
  }
}

/* PowerVLC's page says who it is and what it is after. Reading it here
 * means there is nothing to configure: open the page the player gives
 * you and the add-on knows what to do. */
function readPlayerPage(win) {
  var meta = win.document.querySelector('meta[name="powervlc-handoff"]');
  if (!meta) return false;
  var base = meta.getAttribute("content");
  if (!base) return false;
  var origin = null;
  var mo = win.document.querySelector('meta[name="powervlc-origin"]');
  if (mo) origin = mo.getAttribute("content");

  gBase = base;
  gOrigin = origin;
  setPref(PREF_BASE, base);
  setPref(PREF_ORIGIN, origin);
  /* Tabs of the site are usually open already -- the check was passed in
   * one of them a moment ago -- and they will not load again on their
   * own, so serve them now. */
  fetchScript(injectEverywhere);
  return true;
}

function injectEverywhere() {
  if (!gOrigin || !gScript) return;
  forEachTab(function (cw) {
    if (originOf(cw.location.href) === gOrigin) inject(cw);
  });
}

function onReady(win) {
  var href;
  try { href = String(win.location.href); } catch (e) { return; }
  if (gBase && href.indexOf(gBase) === 0) return; /* our own page */
  if (/^https?:/.test(href)) watchForMedia(win);
  if (/^http:\/\/127\.0\.0\.1:\d+\//.test(href) || /^http:\/\/localhost:\d+\//.test(href)) {
    if (readPlayerPage(win)) return;
  }
  if (!gOrigin || originOf(href) !== gOrigin) return;
  /* Ask the player for the script again rather than reuse the copy in
   * hand. It costs one loopback request of a few kilobytes per page, and
   * it is what keeps a restarted player from being talked to at its old
   * address: a player that is gone answers nothing, fetchScript() drops
   * the stale base, and this tab is left alone instead of being handed a
   * script that knocks at a dead door. */
  fetchScript(function () { inject(win); });
}

var observer = {
  observe: function (subject, topic, data) {
    if (topic != "content-document-global-created") return;
    var win;
    try { win = subject.QueryInterface(Ci.nsIDOMWindow); } catch (e) { return; }
    /* The document is empty at this point; the meta tags and the body the
     * relay writes its banner into arrive with DOMContentLoaded. */
    win.addEventListener("DOMContentLoaded", function ready() {
      win.removeEventListener("DOMContentLoaded", ready, false);
      onReady(win);
    }, false);
  }
};

function startup(data, reason) {
  gBase = getPref(PREF_BASE);
  gOrigin = getPref(PREF_ORIGIN);
  Services.obs.addObserver(observer, "content-document-global-created",
                           false);
  forEachBrowserWindow(addMenu);
  Services.wm.addListener(windowListener);
  if (gBase) fetchScript(injectEverywhere);
}

function shutdown(data, reason) {
  try {
    Services.obs.removeObserver(observer,
                                "content-document-global-created");
  } catch (e) {}
  try { Services.wm.removeListener(windowListener); } catch (e) {}
  forEachBrowserWindow(removeMenu);
  gBase = gOrigin = gScript = null;
}

function install(data, reason) {}

function uninstall(data, reason) {
  setPref(PREF_BASE, null);
  setPref(PREF_ORIGIN, null);
}
