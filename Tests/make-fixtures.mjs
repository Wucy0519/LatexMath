import { mkdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const temml = require("temml");
const outdir = process.argv[2];
if (!outdir) {
  console.error("用法: node Tests/make-fixtures.mjs 输出目录");
  process.exit(1);
}
mkdirSync(outdir, { recursive: true });

const cases = [
  {
    name: "quad",
    latex: String.raw`x=\frac{-b\pm\sqrt{b^{2}-4ac}}{2a}`,
    expect: ["<m:f", "<m:rad"],
  },
  {
    name: "sum",
    latex: String.raw`\sum_{n=0}^{\infty}\frac{f^{(n)}(a)}{n!}(x-a)^{n}`,
    expect: ["<m:nary", "<m:f"],
    naryContains: "m:f",
  },
  {
    name: "integral",
    latex: String.raw`\int_{a}^{b}f(x)\,dx=F(b)-F(a)`,
    expect: ["<m:nary", "∫"],
  },
  {
    name: "matrix",
    latex: String.raw`\begin{pmatrix}a&b\\c&d\end{pmatrix}`,
    expect: ["<m:m", "<m:d"],
  },
  {
    name: "cases",
    latex: String.raw`|x|=\begin{cases}x,&x\ge 0\\-x,&x<0\end{cases}`,
    expect: ["begChr", "{"],
  },
  {
    name: "text",
    latex: String.raw`\text{当 }x>0`,
    expect: ["当"],
  },
  {
    name: "limit",
    latex: String.raw`\lim_{x\to 0}\frac{\sin x}{x}=1`,
    expect: ["lim", "sin"],
  },
  {
    name: "hat",
    latex: String.raw`\hat{x}+\bar{y}+\dot{z}+\vec{v}`,
    expect: ["<m:acc"],
  },
  {
    name: "root",
    latex: String.raw`\sqrt[3]{x}`,
    expect: ["<m:rad", ">3<"],
  },
  {
    name: "euler",
    latex: String.raw`e^{i\pi}+1=0`,
    expect: ["<m:sSup", "π"],
  },
];

for (const entry of cases) {
  const mathml = temml.renderToString(entry.latex, { displayMode: true, xml: true, throwOnError: true });
  const payload = { ...entry, display: true, mathml };
  writeFileSync(`${outdir}/${entry.name}.json`, JSON.stringify(payload));
}
console.log(`fixtures ${cases.length}`);
