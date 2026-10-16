/* Chainmates sport registry. Every sport-specific word the web client shows comes from here;
 * teams, labels and colours come from data/<sport>/players.json. Add a sport by adding a key
 * (and its data folder). A sport picker appears only once there is more than one entry. */
(function (root) {
  'use strict';
  root.CHAINMATES_SPORTS = {
    nfl: {
      title: 'Chainmates',
      mode: 'Football',
      // Mode styling hook: <html data-sport="nfl" data-texture="field"> picks the mode accent and hero texture in app.css.
      texture: 'field',
      emoji: '\u{1F3C8}',
      data: 'data/nfl/',
      lives: 'downs',
      life: 'down',
      miss: 'incompletion',
      lost: 'Turnover on downs',
      tagline: 'Connect two players through teammates.',
      // Who counts as a teammate (docs/spec.md, Stints). Shown under the chain and in How to play.
      rule: 'on the same 53-man roster in the same season',
      // Hints name the team-season and the position of the most famous player who fits the next link.
      // {team} is the label ("2012 Broncos"). Picked per puzzle and chain position so it stays the same on reload.
      positions: {
        QB: 'qb', RB: 'rb', FB: 'rb', HB: 'rb', WR: 'wr', TE: 'te',
        T: 'ol', G: 'ol', C: 'ol', OT: 'ol', OG: 'ol', OL: 'ol',
        DE: 'dl', DT: 'dl', NT: 'dl', DL: 'dl',
        LB: 'lb', ILB: 'lb', MLB: 'lb', OLB: 'lb',
        CB: 'db', S: 'db', FS: 'db', SS: 'db', DB: 'db', SAF: 'db',
        K: 'k', PK: 'k', P: 'p', LS: 'ls',
      },
      hints: {
        qb: ['Somebody was under center for the {team}. Find the quarterback.',
             'Check the {team} depth chart, top line: a quarterback is your guy.'],
        rb: ['Hand it off. A running back on the {team} gets you there.',
             'Feed the running back. He was on the {team}.'],
        wr: ['Go deep: a wide receiver on the {team} is wide open.',
             'Look for a receiver. He was catching passes for the {team}.'],
        te: ['Check down to the tight end on the {team}.',
             'Your link is a tight end who played for the {team}.'],
        ol: ['Nobody notices the big guys. An offensive lineman on the {team} is your link.',
             'Go to the trenches: an offensive lineman blocked for the {team}.'],
        dl: ['Pressure up front: a defensive lineman on the {team}.',
             'Look for a pass rusher with his hand in the dirt for the {team}.'],
        lb: ['A linebacker on the {team} makes this tackle.',
             'Find the linebacker who was flying around for the {team}.'],
        db: ['Look to the secondary: a defensive back on the {team}.',
             'A ball hawk in the {team} secondary is your link.'],
        k:  ['Special teams! The {team} kicker is your link.'],
        p:  ['Special teams! The {team} punter is your link.'],
        ls: ['Respect the long snapper. The {team} had one, and he is your link.'],
        any: ['Try someone from the {team}.'],
      },
      league: 'NFL',
      disclaimer: 'Unofficial fan game. Not affiliated with or endorsed by the NFL, NFLPA, or any team.',
      attribution: { text: 'Player data from nflverse (CC-BY 4.0)', href: 'https://github.com/nflverse' },
    },
  };
  root.CHAINMATES_DEFAULT_SPORT = 'nfl';
})(typeof globalThis !== 'undefined' ? globalThis : this);
