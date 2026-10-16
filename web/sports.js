/* Handoff sport registry. Every sport-specific word the web client shows comes from here;
 * teams, labels and colours come from data/<sport>/players.json. Add a sport by adding a key
 * (and its data folder). A sport picker appears only once there is more than one entry. */
(function (root) {
  'use strict';
  root.HANDOFF_SPORTS = {
    nfl: {
      title: 'Handoff',
      emoji: '\u{1F3C8}',
      data: 'data/nfl/',
      lives: 'downs',
      life: 'down',
      miss: 'incompletion',
      lost: 'Turnover on downs',
      tagline: 'Connect two players through teammates.',
      // Wordmark split: the accent part is drawn in gold ("Hand" + "off").
      accent: 'off',
      league: 'NFL',
      disclaimer: 'Unofficial fan game. Not affiliated with or endorsed by the NFL, NFLPA, or any team.',
      attribution: { text: 'Player data from nflverse (CC-BY 4.0)', href: 'https://github.com/nflverse' },
    },
  };
  root.HANDOFF_DEFAULT_SPORT = 'nfl';
})(typeof globalThis !== 'undefined' ? globalThis : this);
