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
    // HUEVO
    await pg.goto('http://local/#/ventas/huevo'); await pg.waitForSelector('#form-venta'); await pg.waitForSelector('#historial-ventas table');
    await pg.waitForFunction(() => document.querySelectorAll('#form-venta [name=cliente] option').length > 2);
    await pg.selectOption('#form-venta [name=cliente]', '1');
    console.log(nombre, 'RFC:', await pg.textContent('#rfc-cliente'));
     await pg.selectOption('[name=empresa]', '1');
    await pg.selectOption('[name=forma_pago]', 'credito'); await pg.fill('[name=anticipo]', '100000'); await pg.fill('#form-venta [name=destino_ciudad]', 'Monterrey'); await pg.dispatchEvent('#form-venta [name=destino_ciudad]', 'change'); console.log(nombre, 'destino sugerido:', await pg.inputValue('[name=destino_estado]'), await pg.inputValue('[name=aumento_centavos_kg]'), '|', await pg.textContent('#ayuda-aumento')); await pg.fill('[name=destino_colonia]', 'San Nicolás'); await pg.fill('[name=aumento_centavos_kg]', '45');
    const r = '#renglones-venta tr';
    await pg.selectOption(`${r} >> nth=0 >> [name=granja]`, '3'); await pg.selectOption(`${r} >> nth=0 >> [name=calidad]`, 'Línea');
    await pg.fill(`${r} >> nth=0 >> [name=cantidad]`, '300'); await pg.fill(`${r} >> nth=0 >> [name=precio]`, '28.5');
    await pg.click('#btn-renglon-venta'); await pg.selectOption(`${r} >> nth=1 >> [name=calidad]`, 'Sucio');
    await pg.fill(`${r} >> nth=1 >> [name=cantidad]`, '50'); await pg.fill(`${r} >> nth=1 >> [name=precio]`, '24');
    await pg.fill('[name=kg_bascula]', '7850');
    await pg.fill('#facturas-venta [name=f_numero]', 'A-101'); await pg.fill('#facturas-venta [name=f_monto]', '150000');
    await pg.click('#btn-factura'); await pg.fill('#facturas-venta tr:nth-child(2) [name=f_numero]', 'B-55'); await pg.selectOption('#facturas-venta tr:nth-child(2) [name=f_empresa]', '2'); await pg.fill('#facturas-venta tr:nth-child(2) [name=f_monto]', '40000');
    console.log(nombre, 'kg repartidos:', await pg.$$eval('.kg-repartido', (x) => x.map((e) => e.textContent).join(' / ')));
    console.log(nombre, 'cuenta visible sin anticipo?', await pg.isVisible('#zona-cuenta [name=cuenta_id]'));
    await pg.selectOption('#zona-cuenta [name=cuenta_id]', '__nueva__'); await pg.fill('[name=nb_nombre]', 'Banorte maront 9876'); await pg.fill('[name=nb_banco]', 'Banorte'); await pg.click('[data-nb-guardar]'); await pg.waitForTimeout(200);
    console.log(nombre, 'cuenta nueva:', JSON.stringify(await pg.evaluate(() => window.__cuenta)), await pg.inputValue('#zona-cuenta [name=cuenta_id]'));
    await pg.fill('[name=descuento]', '500'); await pg.fill('[name=motivo_descuento]', '5 cajas rotas');
    console.log(nombre, 'renglón 1:', (await pg.textContent(`${r} >> nth=0`)).replace(/\s+/g, ' ').trim().slice(-60));
    console.log(nombre, 'totales:', (await pg.textContent('#totales-venta')).replace(/\s+/g, ' ').trim());
    await pg.screenshot({ path: `${OUT}/${nombre}-venta-huevo.png`, fullPage: true });
    await pg.click('#form-venta button[type=submit]'); await pg.waitForTimeout(300);
    console.log(nombre, 'enviada:', JSON.stringify(await pg.evaluate(() => window.__venta)));
    await pg.click('[data-ver-venta="1"]'); await pg.waitForSelector('#historial-ventas .tabla-detalle');
    console.log(nombre, 'historial:', (await pg.textContent('#historial-ventas')).replace(/\s+/g, ' ').slice(0, 520));
    await pg.click('[data-editar-venta="1"]'); await pg.waitForSelector('form.editando'); await pg.waitForTimeout(200);
    console.log(nombre, 'editar facturas:', await pg.$$eval('#facturas-venta [name=f_numero]', (x) => x.map((e) => e.value).join(',')), 'bascula', await pg.inputValue('[name=kg_bascula]'), await pg.$$eval('.kg-repartido', (x) => x.map((e) => e.textContent).join(' / ')));
    console.log(nombre, 'editar:', await pg.textContent('#titulo-venta'), '| anticipo', await pg.inputValue('[name=anticipo]'), '| renglones', await pg.$$eval('#renglones-venta tr', (x) => x.length));
    // CERDO con cliente nuevo
    await pg.goto('http://local/#/ventas/cerdo'); await pg.waitForSelector('#form-venta [name=muertos]');
    await pg.waitForFunction(() => document.querySelectorAll('#form-venta [name=cliente] option').length > 2);
    await pg.selectOption('#form-venta [name=cliente]', '__nuevo__'); await pg.fill('[name=nc_nombre]', 'huevera del'); 
    console.log(nombre, 'parecidos cliente:', await pg.textContent('#nc-parecidos'));
    await pg.fill('[name=nc_nombre]', 'Carnes Selectas'); await pg.fill('[name=nc_rfc]', 'cse900101aa1'); await pg.click('#btn-nc'); await pg.waitForTimeout(200);
    console.log(nombre, 'cliente nuevo:', JSON.stringify(await pg.evaluate(() => window.__cliente)), await pg.$eval('#form-venta [name=cliente]', (s) => s.selectedOptions[0].textContent));
    console.log(nombre, 'calidades cerdo:', await pg.$$eval(`${r} >> nth=0 >> [name=calidad] option`, (o) => o.map((x) => x.textContent).join(',')).catch(async () => (await pg.$$eval('#renglones-venta [name=calidad] option', (o) => o.map((x) => x.textContent).join(',')))));
    // BORREGO: calidad libre con sugerencias
    await pg.goto('http://local/#/ventas/borrego'); await pg.waitForSelector('#form-venta');
    await pg.waitForFunction(() => document.querySelector('#renglones-venta input[name=calidad]'));
    console.log(nombre, 'borrego calidad libre:', await pg.$eval('#renglones-venta [name=calidad]', (i) => i.tagName + ' list=' + i.getAttribute('list')), '| sugerencias:', await pg.$$eval('datalist option', (o) => o.map((x) => x.value).join(',')));
    const ancho = await pg.evaluate(() => document.documentElement.scrollWidth);
    console.log(nombre, 'scroll horizontal:', ancho > vp.width ? `SÍ (${ancho})` : 'no', 'errores:', errores);
    await pg.close();
  }
  await b.close();
})();
