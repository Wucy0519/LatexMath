import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const katex = require("katex");
const temml = require("temml");
const FormulaEdit = require("../Resources/edit.js");
const { quick, tabs } = require("../Resources/palette.js");

const failures = [];

function check(name, actual, expected) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) failures.push(`${name}\n  得到 ${left}\n  应为 ${right}`);
}

function selectedText(result) {
  return result.value.slice(result.selectionStart, result.selectionEnd);
}

function checkBox(name, result, value) {
  if (result.value !== value) {
    failures.push(`${name}\n  得到 ${result.value}\n  应为 ${value}`);
  } else if (selectedText(result) !== "\\Box") {
    failures.push(`${name} 没有选中空位，选中了 ${JSON.stringify(selectedText(result))}`);
  }
}

checkBox(
  "分式空插入",
  FormulaEdit.applyTemplate("", 0, 0, { mode: "", template: "\\frac{\\Sel}{\\Box}" }),
  "\\frac{\\Box}{\\Box}"
);
checkBox(
  "分式包住选区",
  FormulaEdit.applyTemplate("a+b", 0, 3, { mode: "", template: "\\frac{\\Sel}{\\Box}" }),
  "\\frac{a+b}{\\Box}"
);
checkBox(
  "上标接在字母后",
  FormulaEdit.applyTemplate("x", 1, 1, { mode: "attach", template: "^{\\Box}" }),
  "x^{\\Box}"
);
checkBox(
  "上标包住算式",
  FormulaEdit.applyTemplate("a+b", 0, 3, { mode: "attach", template: "^{\\Box}" }),
  "{a+b}^{\\Box}"
);
checkBox(
  "求和的被加项",
  FormulaEdit.applyTemplate("a+b", 0, 3, { mode: "", template: "\\sum_{\\Box}^{\\Box}\\Grp" }),
  "\\sum_{\\Box}^{\\Box}{a+b}"
);
const sqrt = FormulaEdit.applyTemplate("x", 0, 1, { mode: "wrap", template: "\\sqrt" });
check("根号", sqrt, { value: "\\sqrt{x}", selectionStart: sqrt.value.length, selectionEnd: sqrt.value.length });
check(
  "文本光标",
  FormulaEdit.applyTemplate("", 0, 0, { mode: "text", template: "" }),
  { value: "\\text{}", selectionStart: 6, selectionEnd: 6 }
);
const angle = FormulaEdit.applyTemplate("a+b", 0, 3, { mode: "", template: "\\left\\langle\\Sel\\right\\rangle" });
if (angle.value !== "\\left\\langle a+b\\right\\rangle") {
  failures.push(`尖括号和字母粘在一起了：${angle.value}`);
}
check("去掉双美元", FormulaEdit.stripMathDelimiters("$$ x+1 $$"), "x+1");
check("去掉单美元", FormulaEdit.stripMathDelimiters("$x+1$"), "x+1");
check("去掉方括号", FormulaEdit.stripMathDelimiters("\\[x+1\\]"), "x+1");
check("去掉圆括号定界", FormulaEdit.stripMathDelimiters("\\(x+1\\)"), "x+1");
check("普通文本不动", FormulaEdit.stripMathDelimiters("  x+1"), "  x+1");

const boxed = "a\\Box+b\\Box";
check("下一个空位", FormulaEdit.nextBoxRange(boxed, 0, 0, 1), [1, 5]);
check("选中后再下一个", FormulaEdit.nextBoxRange(boxed, 1, 5, 1), [7, 11]);
check("上一个空位", FormulaEdit.nextBoxRange(boxed, 7, 11, -1), [1, 5]);

const items = [...quick];
for (const tab of tabs) items.push(...tab.items);
const seen = new Set();
for (const entry of items) {
  const key = entry.title + "\0" + entry.template + "\0" + entry.mode;
  if (seen.has(key)) continue;
  seen.add(key);
  const samples = [
    ["展示", entry.display, false],
    ["空插入", FormulaEdit.applyTemplate("", 0, 0, entry).value, !!entry.displayOnly],
    ["包住选区", FormulaEdit.applyTemplate("a+b", 0, 3, entry).value, !!entry.displayOnly],
  ];
  for (const [label, latex, displayOnly] of samples) {
    if (!latex.trim()) {
      failures.push(`${entry.title} 的${label}是空的`);
      continue;
    }
    const modes = displayOnly ? [true] : [true, false];
    for (const displayMode of modes) {
      for (const [engine, render] of [
        ["katex", () => katex.renderToString(latex, { displayMode, throwOnError: true })],
        ["temml", () => temml.renderToString(latex, { displayMode, throwOnError: true })],
      ]) {
        try {
          render();
        } catch (error) {
          failures.push(`${entry.title} / ${label} / ${engine} / ${displayMode ? "独立" : "行内"}：${latex}\n  ${error.message}`);
        }
      }
    }
  }
}

const examples = JSON.parse(readFileSync(new URL("../Resources/examples.json", import.meta.url), "utf8"));
for (const example of examples) {
  try {
    katex.renderToString(example.latex, { displayMode: true, throwOnError: true });
    temml.renderToString(example.latex, { displayMode: true, throwOnError: true, xml: true });
  } catch (error) {
    failures.push(`示例 ${example.name}：${error.message}`);
  }
}

if (failures.length) {
  console.error(failures.join("\n\n"));
  console.error(`\n${failures.length} 项没通过`);
  process.exit(1);
}
console.log(`edit ok, ${seen.size} templates`);
