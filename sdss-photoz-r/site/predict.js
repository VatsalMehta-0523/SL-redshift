/* =============================================================================
 * predict.js — Photometric-redshift prediction in the browser
 *
 * Re-implements the prediction step of the four models trained in R
 * (R/05_train.R) from the parameters exported by R/08_export_web.R into
 * model.js. No training happens here. tests/testthat/test-web.R checks that
 * these functions reproduce R's predictions for every test galaxy.
 * ===========================================================================*/
(function (root) {
  "use strict";

  /* Colours = differences of magnitudes (same as derive_colours() in R) */
  function colours(m) {
    return { u_g: m.u - m.g, g_r: m.g - m.r, r_i: m.r - m.i, i_z: m.i - m.zmag, r: m.r };
  }

  /* caret preProcess: centre and scale with the training mean and SD */
  function standardise(x, sc) {
    return x.map(function (v, j) { return (v - sc.mean[j]) / sc.std[j]; });
  }

  function sqDist(a, b) {
    var s = 0;
    for (var j = 0; j < a.length; j++) { var d = a[j] - b[j]; s += d * d; }
    return s;
  }

  /* M1 linear regression on standardised features */
  function predictLM(x, m) {
    var s = standardise(x, m.scale);
    var z = m.intercept;
    for (var j = 0; j < s.length; j++) z += m.coef[j] * s[j];
    return z;
  }

  /* M2 k-NN regression: mean redshift of the k nearest training galaxies.
   * Like caret's knnreg, neighbours tied with the k-th distance are included
   * (relative tolerance 1e-4). */
  function predictKNN(x, m) {
    var s = standardise(x, m.scale);
    var d = m.x.map(function (row, i) { return { d: sqDist(row, s), y: m.y[i] }; });
    d.sort(function (a, b) { return a.d - b.d; });
    var kth = d[m.k - 1].d * (1 + 1e-4);
    var sum = 0, n = 0;
    for (var i = 0; i < d.length && d[i].d <= kth; i++) { sum += d[i].y; n++; }
    return sum / n;
  }

  /* M3 random forest: average over trees. In each tree, go left when
   * x[var] <= split; a node with left == 0 is a leaf. Indices are 1-based. */
  function predictRF(x, m) {
    var total = 0;
    for (var t = 0; t < m.trees.length; t++) {
      var tr = m.trees[t], node = 0;
      while (tr.l[node] !== 0) {
        node = (x[tr.v[node] - 1] <= tr.s[node] ? tr.l[node] : tr.r[node]) - 1;
      }
      total += tr.p[node];
    }
    return total / m.trees.length;
  }

  /* M4 support vector regression with an RBF kernel (kernlab ksvm) */
  function predictSVR(x, m) {
    var s = standardise(x, m.scale);
    var xs = s.map(function (v, j) { return (v - m.x_center[j]) / m.x_scale[j]; });
    var f = 0;
    for (var i = 0; i < m.sv.length; i++) f += m.coef[i] * Math.exp(-m.sigma * sqDist(m.sv[i], xs));
    f -= m.b;
    return f * m.y_scale + m.y_center;
  }

  var PREDICTORS = { M1_lm: predictLM, M2_knn: predictKNN, M3_rf: predictRF, M4_svr: predictSVR };

  /* Predict with every model and list the features outside the training range */
  function predictAll(mags, P) {
    var c = colours(mags);
    var x = P.features.map(function (f) { return c[f]; });
    var preds = {};
    Object.keys(PREDICTORS).forEach(function (id) { preds[id] = PREDICTORS[id](x, P.models[id]); });
    var outside = P.features.filter(function (f) {
      return c[f] < P.ranges[f][0] || c[f] > P.ranges[f][1];
    });
    return { colours: c, preds: preds, outside: outside };
  }

  /* ---- Cosmology: flat ΛCDM with H0 = 70 km/s/Mpc, Ωm = 0.3, ΩΛ = 0.7 ----
   * Comoving distance  D_C = (c/H0)  ∫ dz / E(z)
   * Lookback time      t_L = (1/H0)  ∫ dz / ((1+z) E(z)),  E = sqrt(Ωm(1+z)^3 + ΩΛ)
   * Integrated with Simpson's rule (error far below the model uncertainty). */
  var H0 = 70, OM = 0.3, OL = 0.7, C_KMS = 299792.458;
  var HUBBLE_TIME_GYR = 977.792 / H0, MLY_PER_MPC = 3.26156;

  function E(z) { return Math.sqrt(OM * Math.pow(1 + z, 3) + OL); }

  function simpson(f, a, b, n) {
    if (b <= a) return 0;
    var h = (b - a) / n, s = f(a) + f(b);
    for (var i = 1; i < n; i++) s += f(a + i * h) * (i % 2 ? 4 : 2);
    return s * h / 3;
  }

  function cosmology(z) {
    var dc = (C_KMS / H0) * simpson(function (t) { return 1 / E(t); }, 0, z, 200);
    var tl = HUBBLE_TIME_GYR * simpson(function (t) { return 1 / ((1 + t) * E(t)); }, 0, z, 200);
    return {
      comoving_mpc: dc,
      comoving_gly: dc * MLY_PER_MPC / 1000,
      lookback_gyr: tl,
      velocity_kms: C_KMS * z /* Hubble's law v ≈ cz, valid at these low z */
    };
  }

  root.PhotoZ = {
    colours: colours, predictAll: predictAll, cosmology: cosmology,
    predictors: PREDICTORS
  };
})(typeof window !== "undefined" ? window : this);
