const { chromium } = require('playwright'); const fs = require('fs');
const path = require('path'); const os = require('os');
const S = __dirname, R = path.resolve(__dirname, '../..'), OUT = process.env.SALIDA || os.tmpdir();
(async () => {
  const b = await chromium.launch();
  for (const [nombre, vp] of [['escritorio', { width: 1280, height: 900 }], ['celular', { width: 390, height: 844 }]]) {
    const pg = await b.newPage({ viewport: vp }); const errores = [];
    pg.on('pageerror', (e) => errores.push(e.message)); pg.on('console', (m) => m.type() === 'error' && errores.push(m.text()));
    await pg.route('http://local/**', (r) => { let ruta = new URL(r.request().url()).pathname; if (ruta === '/') ruta = '/index.html';
      const a = ruta === '/app/api.js' ? `${S}/api_falsa.js` : R + ruta;
      r.fulfill({ body: fs.readFileSync(a), contentType: a.endsWith('.js') ? 'text/javascript' : a.endsWith('.css') ? 'text/css' : 'text/html' }); });
    await pg.goto('http://local/'); await pg.fill('input[name=email]', 'a@b.c'); await pg.fill('input[name=password]', 'bien'); await pg.click('button[type=submit]');
    await pg.waitForSelector('#avisos-inicio');
    await pg.goto('http://local/#/planta/inventario'); await pg.waitForSelector('#form-arranque');
    await pg.fill('tr[data-id="1"] [name=kg]', '1000000'); await pg.fill('tr[data-id="2"] [name=kg]', '50000');
    await pg.fill('tr[data-id="3"] [name=kg]', '850'); await pg.fill('tr[data-id="3"] [name=costo]', '');
    console.log(nombre, 'resumen:', await pg.textContent('#resumen-arranque'));
    await pg.fill('[name=buscar]', 'soya'); console.log(nombre, 'filas visibles al buscar soya:', await pg.$$eval('#form-arranque tbody tr[data-id]:not(.oculto)', (r) => r.length));
    await pg.fill('[name=buscar]', '');
    await pg.screenshot({ path: `${OUT}/${nombre}-arranque.png`, fullPage: true });
    await pg.click('#form-arranque button[type=submit]');
    console.log(nombre, 'confirmación:', (await pg.textContent('#confirmar-arranque')).replace(/\s+/g, ' ').trim());
    await pg.click('#form-arranque button[type=submit]'); await pg.waitForSelector('#form-conteo');
    console.log(nombre, 'arranque enviado:', JSON.stringify(await pg.evaluate(() => window.__arranque)));
    await pg.fill('tr[data-id="1"] [name=fisico]', '2945000');
    console.log(nombre, 'dif sorgo:', await pg.textContent('#form-conteo tr[data-id="1"] .diferencia'), '|', await pg.textContent('#resumen-conteo'));
    await pg.screenshot({ path: `${OUT}/${nombre}-conteo.png`, fullPage: true });
    await pg.click('#form-conteo button[type=submit]'); await pg.waitForTimeout(400);
    console.log(nombre, 'conteo enviado:', JSON.stringify(await pg.evaluate(() => window.__conteo)), '| historial filas:', await pg.$$eval('#historial-conteos tbody tr', (r) => r.length));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
