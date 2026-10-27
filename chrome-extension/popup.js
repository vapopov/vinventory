const $ = id => document.getElementById(id);
const keys = ['number', 'manufacturer', 'supplier', 'spn', 'description', 'package', 'value', 'tolerance', 'datasheet', 'price'];
const titles = ['Part number', 'Manufacturer', 'Supplier', 'Supplier part number', 'Description', 'Package', 'Value', 'Tolerance', 'Datasheet URL', 'Supplier unit price'];
let base = '', loaded = false, imported = false;
let scrapedPrices = '', singleUnitPrice = '', manualPrice = false;
function updatePrice() {
  if (!manualPrice) $('price').value = priceForQuantity(scrapedPrices, Number($('quantity').value), singleUnitPrice);
}
for (const [i, key] of keys.entries()) {
  const label = document.createElement('label'); label.textContent = titles[i];
  const input = document.createElement('input'); input.id = key; input.required = key === 'number';
  if (key === 'datasheet') input.type = 'url';
  label.append(input); $('fields').append(label);
}
$('quantity').addEventListener('input', updatePrice);
$('price').addEventListener('input', () => { manualPrice = true; });
const status = message => { $('status').textContent = message; };
$('purchase').addEventListener('invalid', event => { status(`Check ${event.target.closest('label')?.firstChild?.textContent || 'the highlighted field'}: ${event.target.validationMessage}`); }, true);
function endpoint() {
  const url = new URL($('address').value.trim());
  const port = Number($('port').value);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.pathname !== '/' || url.search || url.hash || !Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Enter an HTTP address without a path and a port from 1–65535.');
  url.port = String(port); return url.origin;
}
async function permission(url) {
  const origin = new URL(url).origin + '/*';
  if (!await chrome.permissions.request({origins: [origin]})) throw new Error('Host access was not granted.');
}
async function api(path, body) {
  const response = await fetch(base + path, {method: body ? 'POST' : 'GET', headers: body ? {'Content-Type': 'application/json'} : {}, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(12000)});
  const data = await response.json();
  if (!response.ok) {
    if (body?.imageBase64 && /Use part, quantity, and assignments fields/.test(data.error || '')) throw new Error('The running app is outdated. Rebuild and relaunch BOM Inventory to enable photo imports.');
    throw new Error(data.error || `API returned ${response.status}`);
  }
  return data;
}
async function loadProjects() {
  loaded = false; $('submit').disabled = true;
  const projects = await api('/v1/projects');
  if (!Array.isArray(projects)) throw new Error('Unexpected projects response.');
  $('projects').replaceChildren();
  for (const project of projects) {
    const row = document.createElement('label'); row.className = 'project';
    const check = document.createElement('input'); check.type = 'checkbox'; check.dataset.project = project.name;
    const name = document.createElement('span'); name.textContent = project.name; name.title = project.description || '';
    const count = document.createElement('input'); count.type = 'number'; count.min = '1'; count.step = '1'; count.value = '1'; count.disabled = true; count.setAttribute('aria-label', `Quantity for ${project.name}`);
    check.addEventListener('change', () => { count.disabled = !check.checked; });
    row.append(check, name, count); $('projects').append(row);
  }
  if (!projects.length) $('projects').textContent = 'No projects yet. You can add an unallocated purchase.';
  loaded = true; $('submit').disabled = false;
}
$('connect').addEventListener('click', async () => {
  try {
    const next = endpoint(); await permission(next); base = next;
    await chrome.storage.local.set({address: $('address').value.trim(), port: $('port').value});
    await loadProjects(); status('Connected. Projects loaded.');
  } catch (error) { status(`Connection failed: ${error.message}`); }
});
for (const id of ['address', 'port']) $(id).addEventListener('input', () => { loaded = false; $('submit').disabled = true; });
$('scrape').addEventListener('click', async () => {
  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    const host = new URL(tab.url).hostname;
    const isLCSC = /(^|\.)lcsc\.com$/i.test(host);
    const isDigiKey = /(^|\.)digikey\.(?:com|ca|co\.uk|de|fr|jp|cn|hk|com\.au|co\.nz|in|sg|tw|kr|nl|it|es|se|dk|no|fi|at|be|ch|ie|co\.il|co\.za|com\.mx)$/i.test(host);
    if (!isLCSC && !isDigiKey) throw new Error('Open an LCSC or DigiKey product detail page first.');
    const [result] = await chrome.scripting.executeScript({target: {tabId: tab.id}, func: isLCSC ? scrapeLCSC : scrapeDigiKey});
    if (!result?.result) throw new Error('Could not read this page.');
    for (const key of [...keys, 'image']) $(key).value = result.result[key] || '';
    scrapedPrices = result.result.price || ''; singleUnitPrice = result.result.singleUnitPrice || ''; manualPrice = false; updatePrice();
    imported = false; $('submit').textContent = 'Add to Purchase';
    $('preview').hidden = true;
    status('Product read. Review the fields, photo URL, datasheet, and quantities before adding.');
  } catch (error) { status(error.message); }
});
async function imageBase64(url) {
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error('Image must use HTTP or HTTPS.');
  const response = await fetch(url, {signal: AbortSignal.timeout(15000), credentials: 'omit'});
  if (!response.ok) throw new Error(`Image download failed (${response.status}).`);
  const blob = await response.blob();
  if (!blob.type.startsWith('image/') || blob.size > 10_000_000) throw new Error('Image must be an image smaller than 10 MB.');
  const bitmap = await createImageBitmap(blob);
  try {
    const scale = Math.min(1, 800 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement('canvas'); canvas.width = Math.max(1, Math.round(bitmap.width * scale)); canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const ctx = canvas.getContext('2d'); ctx.fillStyle = 'white'; ctx.fillRect(0, 0, canvas.width, canvas.height); ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const data = canvas.toDataURL('image/jpeg', .85);
    if (data.length > 800000) throw new Error('Image is too large after resizing.');
    $('preview').src = data; $('preview').hidden = false;
    return data.split(',')[1];
  } finally { bitmap.close(); }
}
$('purchase').addEventListener('submit', async event => {
  event.preventDefault();
  if (!loaded || imported) return;
  $('submit').disabled = true;
  let sending = false;
  try {
    status('Preparing purchase… Keep this popup open until finished.');
    const imageURL = $('image').value.trim();
    // Ask while the submit click still supplies a user gesture.
    if (imageURL) await permission(imageURL);
    const quantity = Number($('quantity').value);
    if (!Number.isSafeInteger(quantity) || quantity < 1) throw new Error('Purchase quantity must be a positive integer.');
    const assignments = [...document.querySelectorAll('.project')].filter(row => row.children[0].checked).map(row => ({project: row.children[0].dataset.project, quantity: Number(row.children[2].value)}));
    if (assignments.some(a => !Number.isSafeInteger(a.quantity) || a.quantity < 1) || assignments.reduce((n, a) => n + a.quantity, 0) > quantity) throw new Error('Project quantities must be positive integers and their total cannot exceed purchase quantity.');
    const part = Object.fromEntries(keys.filter(key => key !== 'price').map(key => [key, $(key).value.trim()]));
    updatePrice();
    const price = $('price').value.trim();
    if (price) part.customFields = {[`${part.supplier || 'Supplier'} Price`]: price};
    if (!part.number) throw new Error('Part number is required.');
    const payload = {part, quantity, assignments};
    status('Preparing purchase… Keep this popup open until finished.');
    if (imageURL) payload.imageBase64 = await imageBase64(imageURL);
    sending = true;
    status('Saving purchase to BOM Inventory…');
    const saved = await api('/v1/purchases', payload);
    if (!saved?.id) throw new Error('The API did not confirm the saved purchase.');
    imported = true; $('submit').textContent = 'Added'; status('Added to Purchase with selected project allocations.');
  } catch (error) { status(`${error.message}${sending ? '\nIf the connection was interrupted, check Purchase before retrying to avoid duplicates.' : '\nNothing was submitted.'}`); }
  finally { $('submit').disabled = imported || !loaded; }
});
(async () => {
  const saved = await chrome.storage.local.get({address: 'http://127.0.0.1', port: '8080'});
  $('address').value = saved.address; $('port').value = saved.port;
  try {
    base = endpoint();
    if (await chrome.permissions.contains({origins: [base + '/*']})) { await loadProjects(); status('Projects loaded. Read an LCSC or DigiKey product to begin.'); }
    else status('Open API settings and connect to your local app.');
  } catch (error) { status(`Start the local API and connect: ${error.message}`); }
})();
