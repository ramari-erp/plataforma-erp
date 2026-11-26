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
    console.log(nombre, 'aviso:', (await pg.$$eval('#avisos-inicio li', (l) => l.map((x) => x.textContent).filter((t) => t.includes('revisar')))).join(''));
    await pg.goto('http://local/#/planta/llegadas'); await pg.waitForSelector('#form-llegada');
    await pg.waitForFunction(() => document.querySelectorAll('[name=materia_prima_id] option').length > 2);
    await pg.selectOption('[name=materia_prima_id]', '__nueva_mp__'); await pg.waitForSelector('[name=mp_nombre]');
    await pg.fill('[name=mp_nombre]', 'pasta soya');
    console.log(nombre, 'parecidas:', await pg.textContent('#mp-parecidas'));
    await pg.screenshot({ path: `${OUT}/${nombre}-nueva-mp.png`, fullPage: true });
    await pg.click('[data-elegir]'); await pg.waitForTimeout(200);
    console.log(nombre, 'eligió existente:', await pg.$eval('[name=materia_prima_id]', (s) => s.selectedOptions[0].textContent), '| caja visible:', await pg.isVisible('#campo-nueva-mp'));
    await pg.selectOption('[name=materia_prima_id]', '__nueva_mp__'); await pg.waitForSelector('[name=mp_nombre]');
    await pg.fill('[name=mp_nombre]', 'gluten de maíz'); await pg.selectOption('[name=mp_grupo]', '1'); await pg.fill('[name=mp_presentacion]', 'saco 40 kg');
    await pg.press('[name=mp_presentacion]', 'Enter'); await pg.waitForTimeout(300);
    console.log(nombre, 'creada:', JSON.stringify(await pg.evaluate(() => window.__nuevaMp)), '| elegida:', await pg.$eval('[name=materia_prima_id]', (s) => s.selectedOptions[0].textContent), '| llegada enviada?', await pg.evaluate(() => !!window.__guardada));
    await pg.goto('http://local/#/planta/materias'); await pg.waitForSelector('#lista-mp table');
    console.log(nombre, 'filtro:', await pg.inputValue('[name=ver]'), '| filas:', await pg.$$eval('#lista-mp tbody tr', (r) => r.length));
    await pg.fill('#lista-mp tr[data-id="99"] [name=minimo]', '2000'); await pg.check('#lista-mp tr[data-id="99"] [name=contrato]');
    await pg.screenshot({ path: `${OUT}/${nombre}-materias.png`, fullPage: true });
    await pg.click('#lista-mp tr[data-id="99"] [data-guardar]'); await pg.waitForTimeout(200);
    console.log(nombre, 'actualizada:', JSON.stringify(await pg.evaluate(() => window.__actualizada)));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
