// Sends every site Calm blocks to a plain black page. The block itself is Calm's (hosts file, DNS
// filter); this only replaces the browser's error page, so turning it off is no way around Calm.
const STATUS = "file:///Library/Application%20Support/Calm/status.json";
const RULE_ID = 1;

const bare = (d) => d.trim().toLowerCase().replace(/^www\./, "");

async function refresh() {
  const builtIn = await (await fetch(chrome.runtime.getURL("sites.json"))).json();
  let extra = [], removed = [];
  try {
    // Needs "Allow access to file URLs" for this extension; without it only the built-in list is used.
    const s = await (await fetch(STATUS, { cache: "no-store" })).json();
    extra = s.extraSites || [];
    removed = s.removedSites || [];
  } catch (e) {}
  const domains = new Set([...builtIn, ...extra].map(bare).filter(Boolean));
  removed.map(bare).forEach((d) => domains.delete(d));
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: [RULE_ID],
    addRules: [{
      id: RULE_ID,
      priority: 1,
      action: { type: "redirect", redirect: { extensionPath: "/blank.html" } },
      condition: { requestDomains: [...domains], resourceTypes: ["main_frame", "sub_frame"] },
    }],
  });
}

chrome.runtime.onInstalled.addListener(refresh);
chrome.runtime.onStartup.addListener(refresh);
chrome.alarms.create("refresh", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(refresh);
refresh();
