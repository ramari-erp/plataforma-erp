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
    await pg.waitForSelector('#avisos-inicio li');
    console.log(nombre, 'aviso pesada:', (await pg.$$eval('#avisos-inicio li', (l) => l.map((x) => x.textContent).filter((t) => t.includes('pesada')))).join(''));
    await pg.goto('http://local/#/planta/produccion'); await pg.waitForSelector('#form-orden');
    await pg.selectOption('select[name=formula]', '5'); await pg.waitForSelector('#filas-ing tr');
    await pg.fill('[name=kg_solicitados]', '30000');
    console.log(nombre, 'resumen sin pesada:', await pg.textContent('#resumen-orden'));
    await pg.click('#form-orden button[type=submit]'); await pg.waitForSelector('[data-pesada]');
    console.log(nombre, 'enviada:', JSON.stringify(await pg.evaluate(() => { const o = window.__orden; return { kg: o.kg, kgReales: o.kgReales, ordenId: o.ordenId }; })));
    console.log(nombre, 'celda:', (await pg.textContent('.celda-pesada')).trim(), '|', await pg.textContent('#historial-ordenes .nota'));
    await pg.click('[data-pesada="1"]'); await pg.fill('.celda-pesada input', '29450'); await pg.click('[data-guardar-pesada]'); await pg.waitForTimeout(300);
    console.log(nombre, 'pesada:', JSON.stringify(await pg.evaluate(() => window.__pesada)), '| celda:', (await pg.textContent('.celda-pesada')).replace(/\s+/g, ' ').trim());
    await pg.screenshot({ path: `${OUT}/${nombre}-pesada-historial.png`, fullPage: true });
    await pg.click('[data-editar="1"]'); await pg.waitForSelector('form.editando');
    console.log(nombre, 'editar:', await pg.textContent('#titulo-orden'), '| sol', await pg.inputValue('[name=kg_solicitados]'), 'real', await pg.inputValue('[name=kg_reales]'), '| extras', await pg.$$eval('.fila-extra', (d) => d.length), '| sorgo kg/t', await pg.inputValue('#filas-ing tr[data-id="1"] [name=kgt]'));
    console.log(nombre, 'resumen edición:', await pg.textContent('#resumen-orden'));
    await pg.screenshot({ path: `${OUT}/${nombre}-pesada-editar.png`, fullPage: true });
    await pg.fill('[name=kg_reales]', '29500'); await pg.fill('[name=notas]', 'Corregida');
    await pg.click('#form-orden button[type=submit]'); await pg.waitForTimeout(400);
    console.log(nombre, 'edición enviada:', JSON.stringify(await pg.evaluate(() => { const o = window.__orden; return { kg: o.kg, kgReales: o.kgReales, ordenId: o.ordenId, extras: o.extras.length, notas: o.notas }; })), '| título:', await pg.textContent('#titulo-orden'));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
