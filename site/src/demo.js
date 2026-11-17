// The —tuck demo. Mirrors the app: pointer actions animate, keyboard actions
// are instant, hover and arrow keys share one selection.
(() => {
  "use strict";

  const svg = (body) =>
    `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

  const GLYPHS = {
    wifi: svg('<path d="M2 6.2a8.5 8.5 0 0 1 12 0"/><path d="M4.2 8.6a5.3 5.3 0 0 1 7.6 0"/><circle cx="8" cy="11.6" r="1" fill="currentColor" stroke="none"/>'),
    search: svg('<circle cx="7" cy="7" r="4.2"/><path d="M10.2 10.2 13.5 13.5"/>'),
    battery: svg('<rect x="1.5" y="4.5" width="11.5" height="7" rx="2"/><rect x="3" y="6" width="6" height="4" rx="1" fill="currentColor" stroke="none"/><path d="M14.5 7v2"/>'),
    ellipsis: svg('<circle cx="3.5" cy="8" r="1.1" fill="currentColor" stroke="none"/><circle cx="8" cy="8" r="1.1" fill="currentColor" stroke="none"/><circle cx="12.5" cy="8" r="1.1" fill="currentColor" stroke="none"/>'),
    check: svg('<path d="M3.5 8.5 6.5 11.5 12.5 4.5"/>'),
    clipboard: svg('<rect x="3.5" y="3" width="9" height="11" rx="1.5"/><path d="M6 3V2h4v1"/><path d="M6 7h4M6 9.5h4"/>'),
    camera: svg('<rect x="2" y="4.5" width="12" height="8.5" rx="1.8"/><circle cx="8" cy="8.7" r="2.3"/><path d="M5.5 4.5 6.5 3h3l1 1.5"/>'),
    timer: svg('<circle cx="8" cy="9" r="5"/><path d="M8 9V6.5M6.5 2h3"/>'),
    cloud: svg('<path d="M4.5 12.5h7a3 3 0 0 0 .2-6A4 4 0 0 0 4 7.2a2.7 2.7 0 0 0 .5 5.3Z"/>'),
    note: svg('<path d="M6 12V3.5l7-1.5V10"/><circle cx="4.5" cy="12" r="1.6"/><circle cx="11.5" cy="10" r="1.6"/>'),
    shield: svg('<path d="M8 1.8 13 3.6v4c0 3-2.2 5.3-5 6.6-2.8-1.3-5-3.6-5-6.6v-4Z"/>'),
  };

  const sep = { sep: true };
  const label = (title) => ({ title, label: true });
  const entry = (title, submenu) => ({ title, submenu });

  // Generic stand-ins for real menu extras. The notch hides them on a real Mac.
  const ITEMS = [
    { title: "Clipboard", glyph: "clipboard", tile: "#6b6b70", menu: [label("Recent"), entry("Meeting notes draft"), entry("tuck.ulasalyesil.com"), sep, entry("Clear History"), entry("Settings…")] },
    { title: "Cloud Sync", glyph: "cloud", tile: "#3a7bd5", menu: [label("Synced 2 min ago"), entry("Sync Now"), entry("Pause Syncing"), sep, entry("Open Folder")] },
    { title: "Music", glyph: "note", tile: "#e0475b", menu: [entry("Play"), entry("Next Track"), sep, entry("Volume", [entry("Mute"), entry("50%"), entry("100%")])] },
    { title: "Screenshot", glyph: "camera", tile: "#7a5af5", menu: null },
    { title: "Timer", glyph: "timer", tile: "#e8833a", menu: [entry("Start Focus · 25:00"), entry("Start Break · 5:00"), sep, entry("Presets", [entry("15 minutes"), entry("45 minutes"), entry("90 minutes")]), sep, entry("Quit Timer")] },
    { title: "VPN", glyph: "shield", tile: "#2f9e6e", menu: [entry("Connect"), entry("Locations", [entry("Frankfurt"), entry("Istanbul"), entry("Lisbon")]), sep, entry("Quit VPN")] },
  ];

  const $ = (s) => document.querySelector(s);
  const screen = $(".screen");
  const bar = $(".bar");
  const toggle = $(".toggle");
  const panel = $("#panel");
  const readout = $(".readout output");
  const segmented = document.querySelectorAll(".segmented button");

  document.querySelectorAll("[data-glyph]").forEach((el) => { el.innerHTML = GLYPHS[el.dataset.glyph] || ""; });

  const state = { open: false, stack: [], sel: null, arranging: false, generation: 0 };

  // ---- Rows ----

  const currentRows = () => {
    const level = state.stack.at(-1);
    if (!level) return ITEMS.map((item) => ({ kind: "item", item, selectable: true, title: item.title }));
    return level.entries.map((e) => e.sep ? { kind: "sep" }
      : e.label ? { kind: "label", title: e.title }
      : { kind: "entry", entry: e, selectable: true, title: e.title });
  };

  const build = () => {
    const el = document.createElement("div");
    el.className = "panel-level";
    const level = state.stack.at(-1);
    if (level) {
      const back = document.createElement("button");
      back.className = "row back";
      back.type = "button";
      back.tabIndex = -1;
      back.textContent = `‹  ${level.title}`;
      back.addEventListener("click", () => goBack(true));
      el.append(back);
    }
    currentRows().forEach((row, index) => {
      if (row.kind === "sep") { el.append(Object.assign(document.createElement("div"), { className: "sep" })); return; }
      if (row.kind === "label") { el.append(Object.assign(document.createElement("div"), { className: "label", textContent: row.title })); return; }
      const b = document.createElement("button");
      b.type = "button";
      b.tabIndex = -1;
      b.setAttribute("role", "menuitem");
      b.className = row.kind === "entry" ? "row entry" : "row";
      b.dataset.index = index;
      if (row.kind === "item") {
        const tile = document.createElement("span");
        tile.className = "tile";
        tile.style.setProperty("background", row.item.tile);
        tile.innerHTML = GLYPHS[row.item.glyph];
        b.append(tile);
      }
      const title = Object.assign(document.createElement("span"), { className: "title", textContent: row.title });
      const more = Object.assign(document.createElement("span"), {
        className: "more",
        textContent: row.kind === "item" ? (row.item.menu ? "›" : "") : (row.entry.submenu ? "›" : ""),
      });
      if (row.kind === "item") b.setAttribute("aria-haspopup", row.item.menu ? "menu" : "false");
      b.append(title, more);
      b.addEventListener("mouseenter", () => select(index));
      b.addEventListener("mouseleave", () => { if (state.sel === index) select(null); });
      b.addEventListener("click", () => activate(index, true));
      el.append(b);
    });
    if (!level) el.append(Object.assign(document.createElement("div"), { className: "panel-foot", textContent: "⌃⌥M to open · right-click ··· to arrange" }));
    return el;
  };

  const select = (index) => {
    state.sel = index;
    panel.querySelectorAll(".row[data-index]").forEach((r) => {
      const on = Number(r.dataset.index) === index;
      r.setAttribute("aria-selected", on ? "true" : "false");
      if (on && panel.contains(document.activeElement)) r.focus({ preventScroll: true });
    });
  };

  const firstSelectable = () => currentRows().findIndex((r) => r.selectable);

  // ---- Layout and motion ----

  const position = () => {
    const s = screen.getBoundingClientRect();
    const t = toggle.getBoundingClientRect();
    panel.style.setProperty("right", `${Math.max(8, s.right - t.right)}px`);
  };

  const fitHeight = (level) => level.offsetHeight + 10; // 5 px padding top and bottom

  /// Swap the level; pointer swaps glide (height + 8 px slide), keyboard swaps jump.
  const showLevel = (animated, direction = "forward") => {
    const old = panel.querySelector(".panel-level");
    const from = old ? panel.offsetHeight : 0;
    const next = build();
    if (old) old.replaceWith(next); else panel.append(next);
    const to = fitHeight(next);
    if (!animated || !old) {
      panel.classList.add("instant");
      panel.style.setProperty("height", `${to}px`);
      void panel.offsetHeight;
      panel.classList.remove("instant");
      return;
    }
    panel.style.setProperty("height", `${from}px`);
    next.classList.add(direction === "back" ? "from-back" : "from-forward");
    void panel.offsetHeight;
    panel.style.setProperty("height", `${to}px`);
    void next.offsetHeight;
    next.classList.add("settled");
  };

  const open = (animated) => {
    if (state.arranging) setArranging(false);
    state.generation += 1;
    state.open = true;
    state.stack = [];
    panel.hidden = false;
    position();
    showLevel(false);
    toggle.setAttribute("aria-expanded", "true");
    // Reduce Motion is handled in CSS: the same classes fade without scaling.
    if (animated) {
      panel.className = "panel entering";
      void panel.offsetHeight; // commit the start state, then transition from it
      panel.className = "panel shown";
    } else {
      panel.className = "panel shown instant";
      void panel.offsetHeight;
      panel.classList.remove("instant");
    }
    select(animated ? null : firstSelectable());
    const target = panel.querySelector('.row[aria-selected="true"]') || panel.querySelector(".row[data-index]");
    target?.focus({ preventScroll: true });
  };

  const close = (animated, refocus = true) => {
    if (!state.open) return;
    state.open = false;
    state.generation += 1;
    const token = state.generation;
    toggle.setAttribute("aria-expanded", "false");
    if (refocus && panel.contains(document.activeElement)) toggle.focus({ preventScroll: true });
    if (!animated) { panel.hidden = true; return; }
    panel.className = "panel leaving";
    setTimeout(() => { if (state.generation === token) panel.hidden = true; }, 140);
  };

  // ---- Actions ----

  const say = (text) => { readout.textContent = text; };

  const activate = (index, animated) => {
    const row = currentRows()[index];
    if (!row || !row.selectable) return;
    const level = state.stack.at(-1);
    if (row.kind === "item") {
      if (!row.item.menu) { close(animated); say(`${row.item.title}: no menu, opens its app`); return; }
      state.stack.push({ title: row.item.title, entries: row.item.menu, root: row.item.title });
      enterLevel(animated);
      return;
    }
    if (row.entry.submenu) {
      state.stack.push({ title: row.entry.title, entries: row.entry.submenu, root: level.root, path: [...(level.path || []), row.entry.title] });
      enterLevel(animated);
      return;
    }
    close(animated);
    say([level.root, ...(level.path || []), row.entry.title].join(" › "));
  };

  // Keep focus inside the panel when its rows are replaced; keyboard entries also select.
  const enterLevel = (animated) => {
    showLevel(animated, "forward");
    select(animated ? null : firstSelectable());
    (panel.querySelector('.row[aria-selected="true"]') || panel.querySelector(".row[data-index]"))?.focus({ preventScroll: true });
  };

  const goBack = (animated) => {
    if (!state.stack.length) return false;
    state.stack.pop();
    showLevel(animated, "back");
    select(null);
    panel.querySelector(".row[data-index]")?.focus({ preventScroll: true });
    return true;
  };

  const move = (delta) => {
    const rows = currentRows();
    if (state.sel === null) {
      const order = delta > 0 ? rows.map((_, i) => i) : rows.map((_, i) => i).reverse();
      const hit = order.find((i) => rows[i].selectable);
      if (hit !== undefined) select(hit);
      return;
    }
    for (let i = state.sel + delta; i >= 0 && i < rows.length; i += delta) {
      if (rows[i].selectable) { select(i); return; }
    }
  };

  const jump = (letter) => {
    const rows = currentRows();
    const start = (state.sel ?? -1) + 1;
    const order = [...rows.keys()].slice(start).concat([...rows.keys()].slice(0, start));
    const hit = order.find((i) => rows[i].selectable && rows[i].title.toLowerCase().startsWith(letter));
    if (hit !== undefined) select(hit);
  };

  const setArranging = (on) => {
    state.arranging = on;
    bar.dataset.arranging = String(on);
    toggle.querySelector(".glyph").innerHTML = on ? GLYPHS.check : GLYPHS.ellipsis;
    toggle.setAttribute("aria-label", on ? "Done arranging" : "Open tucked items");
    segmented.forEach((b) => b.setAttribute("aria-pressed", String((b.dataset.mode === "arranging") === on)));
  };

  // ---- Wiring ----

  toggle.addEventListener("click", (event) => {
    // A click from the keyboard (space/return on the focused button) stays instant.
    const pointer = event.detail > 0;
    if (state.arranging) { setArranging(false); say("Done arranging"); return; }
    state.open ? close(pointer) : open(pointer);
  });

  toggle.addEventListener("contextmenu", (event) => {
    event.preventDefault();
    close(false, false);
    setArranging(!state.arranging);
    say(state.arranging ? "Arranging: ⌘-drag icons across the line" : "Done arranging");
  });

  segmented.forEach((b) => b.addEventListener("click", () => {
    const on = b.dataset.mode === "arranging";
    if (on === state.arranging) return;
    close(true, false);
    setArranging(on);
    say(on ? "Arranging: ⌘-drag icons across the line" : "Done arranging");
  }));

  document.addEventListener("pointerdown", (event) => {
    if (state.open && !panel.contains(event.target) && !toggle.contains(event.target)) close(true, false);
  });

  document.addEventListener("keydown", (event) => {
    if (event.ctrlKey && event.altKey && event.code === "KeyM") {
      event.preventDefault();
      state.open ? close(false) : open(false);
      return;
    }
    if (!state.open) return;
    const handled = {
      ArrowDown: () => move(1),
      ArrowUp: () => move(-1),
      Enter: () => activate(state.sel, false),
      " ": () => activate(state.sel, false),
      ArrowRight: () => {
        const row = currentRows()[state.sel];
        if (row && (row.kind === "item" ? row.item.menu : row.entry?.submenu)) activate(state.sel, false);
      },
      ArrowLeft: () => goBack(false),
      Backspace: () => goBack(false),
      Escape: () => { if (!goBack(false)) close(false); },
    }[event.key];
    if (handled) { event.preventDefault(); handled(); return; }
    if (!event.metaKey && !event.ctrlKey && /^[a-z0-9]$/i.test(event.key)) { event.preventDefault(); jump(event.key.toLowerCase()); }
  });

  addEventListener("resize", () => { if (state.open) position(); });
})();
