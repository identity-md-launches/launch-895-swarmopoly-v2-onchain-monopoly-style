import { cp, mkdir, rm, readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const source=fileURLToPath(new URL('.',import.meta.url));
const output=path.resolve(source,'../dist');
// Explicit runtime allowlist: tooling, tests, caches and package archives never enter the export.
const assets=['index.html','rules.html','style.css','app.js','ui.js','config.json','abi.json','mark.svg','fonts/space-grotesk-latin.woff2','fonts/OFL.txt','vendor/ethers.min.js','vendor/ethers.LICENSE.md'];
const cfg=JSON.parse(await readFile(path.join(source,'config.json'),'utf8'));
if(cfg.chainId!==4663 || cfg.deploymentBlock!==82454371 || !cfg.game || !cfg.vault || !cfg.pot)throw new Error('Incomplete launch configuration');
await rm(output,{recursive:true,force:true});await mkdir(output,{recursive:true});
let bytes=0;
for(const asset of assets){const dest=path.join(output,asset);await mkdir(path.dirname(dest),{recursive:true});await cp(path.join(source,asset),dest);bytes+=(await stat(dest)).size;}
console.log(`Built dist/: ${assets.length} assets, ${bytes.toLocaleString()} bytes. Relative URLs, no CDN.`);
