// Pure presentation helpers. All token metadata is inserted as text, never HTML.
export const names = ['GO','Mediterranean Avenue','Community Chest','Baltic Avenue','Income Tax','Reading Railroad','Oriental Avenue','Chance','Vermont Avenue','Connecticut Avenue','Jail / Just Visiting','St. Charles Place','Electric Company','States Avenue','Virginia Avenue','Pennsylvania Railroad','St. James Place','Community Chest','Tennessee Avenue','New York Avenue','Free Parking','Kentucky Avenue','Chance','Indiana Avenue','Illinois Avenue','B. & O. Railroad','Atlantic Avenue','Ventnor Avenue','Water Works','Marvin Gardens','Go to Jail','Pacific Avenue','North Carolina Avenue','Community Chest','Pennsylvania Avenue','Short Line','Chance','Park Place','Luxury Tax','Boardwalk'];
export const special = new Set([0,2,4,7,10,17,20,22,30,33,36,38]);
export const tiers = ['#b6a2e2','#85d8ec','#e987c3','#f6b37b','#f38686','#e9d47c','#a6d493','#969ef3'];
/** @param {number} slot */
export function boardPosition(slot) {
  if (slot <= 10) return [11, 11 - slot];
  if (slot <= 20) return [21 - slot, 1];
  if (slot <= 30) return [1, slot - 19];
  return [slot - 29, 11];
}
/** @param {string} address */
export const short = address => `${address.slice(0,6)}…${address.slice(-4)}`;
/** @param {string | undefined} a @param {string | undefined} b */
export const equal = (a,b) => !!a && !!b && a.toLowerCase() === b.toLowerCase();
/** @param {string} address */
export function identity(address) {
  let hash = 0;
  for (const c of address.toLowerCase()) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  return { shape: ['imp','seat','kite','orb','crown','bolt'][hash % 6], color: tiers[(hash >>> 3) % 8], label: short(address.toLowerCase()) };
}
/** @param {number} start @param {number} die1 @param {number} die2 @param {number} final */
export function hopPath(start, die1, die2, final) {
  const path = Array.from({length:die1+die2},(_,i)=>(start+i+1)%40);
  if (path.at(-1) !== final) path.push(final); // Chance / Go to Jail relocation.
  return path;
}
/** @param {number} seconds */
export function countdown(seconds) {
  const n = Math.max(0, Math.floor(seconds));
  const d = Math.floor(n/86400), h = Math.floor(n%86400/3600), m = Math.floor(n%3600/60), s=n%60;
  return `${d ? `${d}d ` : ''}${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
}
const paths = {
  swarm:'M5 22V9l7 5 4-8 4 8 7-5v13l-5 5H10z M10 19h3m6 0h3 M13 24h6',
  imp:'M6 25V8l7 5 3-7 3 7 7-5v17l-10 3z M11 20h2m6 0h2',
  seat:'M8 7h16v13H8z M5 20h22v5H5z M8 25v4m16-4v4',
  kite:'M16 3 28 16 16 29 4 16z M16 3v26M4 16h24',
  orb:'M16 5a11 11 0 1 0 0 22 11 11 0 0 0 0-22 M5 16h22M16 5c-8 7-8 15 0 22 8-7 8-15 0-22',
  crown:'M4 10l7 6 5-10 5 10 7-6-4 16H8z M10 22h12',
  bolt:'M18 3 6 18h9l-1 11 12-16h-9z',
  go:'M5 16h22M19 8l8 8-8 8 M5 8v16',
  jail:'M6 27V6h20v21M11 6v21m10-21v21M6 12h20M4 27h24',
  parking:'M7 27V5h11a7 7 0 0 1 0 14H7 M12 10h6a2 2 0 0 1 0 4h-6z',
  gojail:'M3 6h12v20H3M7 6v20m4-20v20M18 16h11m-5-5 5 5-5 5',
  chance:'M12 10a5 5 0 1 1 7 5c-3 1-3 3-3 5M16 24v1M5 3h22v26H5z',
  chest:'M5 11h22v16H5z M8 11V6h16v5M5 17h22M14 15h4v5h-4z',
  tax:'M5 9 16 3l11 6M5 12h22M8 12v11m8-11v11m8-11v11M4 27h24',
  house:'M4 15 16 5l12 10M8 12v15h16V12M14 27v-8h4v8',
  hotel:'M7 28V4h18v24M12 9h2m4 0h2m-8 6h2m4 0h2m-8 6h2m4 0h2',
};
/** @param {string} name @param {string} [className] */
export function icon(name, className='') {
  return `<svg class="icon ${className}" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${paths[name] || paths.swarm}"/></svg>`;
}
/** @param {number} slot */
export function specialIcon(slot) { return ({0:'go',10:'jail',20:'parking',30:'gojail',2:'chest',17:'chest',33:'chest',4:'tax',38:'tax'})[slot] || 'chance'; }
/** @param {number} value */
export function dieFace(value) {
  const positions = {1:[5],2:[1,9],3:[1,5,9],4:[1,3,7,9],5:[1,3,5,7,9],6:[1,3,4,6,7,9]};
  return Array.from({length:9},(_,i)=>`<i class="pip${positions[value].includes(i+1)?' on':''}"></i>`).join('');
}
/** @param {number} value */
export function die(value) {
  return `<div class="die" data-value="${value}">${[1,2,3,4,5,6].map(n=>`<div class="face face-${n}">${dieFace(n)}</div>`).join('')}</div>`;
}
