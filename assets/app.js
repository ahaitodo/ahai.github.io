/* lyej.cn 渲染逻辑 —— 无依赖，数据源 data/products.json（管线自动更新） */
(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }
  function safeLink(href) {
    return typeof href === "string" && href.indexOf("https://") === 0 ? href : "";
  }
  function fmtSales(n) {
    n = Number(n) || 0;
    if (n >= 10000) return (n / 10000).toFixed(1).replace(/\.0$/, "") + "万+";
    if (n >= 100) return Math.round(n / 100) * 100 + "+";
    return n > 0 ? String(n) : "";
  }
  function fmtPrice(n) {
    var v = Number(n) || 0;
    return v % 1 === 0 ? String(v) : v.toFixed(v * 100 % 10 === 0 ? 1 : 2);
  }

  var FALLBACK_HOME = "https://u.jd.com/360lRmW";
  var DATA = null;

  /* ---------- countdown ---------- */
  var T_START = new Date("2026-11-11T00:00:00+08:00");
  var T_END = new Date("2026-11-12T00:00:00+08:00");
  var T_OFF = new Date("2026-11-13T00:00:00+08:00");
  function tick() {
    var cd = $("countdown");
    if (!cd) return;
    var now = Date.now();
    var target, label;
    if (now < T_START.getTime()) { target = T_START; label = "距11.11"; }
    else if (now < T_END.getTime()) { target = T_END; label = "巅峰24h"; }
    else if (now < T_OFF.getTime()) { target = T_OFF; label = "返场截止"; }
    else { cd.style.display = "none"; return; }
    var s = Math.max(0, Math.floor((target.getTime() - now) / 1000));
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
    $("cd-d").textContent = d;
    $("cd-h").textContent = h < 10 ? "0" + h : h;
    $("cd-m").textContent = m < 10 ? "0" + m : m;
    $("cd-s").textContent = sec < 10 ? "0" + sec : sec;
    var lb = cd.querySelector(".cd-label");
    if (lb) lb.textContent = label;
  }
  setInterval(tick, 1000); tick();

  /* ---------- product card ---------- */
  var IMG_FALLBACK = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" fill="#f4f5f7"/><path fill="#d5d8de" d="M12 5a7 7 0 0 0-7 7v5a2.5 2.5 0 0 0 2.5 2.5H9a1.5 1.5 0 0 0 1.5-1.5v-3A1.5 1.5 0 0 0 9 13.5H7.2A4.9 4.9 0 0 1 16.8 13.5H15a1.5 1.5 0 0 0-1.5 1.5v3A1.5 1.5 0 0 0 15 19.5h1.5A2.5 2.5 0 0 0 19 17v-5a7 7 0 0 0-7-7z"/></svg>'
  );

  function productCard(p) {
    var card = el("div", "card");
    var imgBox = el("div", "card-img");
    var img = el("img");
    img.loading = "lazy"; img.decoding = "async"; img.alt = p.shortName || p.name || "蓝牙耳机";
    img.src = safeLink(p.image) || IMG_FALLBACK;
    img.onerror = function () { img.onerror = null; img.src = IMG_FALLBACK; };
    imgBox.appendChild(img);
    if (p.selfRun) { var b = el("span", "card-badge gold", "自营"); imgBox.appendChild(b); }
    else if ((Number(p.sales30d) || 0) >= 20000) { imgBox.appendChild(el("span", "card-badge", "爆款")); }
    card.appendChild(imgBox);

    var body = el("div", "card-body");
    body.appendChild(el("div", "card-name", p.shortName || p.name));

    var meta = el("div", "card-meta");
    if (p.brand) meta.appendChild(el("span", "", p.brand));
    if (p.goodRate > 0) meta.appendChild(el("span", "", "好评 " + Math.round(p.goodRate) + "%"));
    var s = fmtSales(p.sales30d);
    if (s) meta.appendChild(el("span", "", "月销 " + s));
    body.appendChild(meta);

    if (Number(p.couponCut) > 0) {
      body.appendChild(el("span", "coupon-pill", "领券减" + fmtPrice(p.couponCut)));
    }

    var row = el("div", "price-row");
    var pr = el("span", "price", fmtPrice(p.priceAfter));
    pr.title = "到手价（以京东页面实时价为准）";
    row.appendChild(pr);
    if (Number(p.price) > Number(p.priceAfter) * 1.02) {
      row.appendChild(el("span", "price-old", "¥" + fmtPrice(p.price)));
    }
    body.appendChild(row);

    var link = safeLink(p.link);
    if (link) {
      var a = el("a", "card-cta", "去京东抢购");
      a.href = link; a.target = "_blank"; a.rel = "nofollow sponsored noopener";
      body.appendChild(a);
    } else {
      var btn = el("button", "card-cta alt", "复制名称 · 去京东搜");
      btn.type = "button";
      btn.addEventListener("click", function () {
        var name = p.name || "";
        var done = function () {
          btn.textContent = "已复制 ✓ 打开京东粘贴";
          setTimeout(function () { btn.textContent = "复制名称 · 去京东搜"; }, 2200);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(name).then(done, function () { done(); });
        } else { done(); }
        setTimeout(function () { window.open(FALLBACK_HOME, "_blank", "noopener"); }, 350);
      });
      body.appendChild(btn);
    }
    card.appendChild(body);
    return card;
  }

  /* ---------- render ---------- */
  function renderBands(data) {
    var wrapEl = $("band-sections");
    var nav = $("band-nav");
    wrapEl.textContent = ""; nav.textContent = "";
    var shown = 0;
    (data.bands || []).forEach(function (band) {
      var skus = band.skus || [];
      if (!skus.length) return;
      var block = el("div", "band-block");
      block.id = "band-" + band.id;
      var t = el("div", "band-title");
      var h3 = el("h3", "", band.label);
      t.appendChild(h3);
      t.appendChild(el("span", "", skus.length + " 款 · 到手价 " + band.min + "-" + (band.max > 9999 ? "∞" : band.max) + " 元"));
      block.appendChild(t);
      var grid = el("div", "grid");
      skus.forEach(function (sid) {
        var p = (data.products || []).filter(function (x) { return x.skuId === sid; })[0];
        if (p) { grid.appendChild(productCard(p)); shown++; }
      });
      block.appendChild(grid);
      wrapEl.appendChild(block);

      var a = el("a", "", band.label);
      a.href = "#band-" + band.id;
      nav.appendChild(a);
    });
    if (!shown) {
      var empty = el("div", "empty");
      empty.innerHTML = "首批榜单正在从京东同步，今天先去 <b>领券中心</b> 蹲券吧 ↑";
      wrapEl.appendChild(empty);
    }
  }

  function renderScenes(data) {
    var chips = $("scene-chips"), grid = $("scene-grid"), empty = $("scene-empty");
    chips.textContent = ""; grid.textContent = "";
    var map = {};
    (data.products || []).forEach(function (p) {
      (p.scenes || []).forEach(function (s) { (map[s] = map[s] || []).push(p); });
    });
    var keys = Object.keys(map).sort(function (a, b) { return map[b].length - map[a].length; }).slice(0, 8);
    keys.forEach(function (k) {
      var c = el("button", "chip", k);
      c.type = "button";
      c.addEventListener("click", function () {
        var on = c.classList.contains("on");
        Array.prototype.forEach.call(chips.children, function (x) { x.classList.remove("on"); });
        if (on) { grid.textContent = ""; empty.classList.add("hidden"); return; }
        c.classList.add("on");
        grid.textContent = "";
        map[k].slice(0, 10).forEach(function (p) { grid.appendChild(productCard(p)); });
        empty.classList.toggle("hidden", map[k].length > 0);
        grid.scrollIntoView({ behavior: "smooth", block: "nearest" });
      });
      chips.appendChild(c);
    });
  }

  function renderBundles(data) {
    var g = $("bundle-grid");
    g.textContent = "";
    (data.bundles || []).forEach(function (b) {
      var card = el("div", "bcard");
      var imgBox = el("div", "card-img");
      var img = el("img");
      img.loading = "lazy"; img.alt = b.name || "凑单品";
      img.src = safeLink(b.image) || IMG_FALLBACK;
      img.onerror = function () { img.onerror = null; img.src = IMG_FALLBACK; };
      imgBox.appendChild(img);
      card.appendChild(imgBox);
      card.appendChild(el("div", "bcard-name", b.name));
      var pr = el("div", "bcard-price");
      pr.appendChild(el("span", "price", fmtPrice(b.price)));
      var s = fmtSales(b.sales30d);
      if (s) pr.appendChild(el("span", "price-old", "月销" + s));
      card.appendChild(pr);
      var link = safeLink(b.link) || FALLBACK_HOME;
      var a = el("a", "card-cta", "加入凑单");
      a.href = link; a.target = "_blank"; a.rel = "nofollow sponsored noopener";
      card.appendChild(a);
      g.appendChild(card);
    });
  }

  function renderStrip(data) {
    var st = $("strip"), tx = $("strip-text");
    if (!st || !tx) return;
    var n = (data.products || []).length;
    var linked = (data.products || []).filter(function (p) { return safeLink(p.link); }).length;
    var linkedNote = linked > 0 ? "，" + linked + " 款已挂京东推广链接" : "";
    tx.textContent = "榜单更新于 " + data.updatedAt + " · 在榜 " + n + " 款" + linkedNote + " · 到手价以京东页面为准";
  }

  function renderCTA(data) {
    var map = { hongbao1: "hb-1", hongbao2: "hb-2", hongbao3: "hb-3", search: "cta-search", coupon: "cta-coupon" };
    var set = 0;
    Object.keys(map).forEach(function (id) {
      var act = null;
      (data.activities || []).forEach(function (a) { if (a.id === id) act = a; });
      var node = $(map[id]);
      if (!node) return;
      var l = act ? safeLink(act.link) : "";
      if (l) { node.href = l; node.style.display = ""; set++; }
      else { node.style.display = "none"; }
    });
    var hbBlock = $("hero-hb");
    if (hbBlock) hbBlock.style.display = set >= 1 ? "" : "none";
  }

  fetch("data/products.json?_=" + Date.now(), { cache: "no-store" })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (data) {
      DATA = data;
      renderCTA(data);
      renderStrip(data);
      renderBands(data);
      renderScenes(data);
      renderBundles(data);
    })
    .catch(function () {
      var st = $("strip");
      if (st) { st.classList.add("error"); $("strip-text").textContent = "榜单数据加载失败，可直接点上方按钮领券逛京东双11"; }
      var sk = $("skeleton"); if (sk) sk.textContent = "";
    });
})();
