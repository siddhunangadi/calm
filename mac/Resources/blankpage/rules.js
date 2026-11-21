// Which JioHotstar pages may open during the daily Devon Ke Dev Mahadev session.
// Mirrors CalmShared/ShowRules.swift. No URL class, so it also runs under macOS's JavaScript for tests.
const CalmRules = (() => {
  const SLUG = "devon-ke-dev-mahadev";
  const HOSTS = ["hotstar.com", "jiohotstar.com", "hotstarext.com"];
  const ACCOUNT = ["/onboarding", "/login", "/subscribe", "/paywall", "/mypage", "/profiles", "/myspace", "/consent"];

  function parse(url) {
    const m = /^([a-z][a-z0-9+.-]*):\/\/([^\/?#:]+)(?::\d+)?([^?#]*)(\?[^#]*)?/i.exec(url || "");
    if (!m) return null;
    return { scheme: m[1].toLowerCase(), host: m[2].toLowerCase(), path: m[3] || "/", query: m[4] || "" };
  }
  const isHotstarHost = (h) => HOSTS.some((d) => h === d || h.endsWith("." + d));

  function decide(url) {
    const u = parse(url);
    if (!u || u.scheme !== "https" || !isHotstarHost(u.host)) return { type: "block" };
    let parts = u.path.toLowerCase().split("/").filter(Boolean);
    if (parts.length && parts[0].length === 2) parts = parts.slice(1); // "/in/..."
    if (parts[0] === "shows" && parts[1] === SLUG) {
      if (parts.length >= 5 && /^\d+$/.test(parts[4])) return { type: "episode", id: parts[4] };
      return { type: "allow" };
    }
    if (parts[0] === "explore") {
      const m = /[?&]search_query=([^&]*)/.exec(u.query);
      let q = "";
      try { q = decodeURIComponent((m ? m[1] : "").replace(/\+/g, " ")).toLowerCase(); } catch (e) {}
      return q.includes("mahadev") ? { type: "allow" } : { type: "block" };
    }
    const joined = "/" + parts.join("/");
    if (ACCOUNT.some((a) => joined.startsWith(a))) return { type: "allow" };
    return { type: "block" };
  }
  return { decide, parse, isHotstarHost, SLUG };
})();
