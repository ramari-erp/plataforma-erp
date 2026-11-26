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
    console.log(nombre, 'aviso:', (await pg.$$eval('#avisos-inicio li', (l) => l.map((x) => x.textContent).filter((t) => t.includes('pendiente')))).join(' / '));
    await pg.goto('http://local/#/planta/llegadas/pendientes'); await pg.waitForSelector('#historial table');
    console.log(nombre, 'filtro pendientes:', await pg.isChecked('[name=pendientes]'), '| filas:', await pg.$$eval('#historial tbody tr', (r) => r.length), '|', await pg.textContent('#historial .nota'));
    await pg.uncheck('[name=pendientes]'); await pg.waitForFunction(() => document.querySelectorAll('#historial tbody tr').length === 2);
    await pg.screenshot({ path: `${OUT}/${nombre}-llegadas-pendientes.png`, fullPage: true });
    await pg.click('[data-editar-llegada="1"]'); await pg.waitForSelector('form.editando'); await pg.waitForTimeout(200);
    console.log(nombre, 'editar:', await pg.textContent('#titulo-llegada'), '| contrato:', await pg.$eval('[name=contrato_id]', (s) => s.selectedOptions[0]?.textContent), '| TC:', await pg.inputValue('[name=tipo_cambio]'), '| provisional:', await pg.isChecked('[name=precio_provisional]'), '| ayuda:', await pg.textContent('#ayuda-contrato'));
    await pg.fill('#form-llegada [name=tipo_cambio]', '18.42'); await pg.fill('#form-llegada [name=factura]', 'F-101'); await pg.uncheck('#form-llegada [name=precio_provisional]');
    console.log(nombre, 'precio recalculado:', await pg.inputValue('#form-llegada [name=precio_kg]'));
    await pg.screenshot({ path: `${OUT}/${nombre}-llegada-editar.png`, fullPage: true });
    await pg.click('#form-llegada button[type=submit]'); await pg.waitForTimeout(300);
    console.log(nombre, 'editada:', JSON.stringify(await pg.evaluate(() => window.__editada)), '| título:', await pg.textContent('#titulo-llegada'));
    // Nueva llegada con provisional y sin factura
    await pg.selectOption('#form-llegada [name=materia_prima_id]', '1'); await pg.waitForTimeout(150);
    await pg.fill('#form-llegada [name=kg_neto]', '500000'); await pg.check('#form-llegada [name=precio_provisional]');
    console.log(nombre, 'ayuda excedente:', await pg.textContent('#ayuda-contrato'));
    await pg.fill('#form-llegada [name=precio_kg]', '5.12'); await pg.click('#form-llegada button[type=submit]'); await pg.waitForTimeout(300);
    console.log(nombre, 'aviso guardado:', await pg.$$eval('.aviso', (a) => a.map((x) => x.textContent).at(-1)));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
