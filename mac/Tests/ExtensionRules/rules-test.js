function run(argv) {
  const app = Application.currentApplication(); app.includeStandardAdditions = true;
  eval(app.read(Path(argv[0])) + "\n;this.CalmRules = CalmRules;");
  const D = (u) => JSON.stringify(CalmRules.decide(u));
  const cases = [
    ["https://www.hotstar.com/in/shows/devon-ke-dev-mahadev/8001", '{"type":"allow"}'],
    ["https://www.hotstar.com/in/shows/devon-ke-dev-mahadev/8001/the-birth-of-sati/1000123456/watch", '{"type":"episode","id":"1000123456"}'],
    ["https://www.jiohotstar.com/in/shows/devon-ke-dev-mahadev/8001", '{"type":"allow"}'],
    ["https://www.hotstar.com/in/explore?search_query=Devon%20Ke%20Dev%20Mahadev", '{"type":"allow"}'],
    ["https://www.hotstar.com/in/onboarding?ref=x", '{"type":"allow"}'],
    ["https://www.hotstar.com/in/shows/anupamaa/1260022017", '{"type":"block"}'],
    ["https://www.hotstar.com/in/home", '{"type":"block"}'],
    ["https://www.hotstar.com/in/explore?search_query=cricket", '{"type":"block"}'],
    ["http://www.hotstar.com/in/shows/devon-ke-dev-mahadev/8001", '{"type":"block"}'],
    ["https://evilhotstar.com/in/shows/devon-ke-dev-mahadev/8001", '{"type":"block"}'],
    ["https://www.youtube.com/watch?v=1", '{"type":"block"}'],
  ];
  let fail = 0;
  cases.forEach(([u, want]) => { const got = D(u); if (got !== want) { fail++; console.log("FAIL " + u + " got " + got + " want " + want); } });
  return (cases.length - fail) + "/" + cases.length + " passed";
}
