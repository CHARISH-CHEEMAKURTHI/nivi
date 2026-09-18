// DOM user interface: HUD, panels, battle overlay. All buttons carry a
// data-action attribute and are dispatched to the Game from one listener.
import { BUILDINGS, UNITS, CATEGORIES, RESOURCES, ENEMY_KINGDOMS, DECREES, CREATURES, TYPE_RATIOS, BATTLE_TIME } from './config.js';
import { capacities, happiness, armySummary, isBuilt, canAfford, trainError, placeError, bonding, hasBuilt } from './sim.js';
import { buildingSprite, unitIcon } from './sprites.js';
import { countType } from './state.js';

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmtTime = (sec) => { sec = Math.max(0, Math.ceil(sec)); const m = Math.floor(sec / 60), s = sec % 60; return m ? `${m}:${String(s).padStart(2, '0')}` : `${s}s`; };
const costHtml = (cost) => Object.entries(cost || {}).map(([k, v]) => `<span class="${k}"><i class="gem ${k} sm"></i> ${v}</span>`).join(' ') || '<span class="muted">free</span>';

export class UI {
  constructor(game) {
    this.game = game;
    this.panel = null;       // {kind, arg}
    this.toastTimer = 0;
    this.selectedTroop = null;
    $('hud').addEventListener('click', (e) => {
      const el = e.target.closest('[data-action]');
      if (!el) return;
      e.preventDefault();
      this.dispatch(el.dataset.action, el.dataset.arg, el);
    });
  }

  dispatch(action, arg) {
    const g = this.game;
    switch (action) {
      case 'close-panel': this.closePanel(); break;
      case 'open-build': this.openBuild(arg || 'resource'); break;
      case 'build-tab': this.openBuild(arg); break;
      case 'build-pick': g.startPlacing(arg); break;
      case 'place-confirm': g.confirmPlace(); break;
      case 'place-cancel': g.cancelPlace(); break;
      case 'open-army': this.openArmy(); break;
      case 'open-kingdom': this.openKingdom(); break;
      case 'collect-all': g.collectAll(); break;
      case 'open-attack': this.openAttack(); break;
      case 'open-menu': this.openMenu(); break;
      case 'b-collect': g.collectBuilding(Number(arg)); break;
      case 'b-move': g.beginMove(Number(arg)); break;
      case 'b-remove': g.removeBuilding(Number(arg)); break;
      case 'b-train': this.openArmy(arg); break;
      case 'train': g.train(arg); break;
      case 'cancel-train': { const [b, i] = arg.split(':'); g.cancelTraining(b, Number(i)); break; }
      case 'decree': g.decree(arg); break;
      case 'attack-kingdom': this.closeModal(); g.startBattle(arg); break;
      case 'close-modal': this.closeModal(); break;
      case 'battle-end': g.endBattle(); break;
      case 'cmd-hold': g.cmdHold(); break;
      case 'cmd-proceed': g.cmdProceed(); break;
      case 'cmd-deselect': g.cmdDeselect(); break;
      case 'troop-pick': g.selectTroop(arg); break;
      case 'results-close': this.closeModal(); g.finishBattle(); break;
      case 'save-game': g.save(true); break;
      case 'reset-game': g.resetGame(); break;
      case 'help': this.showHelp(); break;
      case 'find-building': g.focusBuilding(arg); this.closePanel(); break;
    }
  }

  // --- generic ---------------------------------------------------------------
  toast(msg, ms = 2200) {
    const t = $('toast'); t.textContent = msg; t.hidden = false;
    clearTimeout(this.toastTimer); this.toastTimer = setTimeout(() => { t.hidden = true; }, ms);
  }

  fillThumbs(root) {
    root.querySelectorAll('[data-thumb]').forEach(el => {
      const [kind, id] = el.dataset.thumb.split(':');
      const src = kind === 'b' ? buildingSprite(id) : unitIcon(id);
      const c = document.createElement('canvas');
      c.width = src.w; c.height = src.h;
      c.getContext('2d').drawImage(src.canvas, 0, 0);
      el.replaceWith(c);
    });
  }

  openPanel(kind, arg, title, html) {
    this.panel = { kind, arg };
    const body = $('panel-body');
    const scroll = body.scrollTop;
    $('panel-title').textContent = title;
    body.innerHTML = html;
    this.fillThumbs(body);
    body.scrollTop = scroll;
    $('panel').hidden = false;
  }
  closePanel() { this.panel = null; $('panel').hidden = true; this.game.selected = null; }

  // re-render whatever panel is open (timers, counts)
  refreshPanel() {
    if (!this.panel) return;
    const { kind, arg } = this.panel;
    if (kind === 'build') this.openBuild(arg);
    else if (kind === 'info') { const b = this.game.state.buildings.find(b => b.id === arg); if (b) this.openBuildingInfo(b); else this.closePanel(); }
    else if (kind === 'army') this.openArmy(arg);
    else if (kind === 'kingdom') this.openKingdom();
  }

  openModal(html) { const m = $('modal-body'); m.innerHTML = html; this.fillThumbs(m); $('modal').hidden = false; }
  closeModal() { $('modal').hidden = true; }

  // --- HUD ---------------------------------------------------------------------
  refreshHUD() {
    const s = this.game.state, cap = capacities(s), army = armySummary(s);
    for (const k of ['serge', 'jade']) {
      const have = Math.floor(s.resources[k]), max = cap.storage[k];
      $(`res-${k}`).textContent = `${have}/${max}`;
      $(`fill-${k}`).style.width = `${max ? Math.min(100, have / max * 100) : 0}%`;
    }
    $('hud-pop').textContent = `${s.citizens.length}/${cap.popCap}`;
    $('hud-happy').textContent = `${happiness(s)}%`;
    $('hud-credits').textContent = (s.credits > 0 ? '+' : '') + s.credits;
    $('hud-army').textContent = `${army.housing}/${army.housingCap}` + (army.cavalryCap ? ` +${army.cavalry}/${army.cavalryCap}` : '');
    $('hud-season').textContent = s.season;
    this.refreshObjectives();
  }

  refreshObjectives() {
    const s = this.game.state;
    const knights = s.army.filter(u => UNITS[u.type].kind === 'human').length;
    const creatures = s.army.filter(u => UNITS[u.type].kind === 'creature').length;
    const objs = [
      ['Build Barracks H', countType(s, 'barracks_h') > 0],
      ['Build a Guard Station', countType(s, 'guard_station') > 0],
      ['Enlist a second soldier', knights >= 2],
      ['Build Barracks L, summon a creature', creatures >= 3],
      ['Build a Short-Fire Cannon', countType(s, 'cannon') > 0],
      ['Raid Ashford Hamlet', s.stats.battles >= 1],
      ['Win a raid (1+ star)', s.stats.wins >= 1],
    ];
    const el = $('objectives');
    if (objs.every(o => o[1])) { el.innerHTML = '<h4>Castle Level One</h4><div class="obj done">All demo objectives complete. Castle Level Two awaits a future milestone.</div>'; return; }
    el.innerHTML = '<h4>Objectives</h4>' + objs.map(([t, d]) => `<div class="obj ${d ? 'done' : ''}">${t}</div>`).join('');
  }

  // --- build menu ----------------------------------------------------------------
  openBuild(cat = 'resource') {
    const s = this.game.state;
    const tabs = CATEGORIES.map(c => `<button class="btn small ${c.id === cat ? 'active gold' : 'wood'}" data-action="build-tab" data-arg="${c.id}">${c.name}</button>`).join('');
    const cards = Object.entries(BUILDINGS).filter(([, d]) => d.category === cat).map(([id, d]) => {
      const n = countType(s, id);
      const err = d.buildable === false ? 'Pre-built' : (n >= d.limit ? 'Limit reached' : (!canAfford(s, d.cost) ? 'Too expensive' : null));
      return `<div class="card ${err ? 'disabled' : ''}" ${err ? '' : `data-action="build-pick" data-arg="${id}"`} title="${esc(d.desc)}">
        <span data-thumb="b:${id}"></span>
        <div class="name">${d.name}</div>
        <div class="cost">${costHtml(d.cost)}</div>
        <div class="count">${n}/${d.limit}${d.time ? ` · ${fmtTime(d.time)}` : ''}${err ? `<span class="err">${esc(err)}</span>` : ''}</div>
      </div>`;
    }).join('');
    this.openPanel('build', cat, 'Build', `<div class="tabs">${tabs}</div><div class="cards">${cards}</div>
      <p class="muted" style="margin-top:10px">Tap a building, then tap the map to position it. Tap the same spot again or press Place to confirm.</p>`);
  }

  // --- building info ---------------------------------------------------------------
  openBuildingInfo(b) {
    const s = this.game.state, d = BUILDINGS[b.type];
    let rows = '';
    if (!isBuilt(b)) rows += `<div class="row"><span>Under construction</span><span>${fmtTime(b.buildRemaining)}</span></div>`;
    if (d.hp) rows += `<div class="row"><span>Hitpoints</span><span>${d.hp}</span></div>`;
    if (d.produces) {
      const mult = this.game.productionMultiplier();
      rows += `<div class="row"><span>Production</span><span>${(d.produces.perSecond * mult * 60).toFixed(0)} ${RESOURCES[d.produces.resource].name}/min</span></div>`;
      rows += `<div class="row"><span>Stored</span><span>${Math.floor(b.stored)}/${d.produces.capacity}</span></div>
        <div class="bar ${d.produces.resource}"><i style="width:${Math.min(100, b.stored / d.produces.capacity * 100)}%"></i></div>`;
    }
    const p = d.provides || {};
    if (p.storage) for (const k in p.storage) rows += `<div class="row"><span>${RESOURCES[k].name} capacity</span><span>+${p.storage[k]}</span></div>`;
    if (p.popCap) rows += `<div class="row"><span>Population capacity</span><span>+${p.popCap}</span></div>`;
    if (p.housing) rows += `<div class="row"><span>Army housing</span><span>+${p.housing}${p.housingFor ? ' (cavalry)' : ''}</span></div>`;
    if (p.happiness) rows += `<div class="row"><span>Happiness</span><span>+${p.happiness}</span></div>`;
    if (p.profession) rows += `<div class="row"><span>Employs</span><span>${p.profession}</span></div>`;
    if (p.healSpeed) rows += `<div class="row"><span>Healing speed</span><span>x${p.healSpeed}</span></div>`;
    if (d.defense) rows += `<div class="row"><span>Range</span><span>${d.defense.range} tiles</span></div><div class="row"><span>Rate of fire</span><span>${(1 / d.defense.rate).toFixed(1)}/s</span></div><div class="row"><span>Damage</span><span>${d.defense.damage}</span></div>`;
    if (d.trains) rows += `<div class="row"><span>Trains</span><span>${d.trains.map(t => UNITS[t].name).join(', ')}</span></div>`;
    if (b.type === 'castle') rows += `<div class="row"><span>Citizens sheltered</span><span>${s.citizens.length}</span></div>`;

    let actions = '';
    if (d.produces && isBuilt(b)) actions += `<button class="btn small gold" data-action="b-collect" data-arg="${b.id}">Collect ${Math.floor(b.stored)}</button>`;
    if (d.trains && isBuilt(b)) actions += `<button class="btn small green" data-action="b-train" data-arg="${b.type}">Train</button>`;
    if (b.type === 'castle') actions += `<button class="btn small" disabled title="Beyond the scope of this demo">Upgrade (locked)</button>`;
    actions += `<button class="btn small wood" data-action="b-move" data-arg="${b.id}">Move</button>`;
    if (b.type !== 'castle') actions += `<button class="btn small danger" data-action="b-remove" data-arg="${b.id}">Demolish</button>`;

    this.openPanel('info', b.id, `${d.name} · Lv ${b.level}`, `
      <div style="display:flex;gap:10px;align-items:flex-start"><span data-thumb="b:${b.type}"></span><p class="muted">${esc(d.desc)}</p></div>
      ${rows}<div class="actions">${actions}</div>`);
  }

  // --- army ------------------------------------------------------------------------
  openArmy(barracks) {
    const s = this.game.state, sum = armySummary(s);
    const bar = (id) => {
      const d = BUILDINGS[id];
      if (!hasBuilt(s, id)) return `<h3>${d.name}</h3><p class="muted">${countType(s, id) ? 'Under construction.' : `Not built yet. Find it under Build → Military.`}</p>`;
      const cards = d.trains.map(t => {
        const u = UNITS[t], err = trainError(s, t);
        return `<div class="card ${err ? 'disabled' : ''}" ${err ? '' : `data-action="train" data-arg="${t}"`} title="${esc(u.desc)}">
          <span data-thumb="u:${t}"></span><div class="name">${u.name}</div>
          <div class="cost">${costHtml(u.cost)}</div>
          <div class="count">${u.hp} HP · ${u.atk} ATK · ${u.housing} space · ${fmtTime(u.time)}${err ? `<span class="err">${esc(err)}</span>` : ''}</div></div>`;
      }).join('');
      const q = s.queues[id].map((it, i) => `<div class="q" data-action="cancel-train" data-arg="${id}:${i}" title="Tap to cancel"><span data-thumb="u:${it.type}"></span>${fmtTime(it.remaining)}</div>`).join('');
      return `<h3>${d.name}</h3><div class="cards">${cards}</div><div class="queue">${q || '<span class="muted">Queue empty</span>'}</div>`;
    };
    const bonds = bonding(s);
    const roster = s.army.map(u => {
      const d = UNITS[u.type];
      const bonded = d.kind === 'human' ? (bonds.get(u.id) || []).map(id => UNITS[s.army.find(x => x.id === id).type].name[0]).join('') : '';
      return `<div class="u ${u.status}" title="${esc(d.desc)}"><span data-thumb="u:${u.type}"></span><div class="n">${d.name}</div>
        <div>${u.status === 'injured' ? `heals ${fmtTime(u.healRemaining / capacities(s).healSpeed)}` : (bonded ? `bonded: ${bonded}` : 'ready')}</div></div>`;
    }).join('');
    const king = s.king.status === 'ready' ? 'ready to lead' : `recovering ${fmtTime(s.king.healRemaining / capacities(s).healSpeed)}`;
    this.openPanel('army', barracks, 'Army', `
      <div class="row"><span>Army housing</span><span>${sum.housing}/${sum.housingCap}</span></div>
      <div class="row"><span>Cavalry housing</span><span>${sum.cavalry}/${sum.cavalryCap}</span></div>
      <div class="row"><span>Ready / injured</span><span>${sum.ready} / ${sum.injured}</span></div>
      ${bar('barracks_h')}${bar('barracks_l')}
      <h3>Roster</h3>
      <div class="roster"><div class="u ${s.king.status}"><span data-thumb="u:king"></span><div class="n">The King</div><div>${king}</div></div>${roster}</div>
      <p class="muted" style="margin-top:8px">Soldiers bond with up to two creatures (shown by initial). Soldiers who fall in battle may die for good; the injured recover faster with a Hospital.</p>`);
  }

  // --- kingdom -------------------------------------------------------------------------
  openKingdom() {
    const s = this.game.state, cap = capacities(s), hap = happiness(s), bonds = bonding(s);
    const byProf = {};
    for (const c of s.citizens) byProf[c.profession] = (byProf[c.profession] || 0) + 1;
    const profs = Object.entries(byProf).map(([p, n]) => `<span class="chip ${p === 'Soldier' ? 'soldier' : ''}">${p} ×${n}</span>`).join(' ');
    const citizens = s.citizens.map(c => `<div class="row"><span>${esc(c.name)}, ${c.age}</span><span>${c.profession}${(bonds.get(c.id) || []).length ? ' · 1 creature' : ''}</span></div>`).join('');
    const decrees = Object.entries(DECREES).map(([id, d]) => {
      const cd = s.decreeCooldowns[id] || 0;
      return `<button class="btn small ${id === 'festival' ? 'green' : 'gold'}" data-action="decree" data-arg="${id}" ${cd > 0 ? 'disabled' : ''} title="${esc(d.desc)}">${d.name}${cd > 0 ? ` (${fmtTime(cd)})` : ''}</button>`;
    }).join('');
    const align = s.credits >= 20 ? 'Beloved' : s.credits > 0 ? 'Respected' : s.credits === 0 ? 'Neutral' : s.credits > -20 ? 'Feared' : 'Tyrant';
    const creatureTable = Object.entries(CREATURES).map(([id, c]) => { const t = TYPE_RATIOS[c.type]; return `<div class="row"><span>${c.name} (${c.base}, ${c.type})</span><span>STR ${t.strength} · MAG ${t.magic} · DEF ${t.defense} · SPD ${c.speed} · HP ${c.hp}</span></div>`; }).join('');
    const logs = s.log.slice(0, 8).map(l => `<div class="muted">· ${esc(l.msg)}</div>`).join('');
    this.openPanel('kingdom', null, 'Kingdom', `
      <div class="row"><span>Population</span><span>${s.citizens.length}/${cap.popCap}</span></div>
      <div class="row"><span>Happiness</span><span>${hap}%</span></div>
      <div class="bar"><i style="width:${hap}%"></i></div>
      <div class="row"><span>Credits (karma)</span><span>${s.credits} · ${align}</span></div>
      <div class="row"><span>Season</span><span>${s.season}</span></div>
      <div class="row"><span>Born / passed away</span><span>${s.stats.born} / ${s.stats.died}</span></div>
      <h3>Decrees</h3><div class="actions">${decrees}</div>
      <p class="muted">How you govern feeds the Credit system. High credits unlock rarer creatures such as Firon; a tyrant is left with only basic ones.</p>
      <h3>Professions</h3><div>${profs || '<span class="muted">Nobody yet</span>'}</div>
      <p class="muted" style="margin-top:6px">Civilians bond 1 creature, soldiers 2, the King up to 5.</p>
      <h3>Citizens</h3>${citizens}
      <h3>Creature types (placeholder ratios)</h3>${creatureTable}
      <h3>Chronicle</h3>${logs}
      <h3>Raids</h3><div class="row"><span>Battles / wins / stars</span><span>${s.stats.battles} / ${s.stats.wins} / ${s.stats.stars}</span></div>
      <div class="row"><span>Looted</span><span>${s.stats.looted.serge} Serge · ${s.stats.looted.jade} Jade</span></div>
      <div class="row"><span>Soldiers lost</span><span>${s.stats.soldiersLost}</span></div>`);
  }

  // --- attack --------------------------------------------------------------------------
  openAttack() {
    const s = this.game.state;
    const ready = s.army.filter(u => u.status === 'ready');
    const list = ENEMY_KINGDOMS.map(k => `<button class="kingdom" data-action="attack-kingdom" data-arg="${k.id}">
      <div class="n">${k.name}</div><div class="muted">${esc(k.desc)}</div>
      <div><i class="gem serge sm"></i> ${k.loot.serge} &nbsp; <i class="gem jade sm"></i> ${k.loot.jade} &nbsp; · &nbsp; Cannons: ${k.cannons}</div></button>`).join('');
    this.openModal(`<h2>Arm-Guard Hologram</h2>
      <p class="muted">Pick a kingdom to raid. You lead ${ready.length} troop${ready.length === 1 ? '' : 's'}${s.king.status === 'ready' ? ' and the King' : ''}. Troops deployed are directed live: tap one to select it, tap a building to focus, or hold and proceed.</p>
      ${ready.length === 0 && s.king.status !== 'ready' ? '<p style="color:var(--danger)">Nobody is ready to fight. Train troops first.</p>' : ''}
      ${list}<div class="actions"><button class="btn wood" data-action="close-modal">Back</button></div>`);
  }

  openMenu() {
    this.openModal(`<h2>Nivi · Castle Level One</h2>
      <p class="muted">A kingdom-builder demo. Your progress is saved in this browser automatically.</p>
      <div class="actions">
        <button class="btn" data-action="help">How to play</button>
        <button class="btn green" data-action="save-game">Save now</button>
        <button class="btn danger" data-action="reset-game">New kingdom</button>
        <button class="btn wood" data-action="close-modal">Close</button></div>`);
  }

  showHelp() {
    this.openModal(`<h2>How to play</h2>
      <h3>Base</h3><ul>
        <li>Drag to pan, scroll or pinch to zoom, <kbd>WASD</kbd> also pans.</li>
        <li>Tap a building to inspect it. Mines fill up: tap them (or Collect) to harvest Serge and Jade.</li>
        <li>Build → pick a building → tap the map → Place. Right-click or <kbd>Esc</kbd> cancels.</li>
        <li>Homes raise population. Citizens take professions from your buildings and bond creatures.</li>
        <li>Barracks H enlists citizens as soldiers; Barracks L summons creatures. Both need army housing (Guard Stations, Outposts, Cavalry Outpost).</li></ul>
      <h3>Attack</h3><ul>
        <li>Pick a troop at the bottom, tap the ground to deploy. Troops can't be dropped next to enemy buildings.</li>
        <li>Tap a troop to select it, then tap a building to focus it. Hold / Proceed control the selection (or everyone).</li>
        <li>The King is deployed like a troop and walks wherever you tap.</li>
        <li>Stars: 50% destruction, the Castle, 100% destruction. Loot comes from destroyed mines, storages and the Castle.</li>
        <li>Soldiers who fall may die permanently. The rest are injured and recover, faster with a Hospital.</li></ul>
      <div class="actions"><button class="btn green" data-action="close-modal">Close</button></div>`);
  }

  // --- battle ---------------------------------------------------------------------------
  enterBattle() {
    $('hud-top').hidden = true; $('hud-stats').hidden = true; $('bottom-bar').hidden = true; $('objectives').hidden = true; $('place-bar').hidden = true;
    this.closePanel(); this.closeModal();
    $('battle-hud').hidden = false; $('hologram').hidden = false;
    this.selectedTroop = null;
  }
  exitBattle() {
    $('hud-top').hidden = false; $('hud-stats').hidden = false; $('bottom-bar').hidden = false; $('objectives').hidden = false;
    $('battle-hud').hidden = true; $('hologram').hidden = true;
  }

  refreshBattle(battle) {
    $('b-time').textContent = fmtTime(battle.timeLeft);
    $('b-destroy').textContent = `${Math.round(battle.destruction * 100)}%`;
    $('b-stars').textContent = '★'.repeat(battle.stars) + '☆'.repeat(3 - battle.stars);
    $('b-serge').textContent = battle.loot.serge; $('b-jade').textContent = battle.loot.jade;
    const sel = battle.selected;
    $('b-selected').textContent = sel ? `${UNITS[sel.type].name} (${Math.ceil(sel.hp)} HP)` : 'All troops';
    $('battle-hint').textContent = battle.started
      ? (sel ? (sel.type === 'king' ? 'Tap the ground to move the King, or a building to attack it.' : 'Tap a building to focus this troop.') : 'Tap a troop to direct it. Tap the ground with a troop type selected to deploy more.')
      : 'Select a troop below, then tap the ground to deploy. The clock starts on first deployment.';
    const counts = battle.availableCounts();
    const types = [...new Set(battle.available.map(u => u.type))];
    if (battle.kingAvailable && !battle.kingDeployed) types.unshift('king');
    const key = types.map(t => `${t}:${counts[t] || 0}`).join('|') + '|' + this.selectedTroop;
    if (this.troopKey === key) return;
    this.troopKey = key;
    const bar = $('troop-bar');
    bar.innerHTML = types.map(t => `<div class="troop ${this.selectedTroop === t ? 'active' : ''}" data-action="troop-pick" data-arg="${t}">
      <span data-thumb="u:${t}"></span><div class="c">${t === 'king' ? '♛' : counts[t]}</div><div class="n">${UNITS[t].name}</div></div>`).join('')
      || '<div class="troop empty"><div class="n">No troops left</div></div>';
    this.fillThumbs(bar);
  }

  showResults(result, outcome) {
    const dead = outcome.dead.map(u => UNITS[u.type].name).join(', ');
    const injured = outcome.injured.map(u => UNITS[u.type].name).join(', ');
    this.openModal(`<h2>${result.stars > 0 ? 'Victory' : 'Defeat'} · ${esc(result.enemyName)}</h2>
      <div class="stars">${'★'.repeat(result.stars)}${'☆'.repeat(3 - result.stars)}</div>
      <p class="muted">${esc(result.reason)}</p>
      <div class="row"><span>Destruction</span><span>${Math.round(result.destruction * 100)}%</span></div>
      <div class="row"><span>Loot</span><span><i class="gem serge sm"></i> ${result.loot.serge} &nbsp; <i class="gem jade sm"></i> ${result.loot.jade}</span></div>
      <div class="row"><span>Survivors</span><span>${result.survivors}</span></div>
      <div class="row"><span>Fallen for good</span><span style="color:var(--danger)">${dead || 'none'}</span></div>
      <div class="row"><span>Injured (recovering)</span><span>${injured || 'none'}</span></div>
      ${result.fallen.some(f => f.type === 'king') ? '<p class="muted">The King was carried off the field and will recover.</p>' : ''}
      <div class="actions"><button class="btn green big" data-action="results-close">Return home</button></div>`);
  }

  showPlaceBar(label) { $('place-label').textContent = label; $('place-bar').hidden = false; }
  hidePlaceBar() { $('place-bar').hidden = true; }
}
