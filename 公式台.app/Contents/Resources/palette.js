(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.FormulaPalette = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function item(title, display, template, mode, displayOnly) {
    return { title, display, template, mode: mode || "", displayOnly: !!displayOnly };
  }
  function sym(title, command) {
    return item(title, command, command);
  }
  function wrap(title, display, command) {
    return item(title, display, command, "wrap");
  }
  function many(pairs) {
    return pairs.map(([title, command]) => sym(title, command));
  }

  const fraction = item("分式", "\\frac{a}{b}", "\\frac{\\Sel}{\\Box}");
  const smallFraction = item("小分式", "\\tfrac{a}{b}", "\\tfrac{\\Sel}{\\Box}");
  const slash = item("斜式", "a/b", "\\Sel/\\Box");
  const sqrt = wrap("根号", "\\sqrt{x}", "\\sqrt");
  const nroot = item("n 次根", "\\sqrt[n]{x}", "\\sqrt[\\Box]{\\Sel}");
  const sup = item("上标", "x^{n}", "^{\\Box}", "attach");
  const sub = item("下标", "x_{i}", "_{\\Box}", "attach");
  const subsup = item("上下标", "x_{i}^{n}", "_{\\Box}^{\\Box}", "attach");
  const sum = item("求和", "\\sum_{i=1}^{n}", "\\sum_{\\Box}^{\\Box}\\Grp");
  const prod = item("连乘", "\\prod_{i=1}^{n}", "\\prod_{\\Box}^{\\Box}\\Grp");
  const integral = item("积分", "\\int_{a}^{b}", "\\int_{\\Box}^{\\Box}\\Grp");
  const iint = item("二重积分", "\\iint", "\\iint_{\\Box}\\Grp");
  const oint = item("环路积分", "\\oint", "\\oint_{\\Box}\\Grp");
  const limit = item("极限", "\\lim_{x\\to 0}", "\\lim_{\\Box}\\Grp");
  const paren = item("圆括号", "(x)", "\\left(\\Sel\\right)");
  const bracket = item("方括号", "[x]", "\\left[\\Sel\\right]");
  const brace = item("花括号", "\\{x\\}", "\\left\\{\\Sel\\right\\}");
  const abs = item("绝对值", "|x|", "\\left|\\Sel\\right|");
  const norm = item("范数", "\\|x\\|", "\\left\\|\\Sel\\right\\|");
  const hat = wrap("帽子", "\\hat{a}", "\\hat");
  const bar = wrap("上横线", "\\bar{a}", "\\bar");
  const overline = wrap("上划线", "\\overline{AB}", "\\overline");
  const matrix = item(
    "矩阵",
    "\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}",
    "\\begin{pmatrix}\\Sel & \\Box \\\\ \\Box & \\Box\\end{pmatrix}",
    "",
    true
  );

  const quick = [
    fraction, sqrt, nroot, sup, sub, subsup, sum, integral, limit, paren, bracket, abs, matrix, hat, overline,
  ];

  const structures = [
    fraction, smallFraction, item("大分式", "\\dfrac{a}{b}", "\\dfrac{\\Sel}{\\Box}"), slash,
    item("二项式", "\\binom{n}{k}", "\\binom{\\Sel}{\\Box}"),
    sqrt, nroot, sup, sub, subsup,
    item("左上标", "{}^{n}x", "{}^{\\Box}_{\\Box}\\Grp"),
    item("撇", "f'", "'", "attach"),
    item("两撇", "f''", "''", "attach"),
    item("度", "30^{\\circ}", "^{\\circ}", "attach"),
    sum, prod, integral, iint, item("三重积分", "\\iiint", "\\iiint_{\\Box}\\Grp"), oint,
    item("并", "\\bigcup_{i}", "\\bigcup_{\\Box}\\Grp"),
    item("交", "\\bigcap_{i}", "\\bigcap_{\\Box}\\Grp"),
    limit,
    item("最大", "\\max", "\\max_{\\Box}\\Grp"),
    item("最小", "\\min", "\\min_{\\Box}\\Grp"),
    paren, bracket, brace, abs, norm,
    item("尖括号", "\\langle x\\rangle", "\\left\\langle\\Sel\\right\\rangle"),
    item("下取整", "\\lfloor x\\rfloor", "\\left\\lfloor\\Sel\\right\\rfloor"),
    item("上取整", "\\lceil x\\rceil", "\\left\\lceil\\Sel\\right\\rceil"),
  ];

  const greekLower = many([
    ["alpha", "\\alpha"], ["beta", "\\beta"], ["gamma", "\\gamma"], ["delta", "\\delta"],
    ["epsilon", "\\epsilon"], ["varepsilon", "\\varepsilon"], ["zeta", "\\zeta"], ["eta", "\\eta"],
    ["theta", "\\theta"], ["vartheta", "\\vartheta"], ["iota", "\\iota"], ["kappa", "\\kappa"],
    ["lambda", "\\lambda"], ["mu", "\\mu"], ["nu", "\\nu"], ["xi", "\\xi"],
    ["pi", "\\pi"], ["varpi", "\\varpi"], ["rho", "\\rho"], ["varrho", "\\varrho"],
    ["sigma", "\\sigma"], ["varsigma", "\\varsigma"], ["tau", "\\tau"], ["upsilon", "\\upsilon"],
    ["phi", "\\phi"], ["varphi", "\\varphi"], ["chi", "\\chi"], ["psi", "\\psi"], ["omega", "\\omega"],
  ]);
  const greekUpper = many([
    ["Gamma", "\\Gamma"], ["Delta", "\\Delta"], ["Theta", "\\Theta"], ["Lambda", "\\Lambda"],
    ["Xi", "\\Xi"], ["Pi", "\\Pi"], ["Sigma", "\\Sigma"], ["Upsilon", "\\Upsilon"],
    ["Phi", "\\Phi"], ["Psi", "\\Psi"], ["Omega", "\\Omega"],
  ]);

  const operators = many([
    ["加", "+"], ["减", "-"], ["正负", "\\pm"], ["负正", "\\mp"],
    ["乘", "\\times"], ["除", "\\div"], ["点乘", "\\cdot"], ["星", "\\ast"],
    ["圈乘", "\\circ"], ["子弹", "\\bullet"], ["星号", "\\star"],
    ["直和", "\\oplus"], ["直差", "\\ominus"], ["张量", "\\otimes"], ["斜除", "\\oslash"],
    ["圈点", "\\odot"], ["楔", "\\wedge"], ["析取", "\\vee"],
    ["交", "\\cap"], ["并", "\\cup"], ["差集", "\\setminus"],
    ["dagger", "\\dagger"], ["ddagger", "\\ddagger"],
  ]);

  const relations = many([
    ["等于", "="], ["不等于", "\\neq"], ["恒等", "\\equiv"], ["约等", "\\approx"],
    ["相似", "\\sim"], ["近似", "\\simeq"], ["全等", "\\cong"], ["正比", "\\propto"],
    ["小于", "<"], ["大于", ">"], ["小于等于", "\\leq"], ["大于等于", "\\geq"],
    ["远小于", "\\ll"], ["远大于", "\\gg"],
    ["先于", "\\prec"], ["后于", "\\succ"], ["先于等于", "\\preceq"], ["后于等于", "\\succeq"],
    ["子集", "\\subset"], ["超集", "\\supset"], ["子集等于", "\\subseteq"], ["超集等于", "\\supseteq"],
    ["属于", "\\in"], ["包含", "\\ni"], ["不属于", "\\notin"],
    ["垂直", "\\perp"], ["平行", "\\parallel"], ["整除", "\\mid"],
    ["模型", "\\models"], ["推出", "\\vdash"],
  ]);

  const arrows = many([
    ["右箭头", "\\rightarrow"], ["左箭头", "\\leftarrow"], ["双向", "\\leftrightarrow"],
    ["推出", "\\Rightarrow"], ["反推", "\\Leftarrow"], ["等价", "\\Leftrightarrow"],
    ["映射", "\\mapsto"], ["长映射", "\\longmapsto"],
    ["长右", "\\longrightarrow"], ["长左", "\\longleftarrow"], ["长双向", "\\longleftrightarrow"],
    ["上", "\\uparrow"], ["下", "\\downarrow"], ["上下", "\\updownarrow"],
    ["东北", "\\nearrow"], ["东南", "\\searrow"], ["西南", "\\swarrow"], ["西北", "\\nwarrow"],
    ["钩左", "\\hookleftarrow"], ["钩右", "\\hookrightarrow"],
    ["右鱼叉", "\\rightharpoonup"], ["左鱼叉", "\\leftharpoonup"],
    ["到", "\\to"],
  ]);

  const symbols = many([
    ["无穷", "\\infty"], ["偏导", "\\partial"], ["梯度", "\\nabla"],
    ["任意", "\\forall"], ["存在", "\\exists"], ["不存在", "\\nexists"],
    ["空集", "\\emptyset"], ["空集变体", "\\varnothing"],
    ["属于", "\\in"], ["不属于", "\\notin"],
    ["交集", "\\cap"], ["并集", "\\cup"], ["差", "\\setminus"],
    ["子集", "\\subset"], ["超集", "\\supset"], ["含于", "\\subseteq"], ["包含于", "\\supseteq"],
    ["省略", "\\ldots"], ["居中省略", "\\cdots"], ["竖省略", "\\vdots"], ["斜省略", "\\ddots"],
    ["角", "\\angle"], ["三角", "\\triangle"], ["素数", "\\prime"],
    ["实部", "\\Re"], ["虚部", "\\Im"], ["ell", "\\ell"], ["hbar", "\\hbar"],
    ["aleph", "\\aleph"], ["wp", "\\wp"],
    ["百分号", "\\%"], ["井号", "\\#"], ["和号", "\\&"],
    ["实数", "\\mathbb{R}"], ["自然数", "\\mathbb{N}"], ["整数", "\\mathbb{Z}"],
    ["有理数", "\\mathbb{Q}"], ["复数", "\\mathbb{C}"],
  ]);

  const functions = [
    item("sin", "\\sin", "\\sin\\left(\\Sel\\right)"),
    item("cos", "\\cos", "\\cos\\left(\\Sel\\right)"),
    item("tan", "\\tan", "\\tan\\left(\\Sel\\right)"),
    item("cot", "\\cot", "\\cot\\left(\\Sel\\right)"),
    item("sec", "\\sec", "\\sec\\left(\\Sel\\right)"),
    item("csc", "\\csc", "\\csc\\left(\\Sel\\right)"),
    item("arcsin", "\\arcsin", "\\arcsin\\left(\\Sel\\right)"),
    item("arccos", "\\arccos", "\\arccos\\left(\\Sel\\right)"),
    item("arctan", "\\arctan", "\\arctan\\left(\\Sel\\right)"),
    item("sinh", "\\sinh", "\\sinh\\left(\\Sel\\right)"),
    item("cosh", "\\cosh", "\\cosh\\left(\\Sel\\right)"),
    item("tanh", "\\tanh", "\\tanh\\left(\\Sel\\right)"),
    item("log", "\\log", "\\log\\left(\\Sel\\right)"),
    item("ln", "\\ln", "\\ln\\left(\\Sel\\right)"),
    item("lg", "\\lg", "\\lg\\left(\\Sel\\right)"),
    item("exp", "\\exp", "\\exp\\left(\\Sel\\right)"),
    limit,
    item("max", "\\max", "\\max_{\\Box}\\Grp"),
    item("min", "\\min", "\\min_{\\Box}\\Grp"),
    item("sup", "\\sup", "\\sup_{\\Box}\\Grp"),
    item("inf", "\\inf", "\\inf_{\\Box}\\Grp"),
    sym("det", "\\det"),
    sym("dim", "\\dim"),
    sym("ker", "\\ker"),
    sym("gcd", "\\gcd"),
    sym("deg", "\\deg"),
    item("mod", "a\\bmod b", "\\bmod"),
    item("pmod", "({\\bmod})", "\\pmod{\\Sel}"),
  ];

  const matrices = [
    matrix,
    item("方括号矩阵", "\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}", "\\begin{bmatrix}\\Sel & \\Box \\\\ \\Box & \\Box\\end{bmatrix}", "", true),
    item("单竖线矩阵", "\\begin{vmatrix}a&b\\\\c&d\\end{vmatrix}", "\\begin{vmatrix}\\Sel & \\Box \\\\ \\Box & \\Box\\end{vmatrix}", "", true),
    item("双竖线矩阵", "\\begin{Vmatrix}a&b\\\\c&d\\end{Vmatrix}", "\\begin{Vmatrix}\\Sel & \\Box \\\\ \\Box & \\Box\\end{Vmatrix}", "", true),
    item("花括号矩阵", "\\begin{Bmatrix}a&b\\\\c&d\\end{Bmatrix}", "\\begin{Bmatrix}\\Sel & \\Box \\\\ \\Box & \\Box\\end{Bmatrix}", "", true),
    item("三阶矩阵", "\\begin{pmatrix}a&b&c\\\\d&e&f\\\\g&h&i\\end{pmatrix}", "\\begin{pmatrix}\\Sel & \\Box & \\Box \\\\ \\Box & \\Box & \\Box \\\\ \\Box & \\Box & \\Box\\end{pmatrix}", "", true),
    item("分段", "|x|=\\begin{cases}a&b\\\\c&d\\end{cases}", "\\begin{cases}\\Sel & \\Box \\\\ \\Box & \\Box\\end{cases}", "", true),
    item("对齐", "\\begin{aligned}a&=b\\\\c&=d\\end{aligned}", "\\begin{aligned}\\Sel &= \\Box \\\\ \\Box &= \\Box\\end{aligned}", "", true),
    item("小矩阵", "\\begin{smallmatrix}a&b\\\\c&d\\end{smallmatrix}", "\\begin{smallmatrix}\\Sel & \\Box \\\\ \\Box & \\Box\\end{smallmatrix}"),
  ];

  const decorations = [
    hat, bar, wrap("向量", "\\vec{v}", "\\vec"), wrap("点", "\\dot{a}", "\\dot"),
    wrap("两点", "\\ddot{a}", "\\ddot"), wrap("波浪", "\\tilde{a}", "\\tilde"),
    wrap("短音", "\\breve{a}", "\\breve"), wrap("对勾", "\\check{a}", "\\check"),
    wrap("锐音", "\\acute{a}", "\\acute"), wrap("钝音", "\\grave{a}", "\\grave"),
    overline, wrap("下划线", "\\underline{a}", "\\underline"),
    wrap("宽帽子", "\\widehat{abc}", "\\widehat"), wrap("宽波浪", "\\widetilde{abc}", "\\widetilde"),
    item("上花括号", "\\overbrace{a+b}^{n}", "\\overbrace{\\Sel}^{\\Box}"),
    item("下花括号", "\\underbrace{a+b}_{n}", "\\underbrace{\\Sel}_{\\Box}"),
    item("上方", "\\overset{a}{b}", "\\overset{\\Box}{\\Sel}"),
    item("下方", "\\underset{a}{b}", "\\underset{\\Box}{\\Sel}"),
    item("文本", "\\text{文本}", "", "text"),
    wrap("罗马体", "\\mathrm{abc}", "\\mathrm"),
    wrap("粗体", "\\mathbf{abc}", "\\mathbf"),
    wrap("意大利体", "\\mathit{abc}", "\\mathit"),
    wrap("花体", "\\mathcal{ABC}", "\\mathcal"),
    wrap("黑板粗体", "\\mathbb{R}", "\\mathbb"),
    wrap("哥特体", "\\mathfrak{abc}", "\\mathfrak"),
    wrap("无衬线", "\\mathsf{abc}", "\\mathsf"),
    item("细空格", "a\\,b", "\\,"),
    item("中空格", "a\\;b", "\\;"),
    item("大空格", "a\\quad b", "\\quad"),
    item("更大空格", "a\\qquad b", "\\qquad"),
    item("贴紧", "a\\!b", "\\!"),
    item("强制大号", "\\displaystyle x", "\\displaystyle "),
  ];

  const tabs = [
    { id: "struct", name: "结构", items: structures },
    { id: "greek", name: "希腊", items: greekLower.concat(greekUpper) },
    { id: "ops", name: "运算", items: operators },
    { id: "rel", name: "关系", items: relations },
    { id: "arrow", name: "箭头", items: arrows },
    { id: "symbol", name: "符号", items: symbols },
    { id: "func", name: "函数", items: functions },
    { id: "matrix", name: "矩阵", items: matrices },
    { id: "decor", name: "修饰", items: decorations },
  ];

  return { quick, tabs };
});
