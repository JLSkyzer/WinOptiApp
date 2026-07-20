(function () {
  const CATEGORY_META = {
    alimentation: { label: 'Alimentation', desc: 'Plans d\'alimentation et gestion de l\'energie du CPU/USB.' },
    reseau: { label: 'Reseau', desc: 'Latence, Nagle, RSS et economie d\'energie de la carte reseau.' },
    affichage: { label: 'Affichage', desc: 'HAGS, MSI Mode et effets visuels pour la fluidite et la visibilite.' },
    jeux: { label: 'Jeux', desc: 'Mode Jeu, GameDVR/overlay et preference GPU par executable.' },
    demarrage: { label: 'Demarrage', desc: 'Applications au demarrage de Windows et desinstallation du bloatware.' },
    services: { label: 'Services', desc: 'Services Windows non essentiels et priorite MMCSS pour le jeu au premier plan.' },
    confidentialite: { label: 'Confidentialite', desc: 'Widgets, Copilot, suggestions Bing et taches planifiees de telemetrie produit (jamais Windows Update / Defender).' }
  };
  const CATEGORY_ORDER = ['alimentation', 'reseau', 'affichage', 'jeux', 'demarrage', 'services', 'confidentialite'];
  const RISK_LABEL = { basique: 'Basique', intermediaire: 'Intermediaire', avance: 'Avance' };

  const state = {
    catalog: [],
    statesById: {},
    pending: {},
    guideSteps: [],
    guideState: {},
    currentPage: 'dashboard',
    currentGuideCategory: null,
    isAdmin: true
  };

  const sidebarEl = document.getElementById('sidebar');
  const contentEl = document.getElementById('content');

  function toast(message, ok) {
    let stack = document.querySelector('.toast-stack');
    if (!stack) {
      stack = document.createElement('div');
      stack.className = 'toast-stack';
      document.body.appendChild(stack);
    }
    const el = document.createElement('div');
    el.className = 'toast ' + (ok ? 'ok' : 'err');
    el.textContent = message;
    stack.appendChild(el);
    setTimeout(() => el.remove(), 4200);
  }

  function entriesForCategory(cat) {
    return state.catalog.filter((e) => e.category === cat);
  }

  function toggleEntriesForCategory(cat) {
    return entriesForCategory(cat).filter((e) => e.kind);
  }

  function categoryCounts(cat) {
    const entries = toggleEntriesForCategory(cat);
    let on = 0;
    entries.forEach((e) => {
      const eff = effectiveState(e.id);
      if (eff === 'on') on++;
    });
    return { on, total: entries.length };
  }

  function effectiveState(id) {
    if (Object.prototype.hasOwnProperty.call(state.pending, id)) {
      return state.pending[id] ? 'on' : 'off';
    }
    const s = state.statesById[id];
    return s ? s.state : 'unknown';
  }

  function isDirty(id) {
    return Object.prototype.hasOwnProperty.call(state.pending, id);
  }

  async function refreshStates() {
    const res = await window.api.callEngine('GetAllStates');
    if (!res.ok) { toast('Erreur de lecture des etats: ' + res.error, false); return; }
    const map = {};
    res.data.forEach((s) => { map[s.id] = s; });
    state.statesById = map;
  }

  async function init() {
    const [catalog, guideSteps, guideState, envInfo] = await Promise.all([
      window.api.getCatalog(),
      window.api.getGuideSteps(),
      window.api.getGuideState(),
      window.api.callEngine('GetEnvironmentInfo')
    ]);
    state.catalog = catalog;
    state.guideSteps = guideSteps;
    state.guideState = guideState || {};
    state.isAdmin = envInfo.ok ? !!envInfo.data.isAdmin : true;
    await refreshStates();
    renderAdminBanner();
    renderSidebar();
    renderPage();
  }

  function renderAdminBanner() {
    if (state.isAdmin) return;
    const banner = document.createElement('div');
    banner.className = 'admin-banner';
    banner.textContent = 'WinOptiApp n\'est pas lance en administrateur : les reglages touchant HKLM (Widgets/Copilot, MSI Mode, MMCSS, taches planifiees...) vont echouer. Ferme l\'app et relance-la avec "Executer en tant qu\'administrateur".';
    document.body.insertBefore(banner, document.body.firstChild);
  }

  function renderSidebar() {
    sidebarEl.innerHTML = '';
    const title = document.createElement('div');
    title.className = 'sidebar-title';
    title.textContent = 'WinOptiApp';
    sidebarEl.appendChild(title);

    addNavItem('dashboard', 'Tableau de bord');

    const groupLabel = document.createElement('div');
    groupLabel.className = 'sidebar-group-label';
    groupLabel.textContent = 'Categories';
    sidebarEl.appendChild(groupLabel);

    CATEGORY_ORDER.forEach((cat) => {
      const meta = CATEGORY_META[cat];
      const counts = categoryCounts(cat);
      addNavItem(cat, meta.label, counts.total ? `${counts.on}/${counts.total}` : null);
    });

    const groupLabel2 = document.createElement('div');
    groupLabel2.className = 'sidebar-group-label';
    groupLabel2.textContent = 'Autres';
    sidebarEl.appendChild(groupLabel2);

    addNavItem('guide', 'Guide manuel');
    addNavItem('restore', 'Points de restauration');
  }

  function addNavItem(key, label, badge) {
    const item = document.createElement('div');
    item.className = 'nav-item' + (state.currentPage === key ? ' active' : '');
    const span = document.createElement('span');
    span.textContent = label;
    item.appendChild(span);
    if (badge) {
      const b = document.createElement('span');
      b.className = 'nav-badge';
      b.textContent = badge;
      item.appendChild(b);
    }
    item.addEventListener('click', () => {
      state.currentPage = key;
      state.pending = {};
      renderSidebar();
      renderPage();
    });
    sidebarEl.appendChild(item);
  }

  function renderPage() {
    contentEl.innerHTML = '';
    if (state.currentPage === 'dashboard') return renderDashboard();
    if (state.currentPage === 'guide') return renderGuide();
    if (state.currentPage === 'restore') return renderRestorePage();
    return renderCategoryPage(state.currentPage);
  }

  function header(titleText, descText) {
    const h = document.createElement('div');
    h.className = 'page-header';
    const left = document.createElement('div');
    const t = document.createElement('h1');
    t.className = 'page-title';
    t.textContent = titleText;
    left.appendChild(t);
    h.appendChild(left);
    contentEl.appendChild(h);
    if (descText) {
      const d = document.createElement('p');
      d.className = 'page-desc';
      d.textContent = descText;
      contentEl.appendChild(d);
    }
    return h;
  }

  function renderDashboard() {
    header('Tableau de bord', 'Vue d\'ensemble de tous les tweaks appliques sur cette machine.');
    const grid = document.createElement('div');
    grid.className = 'dashboard-grid';
    CATEGORY_ORDER.forEach((cat) => {
      const meta = CATEGORY_META[cat];
      const counts = categoryCounts(cat);
      const card = document.createElement('div');
      card.className = 'dash-card';
      card.innerHTML = `<div class="dash-card-title">${meta.label}</div>
        <div class="dash-card-counts"><span class="count-on">${counts.on}</span> / ${counts.total} actives</div>`;
      card.addEventListener('click', () => { state.currentPage = cat; state.pending = {}; renderSidebar(); renderPage(); });
      grid.appendChild(card);
    });
    contentEl.appendChild(grid);
  }

  function switchEl(id, currentOn, disabled, unknown) {
    const sw = document.createElement('div');
    sw.className = 'switch' + (currentOn ? ' on' : '') + (disabled ? ' disabled' : '') + (unknown ? ' unknown' : '');
    const knob = document.createElement('div');
    knob.className = 'switch-knob';
    sw.appendChild(knob);
    if (!disabled) {
      sw.addEventListener('click', () => {
        const nowOn = effectiveState(id) === 'on';
        state.pending[id] = !nowOn;
        renderPage();
      });
    }
    return sw;
  }

  function renderCategoryPage(cat) {
    const meta = CATEGORY_META[cat];
    header(meta.label, meta.desc);

    const actions = document.createElement('div');
    actions.className = 'page-actions';
    actions.style.marginBottom = '18px';

    const dirtyCount = Object.keys(state.pending).length;
    const applyBtn = document.createElement('button');
    applyBtn.className = 'btn btn-primary';
    applyBtn.textContent = dirtyCount ? `Appliquer (${dirtyCount})` : 'Appliquer';
    applyBtn.disabled = dirtyCount === 0;
    applyBtn.addEventListener('click', () => applyPending(cat));
    actions.appendChild(applyBtn);

    const resetBtn = document.createElement('button');
    resetBtn.className = 'btn';
    resetBtn.textContent = 'Reinitialiser cette categorie';
    resetBtn.addEventListener('click', () => resetCategory(cat));
    actions.appendChild(resetBtn);

    if (toggleEntriesForCategory(cat).some((e) => e.requiresExplorerRestart)) {
      const explorerBtn = document.createElement('button');
      explorerBtn.className = 'btn';
      explorerBtn.textContent = 'Redemarrer l\'Explorateur Windows';
      explorerBtn.addEventListener('click', async () => {
        if (!confirm('Ca va fermer et rouvrir la barre des taches et les fenetres de l\'Explorateur quelques secondes. Continuer ?')) return;
        explorerBtn.disabled = true;
        const r = await window.api.callEngine('RestartExplorer');
        explorerBtn.disabled = false;
        if (!r.ok) { toast('Echec: ' + r.error, false); return; }
        toast('Explorateur redemarre.', true);
      });
      actions.appendChild(explorerBtn);
    }

    contentEl.appendChild(actions);

    toggleEntriesForCategory(cat).forEach((entry) => renderToggleCard(entry));

    const specialEntries = entriesForCategory(cat).filter((e) => !e.kind);
    specialEntries.forEach((entry) => renderSpecialWidget(entry));
  }

  function renderToggleCard(entry) {
    const eff = effectiveState(entry.id);
    const dirty = isDirty(entry.id);
    const guardOk = state.statesById[entry.id] ? state.statesById[entry.id].guardOk : true;
    const wantsOn = dirty ? state.pending[entry.id] : eff === 'on';
    const blockedByGuard = !guardOk && wantsOn === false && eff === 'on';
    const disabled = (!guardOk && eff === 'off');

    const card = document.createElement('div');
    card.className = 'card' + (dirty ? ' dirty' : '');

    const main = document.createElement('div');
    main.className = 'card-main';
    const row = document.createElement('div');
    row.className = 'card-label-row';
    const label = document.createElement('span');
    label.className = 'card-label';
    label.textContent = entry.label;
    row.appendChild(label);
    const riskBadge = document.createElement('span');
    riskBadge.className = 'badge badge-' + entry.risk;
    riskBadge.textContent = RISK_LABEL[entry.risk] || entry.risk;
    row.appendChild(riskBadge);
    if (entry.requiresRestart) {
      const rb = document.createElement('span');
      rb.className = 'badge badge-restart';
      rb.textContent = 'Redemarrage requis';
      row.appendChild(rb);
    }
    if (entry.requiresExplorerRestart) {
      const eb = document.createElement('span');
      eb.className = 'badge badge-restart';
      eb.textContent = 'Redemarrage Explorateur requis';
      row.appendChild(eb);
    }
    main.appendChild(row);
    const desc = document.createElement('div');
    desc.className = 'card-desc';
    desc.textContent = entry.description;
    main.appendChild(desc);
    if (entry.guardNoDeviceClass && !guardOk) {
      const guardNote = document.createElement('div');
      guardNote.className = 'guard-note';
      guardNote.textContent = `Peripherique ${entry.guardNoDeviceClass} detecte : desactivation bloquee par securite.`;
      main.appendChild(guardNote);
    }
    card.appendChild(main);

    const sw = switchEl(entry.id, eff === 'on', disabled, eff === 'unknown');
    card.appendChild(sw);

    contentEl.appendChild(card);
  }

  async function applyPending(cat) {
    const ids = Object.keys(state.pending).filter((id) => {
      const e = state.catalog.find((x) => x.id === id);
      return e && e.category === cat;
    });
    if (!ids.length) return;
    const payload = ids.map((id) => ({ id, enabled: state.pending[id] }));
    const res = await window.api.callEngine('Apply', payload);
    if (!res.ok) { toast('Echec de l\'application: ' + res.error, false); return; }
    let okCount = 0;
    (res.data || []).forEach((r) => {
      if (r.ok) okCount++; else toast(`${r.id}: ${r.error}`, false);
      delete state.pending[r.id];
    });
    if (okCount) toast(`${okCount} tweak(s) applique(s).`, true);
    await refreshStates();
    renderSidebar();
    renderPage();
  }

  async function resetCategory(cat) {
    const res = await window.api.callEngine('ResetCategory', { category: cat });
    if (!res.ok) { toast('Echec de la reinitialisation: ' + res.error, false); return; }
    toast('Categorie reinitialisee aux valeurs par defaut.', true);
    state.pending = {};
    await refreshStates();
    renderSidebar();
    renderPage();
  }

  function renderSpecialWidget(entry) {
    if (entry.type === 'startup-list') return renderStartupList(entry);
    if (entry.type === 'bloat-list') return renderBloatList(entry);
    if (entry.type === 'exe-list') return renderGpuPrefList(entry);
  }

  function sectionTitle(text) {
    const t = document.createElement('div');
    t.className = 'section-title';
    t.textContent = text;
    contentEl.appendChild(t);
  }

  async function renderStartupList(entry) {
    sectionTitle(entry.label);
    const holder = document.createElement('div');
    holder.className = 'spinner-note';
    holder.textContent = 'Chargement...';
    contentEl.appendChild(holder);
    const res = await window.api.callEngine('ListStartupApps');
    holder.remove();
    if (!res.ok) { const e = document.createElement('div'); e.className = 'empty-state'; e.textContent = res.error; contentEl.appendChild(e); return; }
    if (!res.data || !res.data.length) { const e = document.createElement('div'); e.className = 'empty-state'; e.textContent = 'Aucune application au demarrage detectee.'; contentEl.appendChild(e); return; }
    res.data.forEach((app) => {
      const row = document.createElement('div');
      row.className = 'list-row';
      const main = document.createElement('div');
      main.className = 'list-row-main';
      const title = document.createElement('div');
      title.className = 'list-row-title';
      title.textContent = app.name;
      main.appendChild(title);
      const sub = document.createElement('div');
      sub.className = 'list-row-sub';
      sub.title = app.command;
      sub.textContent = app.command;
      main.appendChild(sub);
      row.appendChild(main);
      const sw = document.createElement('div');
      sw.className = 'switch' + (app.enabled ? ' on' : '');
      const knob = document.createElement('div');
      knob.className = 'switch-knob';
      sw.appendChild(knob);
      sw.addEventListener('click', async () => {
        const newEnabled = !(sw.classList.contains('on'));
        const r = await window.api.callEngine('SetStartupApp', { name: app.name, hive: app.hive, enabled: newEnabled });
        if (!r.ok) { toast('Echec: ' + r.error, false); return; }
        sw.classList.toggle('on', newEnabled);
      });
      row.appendChild(sw);
      contentEl.appendChild(row);
    });
  }

  async function renderBloatList(entry) {
    sectionTitle(entry.label);
    const holder = document.createElement('div');
    holder.className = 'spinner-note';
    holder.textContent = 'Chargement...';
    contentEl.appendChild(holder);
    const res = await window.api.callEngine('ListBloatApps');
    holder.remove();
    if (!res.ok) { const e = document.createElement('div'); e.className = 'empty-state'; e.textContent = res.error; contentEl.appendChild(e); return; }
    if (!res.data || !res.data.length) { const e = document.createElement('div'); e.className = 'empty-state'; e.textContent = 'Aucune application desinstallable detectee.'; contentEl.appendChild(e); return; }
    res.data.forEach((app) => {
      const row = document.createElement('div');
      row.className = 'list-row';
      const main = document.createElement('div');
      main.className = 'list-row-main';
      const title = document.createElement('div');
      title.className = 'list-row-title';
      title.textContent = app.name;
      main.appendChild(title);
      row.appendChild(main);
      const badge = document.createElement('span');
      badge.className = 'badge badge-' + (app.risk === 'faible' ? 'basique' : app.risk === 'eleve' ? 'avance' : 'intermediaire');
      badge.textContent = app.risk;
      row.appendChild(badge);
      const btn = document.createElement('button');
      btn.className = 'btn btn-danger';
      btn.textContent = 'Desinstaller';
      btn.addEventListener('click', async () => {
        if (!confirm(`Desinstaller ${app.name} ? Cette action est irreversible depuis l'app.`)) return;
        btn.disabled = true;
        const r = await window.api.callEngine('SetBloatApp', { packageFullName: app.packageFullName });
        if (!r.ok) { toast('Echec: ' + r.error, false); btn.disabled = false; return; }
        row.remove();
        toast(`${app.name} desinstalle.`, true);
      });
      row.appendChild(btn);
      contentEl.appendChild(row);
    });
  }

  async function renderGpuPrefList(entry) {
    sectionTitle(entry.label);
    const wrapper = document.createElement('div');
    contentEl.appendChild(wrapper);
    const listHolder = document.createElement('div');
    wrapper.appendChild(listHolder);

    const addBtn = document.createElement('button');
    addBtn.className = 'btn';
    addBtn.textContent = 'Ajouter un executable...';
    addBtn.addEventListener('click', async () => {
      const picked = await window.api.pickExecutable();
      if (!picked.ok) return;
      const r = await window.api.callEngine('AddGpuPrefApp', { path: picked.path });
      if (!r.ok) { toast('Echec: ' + r.error, false); return; }
      await load();
    });
    wrapper.appendChild(addBtn);

    async function load() {
      listHolder.innerHTML = '<div class="spinner-note">Chargement...</div>';
      const res = await window.api.callEngine('ListGpuPrefApps');
      listHolder.innerHTML = '';
      if (!res.ok) { listHolder.innerHTML = `<div class="empty-state">${res.error}</div>`; return; }
      if (!res.data || !res.data.length) { listHolder.innerHTML = '<div class="empty-state">Aucun executable configure.</div>'; return; }
      res.data.forEach((item) => {
        const row = document.createElement('div');
        row.className = 'list-row';
        const main = document.createElement('div');
        main.className = 'list-row-main';
        main.innerHTML = `<div class="list-row-sub" title="${item.path}">${item.path}</div>`;
        row.appendChild(main);
        const btn = document.createElement('button');
        btn.className = 'btn btn-ghost';
        btn.textContent = 'Retirer';
        btn.addEventListener('click', async () => {
          const r = await window.api.callEngine('RemoveGpuPrefApp', { path: item.path });
          if (!r.ok) { toast('Echec: ' + r.error, false); return; }
          await load();
        });
        row.appendChild(btn);
        listHolder.appendChild(row);
      });
    }
    await load();
  }

  function renderGuide() {
    header('Guide manuel', 'Reglages qui ne peuvent pas etre automatises : panneau NVIDIA, BIOS/UEFI, moniteur, parametres in-game. Coche chaque etape au fur et a mesure.');
    const categories = Array.from(new Set(state.guideSteps.map((s) => s.category)));
    if (!state.currentGuideCategory || !categories.includes(state.currentGuideCategory)) {
      state.currentGuideCategory = categories[0];
    }
    const nav = document.createElement('div');
    nav.className = 'guide-nav';
    categories.forEach((cat) => {
      const tab = document.createElement('div');
      tab.className = 'guide-tab' + (state.currentGuideCategory === cat ? ' active' : '');
      tab.textContent = cat;
      tab.addEventListener('click', () => { state.currentGuideCategory = cat; renderPage(); });
      nav.appendChild(tab);
    });
    contentEl.appendChild(nav);

    const steps = state.guideSteps.filter((s) => s.category === state.currentGuideCategory);
    steps.forEach((step) => {
      const done = !!state.guideState[step.id];
      const row = document.createElement('div');
      row.className = 'guide-step' + (done ? ' done' : '');
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = done;
      cb.addEventListener('change', async () => {
        state.guideState[step.id] = cb.checked;
        await window.api.setGuideStepChecked(step.id, cb.checked);
        row.classList.toggle('done', cb.checked);
      });
      row.appendChild(cb);
      const main = document.createElement('div');
      const title = document.createElement('div');
      title.className = 'guide-step-title';
      title.textContent = step.title;
      main.appendChild(title);
      const desc = document.createElement('div');
      desc.className = 'guide-step-desc';
      desc.textContent = step.description;
      main.appendChild(desc);
      if (step.action && step.action.type !== 'none') {
        const link = document.createElement('span');
        link.className = 'link-btn';
        link.textContent = step.action.label || 'Ouvrir';
        link.addEventListener('click', () => window.api.openExternalSettings(step.action.target));
        main.appendChild(link);
      }
      row.appendChild(main);
      contentEl.appendChild(row);
    });
  }

  async function renderRestorePage() {
    header('Points de restauration', 'Filet de securite ultime : cree par l\'app avant les series de modifications importantes. La restauration effective se fait via l\'outil Windows natif.');

    const actions = document.createElement('div');
    actions.className = 'page-actions';
    actions.style.marginBottom = '18px';

    const createBtn = document.createElement('button');
    createBtn.className = 'btn btn-primary';
    createBtn.textContent = 'Creer un point de restauration maintenant';
    createBtn.addEventListener('click', async () => {
      createBtn.disabled = true;
      const res = await window.api.callEngine('CreateRestorePoint', { description: 'WinOptiApp - manuel' });
      createBtn.disabled = false;
      if (!res.ok) { toast('Echec: ' + res.error, false); return; }
      toast('Point de restauration cree.', true);
      loadPoints();
    });
    actions.appendChild(createBtn);

    const restoreBtn = document.createElement('button');
    restoreBtn.className = 'btn';
    restoreBtn.textContent = 'Restaurer via Windows...';
    restoreBtn.addEventListener('click', () => window.api.openExternalSettings('rstrui.exe'));
    actions.appendChild(restoreBtn);

    contentEl.appendChild(actions);

    const listHolder = document.createElement('div');
    contentEl.appendChild(listHolder);

    async function loadPoints() {
      listHolder.innerHTML = '<div class="spinner-note">Chargement...</div>';
      const res = await window.api.callEngine('ListRestorePoints');
      listHolder.innerHTML = '';
      if (!res.ok) { listHolder.innerHTML = `<div class="empty-state">${res.error}</div>`; return; }
      if (!res.data || !res.data.length) { listHolder.innerHTML = '<div class="empty-state">Aucun point de restauration trouve.</div>'; return; }
      res.data.forEach((p) => {
        const row = document.createElement('div');
        row.className = 'list-row';
        row.innerHTML = `<div class="list-row-main"><div class="list-row-title">${p.Description}</div>
          <div class="list-row-sub">${p.CreationTime}</div></div>`;
        listHolder.appendChild(row);
      });
    }
    loadPoints();
  }

  init();
})();
