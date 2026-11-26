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
    console.log(nombre, 'inicio contratos:', (await pg.$$eval('#avisos-inicio li', (l) => l.filter((x) => x.textContent.startsWith('Contratos')).map((x) => x.textContent))).join(' | '));
    await pg.goto('http://local/#/planta/contratos'); await pg.waitForSelector('#lista-contratos table');
    await pg.screenshot({ path: `${OUT}/${nombre}-contratos.png`, fullPage: true });
    await pg.click('#det-contrato summary');
    await pg.fill('[name=folio]', 'PRV-120'); await pg.selectOption('#form-contrato [name=proveedor_id]', '1');
    await pg.selectOption('#form-contrato [name=materia_prima_id]', '1'); await pg.fill('[name=toneladas]', '800'); await pg.fill('#form-contrato [name=precio]', '5.20');
    await pg.fill('[name=fecha_fin]', '2027-01-31');
    console.log(nombre, 'valor:', await pg.textContent('#resumen-contrato'));
    await pg.click('#form-contrato button[type=submit]'); await pg.waitForTimeout(300);
    console.log(nombre, 'contrato:', JSON.stringify(await pg.evaluate(() => window.__contrato)));
    await pg.click('[data-cerrar="1"]'); await pg.click('[data-cerrar="1"]'); await pg.waitForTimeout(200);
    console.log(nombre, 'estado:', JSON.stringify(await pg.evaluate(() => window.__estado)));
    await pg.goto('http://local/#/planta/llegadas'); await pg.waitForSelector('#form-llegada');
    await pg.selectOption('#form-llegada [name=proveedor_id]', '1');
    await pg.selectOption('#form-llegada [name=materia_prima_id]', '1'); await pg.waitForTimeout(200);
    console.log(nombre, 'opciones contrato:', await pg.$$eval('[name=contrato_id] option', (o) => o.map((x) => x.textContent).join(' || ')));
    await pg.selectOption('[name=contrato_id]', '9');   // el contrato PRV-120 recién creado
    console.log(nombre, 'TC visible (contrato en pesos, debe ser false):', await pg.isVisible('#campo-tc'));
    await pg.fill('#form-llegada [name=kg_neto]', '30000');
    console.log(nombre, 'precio:', await pg.inputValue('#form-llegada [name=precio_kg]'), '| ayuda:', await pg.textContent('#ayuda-contrato'));
    await pg.screenshot({ path: `${OUT}/${nombre}-llegada-contrato.png`, fullPage: true });
    await pg.click('#form-llegada button[type=submit]'); await pg.waitForTimeout(300);
    console.log(nombre, 'llegada:', JSON.stringify(await pg.evaluate(() => window.__guardada)));
    await pg.goto('http://local/#/planta/resumen'); await pg.waitForSelector('.capacidad');
    console.log(nombre, 'resumen alertas:', (await pg.textContent('.caja-alerta')).replace(/\s+/g, ' ').trim().slice(0, 300));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
