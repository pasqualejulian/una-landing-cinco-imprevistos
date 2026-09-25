import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,join} from 'node:path';
import {tmpdir} from 'node:os';
import {execFileSync} from 'node:child_process';
await mkdir('qa',{recursive:true});
const browser=await chromium.launch({headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{
 window.audioProbe={contexts:[],analysers:[],peak:0};
 const connect=AudioNode.prototype.connect;
 AudioNode.prototype.connect=function(...args){
  const result=connect.apply(this,args);
  if(args[0]===this.context.destination && !window.audioProbe.contexts.includes(this.context)){
   const analyser=this.context.createAnalyser();analyser.fftSize=256;
   connect.call(this,analyser);audioProbe.contexts.push(this.context);audioProbe.analysers.push(analyser);
  }
  return result;
 };
 setInterval(()=>{for(const analyser of audioProbe.analysers){const data=new Float32Array(256);analyser.getFloatTimeDomainData(data);audioProbe.peak=Math.max(audioProbe.peak,...data.map(Math.abs));}},10);
});
const page=await context.newPage();
const errors=[],requests=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
page.on('request',r=>requests.push(r.url()));
const state=()=>page.evaluate(()=>OMG.snapshot());
const ui=()=>page.evaluate(()=>OMG.ui);
const checks=[];
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS '+label);};
const settle=()=>page.waitForTimeout(350);
const point=([x,y,w,h])=>[(x+(w||0)/2)*.75,(y+(h||0)/2)*.75+45];
async function clickRect(key){const d=await ui();await page.mouse.click(...point(d[key]));await settle();}
async function start(){await page.getByRole('button',{name:'Jugar con sonido'}).click({timeout:30000});await page.waitForFunction(()=>window.OMG?.ui);await page.waitForTimeout(800);}
async function drag(card,target){await page.waitForTimeout(650);const d=await ui();assert.ok(d.cards[card]);await page.mouse.move(...point(d.cards[card]));await page.waitForTimeout(120);await page.mouse.down();await page.waitForTimeout(100);await page.mouse.move(...point(Array.isArray(target)?target:d[target]),{steps:20});await page.mouse.up();await settle();}
async function command(text){await clickRect('input');await page.keyboard.type(text);await page.keyboard.press('Enter');await settle();}
const waitPhase=p=>page.waitForFunction(phase=>OMG.snapshot().phase===phase&&!OMG.ui.busy, p);
async function choose(index){await page.mouse.click(...point((await ui()).choices[index]));await waitPhase('add');await settle();}
async function next(){await clickRect('next');await settle();}
async function saveWithCards(message){await drag('add','file_target');await waitPhase('commit');await drag('commit','commit_target');await page.waitForFunction(()=>OMG.ui.message_visible);await page.keyboard.type(message);await page.keyboard.press('Enter');await waitPhase('done');await settle();}
try{
 await page.goto('http://127.0.0.1:4173/');await start();
 check((await state()).chapter===0&&(await state()).commits==='1','historia nueva desde un commit base');
 await page.waitForTimeout(1000);check(await page.evaluate(()=>audioProbe.contexts.some(c=>c.state==='running')&&audioProbe.peak>.001),'audio activo tras Jugar');
 await choose(0);const base=(await state()).head,instance=(await ui()).nodes[base].instance;
 await drag('add','commit_target');check(!(await state()).prepared,'carta en destino incorrecto no prepara');
 await drag('commit','commit_target');await page.keyboard.press('Escape');await settle();check((await state()).commits==='1','cancelar commit conserva historial');
 await saveWithCards('Mi primer hero');check((await state()).can_continue,'capítulo 1 habilita siguiente mensaje');
 check((await ui()).nodes[base].instance===instance,'conserva instancia del nodo inicial');
 const hero=(await state()).head;
 await next();await waitPhase('branch');check((await state()).head===hero,'capítulo 2 conserva timeline anterior');
 await drag('branch','commit_target');await waitPhase('checkout');check((await state()).branch==='main','crear rama no cambia HEAD');
 await drag('checkout','commit_target');await waitPhase('choose');check((await state()).branch==='experimento-wording','checkout mueve HEAD al experimento');
 await choose(1);await saveWithCards('Wording con menos trámite');const experiment=(await state()).head;
 check((await state()).refs.main===hero,'main conserva el hero mientras el wording vive en su rama');
 await page.screenshot({path:'qa/campaign-02-rama.png'});
 await page.reload();await start();check((await state()).chapter===1&&(await state()).head===experiment,'recarga retoma capítulo y rama completos');
 await next();await waitPhase('checkout');await drag('checkout','commit_target');await waitPhase('choose');
 check((await state()).preview.button==='Empezá ahora','volver a main recupera su preview');
 await choose(0);check((await state()).file==='styles.css','pedido urgente modifica CSS');
 await command('git add styles.css');await waitPhase('commit');await command('git commit -m "Pedido de las 18:57"');await waitPhase('done');const urgent=(await state()).head;
 check((await state()).refs['experimento-wording']===experiment,'pedido urgente no mueve rama de wording');
 await page.screenshot({path:'qa/campaign-03-dos-caminos.png'});
 await next();await waitPhase('merge');await drag('merge','commit_target');await waitPhase('done');const merged=await state();
 check(merged.preview.button==='Ver qué puedo crear'&&merged.preview.color==='#d94a4a','merge conserva texto aprobado y color urgente');
 const graph=await page.evaluate(()=>OMG.graph());check(JSON.stringify(graph.commits.find(c=>c.hash===merged.head).parents)===JSON.stringify([urgent,experiment]),'grafo tiene merge real con dos padres');
 await page.screenshot({path:'qa/campaign-04-merge.png'});
 await next();await waitPhase('revert');await command('git revert '+hero);check((await state()).head===merged.head,'rechaza revertir el commit equivocado');
 await drag('revert','commit_target');await waitPhase('done');const final=await state();
 check(final.campaign_completed&&final.commits==='6'&&final.clean,'cinco capítulos completados con seis commits y repo limpio');
 check(final.preview.button==='Ver qué puedo crear'&&final.preview.color==='#6750a4','revert quita color y conserva wording');
 check((await page.evaluate(()=>OMG.graph())).commits.some(c=>c.hash===urgent),'el pedido equivocado permanece en la historia');
 await page.screenshot({path:'qa/campaign-05-final.png'});
 // The original draggable graph remains interactive after the whole campaign.
 const nd=(await ui()).nodes[base],from=point([nd.x,nd.y]);await page.mouse.move(...from);await page.waitForTimeout(150);await page.mouse.down();await page.mouse.move(from[0]+80,from[1]-65,{steps:10});await page.waitForTimeout(250);
 const moved=(await ui()).nodes[base];await page.mouse.up();check(Math.hypot(moved.x-nd.x,moved.y-nd.y)>35,'nodos de la timeline se pueden arrastrar');
 await page.reload();await start();check((await state()).campaign_completed,'recarga conserva final de campaña');
 await clickRect('restart');await clickRect('restart_confirm');await waitPhase('choose');check((await state()).chapter===0&&(await state()).commits==='1','nueva historia reinicia tras confirmar');
 check(errors.length===0,'sin errores JS o de Godot en consola');
 await writeFile('qa/campaign-browser-report.json',JSON.stringify({passed:true,checks,errors,final},null,2));console.log('ALL CAMPAIGN BROWSER CHECKS PASSED');
}catch(error){await page.screenshot({path:'qa/campaign-failure.png'});console.error(JSON.stringify({state:await state().catch(()=>null),ui:await ui().catch(()=>null),errors},null,2));throw error;}
finally{await browser.close();}
