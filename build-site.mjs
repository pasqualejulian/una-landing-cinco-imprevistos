import {build} from 'esbuild';
import {nodeModulesPolyfillPlugin} from 'esbuild-plugins-node-modules-polyfill';
import {cp,mkdir} from 'node:fs/promises';
await mkdir('dist',{recursive:true});
await cp('game-export','dist',{recursive:true});
await build({entryPoints:['src/browser.mjs'],bundle:true,format:'iife',globalName:'GitBrowser',platform:'browser',outfile:'dist/git-browser.js',minify:true,plugins:[nodeModulesPolyfillPlugin({globals:{process:true,Buffer:true}})]});
console.log('Static game ready in dist/');
