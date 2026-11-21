// Calm's browser helper.
// 1. Every site Calm blocks opens as a plain black page instead of an error (the block itself is Calm's:
//    hosts file, DNS filter, firewall; this only changes what you see).
// 2. During the daily Devon Ke Dev Mahadev session, JioHotstar opens here but only for that series and
//    only the first episode opened in the session. Calm's guard closes Comet during the session unless
//    this extension is on (with file access), so it can't be skipped.
importScripts("rules.js");

const STATUS = "file:///Library/Application%20Support/Calm/status.json";
const RULE_ID = 1;
const BLANK = chrome.runtime.getURL("blank.html");
const bare = (d) => d.trim().toLowerCase().replace(/^www\./, "");

async function readStatus() {
  try { return await (await fetch(STATUS, { cache: "no-store" })).json(); } catch (e) { return null; }
}
const sessionOn = (s) => !!(s && s.showSessionEnds && new Date(s.showSessionEnds) > new Date());

async function refresh() {
  const builtIn = await (await fetch(chrome.runtime.getURL("sites.json"))).json();
  const s = await readStatus();
  const domains = new Set([...builtIn, ...((s && s.extraSites) || [])].map(bare).filter(Boolean));
  ((s && s.removedSites) || []).map(bare).forEach((d) => domains.delete(d));
  // During the session Hotstar isn't blacked out wholesale; the page rules below take over.
  if (sessionOn(s)) [...domains].filter(CalmRules.isHotstarHost).forEach((d) => domains.delete(d));
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: [RULE_ID],
    addRules: [{
      id: RULE_ID,
      priority: 1,
      action: { type: "redirect", redirect: { extensionPath: "/blank.html" } },
      condition: { requestDomains: [...domains], resourceTypes: ["main_frame", "sub_frame"] },
    }],
  });
  return s;
}

const toBlank = (tabId) => chrome.tabs.update(tabId, { url: BLANK }).catch(() => {});

// Hotstar changes pages without reloading, so check every address change, not just page loads.
async function police(details) {
  if (details.frameId !== 0) return;
  const u = CalmRules.parse(details.url);
  if (!u || !CalmRules.isHotstarHost(u.host)) return;
  const s = await readStatus();
  if (!sessionOn(s)) return toBlank(details.tabId);
  const d = CalmRules.decide(details.url);
  if (d.type === "block") return toBlank(details.tabId);
  if (d.type === "episode") {
    const session = s.showSessionEnds;                 // one session a day, so one episode a day
    const saved = await chrome.storage.local.get(["session", "episode"]);
    let chosen = saved.session === session ? saved.episode : null;
    if (!chosen && s.showEpisodeID) chosen = s.showEpisodeID;
    if (chosen && chosen !== d.id) return toBlank(details.tabId);
    if (!chosen) await chrome.storage.local.set({ session, episode: d.id });
  }
}

chrome.webNavigation.onCommitted.addListener(police);
chrome.webNavigation.onHistoryStateUpdated.addListener(police);
chrome.webNavigation.onReferenceFragmentUpdated.addListener(police);
chrome.runtime.onInstalled.addListener(refresh);
chrome.runtime.onStartup.addListener(refresh);
chrome.alarms.create("refresh", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(refresh);
refresh();
