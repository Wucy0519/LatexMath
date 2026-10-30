(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.FormulaEdit = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const BOX = "\\Box";

  function needsGroup(value) {
    if (/^[A-Za-z0-9]$/.test(value)) return false;
    if (/^\\[A-Za-z]+$/.test(value)) return false;
    return true;
  }

  function replaceToken(template, token, replacement) {
    let result = "";
    let index = 0;
    while (index <= template.length) {
      const at = template.indexOf(token, index);
      if (at < 0) {
        result += template.slice(index);
        break;
      }
      const previous = at > 0 ? template[at - 1] : "";
      result += template.slice(index, at);
      if (/[A-Za-z]/.test(previous) && replacement && /[A-Za-z]/.test(replacement[0])) result += " ";
      result += replacement;
      index = at + token.length;
    }
    return result;
  }

  function expandSlots(template, selected) {
    const raw = selected ? selected : BOX;
    const grouped = selected ? (needsGroup(selected) ? `{${selected}}` : selected) : BOX;
    return replaceToken(replaceToken(template, "\\Grp", grouped), "\\Sel", raw);
  }

  function applyTemplate(source, start, end, item) {
    const selected = source.slice(start, end);
    if (item.mode === "text") {
      const body = `\\text{${selected}}`;
      const value = source.slice(0, start) + body + source.slice(end);
      const caret = start + "\\text{".length + selected.length;
      return { value, selectionStart: caret, selectionEnd: caret };
    }

    let body;
    if (item.mode === "wrap") {
      body = `${item.template}{${selected || BOX}}`;
    } else if (item.mode === "attach") {
      const base = selected ? (needsGroup(selected) ? `{${selected}}` : selected) : "";
      body = base + item.template;
    } else {
      body = expandSlots(item.template, selected);
    }

    const value = source.slice(0, start) + body + source.slice(end);
    const boxAt = body.indexOf(BOX);
    if (boxAt >= 0) {
      return {
        value,
        selectionStart: start + boxAt,
        selectionEnd: start + boxAt + BOX.length,
      };
    }
    const caret = start + body.length;
    return { value, selectionStart: caret, selectionEnd: caret };
  }

  function nextBoxRange(value, start, end, direction) {
    if (!value.includes(BOX)) return null;
    const selected = value.slice(start, end);
    if (direction >= 0) {
      if (selected !== BOX && value.startsWith(BOX, start)) return [start, start + BOX.length];
      const from = selected === BOX ? end : start;
      let index = value.indexOf(BOX, from);
      if (index < 0) index = value.indexOf(BOX);
      return index < 0 ? null : [index, index + BOX.length];
    }
    const from = (selected === BOX ? start : end) - 1;
    let index = from >= 0 ? value.lastIndexOf(BOX, from) : -1;
    if (index < 0) index = value.lastIndexOf(BOX);
    return index < 0 ? null : [index, index + BOX.length];
  }

  function stripMathDelimiters(input) {
    const trimmed = input.trim();
    const pairs = [
      ["$$", "$$"],
      ["\\[", "\\]"],
      ["\\(", "\\)"],
      ["$", "$"],
    ];
    for (const [open, close] of pairs) {
      if (
        trimmed.length >= open.length + close.length &&
        trimmed.startsWith(open) &&
        trimmed.endsWith(close)
      ) {
        return trimmed.slice(open.length, trimmed.length - close.length).trim();
      }
    }
    return input;
  }

  return { applyTemplate, nextBoxRange, stripMathDelimiters, needsGroup, BOX };
});
