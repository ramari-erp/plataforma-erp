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
    await pg.goto('http://local/#/planta/contratos'); await pg.waitForSelector('#lista-contratos table');
    console.log(nombre, 'vigentes:', await pg.$$eval('#lista-contratos tbody tr', (r) => r.length), '|', await pg.textContent('#totales-contratos'));
    await pg.selectOption('[name=ver]', 'terminados'); await pg.waitForTimeout(150);
    console.log(nombre, 'terminados:', await pg.$$eval('#lista-contratos tbody tr', (r) => r.map((x) => x.cells[0].textContent.trim()).join(', ')), '|', await pg.textContent('#totales-contratos'));
    await pg.selectOption('[name=ver]', 'todos'); await pg.waitForTimeout(150);
    console.log(nombre, 'proveedores filtro:', await pg.$$eval('#filtros-contratos [name=proveedor] option', (o) => o.map((x) => x.textContent).join(', ')));
    await pg.selectOption('#filtros-contratos [name=proveedor]', '1'); await pg.waitForTimeout(150);
    console.log(nombre, 'LANDUS todos:', await pg.$$eval('#lista-contratos tbody tr', (r) => r.length), '|', await pg.textContent('#totales-contratos'));
    await pg.screenshot({ path: `${OUT}/${nombre}-contratos-filtro.png`, fullPage: true });
    await pg.click('#det-contrato summary'); await pg.fill('#form-contrato [name=folio]', 'prv-101'); await pg.waitForTimeout(500);
    console.log(nombre, 'ayuda folio:', await pg.textContent('#ayuda-folio'));
    await pg.goto('http://local/#/planta/llegadas'); await pg.waitForSelector('#form-llegada');
    await pg.fill('#form-llegada [name=boleta]', '8812'); await pg.fill('#form-llegada [name=factura]', 'A-123'); await pg.waitForTimeout(500);
    console.log(nombre, 'boleta:', await pg.textContent('#ayuda-boleta'), '| factura:', await pg.textContent('#ayuda-factura'));
    await pg.selectOption('#form-llegada [name=materia_prima_id]', '1'); await pg.fill('#form-llegada [name=kg_neto]', '1000'); await pg.fill('#form-llegada [name=precio_kg]', '5');
    await pg.evaluate(() => { window.__guardada = null; });
    await pg.click('#form-llegada button[type=submit]'); await pg.waitForTimeout(400);
    console.log(nombre, 'bloqueó guardado:', await pg.evaluate(() => window.__guardada === null), '|', await pg.$$eval('.aviso', (a) => a.map((x) => x.textContent).at(-1)));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
