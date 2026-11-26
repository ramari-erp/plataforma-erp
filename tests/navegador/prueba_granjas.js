const { chromium } = require('playwright'); const fs = require('fs');
const path = require('path'); const os = require('os');
const S = __dirname, R = path.resolve(__dirname, '../..'), OUT = process.env.SALIDA || os.tmpdir();
(async () => {
  const b = await chromium.launch();
  for (const [nombre, vp] of [['escritorio', { width: 1280, height: 900 }], ['celular', { width: 390, height: 844 }]]) {
    const pg = await b.newPage({ viewport: vp }); const errores = [];
    pg.on('pageerror', (e) => errores.push(e.message)); pg.on('console', (m) => m.type() === 'error' && errores.push(m.text()));
    await pg.route('http://local/**', (r) => { let ruta = new URL(r.request().url()).pathname; if (ruta === '/') ruta = '/index.html';
      const a = ruta === '/app/api.js' ? `${S}/api_falsa_granjas.js` : R + ruta;
      r.fulfill({ body: fs.readFileSync(a), contentType: a.endsWith('.js') ? 'text/javascript' : a.endsWith('.css') ? 'text/css' : 'text/html' }); });
    await pg.goto('http://local/'); await pg.fill('input[name=email]', 'a@b.c'); await pg.fill('input[name=password]', 'bien'); await pg.click('button[type=submit]');
    await pg.waitForSelector('#avisos-inicio');
    await pg.goto('http://local/#/granjas'); await pg.waitForSelector('.acceso');
    console.log(nombre, 'tarjetas:', await pg.$$eval('#resumen-granjas .acceso', (l) => l.map((x) => x.innerText.replace(/\n/g, ' — ')).join(' | ')));
    const idLaRed = await pg.$$eval('#resumen-granjas .acceso', (l) => l.find((x) => x.textContent.includes('La Red')).getAttribute('href'));
    await pg.goto('http://local/' + idLaRed); await pg.waitForSelector('#detalle-granja table');
    console.log(nombre, 'filas La Red:', await pg.$$eval('#detalle-granja tbody tr', (r) => r.length));
    await pg.screenshot({ path: `${OUT}/${nombre}-granjas.png`, fullPage: true });
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
