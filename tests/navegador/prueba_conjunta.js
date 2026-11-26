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
    // --- Pesada conjunta
    await pg.goto('http://local/#/planta/produccion'); await pg.waitForSelector('#historial-ordenes table');
    await pg.check('[data-sel="11"]'); await pg.check('[data-sel="12"]');
    await pg.click('#barra-pesada [name=kg_total]'); await pg.keyboard.type('16000.5', { delay: 20 }); console.log(nombre, 'tecleado:', await pg.inputValue('#barra-pesada [name=kg_total]'), '|', (await pg.textContent('#barra-pesada .lista-reparto')).trim());
    console.log(nombre, 'barra:', (await pg.textContent('#barra-pesada')).replace(/\s+/g, ' ').trim());
    await pg.screenshot({ path: `${OUT}/${nombre}-pesada-conjunta.png`, fullPage: true });
    await pg.click('[data-registrar-conjunta]'); await pg.waitForTimeout(400);
    console.log(nombre, 'enviada:', JSON.stringify(await pg.evaluate(() => window.__conjunta)), '| celda 11:', (await pg.textContent('tr[data-orden="11"] .celda-pesada')).replace(/\s+/g, ' ').trim());
    await pg.click('tr[data-orden="11"] [data-corregir-conjunta]'); await pg.waitForTimeout(300);
    console.log(nombre, 'corregir:', (await pg.textContent('#barra-pesada p')).trim(), '| total prellenado:', await pg.inputValue('#barra-pesada [name=kg_total]'), '| marcadas:', await pg.$$eval('[data-sel]:checked', (c) => c.map((x) => x.dataset.sel).join(',')));
    await pg.click('[data-cancelar-conjunta]');
    // --- Nota con varios productos
    await pg.goto('http://local/#/planta/llegadas'); await pg.waitForSelector('#form-llegada');
    await pg.waitForFunction(() => document.querySelectorAll('#form-llegada [name=materia_prima_id] option').length > 2);
    await pg.check('[name=modo-llegada][value=nota]');
    console.log(nombre, 'modo nota visible:', await pg.isVisible('#form-nota'), '| form simple oculto:', !(await pg.isVisible('#form-llegada')));
    await pg.selectOption('#form-nota [name=proveedor_id]', '1'); await pg.fill('#form-nota [name=folio]', 'N-501');
    const r = '#renglones-nota tr';
    await pg.selectOption(`${r} >> nth=0 >> [name=mp]`, '5'); await pg.fill(`${r} >> nth=0 >> [name=kg]`, '500'); await pg.fill(`${r} >> nth=0 >> [name=precio]`, '20');
    await pg.selectOption(`${r} >> nth=1 >> [name=mp]`, '7'); await pg.fill(`${r} >> nth=1 >> [name=kg]`, '400'); await pg.fill(`${r} >> nth=1 >> [name=precio]`, '0.44');
    await pg.click('#btn-renglon'); await pg.selectOption(`${r} >> nth=2 >> [name=mp]`, '3'); await pg.fill(`${r} >> nth=2 >> [name=kg]`, '100'); await pg.fill(`${r} >> nth=2 >> [name=precio]`, '52.89');
    await pg.fill('#form-nota [name=kg_bascula]', '1010');
    console.log(nombre, 'resumen nota:', await pg.textContent('#nota-resumen'), '| total:', await pg.textContent('#nota-importe'));
    await pg.screenshot({ path: `${OUT}/${nombre}-nota-productos.png`, fullPage: true });
    await pg.click('#form-nota button[type=submit]'); await pg.waitForTimeout(400);
    console.log(nombre, 'nota enviada:', JSON.stringify(await pg.evaluate(() => window.__nota)));
    console.log(nombre, 'aviso:', await pg.$$eval('.aviso', (a) => a.map((x) => x.textContent).at(-1)));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
