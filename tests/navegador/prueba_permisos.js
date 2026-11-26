const { chromium } = require('playwright'); const fs = require('fs');
const path = require('path'); const os = require('os');
const S = __dirname, R = path.resolve(__dirname, '../..'), OUT = process.env.SALIDA || os.tmpdir();
const txt = async (pg, s) => (await pg.textContent(s)).replace(/\s+/g, ' ').trim();
(async () => {
  const b = await chromium.launch();
  for (const [nombre, vp] of [['escritorio', { width: 1280, height: 900 }], ['celular', { width: 390, height: 844 }]]) {
    // 1) Capturista solo de ventas de huevo
    let pg = await b.newPage({ viewport: vp }); const errores = [];
    pg.on('pageerror', (e) => errores.push(e.message)); pg.on('console', (m) => m.type() === 'error' && errores.push(m.text()));
    await pg.addInitScript(() => { window.__perfilPrueba = { id: 'h', nombre: 'Lupita', rol: 'capturista', activo: true, modulos: ['ventas_huevo'], captura: ['ventas_huevo'] }; });
    await pg.route('http://local/**', (r) => { let ruta = new URL(r.request().url()).pathname; if (ruta === '/') ruta = '/index.html';
      const a = ruta === '/app/api.js' ? `${S}/api_falsa.js` : R + ruta;
      r.fulfill({ body: fs.readFileSync(a), contentType: a.endsWith('.js') ? 'text/javascript' : a.endsWith('.css') ? 'text/css' : 'text/html' }); });
    await pg.goto('http://local/'); await pg.fill('input[name=email]', 'a@b.c'); await pg.fill('input[name=password]', 'bien'); await pg.click('button[type=submit]');
    await pg.waitForSelector('.accesos');
    console.log(nombre, 'menú:', await pg.$$eval('#menu a', (x) => x.map((a) => a.textContent.trim()).join(' | ')));
    console.log(nombre, 'inicio:', await txt(pg, '#contenido'));
    await pg.goto('http://local/#/planta/resumen'); await pg.waitForTimeout(300);
    console.log(nombre, 'a planta → título:', await txt(pg, '#contenido h1'));
    await pg.goto('http://local/#/ventas/cerdo'); await pg.waitForSelector('#form-venta');
    console.log(nombre, 'ventas/cerdo → ', await txt(pg, '#titulo-venta'), '| pestañas:', await pg.$$eval('.pestanas a', (x) => x.length));
    console.log(nombre, 'errores:', errores);
    await pg.close();
    // 2) Administrador: formulario de usuarios
    pg = await b.newPage({ viewport: vp }); const err2 = [];
    pg.on('pageerror', (e) => err2.push(e.message)); pg.on('console', (m) => m.type() === 'error' && err2.push(m.text()));
    await pg.route('http://local/**', (r) => { let ruta = new URL(r.request().url()).pathname; if (ruta === '/') ruta = '/index.html';
      const a = ruta === '/app/api.js' ? `${S}/api_falsa.js` : R + ruta;
      r.fulfill({ body: fs.readFileSync(a), contentType: a.endsWith('.js') ? 'text/javascript' : a.endsWith('.css') ? 'text/css' : 'text/html' }); });
    await pg.goto('http://local/'); await pg.fill('input[name=email]', 'a@b.c'); await pg.fill('input[name=password]', 'bien'); await pg.click('button[type=submit]');
    await pg.waitForSelector('#avisos-inicio');
    await pg.goto('http://local/#/usuarios'); await pg.waitForSelector('[data-permiso="ventas_huevo"]');
    await pg.fill('#form-usuario [name=email]', 'lupita@x.com'); await pg.fill('#form-usuario [name=nombre]', 'Lupita');
    await pg.selectOption('[data-permiso="ventas_huevo"]', 'capturar'); await pg.selectOption('[data-permiso="cobranza"]', 'ver');
    await pg.screenshot({ path: `${OUT}/${nombre}-usuarios.png`, fullPage: true });
    await pg.click('#form-usuario button[type=submit]'); await pg.waitForTimeout(200);
    console.log(nombre, 'usuario enviado:', JSON.stringify(await pg.evaluate(() => window.__usuario)));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll:', ancho > vp.width ? `SÍ ${ancho}` : 'no', 'errores:', err2);
    await pg.close();
  }
  await b.close();
})();
