// Packs PNGs into a Windows .ico, for the NSIS installer's own icon.
// (scripts/patch-win-icon.mjs does the same internally for the game exe, but
// writes the result into a PE resource table rather than to a file.)
//
//   node scripts/png-to-ico.mjs <out.ico> <png> [<png>...]
import fs from "node:fs";
import pngToIco from "png-to-ico";

const [, , output, ...pngs] = process.argv;
if (!output || pngs.length === 0) {
  console.error("usage: png-to-ico.mjs <out.ico> <png> [<png>...]");
  process.exit(2);
}

fs.writeFileSync(output, await pngToIco(pngs));
console.log(`wrote ${output} (${pngs.length} sizes)`);
