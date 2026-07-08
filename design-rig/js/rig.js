/* ============================================================
   rig.js — tiny harness helper. NO app logic.
   1. Wraps the screen's <main class="screen"> in the shared
      iPhone frame (Dynamic Island, status bar, home indicator).
   2. Renders the screen-switcher nav OUTSIDE the frame.
   3. Expands declarative markers into inline SVG:
        <span class="mon"   data-kind="asanoha|genji|kikkou|maru">
        <span class="enso"  data-level="5" data-size="48">
        <span class="torii" data-kanji="五" data-size="96" data-dashed>
   4. Injects <i class="sumi"> corner marks into .room / .has-sumi.
   ============================================================ */
(function () {
  'use strict';

  var SCREENS = [
    ['home',      'Home'],
    ['session',   'Session'],
    ['summary',   'Summary'],
    ['etude',     'Étude'],
    ['rpg',       'RPG'],
    ['companion', 'Companion']
  ];

  // ---------- status bar glyphs (inline SVG, rig chrome only) ----------
  var SIGNAL_SVG =
    '<svg width="19" height="12" viewBox="0 0 19 12" fill="currentColor">' +
    '<rect x="0"  y="8" width="3" height="4"  rx="1"/>' +
    '<rect x="5"  y="5" width="3" height="7"  rx="1"/>' +
    '<rect x="10" y="2" width="3" height="10" rx="1"/>' +
    '<rect x="15" y="0" width="3" height="12" rx="1"/></svg>';

  var WIFI_SVG =
    '<svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor">' +
    '<path d="M8.5 10.3 L6.6 8.2 a2.9 2.9 0 0 1 3.8 0 Z"/>' +
    '<path d="M8.5 12 L10.9 9.3 a5.4 5.4 0 0 0 -4.8 0 Z" opacity="0"/>' +
    '<path d="M4.8 6.2 a5.6 5.6 0 0 1 7.4 0 L11 7.5 a3.9 3.9 0 0 0 -5 0 Z"/>' +
    '<path d="M2.2 3.3 a9.5 9.5 0 0 1 12.6 0 L13.5 4.7 a7.6 7.6 0 0 0 -10 0 Z"/></svg>';

  var BATTERY_SVG =
    '<svg width="27" height="13" viewBox="0 0 27 13" fill="none">' +
    '<rect x="0.5" y="0.5" width="23" height="12" rx="3.5" stroke="currentColor" opacity="0.4"/>' +
    '<rect x="2" y="2" width="17" height="9" rx="2" fill="currentColor"/>' +
    '<path d="M25 4.5 v4 a2.2 2.2 0 0 0 0-4 Z" fill="currentColor" opacity="0.4"/></svg>';

  // ---------- MonCrest geometry (MonCrest.swift MonCrestShape) ----------
  // viewBox 0 0 28 28, c=(14,14), r = 14*0.92 ≈ 12.9
  function monSVG(kind) {
    var c = 14, r = 12.9, i, a, x, y, pts, s;
    var sw = 1.8; // ≈ size*0.066 at preview scale, scales with viewBox
    var head = '<svg viewBox="0 0 28 28" fill="none" stroke="currentColor" stroke-width="' + sw + '">';
    var body = '';
    if (kind === 'asanoha') {
      body += '<circle cx="14" cy="14" r="' + r + '"/>';
      for (i = 0; i < 6; i++) {
        a = i * Math.PI / 3 - Math.PI / 2;
        x = c + Math.cos(a) * r * 0.88;
        y = c + Math.sin(a) * r * 0.88;
        body += '<line x1="14" y1="14" x2="' + x.toFixed(2) + '" y2="' + y.toFixed(2) + '"/>';
      }
    } else if (kind === 'genji') {
      body += '<circle cx="14" cy="14" r="' + r + '"/>';
      body += '<line x1="14" y1="' + (c - r) + '" x2="14" y2="' + (c + r) + '"/>';
      body += '<line x1="' + (c - r) + '" y1="14" x2="' + (c + r) + '" y2="14"/>';
    } else if (kind === 'kikkou') {
      pts = [];
      for (i = 0; i < 6; i++) {
        a = i * Math.PI / 3;
        pts.push((c + Math.cos(a) * r).toFixed(2) + ',' + (c + Math.sin(a) * r).toFixed(2));
      }
      body += '<polygon points="' + pts.join(' ') + '"/>';
    } else { // maru
      s = r * 0.85;
      body += '<circle cx="14" cy="14" r="' + s.toFixed(2) + '"/>';
    }
    return head + body + '</svg>';
  }

  // ---------- Enso (EnsoRankView.swift EnsoBrushShape + EnsoTailWisp) ----------
  // Bézier control points transcribed from the Swift shape (unit coords ×100).
  function ensoSVG(level, size) {
    var ring = 'M81 19 C90 28 94 42 90 58 C86 78 72 92 52 92 ' +
               'C28 92 10 78 10 56 C10 30 26 12 48 12 C58 12 66 13 72 16';
    var wisp = 'M84 14 Q90 9 92 7';
    var showNum = size >= 40; // numeralThreshold (EnsoRankView.swift:31)
    var gid = 'enso-g-' + Math.random().toString(36).slice(2, 8);
    var html =
      '<svg width="' + size + '" height="' + size + '" viewBox="0 0 100 100" fill="none">' +
      '<defs><linearGradient id="' + gid + '" x1="100%" y1="0%" x2="0%" y2="100%">' +
      '<stop offset="0%" stop-color="currentColor" stop-opacity="0.35"/>' +
      '<stop offset="30%" stop-color="currentColor" stop-opacity="1"/>' +
      '<stop offset="70%" stop-color="currentColor" stop-opacity="1"/>' +
      '<stop offset="100%" stop-color="currentColor" stop-opacity="0"/>' +
      '</linearGradient></defs>' +
      // main brush pass — lineWidth size*0.065 → 6.5 in viewBox units
      '<path d="' + ring + '" stroke="url(#' + gid + ')" stroke-width="6.5" stroke-linecap="round"/>' +
      // thin inner ink-variation pass — 2.0
      '<path d="' + ring + '" stroke="currentColor" stroke-opacity="0.55" stroke-width="2" stroke-linecap="round"/>' +
      // dry-brush tail wisp — 1.8
      '<path d="' + wisp + '" stroke="currentColor" stroke-opacity="0.45" stroke-width="1.8" stroke-linecap="round"/>' +
      '</svg>';
    if (showNum) {
      html += '<span class="enso-num" style="font-size:' + Math.round(size * 0.42) + 'px">' + level + '</span>';
    }
    return html;
  }

  // ---------- Torii (ToriiFrame.swift ToriiShape) ----------
  function toriiSVG(size, dashed) {
    var lw = dashed ? 2.5 : 4;
    var dash = dashed ? ' stroke-dasharray="3 4"' : '';
    // Transcribed proportions ×100 (viewBox 0 0 100 100)
    var d =
      'M12 95 L12 30 M88 95 L88 30 ' +                         // pillars
      'M4 8 Q25 20 50 18 Q75 20 96 8 ' +                        // kasagi with tip sweep
      'M18 32 L82 32';                                          // nuki
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 100 100" fill="none">' +
      '<path d="' + d + '" stroke="currentColor" stroke-width="' + lw + '" stroke-linecap="round" stroke-linejoin="round"' + dash + '/></svg>';
  }

  // ---------- build the frame ----------
  function build() {
    var body = document.body;
    var screenEl = document.querySelector('main.screen');
    if (!screenEl) return;

    var current = body.dataset.screen || '';
    var marble = body.dataset.marble || '5';
    var statusbar = body.dataset.statusbar || 'light';

    // nav (outside the frame)
    var nav = document.createElement('nav');
    nav.className = 'rig-nav';
    var navHTML = '<a href="../index.html">◱ Gallery</a>';
    SCREENS.forEach(function (s) {
      navHTML += '<a href="' + s[0] + '.html"' +
        (s[0] === current ? ' class="active"' : '') + '>' + s[1] + '</a>';
    });
    nav.innerHTML = navHTML;

    // frame
    var stage = document.createElement('div');
    stage.className = 'stage';
    var device = document.createElement('div');
    device.className = 'device';
    var deviceScreen = document.createElement('div');
    deviceScreen.className = 'device-screen marble-' + marble;

    var sb = document.createElement('div');
    sb.className = 'status-bar' + (statusbar === 'hidden' ? ' hidden' : '');
    sb.innerHTML =
      '<span class="sb-time">9:41</span>' +
      '<span class="sb-icons">' + SIGNAL_SVG + WIFI_SVG + BATTERY_SVG + '</span>';

    var island = document.createElement('div');
    island.className = 'dynamic-island';
    var homeIndicator = document.createElement('div');
    homeIndicator.className = 'home-indicator';

    deviceScreen.appendChild(sb);
    deviceScreen.appendChild(screenEl); // move screen content into frame
    deviceScreen.appendChild(island);
    deviceScreen.appendChild(homeIndicator);
    device.appendChild(deviceScreen);
    stage.appendChild(device);

    body.insertBefore(stage, body.firstChild);
    body.insertBefore(nav, stage);
  }

  // ---------- expand declarative components ----------
  function expand() {
    document.querySelectorAll('.mon[data-kind]').forEach(function (el) {
      el.innerHTML = monSVG(el.dataset.kind);
    });
    document.querySelectorAll('.enso[data-level]').forEach(function (el) {
      var size = parseInt(el.dataset.size || '48', 10);
      el.style.width = size + 'px';
      el.style.height = size + 'px';
      if (!el.style.color) el.style.color = 'var(--gold)';
      el.innerHTML = ensoSVG(el.dataset.level, size);
    });
    document.querySelectorAll('.torii[data-kanji]').forEach(function (el) {
      var size = parseInt(el.dataset.size || '96', 10);
      var dashed = el.hasAttribute('data-dashed');
      if (dashed) el.classList.add('torii--dashed');
      el.innerHTML = toriiSVG(size, dashed) +
        '<span class="torii-kanji" style="font-size:' + Math.round(size * 0.40) + 'px">' +
        el.dataset.kanji + '</span>';
    });
    // sumi corner marks
    document.querySelectorAll('.room, .has-sumi, .cta-tatami, .grade-btn').forEach(function (el) {
      if (!el.querySelector(':scope > i.sumi')) {
        var i = document.createElement('i');
        i.className = 'sumi';
        el.appendChild(i);
      }
    });
  }

  build();
  expand();
})();
