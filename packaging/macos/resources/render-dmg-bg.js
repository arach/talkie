#!/usr/bin/env node
/**
 * Renders dmg-background.html to PNG at 1x and 2x resolutions
 * Usage: npx puppeteer ./render-dmg-bg.js
 */

const puppeteer = require('puppeteer');
const path = require('path');

async function render() {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const htmlPath = path.join(__dirname, 'dmg-background.html');
  const fileUrl = `file://${htmlPath}`;

  // Render 1x version (520x340)
  console.log('Rendering 1x version...');
  const page1x = await browser.newPage();
  await page1x.setViewport({ width: 520, height: 340, deviceScaleFactor: 1 });
  await page1x.goto(fileUrl, { waitUntil: 'networkidle0' });
  await page1x.screenshot({
    path: path.join(__dirname, 'dmg-background.png'),
    type: 'png',
    omitBackground: false
  });
  await page1x.close();
  console.log('  -> dmg-background.png');

  // Render 2x version (1040x680)
  console.log('Rendering 2x version...');
  const page2x = await browser.newPage();
  await page2x.setViewport({ width: 520, height: 340, deviceScaleFactor: 2 });
  await page2x.goto(fileUrl, { waitUntil: 'networkidle0' });
  await page2x.screenshot({
    path: path.join(__dirname, 'dmg-background@2x.png'),
    type: 'png',
    omitBackground: false
  });
  await page2x.close();
  console.log('  -> dmg-background@2x.png');

  await browser.close();
  console.log('Done!');
}

render().catch(console.error);
