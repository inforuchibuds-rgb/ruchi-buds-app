// =====================================================================
// RUCHI BUDS APP · core.js · Version 1.6 · 28-Nov-2026 (1.6: one heading layout on every screen, running line on the yellow strip; 1.5: share by WhatsApp or email; 1.3: Back, Home, Close, Hide, Refresh, Print, Excel, Help, Search, automatic sign-out; 1.4: online shop alerts on the home screen)
// Sign-in, first-time password set-up, home menu, page routing and the
// small helpers every other screen file uses (dates, messages, grids).
// =====================================================================
(function () {
  'use strict';

  const RB = (window.RB = {
    sb: null,          // Supabase client
    profile: null,     // the signed-in user (from rb_my_profile)
    screens: {},       // screen renderers registered by users.js, settings.js, ...
    cache: {},
  });

  const ICONS = {
    cart: '🛒', truck: '🚚', boxes: '📦', pot: '🍲', tag: '🏷️', receipt: '🧾', people: '👥',
    coins: '💰', wallet: '👛', bank: '🏦', list: '📋', book: '📒', chart: '📊', bag: '🛍️',
    user: '🔑', gear: '⚙️', clock: '🕒',
  };
  const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  // ---------- small helpers ----------
  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  RB.$ = $; RB.$$ = $$;

  RB.esc = (v) => String(v == null ? '' : v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

  // dd-mmm-yyyy everywhere, e.g. 25-Nov-2026
  RB.fmtDate = (v) => {
    if (!v) return '';
    const d = typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) ? new Date(v + 'T00:00:00') : new Date(v);
    if (isNaN(d)) return '';
    return String(d.getDate()).padStart(2, '0') + '-' + MONTHS[d.getMonth()] + '-' + d.getFullYear();
  };
  RB.fmtDateTime = (v) => {
    if (!v) return '';
    const d = new Date(v);
    return RB.fmtDate(d) + ' ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  };
  RB.today = () => {
    const d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  };
  RB.rupees = (paise) => paise == null ? '' :
    '₹' + (Number(paise) / 100).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  RB.toast = (text, isError) => {
    const t = $('#toast');
    t.textContent = text;
    t.className = isError ? 'error' : '';
    clearTimeout(RB._toastTimer);
    RB._toastTimer = setTimeout(() => t.classList.add('hidden'), isError ? 6000 : 2500);
  };

  // Turn database errors into plain English.
  RB.friendly = (err) => {
    const m = (err && (err.message || err.error_description || err.msg)) || String(err || 'Something went wrong');
    if (/RB_NOT_INVITED|Database error saving new user/i.test(m))
      return 'This email has not been invited yet. Ask a Director, the FC or the Accountant to add you in Users first.';
    if (/Invalid login credentials/i.test(m)) return 'Wrong email or password.';
    if (/User already registered/i.test(m)) return 'This email already has a password. Use Sign in instead.';
    if (/Password should be at least/i.test(m)) return 'The password must be at least 8 characters.';
    if (/Failed to fetch|NetworkError/i.test(m)) return 'No connection to the database. Check the internet and try again.';
    if (/JWT expired/i.test(m)) return 'Your session ran out. Please sign in again.';
    if (/permission denied/i.test(m)) return 'You do not have access to this.';
    return m.replace(/^ERROR:\s*/, '');
  };

  // Call a database function; throws a friendly Error on failure.
  RB.rpc = async (name, args) => {
    const { data, error } = await RB.sb.rpc(name, args || {});
    if (error) throw new Error(RB.friendly(error));
    return data;
  };
  // Read rows from a table; throws a friendly Error on failure.
  RB.select = async (table, columns, build) => {
    let q = RB.sb.from(table).select(columns || '*');
    if (build) q = build(q);
    const { data, error } = await q;
    if (error) throw new Error(RB.friendly(error));
    return data;
  };

  RB.has = (perm) => !!(RB.profile && RB.profile.permissions.includes(perm));

  // ---------- modal ----------
  RB.modal = (html, opts) => {
    const bg = document.createElement('div');
    bg.className = 'modal-bg';
    bg.innerHTML = '<div class="modal ' + ((opts && opts.wide) ? 'wide' : '') + '" role="dialog" aria-modal="true">' +
      '<button type="button" class="modal-x" data-close aria-label="Close" title="Close">✕</button>' + html + '</div>';
    document.body.appendChild(bg);
    const close = () => bg.remove();
    bg.addEventListener('click', (e) => { if (e.target === bg) close(); });
    $$('[data-close]', bg).forEach((b) => b.addEventListener('click', close));
    const first = $('input, select, textarea', bg);
    if (first) setTimeout(() => first.focus(), 30);
    return { el: bg, close };
  };

  // Ask the user to type a word before something that cannot be undone.
  RB.confirmTyped = (title, explain, word) => new Promise((resolve) => {
    const m = RB.modal(
      '<h2>' + RB.esc(title) + '</h2><p>' + explain + '</p>' +
      '<div class="field"><label>Type <b>' + RB.esc(word) + '</b> to confirm</label><input id="cf-word" autocomplete="off"></div>' +
      '<div class="actions"><button class="danger" id="cf-yes" disabled>Confirm</button><button data-close>Cancel</button></div>');
    const inp = $('#cf-word', m.el), yes = $('#cf-yes', m.el);
    inp.addEventListener('input', () => { yes.disabled = inp.value.trim() !== word; });
    yes.addEventListener('click', () => { m.close(); resolve(inp.value.trim()); });
    $$('[data-close]', m.el).forEach((b) => b.addEventListener('click', () => resolve(null)));
  });

  RB.confirm = (title, explain) => new Promise((resolve) => {
    const m = RB.modal('<h2>' + RB.esc(title) + '</h2><p>' + explain + '</p>' +
      '<div class="actions"><button class="primary" id="cf-ok">Yes</button><button data-close>No</button></div>');
    $('#cf-ok', m.el).addEventListener('click', () => { m.close(); resolve(true); });
    $$('[data-close]', m.el).forEach((b) => b.addEventListener('click', () => resolve(false)));
  });

  // ---------- grids ----------
  // A spreadsheet-style grid with sort, header filters and Excel download.
  RB.grid = (el, columns, data, opts) => new Tabulator(el, Object.assign({
    data, columns, layout: 'fitDataStretch', height: opts && opts.height,
    placeholder: 'Nothing to show yet', movableColumns: true,
    pagination: data.length > 50, paginationSize: 50,
    columnDefaults: { headerFilter: 'input', headerFilterPlaceholder: 'filter…', tooltip: true },
    printAsHtml: true, printRowRange: 'active',  // Print shows every row that passes the filters, not just this page
  }, opts || {}));

  RB.downloadExcel = (grid, name) => {
    grid.download('xlsx', name + ' ' + RB.fmtDate(new Date()) + '.xlsx', { sheetName: name.slice(0, 30) });
  };

  RB.badge = (cls, text) => '<span class="badge ' + cls + '">' + RB.esc(text) + '</span>';

  // ---------- share by WhatsApp or email (free links, nothing is sent by the app) ----------
  // An Indian mobile number in any common form (98xxxxxxxx, 098..., +91 98..., 91-98...) becomes 9198xxxxxxxx.
  RB.waNumber = (phone) => {
    let d = String(phone || '').replace(/\D/g, '');
    if (d.length === 11 && d[0] === '0') d = d.slice(1);
    if (d.length === 10) d = '91' + d;
    return d.length >= 11 && d.length <= 15 ? d : '';
  };
  // With no usable number WhatsApp opens and asks who to send it to.
  RB.waUrl = (phone, text) => 'https://wa.me/' + RB.waNumber(phone) + '?text=' + encodeURIComponent(text || '');
  RB.mailUrl = (email, subject, text) => 'mailto:' + encodeURIComponent(String(email || '').trim()).replace(/%40/g, '@') +
    '?subject=' + encodeURIComponent(subject || '') + '&body=' + encodeURIComponent(text || '');
  // Two buttons: "Share on WhatsApp" and "Send by email". o = { phone, email, subject, text, label }
  RB.shareButtons = (o) => '<a class="btn wa no-print" target="_blank" rel="noopener" href="' + RB.esc(RB.waUrl(o.phone, o.text)) + '">' +
    RB.esc(o.label || 'Share on WhatsApp') + '</a>' +
    '<a class="btn no-print" href="' + RB.esc(RB.mailUrl(o.email, o.subject, o.text)) + '">' + RB.esc(o.mailLabel || 'Send by email') + '</a>';
  // Phone and email of a customer or supplier (empty when not on file or not readable).
  RB.contactOf = async (table, id) => {
    if (!id) return {};
    try { return (await RB.select(table, 'phone,email', (q) => q.eq('id', id)))[0] || {}; } catch (e) { return {}; }
  };
  RB.appUrl = () => location.href.split('#')[0].replace(/index\.html$/, '');
  RB.demoBadge = (row) => (row && row.is_demo ? ' ' + RB.badge('demo', 'DEMO') : '');

  // ---------- start-up ----------
  RB.start = async () => {
    const c = window.RB_CONFIG || {};
    if (!c.SUPABASE_URL || /PASTE_/.test(c.SUPABASE_URL) || !c.SUPABASE_ANON_KEY || /PASTE_/.test(c.SUPABASE_ANON_KEY)) {
      $('#app').innerHTML = '<div class="login-wrap"><img class="wordmark" src="assets/wordmark.png" alt="Ruchi Buds">' +
        '<div class="login-card"><h1>Almost there</h1><p>The app is not connected to its database yet. ' +
        'Open <b>config.js</b> and paste the Project URL and anon key from Supabase → Project Settings → API.</p></div></div>';
      return;
    }
    RB.sb = supabase.createClient(c.SUPABASE_URL, c.SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true },
    });
    // A customer opening a statement link: show just that statement, no sign-in.
    const pub = location.hash.match(/^#\/s\/([0-9a-f]{20,})$/);
    if (pub && RB.invoices) return RB.invoices.publicStatement(pub[1]);
    window.addEventListener('hashchange', () => {
      clearTimeout(RB.backTimer);
      if (RB.goingBack) { RB.goingBack = false; RB.navDepth = Math.max(0, RB.navDepth - 1); } else RB.navDepth++;
      RB.route();
    });
    const { data } = await RB.sb.auth.getSession();
    if (data.session) await RB.afterSignIn(false);
    else RB.showLogin('signin');
  };

  // ---------- login screens ----------
  RB.showLogin = (mode, message) => {
    // Draw straight away; swap in the firm's own word mark when it arrives.
    const brand = RB.cache.brand || { firm_name: 'Ruchi Buds', wordmark_url: null };
    if (!RB.cache.brand) {
      RB.sb.rpc('rb_public_branding').then(({ data }) => {
        if (!data) return;
        RB.cache.brand = data;
        const img = $('.login-wrap .wordmark');
        if (img && data.wordmark_url) img.src = data.wordmark_url;
      }, () => { /* offline: keep the standard word mark */ });
    }
    const logo = brand.wordmark_url || 'assets/wordmark.png';
    const first = mode === 'firsttime';
    $('#app').innerHTML =
      '<div class="login-wrap"><img class="wordmark" src="' + RB.esc(logo) + '" alt="' + RB.esc(brand.firm_name) + '">' +
      '<form class="login-card" id="login-form" novalidate>' +
      '<h1>' + (first ? 'Set up your password' : 'Sign in') + '</h1>' +
      (first ? '<p class="muted">Use the email a Director, the FC or the Accountant added for you.</p>' : '') +
      '<div id="login-msg">' + (message ? '<div class="msg info">' + message + '</div>' : '') + '</div>' +
      '<div class="field"><label for="li-email">Email</label><input id="li-email" type="email" autocomplete="username" required></div>' +
      '<div class="field"><label for="li-pass">' + (first ? 'Choose a password' : 'Password') + '</label>' +
      '<input id="li-pass" type="password" autocomplete="' + (first ? 'new-password' : 'current-password') + '" required minlength="8"></div>' +
      (first ? '<div class="field"><label for="li-pass2">Type the password again</label><input id="li-pass2" type="password" autocomplete="new-password" required></div>' : '') +
      '<button class="primary" style="width:100%" type="submit">' + (first ? 'Create my password' : 'Sign in') + '</button>' +
      '<div class="links">' + (first
        ? '<a href="#" id="to-signin">Already have a password? Sign in</a>'
        : '<a href="#" id="to-first">First time here? Set up your password</a><br><br>' +
          '<span class="muted">Forgot your password? Ask a Director or the FC for a temporary one.</span>') +
      '</div></form></div>';
    const sw = $(first ? '#to-signin' : '#to-first');
    sw.addEventListener('click', (e) => { e.preventDefault(); RB.showLogin(first ? 'signin' : 'firsttime'); });
    $('#login-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const email = $('#li-email').value.trim(), pass = $('#li-pass').value;
      const msg = $('#login-msg'), btn = $('#login-form button[type=submit]');
      const fail = (t) => { msg.innerHTML = '<div class="msg error">' + RB.esc(t) + '</div>'; btn.disabled = false; };
      if (!email || !pass) return fail('Please enter your email and password.');
      btn.disabled = true;
      if (first) {
        if (pass.length < 8) return fail('The password must be at least 8 characters.');
        if (pass !== $('#li-pass2').value) return fail('The two passwords are not the same.');
        const { data, error } = await RB.sb.auth.signUp({ email, password: pass });
        if (error) return fail(RB.friendly(error));
        if (!data.session) return fail('Your password is saved, but Supabase is waiting for an email confirmation. ' +
          'Ask the owner to switch off "Confirm email" in Supabase (see the setup guide), then sign in.');
        await RB.afterSignIn(true);
      } else {
        const { error } = await RB.sb.auth.signInWithPassword({ email, password: pass });
        if (error) {
          if (/Invalid login credentials/i.test(error.message)) { try { await RB.sb.rpc('rb_login_failed', { p_email: email }); } catch (x) { /* ignore */ } }
          return fail(RB.friendly(error) + (/Invalid login/i.test(error.message) ? ' Too many wrong tries will lock the account.' : ''));
        }
        await RB.afterSignIn(true);
      }
    });
  };

  RB.signOut = async (message) => {
    await RB.sb.auth.signOut();
    RB.profile = null; RB.cache = { brand: RB.cache.brand };
    $('#toast').classList.add('hidden');
    location.hash = '';
    RB.showLogin('signin', message);
  };

  RB.afterSignIn = async (fresh) => {
    let p;
    try { p = fresh ? await RB.rpc('rb_login_ok') : await RB.rpc('rb_my_profile'); }
    catch (e) { return RB.signOut(RB.esc(e.message)); }
    if (!p) return RB.signOut('This login is not linked to a Ruchi Buds user. Ask a Director to invite your email.');
    if (p.status === 'locked') return RB.signOut('Your account is <b>locked</b> after too many wrong passwords. Ask a Director, the FC or the Accountant to unlock it.');
    if (p.status === 'inactive') return RB.signOut('Your account is switched off. Ask a Director or the FC.');
    RB.profile = p;
    try {
      const s = await RB.select('app_settings', 'wordmark_url,firm_name,training_mode,go_live_date', (q) => q.eq('id', 1).single());
      RB.cache.settings = s;
    } catch (e) { RB.cache.settings = p.settings; }
    try { RB.cache.idleMinutes = (await RB.select('app_settings', 'idle_signout_minutes', (q) => q.eq('id', 1).single())).idle_signout_minutes; }
    catch (e) { RB.cache.idleMinutes = 30; }  // before 01_core_users.sql 1.1 is run
    RB.idleSignout();
    if (p.must_change_password) return RB.showChangePassword(true);
    RB.route();
  };

  // ---------- page frame ----------
  RB.frame = (title, opts) => {
    const p = RB.profile, s = RB.cache.settings || {};
    const logo = s.wordmark_url || 'assets/wordmark.png';
    $('#app').innerHTML =
      '<header class="banner"><a href="#/" aria-label="Home"><img class="wordmark" src="' + RB.esc(logo) + '" alt="Ruchi Buds"></a>' +
      '<div class="spacer"></div><div class="who">' + RB.esc(p.short_name || p.full_name) +
      '<small>' + RB.esc(p.category) + '</small></div>' +
      '<button id="btn-search" type="button" title="Find an invoice, purchase, journal, customer or supplier (Ctrl+K)">🔍 <span class="lbl">Search</span></button>' +
      '<button id="btn-hide" type="button" title="Hide the screen (Ctrl+Shift+H)">🙈 <span class="lbl">Hide</span></button>' +
      '<button id="btn-signout" type="button">Sign out</button></header>' +
      '<div id="ticker" class="training-strip ticker" role="marquee" aria-live="off" hidden></div>' +
      '<main id="page">' +
      // Row 1: Back, Home, the title, and Refresh / Print / Excel / Help on the right.
      // Row 2 (#page-tools): this screen's own buttons, such as + New or Pay. It hides itself when empty.
      (opts && opts.home ? '' : '<div class="page-head"><div class="nav-btns"><button type="button" id="nav-back">‹ Back</button><a class="btn back" href="#/" hidden></a><a class="btn" id="nav-home" href="#/">⌂ Home</a></div><h1>' + RB.esc(title) + '</h1>' +
        '<div class="page-extra"><button type="button" id="pg-refresh" title="Load the figures again" aria-label="Refresh">⟳<span class="lbl"> Refresh</span></button>' +
        '<button type="button" id="pg-print" title="Print this screen" aria-label="Print">🖨<span class="lbl"> Print</span></button>' +
        '<button type="button" id="pg-xls" title="Download the lists and tables on this screen" aria-label="Excel">⬇<span class="lbl"> Excel</span></button>' +
        '<button type="button" id="pg-help" title="Help for this screen" aria-label="Help">?<span class="lbl"> Help</span></button></div>' +
        '<div id="page-tools" class="actions"></div></div>') +
      '<div id="page-body"></div></main>';
    $('#btn-signout').addEventListener('click', () => RB.signOut());
    $('#btn-hide').addEventListener('click', () => RB.privacy(true));
    $('#btn-search').addEventListener('click', () => RB.search());
    const pb = (id, fn) => { const b = $(id); if (b) b.addEventListener('click', fn); };
    pb('#pg-refresh', () => RB.route());
    pb('#pg-print', () => window.print());
    pb('#pg-xls', () => RB.pageExcel(title));
    pb('#pg-help', () => (RB.showHelp ? RB.showHelp() : null));
    if ($('#nav-back')) $('#nav-back').addEventListener('click', RB.goBack);
    RB.loadTicker();
    return $('#page-body');
  };

  // ---------- Running line on the yellow strip ----------
  // Short notices scroll across the strip under the top bar: training mode, plus alerts that other
  // modules add with RB.tickerSources.push(async () => [{ text, href }]). Alerts are fetched again every
  // 5 minutes at most. It pauses under the mouse or finger, and stands still for people who turn off motion.
  RB.tickerSources = [];
  RB.ticker = { msgs: [], at: 0 };
  RB.tickerSources.push(async () => {  // backups: shown to people who can see Settings
    if (!RB.has('settings.view')) return [];
    const rows = await RB.select('backup_log', 'at,kind,status', (q) => q.in('kind', ['nightly', 'manual']).order('at', { ascending: false }).limit(20));
    const good = rows.find((r) => r.status === 'ok');
    if (rows.length && rows[0].status === 'failed') return [{ text: 'The last backup failed. Check Settings, Backups', href: '#/settings' }];
    if (!good) return rows.length || !(RB.cache.settings || {}).training_mode ? [{ text: 'No good backup yet. Check Settings, Backups', href: '#/settings' }] : [];
    if (Date.now() - new Date(good.at).getTime() > 36 * 3600 * 1000) return [{ text: 'No backup since ' + RB.fmtDate(good.at) + '. Check Settings, Backups', href: '#/settings' }];
    return [];
  });
  RB.loadTicker = async (force) => {
    RB.drawTicker();
    if (!force && Date.now() - RB.ticker.at < 5 * 60 * 1000) return;
    RB.ticker.at = Date.now();
    const lists = await Promise.all(RB.tickerSources.map((f) => Promise.resolve().then(f).catch(() => [])));
    RB.ticker.msgs = [].concat(...lists.map((x) => x || []));
    RB.drawTicker();
  };
  RB.drawTicker = () => {
    const el = $('#ticker'); if (!el) return;
    const msgs = ((RB.cache.settings || {}).training_mode ? [{ text: 'Training mode: entries made now are cleared at go-live' }] : []).concat(RB.ticker.msgs);
    el.hidden = !msgs.length;
    if (!msgs.length) { el.innerHTML = ''; return; }
    const one = (m) => (m.href ? '<a href="' + RB.esc(m.href) + '">' + RB.esc(m.text) + '</a>' : '<span>' + RB.esc(m.text) + '</span>');
    const html = '<div class="ticker-track">' + msgs.map(one).join('<i aria-hidden="true">✦</i>') + '</div>';
    if (el.innerHTML === html) return;  // keep the line running smoothly when nothing changed
    el.innerHTML = html;
    const track = $('.ticker-track', el);
    // About 60 pixels a second, whatever the screen width and however many notices there are.
    const secs = Math.max(8, (el.clientWidth + track.scrollWidth) / 60);
    track.style.animationDuration = secs + 's';
    // Carry on from where the line was, so moving between screens does not restart it from the right edge.
    track.style.animationDelay = -((performance.now() / 1000) % secs) + 's';
  };

  // ---------- Privacy: blur the screen ----------
  // Hide button, Ctrl+Shift+H, after 3 minutes without use, and when the app
  // goes into the background. Tap or click anywhere (or any key) to show it again.
  RB.privacy = (on) => {
    if (!RB.profile) return;
    const cover = $('#privacy');
    if (on && !cover) {
      const c = document.createElement('div');
      c.id = 'privacy'; c.setAttribute('role', 'button'); c.tabIndex = 0;
      c.innerHTML = '<div><span aria-hidden="true">🙈</span><b>Screen hidden</b><small>Tap or click anywhere to show it</small></div>';
      c.addEventListener('click', () => RB.privacy(false));
      document.body.appendChild(c); document.body.classList.add('privacy'); c.focus();
    } else if (!on && cover) { cover.parentNode.removeChild(cover); document.body.classList.toggle('privacy', false); }
  };
  RB.IDLE_MS = 3 * 60 * 1000;
  (() => {
    let t;
    const poke = () => { clearTimeout(t); t = setTimeout(() => RB.privacy(true), RB.IDLE_MS); };
    ['pointerdown', 'keydown', 'wheel', 'touchstart'].forEach((ev) => document.addEventListener(ev, poke, { passive: true, capture: true }));
    poke();
    document.addEventListener('visibilitychange', () => { if (document.hidden) RB.privacy(true); });
    document.addEventListener('keydown', (e) => {
      if (e.ctrlKey && e.shiftKey && (e.key === 'H' || e.key === 'h')) { e.preventDefault(); RB.privacy(!$('#privacy')); return; }
      if ($('#privacy')) { e.preventDefault(); e.stopPropagation(); RB.privacy(false); return; }
      if (e.key === 'Escape') { const x = $$('.modal-bg .modal-x').pop(); if (x) x.click(); }
      if ((e.ctrlKey || e.metaKey) && (e.key === 'k' || e.key === 'K') && RB.profile) { e.preventDefault(); RB.search(); }
    }, true);
  })();

  // ---------- Excel of whatever is on the screen ----------
  // Every visible grid and table on the screen (or the open pop-up) becomes a sheet.
  RB.pageExcel = (title) => {
    const top = $$('.modal-bg').pop();
    const root = top || $('#page-body');
    const seen = (el) => el.offsetParent !== null;
    const wb = XLSX.utils.book_new(); const names = {};
    const add = (ws, name) => {
      let n = (name || 'Sheet').replace(/[\\/?*[\]:]/g, ' ').slice(0, 28) || 'Sheet';
      if (names[n]) n = n.slice(0, 25) + ' ' + (++names[n]); else names[n] = 1;
      XLSX.utils.book_append_sheet(wb, ws, n);
    };
    const nameNear = (el) => { const h = el.closest('section, .card, .modal'); const t = h && $('h2, h3', h); return t ? t.textContent : title; };
    $$('.tabulator', root).filter(seen).forEach((el) => {
      const t = (Tabulator.findTable(el) || [])[0]; if (!t) return;
      const cols = t.getColumns().filter((c) => c.isVisible() && c.getField());
      const strip = (h) => String(h || '').replace(/<[^>]*>/g, '').trim();
      const aoa = [cols.map((c) => strip(c.getDefinition().title))].concat(t.getData('active').map((r) => cols.map((c) => {
        const v = r[c.getField()]; return v == null ? '' : (typeof v === 'object' ? JSON.stringify(v) : v); })));
      add(XLSX.utils.aoa_to_sheet(aoa), nameNear(el));
    });
    $$('table', root).filter((el) => seen(el) && !el.closest('.tabulator')).forEach((el) => add(XLSX.utils.table_to_sheet(el, { raw: true }), nameNear(el)));
    if (!wb.SheetNames.length) return RB.toast('There is no list or table on this screen to download.', true);
    XLSX.writeFile(wb, (title || 'Ruchi Buds') + ' ' + RB.fmtDate(new Date()) + '.xlsx');
  };

  // ---------- Quick search ----------
  RB.search = () => {
    const m = RB.modal('<h2>🔍 Search</h2>' +
      '<input id="qs-q" type="search" autocomplete="off" placeholder="Invoice or PO number, journal number, name or phone…">' +
      '<p class="muted" style="margin:.4rem 0">Type at least 2 letters. Finds invoices, purchases, journals, customers and suppliers you may see.</p>' +
      '<div id="qs-out"></div>', { wide: true });
    const inp = $('#qs-q', m.el), out = $('#qs-out', m.el);
    let t, seq = 0;
    const go = async () => {
      const q = inp.value.trim(), my = ++seq;
      if (q.length < 2) { out.innerHTML = ''; return; }
      out.innerHTML = '<p class="muted">Searching…</p>';
      try {
        const rows = await RB.rpc('rb_quick_search', { p_q: q });
        if (my !== seq) return;
        out.innerHTML = rows.length ? '<div class="qs-list">' + rows.map((r) =>
          '<a class="qs-row" href="' + RB.esc(r.link) + '"><span class="badge">' + RB.esc(r.kind) + '</span><b>' + RB.esc(r.label) + '</b>' +
          '<span class="muted">' + RB.esc(r.detail || '') + (r.on_date ? ' · ' + RB.fmtDate(r.on_date) : '') + '</span></a>').join('') + '</div>'
          : '<p class="muted">Nothing found for "' + RB.esc(q) + '".</p>';
        $$('.qs-row', out).forEach((a) => a.addEventListener('click', () => m.close()));
      } catch (e) { if (my === seq) out.innerHTML = '<div class="msg error">' + RB.esc(e.message) + '</div>'; }
    };
    inp.addEventListener('input', () => { clearTimeout(t); t = setTimeout(go, 250); });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') { const a = $('.qs-row', out); if (a) { a.click(); location.hash = a.getAttribute('href'); } } });
    setTimeout(() => inp.focus(), 30);
  };

  // ---------- Automatic sign-out ----------
  // After the number of idle minutes set in Settings (0 = never). Default 30.
  RB.idleSignout = (() => {
    let t;
    const arm = () => {
      clearTimeout(t);
      const min = RB.profile && RB.cache.idleMinutes != null ? RB.cache.idleMinutes : 30;
      if (!RB.profile || !min) return;
      t = setTimeout(() => { if (RB.profile) { RB.privacy(false); $$('.modal-bg').forEach((b) => b.parentNode.removeChild(b));
        RB.signOut('You were signed out after ' + min + ' minutes without use.'); } }, min * 60 * 1000);
    };
    ['pointerdown', 'keydown', 'wheel', 'touchstart'].forEach((ev) => document.addEventListener(ev, arm, { passive: true, capture: true }));
    return arm;
  })();

  // ---------- Back button ----------
  // The installed app (home-screen icon) has no browser Back button, so every
  // screen has its own. It goes to the previous screen; if there is none (the
  // app was just opened), it goes one level up: a record to its list, a list to Home.
  RB.navDepth = 0;
  RB.goBack = () => {
    // Going up replaces the current entry, so Back never bounces between a record and its list.
    const up = () => { const [name, arg] = location.hash.replace(/^#\/?/, '').split('/'); RB.goingBack = true; location.replace(arg ? '#/' + name : '#/'); };
    if (RB.navDepth > 0) {
      RB.goingBack = true; history.back();
      // If nothing happened (no earlier page in this app), go up a level instead.
      RB.backTimer = setTimeout(() => { RB.goingBack = false; RB.navDepth = 0; up(); }, 400);
    } else up();
  };

  // ---------- routing ----------
  RB.route = async () => {
    if (!RB.profile) return;
    const hash = location.hash.replace(/^#\/?/, '');
    const [name, arg] = hash.split('/');
    if (!name) return RB.showHome();
    if (name === 'password') return RB.showChangePassword(false);
    const screen = (await RB.loadScreens()).find((s) => s.code === name);
    if (!screen || !RB.has(name + '.view')) { RB.toast('You do not have access to that screen.', true); location.hash = '#/'; return; }
    if (!screen.available || !RB.screens[name]) {
      const body = RB.frame(screen.name);
      body.innerHTML = '<div class="card"><p>This screen arrives with <b>module ' + screen.module + '</b>.</p></div>';
      return;
    }
    const body = RB.frame(screen.name);
    try { await RB.screens[name](body, arg); }
    catch (e) { body.innerHTML = '<div class="msg error">' + RB.esc(RB.friendly(e)) + '</div>'; }
  };

  RB.loadScreens = async () => {
    if (!RB.cache.screens) RB.cache.screens = await RB.select('screens', '*', (q) => q.order('sort'));
    return RB.cache.screens;
  };

  RB.showHome = async () => {
    const body = RB.frame('Home', { home: true });
    const p = RB.profile;
    let screens = [];
    try { screens = await RB.loadScreens(); } catch (e) { body.innerHTML = '<div class="msg error">' + RB.esc(e.message) + '</div>'; return; }
    const mine = screens.filter((s) => s.in_menu && RB.has(s.code + '.view'));
    body.innerHTML =
      '<div class="page-head"><h1>Hello, ' + RB.esc(p.full_name.split(' ')[0]) + '</h1>' +
      '<a class="btn" href="#/password">Change my password</a></div>' +
      (p.learning_phase_end && p.learning_phase_end >= RB.today()
        ? '<div class="msg info">You are in your learning phase until <b>' + RB.fmtDate(p.learning_phase_end) + '</b>. Until then a Director or the FC can fully delete your mistakes.</div>' : '') +
      '<nav class="menu">' + mine.map((s) =>
        '<a class="tile ' + (s.available ? '' : 'disabled') + '" href="#/' + s.code + '">' +
        '<span class="ico" aria-hidden="true">' + (ICONS[s.icon] || '•') + '</span>' + RB.esc(s.name) +
        (s.available ? '' : '<span class="soon">Module ' + s.module + '</span>') + '</a>').join('') +
      '</nav>' + (mine.length ? '' : '<p class="muted">No screens are ticked for you yet. Ask a Director or the FC.</p>');
    // Online shop orders waiting (module 10).
    if (RB.shopAlerts) RB.shopAlerts(true);
  };

  // ---------- change password ----------
  RB.showChangePassword = (forced) => {
    const body = forced ? (function () {
      $('#app').innerHTML = '<div class="login-wrap"><img class="wordmark" src="assets/wordmark.png" alt="Ruchi Buds"><div class="login-card" id="pw-card"></div></div>';
      return $('#pw-card');
    })() : RB.frame('Change my password');
    body.innerHTML =
      (forced ? '<h1>Choose a new password</h1><p class="muted">You signed in with a temporary password. Choose your own to continue.</p>' : '<div class="card" style="max-width:420px">') +
      '<form id="pw-form"><div id="pw-msg"></div>' +
      '<div class="field"><label for="pw1">New password</label><input id="pw1" type="password" autocomplete="new-password" minlength="8"></div>' +
      '<div class="field"><label for="pw2">Type it again</label><input id="pw2" type="password" autocomplete="new-password"></div>' +
      '<div class="field hint">At least 8 characters. A short sentence is easy to remember and hard to guess.</div>' +
      '<button class="primary" type="submit">Save new password</button>' +
      (forced ? ' <button type="button" id="pw-out">Sign out</button>' : '') + '</form>' + (forced ? '' : '</div>');
    if (forced) $('#pw-out').addEventListener('click', () => RB.signOut());
    $('#pw-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const a = $('#pw1').value, b = $('#pw2').value, msg = $('#pw-msg');
      if (a.length < 8) { msg.innerHTML = '<div class="msg error">At least 8 characters, please.</div>'; return; }
      if (a !== b) { msg.innerHTML = '<div class="msg error">The two passwords are not the same.</div>'; return; }
      const { error } = await RB.sb.auth.updateUser({ password: a });
      if (error) { msg.innerHTML = '<div class="msg error">' + RB.esc(RB.friendly(error)) + '</div>'; return; }
      try { await RB.rpc('rb_password_changed'); } catch (x) { /* flag clears next time */ }
      RB.profile.must_change_password = false;
      RB.toast('Password changed');
      location.hash = '#/'; RB.route();
    });
  };
})();
