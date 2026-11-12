// Deterministisk konvertering av Androids VectorDrawable-original till SVG + PNG.
// Ingen omritning: pathData, färger, fillType och gruppens skala/förflyttning
// förs över oförändrade.
const fs = require('fs');
const path = require('path');
const { XMLParser } = require('fast-xml-parser');
const { Resvg } = require('@resvg/resvg-js');

const RES = 'C:/mina_appar/vardag-projektet/vardag-android/app/src/main/res/drawable';
const OUT = path.join(__dirname, 'out');
fs.mkdirSync(OUT, { recursive: true });

const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '' });

function num(v, d) { return v === undefined ? d : Number(v); }

function nodeToSvg(node, tag) {
  let out = '';
  const paths = [].concat(node.path || []);
  const groups = [].concat(node.group || []);
  for (const g of groups) {
    const tx = num(g['android:translateX'], 0), ty = num(g['android:translateY'], 0);
    const sx = num(g['android:scaleX'], 1), sy = num(g['android:scaleY'], 1);
    if (g['android:rotation'] || g['android:pivotX'] || g['android:pivotY']) {
      throw new Error('rotation/pivot stöds inte i konverteraren');
    }
    out += `<g transform="translate(${tx} ${ty}) scale(${sx} ${sy})">${nodeToSvg(g)}</g>`;
  }
  for (const p of paths) {
    const fill = p['android:fillColor'] || '#000000';
    const rule = p['android:fillType'] === 'evenOdd' ? 'evenodd' : 'nonzero';
    out += `<path fill="${fill}" fill-rule="${rule}" d="${p['android:pathData']}"/>`;
  }
  return out;
}

/** Läser en VectorDrawable och returnerar {w,h,inner}. */
function readVector(file, fillOverride) {
  const xml = fs.readFileSync(path.join(RES, file), 'utf8');
  const v = parser.parse(xml).vector;
  let inner = nodeToSvg(v);
  if (fillOverride) inner = inner.replace(/fill="#[0-9A-Fa-f]+"/g, `fill="${fillOverride}"`);
  return { w: num(v['android:viewportWidth']), h: num(v['android:viewportHeight']), inner };
}

function svgDoc(w, h, inner) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">${inner}</svg>`;
}

function render(svg, widthPx, file) {
  const r = new Resvg(svg, { fitTo: { mode: 'width', value: widthPx }, background: 'rgba(0,0,0,0)' });
  const png = r.render().asPng();
  fs.writeFileSync(path.join(OUT, file), png);
  console.log('skrev', file, widthPx);
}

// 1) Hela loggan (symbol + ordmärke), #1E5155 på transparent.
const logo = readVector('vardag_logo.xml');
const logoSvg = svgDoc(logo.w, logo.h, logo.inner);
fs.writeFileSync(path.join(OUT, 'vardag_logo.svg'), logoSvg);
render(logoSvg, 1510, 'vardag_logo.png');

// 2) Appikonen: bakgrund + förgrund i 108-viewport (adaptiv ikon som helhet).
const bg = readVector('ic_launcher_background.xml');
const fg = readVector('ic_launcher_foreground.xml');
const iconSvg = svgDoc(108, 108, bg.inner + fg.inner);
fs.writeFileSync(path.join(OUT, 'vardag_icon.svg'), iconSvg);
for (const s of [16, 32, 48, 72, 96, 144, 180, 192, 512, 1024]) render(iconSvg, s, `icon_${s}.png`);

// 3) Startskärmens symbol: #1E5155 på transparent (Androids ic_splash_logo).
const splash = readVector('ic_splash_logo.xml');
const splashSvg = svgDoc(108, 108, splash.inner);
fs.writeFileSync(path.join(OUT, 'vardag_splash.svg'), splashSvg);
render(splashSvg, 432, 'splash_symbol.png');

// 4) Förgrund separat (vit symbol på transparent) för adaptiv ikon i PNG-form.
const fgSvg = svgDoc(108, 108, fg.inner);
render(fgSvg, 432, 'icon_foreground.png');

// 5) Symbolen ensam, tätt beskuren i loggans färg (för små ytor i appen).
const sym = readVector('ic_launcher_foreground.xml', '#1E5155');
fs.writeFileSync(path.join(OUT, 'vardag_symbol_108.svg'), svgDoc(108, 108, sym.inner));
