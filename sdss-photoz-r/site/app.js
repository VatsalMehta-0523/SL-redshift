/* =============================================================================
 * app.js — UI for Galaxy Redshift Lab
 * Prediction maths lives in predict.js; model parameters in model.js (from R).
 * ===========================================================================*/
(function () {
  "use strict";

  var P = window.PHOTOZ;
  var Z = window.PhotoZ;
  var REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var SVGNS = "http://www.w3.org/2000/svg";

  var BANDS = [
    { key: "u", band: "u", name: "Ultraviolet", lambda: 3551, colour: "var(--u)" },
    { key: "g", band: "g", name: "Green-blue", lambda: 4686, colour: "var(--g)" },
    { key: "r", band: "r", name: "Red", lambda: 6166, colour: "var(--r)" },
    { key: "i", band: "i", name: "Near-infrared", lambda: 7480, colour: "var(--i)" },
    { key: "zmag", band: "z", name: "Infrared", lambda: 8932, colour: "var(--z)" }
  ];
  var BAND_HEX = { u: "#9b7cff", g: "#3fa9f5", r: "#ff8a3d", i: "#e0475a", z: "#a3243f" };
  var MODEL_IDS = ["M1_lm", "M2_knn", "M3_rf", "M4_svr"];
  var MODEL_NAMES = { M1_lm: "Linear", M2_knn: "k-NN", M3_rf: "Random forest", M4_svr: "SVR" };
  var FEATURE_NAMES = { u_g: "u − g", g_r: "g − r", r_i: "r − i", i_z: "i − z", r: "r magnitude" };

  var state = { preset: null, z: 0, shown: { z: 0, lookback: 0, distance: 0, velocity: 0 } };

  var $ = function (id) { return document.getElementById(id); };

  /* ---------------- Star field ---------------- */
  function sky() {
    var c = $("sky"), ctx = c.getContext("2d");
    var dpr = Math.min(window.devicePixelRatio || 1, 2), stars = [];
    function resize() {
      c.width = innerWidth * dpr; c.height = innerHeight * dpr;
      var n = Math.round(innerWidth * innerHeight / 2600);
      stars = [];
      for (var k = 0; k < n; k++) {
        stars.push({ x: Math.random() * c.width, y: Math.random() * c.height,
          r: (Math.random() < 0.92 ? Math.random() * 0.9 + 0.2 : Math.random() * 1.6 + 0.9) * dpr,
          a: Math.random() * 0.6 + 0.25, t: Math.random() * Math.PI * 2, s: Math.random() * 0.8 + 0.2 });
      }
    }
    function draw(time) {
      ctx.clearRect(0, 0, c.width, c.height);
      for (var k = 0; k < stars.length; k++) {
        var st = stars[k];
        var a = REDUCED ? st.a : st.a * (0.65 + 0.35 * Math.sin(st.t + time * 0.0008 * st.s));
        ctx.globalAlpha = a;
        ctx.fillStyle = st.r > 1.4 * dpr ? "#fff4dc" : "#dfe6ff";
        ctx.beginPath(); ctx.arc(st.x, st.y, st.r, 0, 6.2832); ctx.fill();
      }
      if (!REDUCED) requestAnimationFrame(draw);
    }
    resize(); addEventListener("resize", function () { resize(); if (REDUCED) draw(0); });
    requestAnimationFrame(draw);
  }

  /* ---------------- Inputs ---------------- */
  function buildInputs() {
    var host = $("mag-inputs");
    BANDS.forEach(function (b) {
      var row = document.createElement("div");
      row.className = "mag";
      row.style.setProperty("--band", b.colour);
      row.innerHTML =
        '<span class="chip" aria-hidden="true">' + b.band + "</span>" +
        '<label for="mag-' + b.key + '"><span>' + b.band + " magnitude</span>" +
        "<span>" + b.name + " · " + b.lambda + " Å</span></label>" +
        '<input id="mag-' + b.key + '" type="number" step="0.001" min="10" max="30" inputmode="decimal" required>';
      host.appendChild(row);
    });
    host.addEventListener("input", function () {
      if (state.preset) { state.preset = null; setSource(); }
    });
  }

  function readMags() {
    var mags = {}, bad = [];
    BANDS.forEach(function (b) {
      var el = $("mag-" + b.key), v = parseFloat(el.value);
      var ok = isFinite(v) && v >= 10 && v <= 30;
      el.setAttribute("aria-invalid", ok ? "false" : "true");
      if (!ok) bad.push(b.band);
      mags[b.key] = v;
    });
    return { mags: mags, bad: bad };
  }

  function fillMags(g) {
    BANDS.forEach(function (b) {
      var el = $("mag-" + b.key);
      el.value = (+g[b.key]).toFixed(3);
      el.setAttribute("aria-invalid", "false");
    });
  }

  function setSource() {
    var note = $("source-note");
    if (state.preset) {
      note.innerHTML = "Real SDSS galaxy <b>" + state.preset.objid + "</b> from the held-out test set (the models never saw it).";
    } else {
      note.textContent = "Custom values.";
    }
  }

  /* ---------------- Number animation ---------------- */
  function ease(t) { return 1 - Math.pow(1 - t, 3); }

  function tween(from, to, ms, step, done) {
    if (REDUCED || ms <= 0) { step(to); if (done) done(); return; }
    var t0 = performance.now();
    function frame(now) {
      var t = Math.min(1, (now - t0) / ms);
      step(from + (to - from) * ease(t));
      if (t < 1) requestAnimationFrame(frame); else if (done) done();
    }
    requestAnimationFrame(frame);
  }

  function animateNumber(id, key, to, fmt) {
    var from = state.shown[key];
    tween(from, to, 900, function (v) { $(id).textContent = fmt(v); });
    state.shown[key] = to;
  }

  var fmt4 = function (v) { return v.toFixed(4); };
  var fmt2 = function (v) { return v.toFixed(2); };
  var fmtVel = function (v) { return (Math.round(v / 100) * 100).toLocaleString("en-US"); };

  /* ---------------- Prediction ---------------- */
  function run(animate) {
    var read = readMags(), err = $("form-error");
    if (read.bad.length) {
      err.hidden = false;
      err.textContent = "Enter a magnitude between 10 and 30 for: " + read.bad.join(", ") + ".";
      return;
    }
    err.hidden = true;

    // Typed-in values that match a held-out SDSS galaxy still show its true z
    if (!state.preset) {
      state.preset = P.presets.find(function (g) {
        return BANDS.every(function (b) { return Math.abs(g[b.key] - read.mags[b.key]) < 0.0006; });
      }) || null;
      setSource();
    }

    var res = Z.predictAll(read.mags, P);
    var z = res.preds[P.recommended];
    var cosmo = Z.cosmology(Math.max(z, 0));

    var zEl = $("z-value");
    animateNumber("z-value", "z", z, fmt4);
    zEl.classList.remove("pulse"); void zEl.offsetWidth; zEl.classList.add("pulse");
    animateNumber("lookback", "lookback", cosmo.lookback_gyr, fmt2);
    animateNumber("distance", "distance", cosmo.comoving_gly, fmt2);
    animateNumber("velocity", "velocity", cosmo.velocity_kms, fmtVel);

    renderTruth(z);
    renderValidity(res);
    renderModels(res);
    animateSpectrum(state.z, z, animate);
    renderContext(res, z);
    state.z = z;
  }

  function renderTruth(z) {
    var box = $("truth");
    var g = state.preset;
    if (!g) { box.hidden = true; return; }
    var dz = (z - g.z_spec) / (1 + g.z_spec);
    box.hidden = false;
    box.innerHTML = "SDSS spectrum says <b>z = " + g.z_spec.toFixed(4) + "</b>" +
      "<span>error Δz/(1+z) = <b>" + (dz >= 0 ? "+" : "") + dz.toFixed(4) + "</b></span>";
  }

  function renderValidity(res) {
    var box = $("validity");
    var negatives = MODEL_IDS.filter(function (id) { return res.preds[id] < 0; });
    if (!res.outside.length) {
      box.className = "validity ok";
      box.innerHTML = "<strong>Inside the training range.</strong> Every colour and the r magnitude lie within the 80 galaxies the models learned from.";
      return;
    }
    var names = res.outside.map(function (f) { return FEATURE_NAMES[f]; }).join(", ");
    box.className = "validity warn";
    box.innerHTML = "<strong>Outside the training range: " + names + ".</strong> The models are extrapolating, so read the result with caution." +
      (negatives.length ? " " + negatives.map(function (id) { return MODEL_NAMES[id]; }).join(" and ") +
        " even predict an impossible negative redshift." : "");
  }

  /* ---------------- Models ---------------- */
  var metricsById = {};
  (P.metrics || []).forEach(function (m) { metricsById[m.model] = m; });

  function buildModelRows() {
    var host = $("model-rows");
    MODEL_IDS.forEach(function (id) {
      var row = document.createElement("div");
      row.className = "model-row" + (id === P.recommended ? " recommended" : "");
      row.id = "row-" + id;
      row.style.setProperty("--c", P.colours[id]);
      var m = metricsById[id];
      row.innerHTML = '<div class="name">' + MODEL_NAMES[id] +
        "<small>error ±" + (m ? m.rmse.toFixed(3) : "—") + "</small></div>" +
        '<div class="track"><div class="bar"></div><div class="dot"></div></div>' +
        '<div class="val">—</div>';
      host.appendChild(row);
    });
    var axis = document.createElement("div");
    axis.className = "axis-note"; axis.id = "model-axis";
    host.appendChild(axis);
  }

  function renderModels(res) {
    var vals = MODEL_IDS.map(function (id) { return res.preds[id]; });
    var lo = Math.min(0, Math.min.apply(null, vals) - 0.01), hi = Math.max(0.25, Math.max.apply(null, vals) + 0.01);
    MODEL_IDS.forEach(function (id) {
      var v = res.preds[id], row = $("row-" + id);
      var pct = ((v - lo) / (hi - lo)) * 100;
      row.querySelector(".dot").style.left = pct + "%";
      row.querySelector(".bar").style.width = pct + "%";
      row.querySelector(".val").textContent = v.toFixed(4);
      row.classList.toggle("bad", v < 0);
    });
    $("model-axis").innerHTML = "<span>z = " + lo.toFixed(2) + "</span><span>z = " + hi.toFixed(2) + "</span>";
  }

  /* ---------------- Spectrum strip ---------------- */
  var SPEC = { w: 1000, h: 320, l: 46, r: 18, t: 58, b: 46, lmin: 3000, lmax: 10000 };
  var LINES = [ // absorption features of an old stellar population (rest Å)
    { c: 3934, d: 0.20, s: 11 }, { c: 3969, d: 0.17, s: 11 }, { c: 4304, d: 0.08, s: 14 },
    { c: 4861, d: 0.04, s: 12 }, { c: 5175, d: 0.11, s: 16 }, { c: 5270, d: 0.05, s: 14 },
    { c: 5893, d: 0.08, s: 13 }, { c: 6563, d: 0.04, s: 12 }
  ];

  function restFlux(l) { // schematic early-type galaxy spectrum, arbitrary units
    var step = 1 / (1 + Math.exp(-(l - 4000) / 28));
    var f = 0.40 + 0.06 * (l - 3000) / 1000 + 0.55 * step + 0.18 * Math.min(1, Math.max(0, (l - 4000) / 3000));
    for (var k = 0; k < LINES.length; k++) {
      var ln = LINES[k], u = (l - ln.c) / ln.s;
      f -= ln.d * Math.exp(-0.5 * u * u);
    }
    return f;
  }

  function sx(l) { return SPEC.l + (l - SPEC.lmin) / (SPEC.lmax - SPEC.lmin) * (SPEC.w - SPEC.l - SPEC.r); }
  function sy(f) { return SPEC.h - SPEC.b - (f / 1.35) * (SPEC.h - SPEC.t - SPEC.b); }

  function el(name, attrs, parent) {
    var n = document.createElementNS(SVGNS, name);
    for (var k in attrs) n.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(n);
    return n;
  }

  var specParts = {};
  function buildSpectrum() {
    var svg = $("spectrum-svg");
    var defs = el("defs", {}, svg);
    var grad = el("linearGradient", { id: "fluxfill", x1: 0, y1: 0, x2: 0, y2: 1 }, defs);
    el("stop", { offset: "0%", "stop-color": "#f2ecdf", "stop-opacity": 0.22 }, grad);
    el("stop", { offset: "100%", "stop-color": "#f2ecdf", "stop-opacity": 0 }, grad);
    var glow = el("filter", { id: "glow", x: "-50%", y: "-50%", width: "200%", height: "200%" }, defs);
    el("feGaussianBlur", { stdDeviation: 4, result: "b" }, glow);
    var merge = el("feMerge", {}, glow);
    el("feMergeNode", { in: "b" }, merge); el("feMergeNode", { in: "SourceGraphic" }, merge);

    // filter bands
    P.filters.forEach(function (f) {
      var x0 = sx(f.lambda - f.fwhm / 2), x1 = sx(f.lambda + f.fwhm / 2);
      el("rect", { x: x0, y: SPEC.t - 14, width: x1 - x0, height: SPEC.h - SPEC.t - SPEC.b + 14,
        fill: BAND_HEX[f.band], "fill-opacity": 0.13, rx: 6 }, svg);
      el("rect", { x: x0, y: SPEC.t - 14, width: x1 - x0, height: 3, fill: BAND_HEX[f.band], rx: 1.5 }, svg);
      var t = el("text", { x: (x0 + x1) / 2, y: SPEC.t - 24, "text-anchor": "middle",
        fill: BAND_HEX[f.band], "font-family": "Instrument Serif, serif", "font-style": "italic", "font-size": 26, class: "band-label" }, svg);
      t.textContent = f.band;
    });

    // axis
    var axisY = SPEC.h - SPEC.b;
    el("line", { x1: SPEC.l, x2: SPEC.w - SPEC.r, y1: axisY, y2: axisY, stroke: "rgba(242,236,223,.25)" }, svg);
    for (var l = 3000; l <= 10000; l += 1000) {
      el("line", { x1: sx(l), x2: sx(l), y1: axisY, y2: axisY + 5, stroke: "rgba(242,236,223,.35)" }, svg);
      var tx = el("text", { x: sx(l), y: axisY + 20, "text-anchor": "middle", fill: "#6f7790",
        "font-family": "JetBrains Mono, monospace", "font-size": 11 }, svg);
      tx.textContent = l;
    }
    var lab = el("text", { x: SPEC.w - SPEC.r, y: axisY + 38, "text-anchor": "end", fill: "#a7adbd",
      "font-family": "JetBrains Mono, monospace", "font-size": 11 }, svg);
    lab.textContent = "wavelength (Å)";
    var fl = el("text", { x: SPEC.l, y: axisY + 38, fill: "#6f7790",
      "font-family": "JetBrains Mono, monospace", "font-size": 11 }, svg);
    fl.textContent = "schematic spectrum";

    specParts.area = el("path", { fill: "url(#fluxfill)" }, svg);
    specParts.line = el("path", { fill: "none", stroke: "#f2ecdf", "stroke-width": 2, "stroke-linejoin": "round" }, svg);

    // rest-frame break (ghost) and observed break
    specParts.rest = el("line", { x1: sx(4000), x2: sx(4000), y1: SPEC.t, y2: axisY,
      stroke: "rgba(242,236,223,.45)", "stroke-dasharray": "4 5" }, svg);
    var rt = el("text", { x: sx(4000) + 6, y: axisY - 8, "text-anchor": "start", fill: "#a7adbd",
      "font-family": "JetBrains Mono, monospace", "font-size": 11 }, svg);
    rt.textContent = "at rest 4000 Å";
    specParts.arrow = el("line", { y1: sy(1.22), y2: sy(1.22), stroke: "#ffb347", "stroke-width": 1.5,
      "marker-end": "url(#arrowhead)" }, svg);
    var mk = el("marker", { id: "arrowhead", viewBox: "0 0 10 10", refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: "auto" }, defs);
    el("path", { d: "M0,0 L10,5 L0,10 z", fill: "#ffb347" }, mk);
    specParts.obs = el("line", { y1: SPEC.t - 4, y2: axisY, stroke: "#ffb347", "stroke-width": 2.5, filter: "url(#glow)" }, svg);
    specParts.obsText = el("text", { y: SPEC.t + 34, fill: "#ffb347",
      "font-family": "JetBrains Mono, monospace", "font-size": 12, "font-weight": 600 }, svg);
  }

  function drawSpectrum(z) {
    var pts = [], n = 420;
    for (var k = 0; k <= n; k++) {
      var l = SPEC.lmin + (SPEC.lmax - SPEC.lmin) * k / n;
      pts.push([sx(l), sy(restFlux(l / (1 + z)))]);
    }
    var d = "M" + pts.map(function (p) { return p[0].toFixed(1) + "," + p[1].toFixed(1); }).join("L");
    specParts.line.setAttribute("d", d);
    specParts.area.setAttribute("d", d + "L" + sx(SPEC.lmax) + "," + sy(0) + "L" + sx(SPEC.lmin) + "," + sy(0) + "z");

    var lb = P.break_rest * (1 + Math.max(z, 0)), x = sx(lb);
    specParts.obs.setAttribute("x1", x); specParts.obs.setAttribute("x2", x);
    specParts.arrow.setAttribute("x1", sx(4000) + 2);
    specParts.arrow.setAttribute("x2", Math.max(sx(4000) + 3, x - 4));
    specParts.arrow.style.opacity = x - sx(4000) > 12 ? 1 : 0;
    specParts.obsText.setAttribute("x", x + 8);
    specParts.obsText.textContent = "observed " + Math.round(lb) + " Å";
    var inG = lb >= 4686 - 1379 / 2 && lb <= 4686 + 1379 / 2;
    $("break-tag").textContent = "break at " + Math.round(lb) + " Å · " + (inG ? "inside g" : "outside g");
  }

  function animateSpectrum(from, to, animate) {
    tween(from, to, animate ? 1100 : 0, drawSpectrum);
  }

  /* ---------------- Context scatter ---------------- */
  function renderContext(res, z) {
    var svg = $("context-svg");
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    var W = 520, H = 330, L = 52, R = 16, T = 16, B = 46;
    var gr = res.colours.g_r;
    var zs = P.train_points.map(function (p) { return p.redshift; });
    var ys = P.train_points.map(function (p) { return p.g_r; });
    var zlo = Math.min(0, z - 0.01, Math.min.apply(null, zs)), zhi = Math.max(0.25, z + 0.01);
    var ylo = Math.min(0.3, gr - 0.05), yhi = Math.max(1.4, gr + 0.05);
    var X = function (v) { return L + (v - zlo) / (zhi - zlo) * (W - L - R); };
    var Y = function (v) { return H - B - (v - ylo) / (yhi - ylo) * (H - T - B); };

    if (zlo < 0) {
      el("rect", { x: X(zlo), y: T, width: X(0) - X(zlo), height: H - T - B, fill: "rgba(255,122,89,.10)" }, svg);
      var nt = el("text", { x: X(zlo) + 6, y: T + 14, fill: "#ff7a59", "font-family": "JetBrains Mono, monospace", "font-size": 10 }, svg);
      nt.textContent = "z < 0";
    }
    // grid + ticks
    for (var zt = 0; zt <= zhi + 1e-9; zt += 0.05) {
      el("line", { x1: X(zt), x2: X(zt), y1: T, y2: H - B, stroke: "rgba(242,236,223,.06)" }, svg);
      var t1 = el("text", { x: X(zt), y: H - B + 18, "text-anchor": "middle", fill: "#6f7790", "font-family": "JetBrains Mono, monospace", "font-size": 10 }, svg);
      t1.textContent = zt.toFixed(2);
    }
    for (var yt = Math.ceil(ylo * 5) / 5; yt <= yhi + 1e-9; yt += 0.2) {
      el("line", { x1: L, x2: W - R, y1: Y(yt), y2: Y(yt), stroke: "rgba(242,236,223,.06)" }, svg);
      var t2 = el("text", { x: L - 8, y: Y(yt) + 3, "text-anchor": "end", fill: "#6f7790", "font-family": "JetBrains Mono, monospace", "font-size": 10 }, svg);
      t2.textContent = yt.toFixed(1);
    }
    var xl = el("text", { x: W - R, y: H - 8, "text-anchor": "end", fill: "#a7adbd", "font-family": "JetBrains Mono, monospace", "font-size": 11 }, svg);
    xl.textContent = "redshift z";
    var yl = el("text", { x: 12, y: T + 4, fill: "#a7adbd", "font-family": "JetBrains Mono, monospace", "font-size": 11,
      transform: "rotate(-90 12 " + (T + 4) + ")", "text-anchor": "end" }, svg);
    yl.textContent = "colour g − r";

    P.train_points.forEach(function (p) {
      el("circle", { cx: X(p.redshift), cy: Y(p.g_r), r: 3.2, fill: "#f2ecdf", "fill-opacity": 0.38 }, svg);
    });
    el("line", { x1: L, x2: W - R, y1: Y(gr), y2: Y(gr), stroke: "#ffb347", "stroke-opacity": 0.45, "stroke-dasharray": "3 5" }, svg);
    if (state.preset) {
      el("circle", { cx: X(state.preset.z_spec), cy: Y(gr), r: 8, fill: "none", stroke: "#7fd4ff", "stroke-width": 2 }, svg);
    }
    el("circle", { cx: X(z), cy: Y(gr), r: 11, fill: "#ffb347", "fill-opacity": 0.18 }, svg);
    el("circle", { cx: X(z), cy: Y(gr), r: 5.5, fill: "#ffb347" }, svg);

    var key = el("text", { x: W - R, y: T + 12, "text-anchor": "end", fill: "#a7adbd", "font-family": "Figtree, sans-serif", "font-size": 11 }, svg);
    key.innerHTML = '<tspan fill="#ffb347">●</tspan> this galaxy (predicted)' +
      (state.preset ? '   <tspan fill="#7fd4ff">○</tspan> measured' : "") +
      '   <tspan fill="#f2ecdf" fill-opacity=".6">●</tspan> training';
  }

  /* ---------------- Wiring ---------------- */
  function pickPreset(exclude) {
    var list = P.presets.filter(function (g) { return !exclude || g.objid !== exclude.objid; });
    return list[Math.floor(Math.random() * list.length)];
  }

  function init() {
    sky();
    buildInputs();
    buildModelRows();
    buildSpectrum();
    $("ntrain-tag").textContent = P.n_train + " galaxies";
    $("build-info").textContent = "Models exported from R on " + P.generated + " · trained on " + P.n_train + " SDSS galaxies";

    // Start with a real, typical test galaxy (median redshift of the test set)
    state.preset = P.presets[Math.floor(P.presets.length / 2)];
    fillMags(state.preset);
    setSource();
    drawSpectrum(0);
    setTimeout(function () { run(true); }, REDUCED ? 0 : 450);

    $("mag-form").addEventListener("submit", function (e) { e.preventDefault(); run(true); });
    $("random-btn").addEventListener("click", function () {
      state.preset = pickPreset(state.preset);
      fillMags(state.preset);
      setSource();
      run(true);
    });
  }

  if (!P || !Z) {
    document.body.insertAdjacentHTML("afterbegin", '<p style="color:#ff7a59;padding:16px">Model files failed to load.</p>');
    return;
  }
  init();
})();
