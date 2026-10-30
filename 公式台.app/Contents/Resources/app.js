"use strict";

const native = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.desk);
const editor = document.getElementById("editor");
const nameInput = document.getElementById("name");
const tagInput = document.getElementById("tag");
const noteInput = document.getElementById("note");
const previewMath = document.getElementById("preview-math");
const previewKicker = document.getElementById("preview-kicker");
const previewError = document.getElementById("preview-error");
const librarySearch = document.getElementById("library-search");
const libraryList = document.getElementById("library-list");
const tagRow = document.getElementById("tag-row");
const statusText = document.getElementById("status-text");
const slotHint = document.getElementById("slot-hint");
const saveButton = document.getElementById("save");
const saveNewButton = document.getElementById("save-new");
const sizeSlider = document.getElementById("size");
const segment = document.getElementById("segment");
const quick = document.getElementById("quick");
const tabs = document.getElementById("tabs");
const panels = document.getElementById("panels");
const palette = document.getElementById("palette");
const symbolSearch = document.getElementById("symbol-search");
const toastEl = document.getElementById("toast");
const modal = document.getElementById("modal");
const modalTitle = document.getElementById("modal-title");
const modalText = document.getElementById("modal-text");
const modalActions = document.getElementById("modal-actions");
const cardMenu = document.getElementById("card-menu");
const moreMenu = document.getElementById("more-menu");
const moreButton = document.getElementById("more");
const copyLatexButton = document.getElementById("copy-latex");
const copyImageButton = document.getElementById("copy-image");
const copyWordButton = document.getElementById("copy-word");
const pasteSize = document.getElementById("paste-size");
const pinItem = cardMenu.querySelector('[data-act="pin"]');

const state = {
  formulas: [],
  loadedId: null,
  display: true,
  previewSize: 32,
  libraryWidth: 300,
  pastePoints: 18,
  tagFilter: "",
  booted: false,
  katexOK: false,
  temmlOK: false,
  sel: [0, 0],
};

let saveTimer = 0;
let previewTimer = 0;
let toastTimer = 0;
let closeModal = null;
let menuId = null;
let silent = false;

function post(message) {
  if (native) window.webkit.messageHandlers.desk.postMessage(message);
}

function toast(text, tone) {
  toastEl.hidden = false;
  toastEl.textContent = text;
  toastEl.className = "toast" + (tone === "warn" ? " warn" : "");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { toastEl.hidden = true; }, 3800);
}

function ask(options) {
  return new Promise((resolve) => {
    modalTitle.textContent = options.title;
    modalText.textContent = options.text || "";
    modalActions.replaceChildren();
    closeModal = (id) => {
      modal.hidden = true;
      closeModal = null;
      resolve(id);
    };
    for (const button of options.buttons) {
      const el = document.createElement("button");
      el.type = "button";
      el.className = "btn" + (button.primary ? " primary" : "") + (button.danger ? " danger-fill" : "");
      el.textContent = button.label;
      el.addEventListener("click", () => closeModal(button.id));
      modalActions.append(el);
    }
    modal.hidden = false;
    modalActions.querySelector(".primary, .danger-fill, .btn")?.focus();
  });
}

function deriveName(latex) {
  const one = latex.replace(/\s+/g, " ").trim();
  if (!one) return "未命名公式";
  return one.length > 24 ? one.slice(0, 24) + "…" : one;
}

function currentFormula() {
  return state.formulas.find((item) => item.id === state.loadedId) || null;
}

function isDirty() {
  if (!state.booted) return false;
  const formula = currentFormula();
  if (!formula) return editor.value.trim().length > 0;
  return editor.value !== formula.latex
    || nameInput.value !== (formula.name || "")
    || noteInput.value !== (formula.note || "")
    || tagInput.value !== (formula.tag || "")
    || state.display !== (formula.display !== false);
}

function snapshot() {
  return {
    version: 1,
    draft: {
      latex: editor.value,
      name: nameInput.value,
      note: noteInput.value,
      tag: tagInput.value.trim(),
      display: state.display,
      loadedId: state.loadedId,
    },
    settings: {
      previewSize: state.previewSize,
      libraryWidth: state.libraryWidth,
      pastePoints: state.pastePoints,
    },
    formulas: state.formulas,
  };
}

function scheduleSave() {
  if (!state.booted) return;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(flush, 350);
}

function flush() {
  const snap = snapshot();
  if (native) post({ type: "save", library: snap });
  else localStorage.setItem("公式台.library", JSON.stringify(snap));
  return snap;
}

function applyChrome() {
  silent = true;
  sizeSlider.value = String(state.previewSize);
  if ([...pasteSize.options].some((option) => Number(option.value) === state.pastePoints)) {
    pasteSize.value = String(state.pastePoints);
  }
  document.documentElement.style.setProperty("--preview-size", state.previewSize + "px");
  document.documentElement.style.setProperty("--lib-width", state.libraryWidth + "px");
  syncDisplayButtons();
  silent = false;
}

function syncDisplayButtons() {
  previewKicker.textContent = state.display ? "独立公式" : "行内公式";
  for (const button of segment.querySelectorAll("button")) {
    button.classList.toggle("is-on", button.dataset.display === (state.display ? "display" : "inline"));
  }
}

function setDisplay(display) {
  state.display = display;
  syncDisplayButtons();
  renderPreview();
  markDirty();
  scheduleSave();
}

function markDirty() {
  saveButton.classList.toggle("is-dirty", isDirty());
  slotHint.hidden = !editor.value.includes("\\Box");
}

function syncActions() {
  const empty = !editor.value.trim();
  copyLatexButton.disabled = empty;
  copyImageButton.disabled = empty || !state.katexOK;
  copyWordButton.disabled = empty || !state.temmlOK;
  markDirty();
}

function renderPreview() {
  const latex = editor.value;
  previewMath.replaceChildren();
  if (!latex.trim()) {
    state.katexOK = false;
    state.temmlOK = false;
    previewError.textContent = "";
    const hint = document.createElement("div");
    hint.className = "preview-placeholder";
    hint.textContent = "预览会显示在这里";
    previewMath.append(hint);
    syncActions();
    return;
  }
  try {
    katex.render(latex, previewMath, {
      displayMode: state.display,
      throwOnError: true,
      output: "html",
      trust: false,
    });
    markSlots(previewMath);
    state.katexOK = true;
    previewError.textContent = "";
  } catch (error) {
    try {
      katex.render(latex, previewMath, {
        displayMode: state.display,
        throwOnError: false,
        errorColor: "#c24b32",
        output: "html",
        trust: false,
      });
    } catch (_) { /* 排版器自己也失败时留空 */ }
    state.katexOK = false;
    state.temmlOK = false;
    previewError.textContent = error.message || "这行公式还排不出来";
    syncActions();
    return;
  }
  try {
    temml.renderToString(latex, { displayMode: state.display, throwOnError: true });
    state.temmlOK = true;
  } catch (_) {
    state.temmlOK = false;
    previewError.textContent = "预览正常，但这条暂时转不成 Word 公式。";
  }
  syncActions();
}

function schedulePreview() {
  clearTimeout(previewTimer);
  previewTimer = setTimeout(renderPreview, 40);
}

function markSlots(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    if (node.nodeValue && node.nodeValue.includes("□")) node.parentElement?.classList.add("slot");
  }
}

function mathMLOf(latex, display) {
  return temml.renderToString(latex, { displayMode: display, xml: true, throwOnError: true });
}

function requireLatex() {
  if (!editor.value.trim()) {
    toast("还没有公式", "warn");
    return false;
  }
  return true;
}

function editorRange() {
  if (document.activeElement === editor) return [editor.selectionStart, editor.selectionEnd];
  return state.sel || [editor.value.length, editor.value.length];
}

function rememberSelection() {
  if (document.activeElement === editor) state.sel = [editor.selectionStart, editor.selectionEnd];
}

function insertRaw(text) {
  const [start, end] = editorRange();
  editor.focus();
  editor.setSelectionRange(start, end);
  if (!document.execCommand("insertText", false, text)) {
    editor.value = editor.value.slice(0, start) + text + editor.value.slice(end);
    const caret = start + text.length;
    editor.setSelectionRange(caret, caret);
  }
  onEdit();
}

function insertItem(entry) {
  if (entry.displayOnly && !state.display) setDisplay(true);
  const [start, end] = editorRange();
  const result = FormulaEdit.applyTemplate(editor.value, start, end, entry);
  const bodyLength = result.value.length - (editor.value.length - (end - start));
  const body = result.value.slice(start, start + bodyLength);
  editor.focus();
  editor.setSelectionRange(start, end);
  if (!document.execCommand("insertText", false, body)) editor.value = result.value;
  editor.setSelectionRange(result.selectionStart, result.selectionEnd);
  state.sel = [result.selectionStart, result.selectionEnd];
  onEdit();
}

function onEdit() {
  schedulePreview();
  markDirty();
  scheduleSave();
}

function filtered() {
  const query = librarySearch.value.trim().toLowerCase();
  const items = state.formulas.filter((formula) => {
    if (state.tagFilter && formula.tag !== state.tagFilter) return false;
    if (!query) return true;
    return [formula.name, formula.latex, formula.note, formula.tag].join("\n").toLowerCase().includes(query);
  });
  return items.sort((a, b) => Number(b.pinned) - Number(a.pinned));
}

function renderLibrary(scrollSelected) {
  const tags = [...new Set(state.formulas.map((formula) => formula.tag).filter(Boolean))];
  tags.sort((a, b) => a.localeCompare(b, "zh"));
  if (state.tagFilter && !tags.includes(state.tagFilter)) state.tagFilter = "";
  tagRow.replaceChildren();
  tagRow.append(chip("全部", ""));
  for (const tag of tags) tagRow.append(chip(tag, tag));

  const items = filtered();
  const top = libraryList.scrollTop;
  libraryList.replaceChildren();
  if (!items.length) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = state.formulas.length ? "没有匹配的公式" : "公式库是空的";
    libraryList.append(empty);
  } else {
    for (const formula of items) libraryList.append(card(formula));
  }
  libraryList.scrollTop = top;
  if (scrollSelected) libraryList.querySelector(".is-selected")?.scrollIntoView({ block: "nearest" });
  statusText.textContent = items.length === state.formulas.length
    ? `公式库 · ${state.formulas.length} 条`
    : `显示 ${items.length} / ${state.formulas.length}`;
  markDirty();
}

function chip(label, value) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "chip" + (state.tagFilter === value ? " is-on" : "");
  button.textContent = label;
  button.addEventListener("click", () => {
    state.tagFilter = value;
    renderLibrary(false);
  });
  return button;
}

function card(formula) {
  const el = document.createElement("article");
  el.className = "card" + (formula.id === state.loadedId ? " is-selected" : "");
  el.dataset.id = formula.id;
  const top = document.createElement("div");
  top.className = "card-top";
  const title = document.createElement("div");
  title.className = "card-name";
  title.textContent = formula.name || "未命名";
  const more = document.createElement("button");
  more.type = "button";
  more.className = "card-more";
  more.textContent = "···";
  more.title = "更多";
  more.dataset.menu = formula.id;
  top.append(title, more);
  const math = document.createElement("div");
  math.className = "card-math";
  try {
    katex.render(formula.latex, math, { displayMode: false, throwOnError: false, output: "html" });
  } catch (_) {
    math.textContent = formula.latex;
  }
  const source = document.createElement("div");
  source.className = "card-latex";
  source.textContent = formula.latex.replace(/\s+/g, " ");
  el.append(top, math, source);
  if (formula.tag) {
    const tag = document.createElement("div");
    tag.className = "card-tag";
    tag.textContent = formula.tag;
    el.append(tag);
  }
  return el;
}

async function confirmIfDirty() {
  if (!isDirty()) return true;
  const choice = await ask({
    title: "这条修改还没保存",
    text: "离开之后，编辑区里没保存的修改会被换掉。",
    buttons: [
      { id: "cancel", label: "取消" },
      { id: "discard", label: "不保存" },
      { id: "save", label: "先保存", primary: true },
    ],
  });
  if (choice === "cancel") return false;
  if (choice === "save" && !saveCurrent()) return false;
  return true;
}

async function openFormula(id) {
  if (id === state.loadedId) return;
  if (!(await confirmIfDirty())) return;
  const formula = state.formulas.find((item) => item.id === id);
  if (!formula) return;
  state.loadedId = id;
  editor.value = formula.latex;
  nameInput.value = formula.name || "";
  noteInput.value = formula.note || "";
  tagInput.value = formula.tag || "";
  state.display = formula.display !== false;
  applyChrome();
  renderPreview();
  renderLibrary(true);
  scheduleSave();
  editor.focus();
  const end = editor.value.length;
  editor.setSelectionRange(end, end);
  state.sel = [end, end];
}

async function newFormula() {
  if (!(await confirmIfDirty())) return;
  state.loadedId = null;
  editor.value = "";
  nameInput.value = "";
  noteInput.value = "";
  tagInput.value = "";
  renderPreview();
  renderLibrary(false);
  scheduleSave();
  editor.focus();
}

function saveCurrent() {
  if (!editor.value.trim()) {
    toast("没有可以保存的公式", "warn");
    return false;
  }
  const now = Date.now();
  const formula = currentFormula();
  if (!formula) return saveAsNew();
  formula.latex = editor.value;
  formula.name = nameInput.value.trim() || deriveName(editor.value);
  formula.note = noteInput.value;
  formula.tag = tagInput.value.trim();
  formula.display = state.display;
  formula.updated = now;
  nameInput.value = formula.name;
  renderLibrary(false);
  scheduleSave();
  toast("已更新「" + formula.name + "」");
  return true;
}

function saveAsNew() {
  if (!editor.value.trim()) {
    toast("没有可以保存的公式", "warn");
    return false;
  }
  const now = Date.now();
  const formula = {
    id: crypto.randomUUID(),
    name: nameInput.value.trim() || deriveName(editor.value),
    latex: editor.value,
    note: noteInput.value,
    tag: tagInput.value.trim(),
    pinned: false,
    display: state.display,
    created: now,
    updated: now,
  };
  state.formulas.unshift(formula);
  state.loadedId = formula.id;
  nameInput.value = formula.name;
  renderLibrary(true);
  scheduleSave();
  toast("已存入公式库");
  return true;
}

function copyText(text, done) {
  if (native) post({ type: "copyText", text, done });
  else navigator.clipboard.writeText(text).then(() => toast(done)).catch(() => toast("复制失败", "warn"));
}

function copyLatexOf(latex) {
  copyText(latex, "已复制 LaTeX");
}

function copyOfficeOf(latex, display, target) {
  let mathml;
  try {
    mathml = mathMLOf(latex, display);
  } catch (error) {
    toast("转不成 Office 公式：" + (error.message || ""), "warn");
    return;
  }
  if (!native) {
    toast("复制到 Word 或 PowerPoint 需要打开公式台", "warn");
    return;
  }
  post({ type: "copyOffice", target, mathml, display, points: state.pastePoints });
}

function copyImageOf(latex, display, appearance) {
  if (!native) {
    toast("复制图片需要打开公式台", "warn");
    return;
  }
  toast("正在生成图片…");
  post({ type: "copyImage", latex, display, appearance });
}

function copyLatex() {
  if (!requireLatex()) return;
  copyLatexOf(editor.value);
}

function copyWord() {
  if (!requireLatex()) return;
  copyOfficeOf(editor.value, state.display, "word");
}

function copyPowerPoint() {
  copyWord();
}

function copyImageAppearance(appearance) {
  if (!requireLatex()) return;
  if (!state.katexOK) {
    toast("这条公式还排不出来", "warn");
    return;
  }
  copyImageOf(editor.value, state.display, appearance);
}

function copyMathML() {
  if (!requireLatex()) return;
  let mathml;
  try { mathml = mathMLOf(editor.value, state.display); }
  catch (error) {
    toast(error.message || "转不成 MathML", "warn");
    return;
  }
  if (native) post({ type: "copyMathML", mathml });
  else copyText(mathml, "已复制 MathML");
}

function copyDollars() {
  if (!requireLatex()) return;
  const body = editor.value.trim();
  const text = state.display ? "$$\n" + body + "\n$$" : "$" + body + "$";
  copyText(text, "已复制带定界符的 LaTeX");
}

function exportDocx() {
  if (!requireLatex()) return;
  let mathml;
  try { mathml = mathMLOf(editor.value, state.display); }
  catch (error) {
    toast(error.message || "转不成 Word 公式", "warn");
    return;
  }
  if (!native) {
    toast("导出 Word 需要打开公式台", "warn");
    return;
  }
  post({
    type: "exportDocx",
    mathml,
    display: state.display,
    points: state.pastePoints,
    name: nameInput.value.trim() || deriveName(editor.value),
  });
}

function help() {
  ask({
    title: "怎么用",
    text: "公式保存在本机，格式就是 LaTeX。\n\n从上面点模板会插进源码。方框 □ 是空位，直接输入就会替换它，Tab 跳到下一个。选中一段再点模板，会把选中的内容包进去。\n\n「粘贴字号」决定复制到 Word 和 PowerPoint 后的大小。复制后在文档里按 ⌘V，公式可以继续编辑。\n复制图片则按预览的样子贴上。白底适合文档，透明底适合浅色幻灯片，白字适合深色幻灯片。\n\n⌘S 保存    ⌘⇧S 存为新公式    ⌘N 新公式\n⇧⌘W 复制到 Word / PPT\n⇧⌘I 复制图片    ⇧⌘C 复制 LaTeX    ⌘D 切换独立 / 行内\n\n公式库在「资源库 → Application Support → 公式台」。",
    buttons: [{ id: "ok", label: "知道了", primary: true }],
  });
}

function onLibrary(data) {
  if (!data || !Array.isArray(data.formulas)) return;
  state.formulas = data.formulas;
  state.previewSize = Number(data.settings?.previewSize) || 32;
  state.libraryWidth = Number(data.settings?.libraryWidth) || 300;
  state.pastePoints = Number(data.settings?.pastePoints) || 18;
  const draft = data.draft || {};
  state.loadedId = draft.loadedId || null;
  state.display = draft.display !== false;
  editor.value = draft.latex || "";
  nameInput.value = draft.name || "";
  noteInput.value = draft.note || "";
  tagInput.value = draft.tag || "";
  state.booted = true;
  applyChrome();
  renderLibrary(true);
  renderPreview();
}

async function browserBoot() {
  const saved = localStorage.getItem("公式台.library");
  if (saved) {
    try {
      onLibrary(JSON.parse(saved));
      return;
    } catch (_) { /* 损坏的话重新放示例 */ }
  }
  const examples = await fetch("examples.json").then((response) => response.json());
  const now = Date.now();
  const formulas = examples.map((example, index) => ({
    ...example,
    pinned: false,
    display: true,
    created: now + index,
    updated: now + index,
  }));
  const first = formulas[0];
  onLibrary({
    version: 1,
    draft: {
      latex: first.latex,
      name: first.name,
      note: first.note,
      tag: first.tag,
      display: true,
      loadedId: first.id,
    },
    settings: { previewSize: 32, libraryWidth: 300 },
    formulas,
  });
}

function prettyTemplate(entry) {
  if (entry.mode === "wrap") return entry.template + "{□}";
  if (entry.mode === "text") return "\\text{…}";
  return entry.template.replaceAll("\\Sel", "□").replaceAll("\\Grp", "□").replaceAll("\\Box", "□");
}

function symbolButton(entry) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "sym";
  button.title = entry.title + " · " + prettyTemplate(entry);
  button.dataset.hay = (entry.title + " " + entry.template + " " + entry.display).toLowerCase();
  button.addEventListener("mousedown", (event) => event.preventDefault());
  button.addEventListener("click", () => insertItem(entry));
  const span = document.createElement("span");
  try {
    katex.render(entry.display, span, { displayMode: false, throwOnError: false, output: "html" });
  } catch (_) {
    span.textContent = entry.title;
  }
  button.append(span);
  return button;
}

function buildPalette() {
  quick.replaceChildren();
  for (const entry of FormulaPalette.quick) quick.append(symbolButton(entry));
  tabs.replaceChildren();
  panels.replaceChildren();
  FormulaPalette.tabs.forEach((tab, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "tab" + (index === 0 ? " is-on" : "");
    button.dataset.tab = tab.id;
    button.textContent = tab.name;
    button.addEventListener("click", () => selectTab(tab.id));
    tabs.append(button);
    const panel = document.createElement("div");
    panel.className = "tab-panel" + (index === 0 ? " is-on" : "");
    panel.dataset.tab = tab.id;
    const label = document.createElement("div");
    label.className = "panel-label";
    label.textContent = tab.name;
    const grid = document.createElement("div");
    grid.className = "grid";
    for (const entry of tab.items) grid.append(symbolButton(entry));
    panel.append(label, grid);
    panels.append(panel);
  });
}

function selectTab(id) {
  symbolSearch.value = "";
  for (const tab of tabs.querySelectorAll(".tab")) tab.classList.toggle("is-on", tab.dataset.tab === id);
  for (const panel of panels.querySelectorAll(".tab-panel")) panel.classList.toggle("is-on", panel.dataset.tab === id);
  applyFilter();
}

function applyFilter() {
  const query = symbolSearch.value.trim().toLowerCase();
  palette.classList.toggle("is-filtering", query.length > 0);
  for (const panel of panels.querySelectorAll(".tab-panel")) {
    let visible = 0;
    for (const button of panel.querySelectorAll(".sym")) {
      const show = !query || button.dataset.hay.includes(query);
      button.hidden = !show;
      if (show) visible += 1;
    }
    panel.classList.toggle("is-empty", visible === 0);
  }
  for (const button of quick.querySelectorAll(".sym")) {
    button.hidden = query.length > 0 && !button.dataset.hay.includes(query);
  }
}

function openCardMenu(button, id) {
  menuId = id;
  const formula = state.formulas.find((item) => item.id === id);
  pinItem.textContent = formula && formula.pinned ? "取消置顶" : "置顶";
  cardMenu.hidden = false;
  const rect = button.getBoundingClientRect();
  const width = cardMenu.offsetWidth;
  const height = cardMenu.offsetHeight;
  cardMenu.style.top = Math.min(rect.bottom + 4, window.innerHeight - height - 8) + "px";
  cardMenu.style.left = Math.min(rect.left, window.innerWidth - width - 8) + "px";
}

function storedFormula() {
  return state.formulas.find((item) => item.id === menuId) || null;
}

function placeMenu(menu, anchor) {
  menu.hidden = false;
  const rect = anchor.getBoundingClientRect();
  const width = menu.offsetWidth;
  const height = menu.offsetHeight;
  menu.style.top = Math.max(8, rect.top - height - 6) + "px";
  menu.style.left = Math.min(rect.right - width, window.innerWidth - width - 8) + "px";
}

document.getElementById("splitter").addEventListener("mousedown", (event) => {
  event.preventDefault();
  const startX = event.clientX;
  const start = state.libraryWidth;
  function move(ev) {
    state.libraryWidth = Math.min(460, Math.max(220, start + ev.clientX - startX));
    document.documentElement.style.setProperty("--lib-width", state.libraryWidth + "px");
  }
  function up() {
    window.removeEventListener("mousemove", move);
    scheduleSave();
  }
  window.addEventListener("mousemove", move);
  window.addEventListener("mouseup", up, { once: true });
});

editor.addEventListener("input", onEdit);
editor.addEventListener("keyup", rememberSelection);
editor.addEventListener("mouseup", rememberSelection);
editor.addEventListener("select", rememberSelection);
editor.addEventListener("keydown", (event) => {
  if (event.key !== "Tab" || !editor.value.includes("\\Box")) return;
  const range = FormulaEdit.nextBoxRange(editor.value, editor.selectionStart, editor.selectionEnd, event.shiftKey ? -1 : 1);
  if (!range) return;
  event.preventDefault();
  editor.setSelectionRange(range[0], range[1]);
  state.sel = range;
});
editor.addEventListener("paste", (event) => {
  const text = event.clipboardData?.getData("text/plain");
  if (!text) return;
  const stripped = FormulaEdit.stripMathDelimiters(text);
  if (stripped === text) return;
  event.preventDefault();
  insertRaw(stripped);
});

for (const input of [nameInput, tagInput, noteInput]) {
  input.addEventListener("input", () => { markDirty(); scheduleSave(); });
}
nameInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    saveCurrent();
  }
});

segment.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  setDisplay(button.dataset.display === "display");
});
sizeSlider.addEventListener("input", () => {
  if (silent) return;
  state.previewSize = Number(sizeSlider.value);
  document.documentElement.style.setProperty("--preview-size", state.previewSize + "px");
  scheduleSave();
});
librarySearch.addEventListener("input", () => renderLibrary(false));
symbolSearch.addEventListener("input", applyFilter);
saveButton.addEventListener("click", saveCurrent);
saveNewButton.addEventListener("click", saveAsNew);
document.getElementById("new-formula").addEventListener("click", newFormula);
document.getElementById("help").addEventListener("click", help);
copyLatexButton.addEventListener("click", copyLatex);
copyImageButton.addEventListener("click", () => copyImageAppearance("paper"));
copyWordButton.addEventListener("click", copyWord);
pasteSize.addEventListener("change", () => {
  state.pastePoints = Number(pasteSize.value) || 18;
  scheduleSave();
});
moreButton.addEventListener("click", () => {
  cardMenu.hidden = true;
  if (!moreMenu.hidden) { moreMenu.hidden = true; return; }
  placeMenu(moreMenu, moreButton);
});

libraryList.addEventListener("click", (event) => {
  const more = event.target.closest(".card-more");
  if (more) {
    event.stopPropagation();
    openCardMenu(more, more.dataset.menu);
    return;
  }
  const cardEl = event.target.closest(".card");
  if (cardEl) openFormula(cardEl.dataset.id);
});

cardMenu.addEventListener("click", (event) => {
  const action = event.target.closest("button")?.dataset.act;
  const formula = storedFormula();
  cardMenu.hidden = true;
  if (!action || !formula) return;
  if (action === "insert") insertRaw(formula.latex);
  if (action === "latex") copyLatexOf(formula.latex);
  if (action === "office") copyOfficeOf(formula.latex, formula.display !== false, "word");
  if (action === "image") copyImageOf(formula.latex, formula.display !== false, "paper");
  if (action === "pin") {
    formula.pinned = !formula.pinned;
    formula.updated = Date.now();
    renderLibrary(false);
    scheduleSave();
  }
  if (action === "duplicate") {
    state.formulas.unshift({
      ...formula,
      id: crypto.randomUUID(),
      name: (formula.name || "公式") + " 副本",
      pinned: false,
      created: Date.now(),
      updated: Date.now(),
    });
    renderLibrary(false);
    scheduleSave();
  }
  if (action === "delete") {
    ask({
      title: "删除这条公式？",
      text: formula.name || formula.latex,
      buttons: [
        { id: "cancel", label: "取消" },
        { id: "ok", label: "删除", danger: true },
      ],
    }).then((choice) => {
      if (choice !== "ok") return;
      state.formulas = state.formulas.filter((item) => item.id !== formula.id);
      if (state.loadedId === formula.id) state.loadedId = null;
      renderLibrary(false);
      scheduleSave();
      toast("已从公式库删除，编辑区里的内容还在");
    });
  }
});

moreMenu.addEventListener("click", (event) => {
  const action = event.target.closest("button")?.dataset.act;
  moreMenu.hidden = true;
  if (action === "mathml") copyMathML();
  if (action === "dollars") copyDollars();
  if (action === "clear") copyImageAppearance("clear");
  if (action === "chalk") copyImageAppearance("chalk");
  if (action === "docx") exportDocx();
  if (action === "reveal") {
    if (native) post({ type: "reveal" });
    else toast("浏览器预览里公式存在这个页面的本地存储", "warn");
  }
});

document.addEventListener("mousedown", (event) => {
  if (!cardMenu.hidden && !cardMenu.contains(event.target) && !event.target.closest(".card-more")) cardMenu.hidden = true;
  if (!moreMenu.hidden && !moreMenu.contains(event.target) && event.target !== moreButton) moreMenu.hidden = true;
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    cardMenu.hidden = true;
    moreMenu.hidden = true;
    if (closeModal) closeModal("cancel");
    return;
  }
  const meta = event.metaKey || event.ctrlKey;
  if (!meta) return;
  const key = event.key.toLowerCase();
  if (key === "s" && !event.shiftKey) { event.preventDefault(); saveCurrent(); }
  else if (key === "s" && event.shiftKey) { event.preventDefault(); saveAsNew(); }
  else if (key === "n") { event.preventDefault(); newFormula(); }
  else if (key === "d") { event.preventDefault(); setDisplay(!state.display); }
  else if (key === "f" && !event.shiftKey) { event.preventDefault(); librarySearch.focus(); librarySearch.select(); }
  else if (key === "f" && event.shiftKey) { event.preventDefault(); symbolSearch.focus(); }
  else if (key === "=" || key === "+") { event.preventDefault(); state.previewSize = Math.min(64, state.previewSize + 2); applyChrome(); scheduleSave(); }
  else if (key === "-" || key === "_") { event.preventDefault(); state.previewSize = Math.max(20, state.previewSize - 2); applyChrome(); scheduleSave(); }
  else if (event.shiftKey && key === "c") { event.preventDefault(); copyLatex(); }
  else if (event.shiftKey && key === "w") { event.preventDefault(); copyWord(); }
  else if (event.shiftKey && key === "p") { event.preventDefault(); copyWord(); }
  else if (event.shiftKey && key === "i") { event.preventDefault(); copyImageAppearance("paper"); }
});

window.desk = {
  onLibrary,
  onNotice(payload) { if (payload && payload.text) toast(payload.text, payload.tone); },
  snapshotJSON() { return JSON.stringify(snapshot()); },
  newFormula,
  save: saveCurrent,
  saveAsNew,
  copyLatex,
  copyWord,
  copyPowerPoint,
  copyImage() { copyImageAppearance("paper"); },
  copyClearImage() { copyImageAppearance("clear"); },
  copyChalkImage() { copyImageAppearance("chalk"); },
  copyMathML,
  copyDollars,
  toggleDisplay() { setDisplay(!state.display); },
  bumpSize(delta) {
    state.previewSize = Math.min(64, Math.max(20, state.previewSize + Number(delta || 0)));
    applyChrome();
    scheduleSave();
  },
  focusSearch() { librarySearch.focus(); librarySearch.select(); },
  exportDocx,
  help,
};

if (!window.katex || !window.temml || !window.FormulaEdit || !window.FormulaPalette) {
  statusText.textContent = "公式组件没有加载成功";
} else {
  buildPalette();
  if (!native) {
    document.getElementById("browser-note").hidden = false;
    browserBoot();
  } else {
    post({ type: "ready" });
  }
}
