import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync,mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {createCampaignRuntime} from '../src/campaign-runtime.mjs';
import {createGitRuntime} from '../src/git-runtime.mjs';
const config=JSON.parse(readFileSync(new URL('../game-export/mission-config.json',import.meta.url)));
const storage=()=>{const m=new Map();return {getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,v),m};};
async function setup(store=storage()){return createCampaignRuntime({storage:store,key:'test',config});}
async function ok(promise){const r=await promise;assert.equal(r.exit_code,0,r.output);return r;}
async function save(app,message){await ok(app.execute('git add .'));await ok(app.execute(`git commit -m "${message}"`));assert.ok(app.snapshot().completed);}
async function untilMerge(app,hero='idea_vida',wording='probar',color='rojo'){
 await ok(app.choose(hero));await save(app,'Hero');const heroHead=app.snapshot().head;
 await ok(app.advance());assert.equal(app.snapshot().phase,'branch');
 await ok(app.execute('git branch experimento-wording'));assert.equal(app.snapshot().branch,'main');
 await ok(app.execute('git checkout experimento-wording'));await ok(app.choose(wording));await save(app,'Wording');
 const experiment=app.snapshot().head;assert.equal(app.snapshot().refs.main,heroHead);
 await ok(app.advance());await ok(app.execute('git checkout main'));assert.equal(app.snapshot().preview.button,'Empezá ahora');
 await ok(app.choose(color));await save(app,'Color urgente');const urgent=app.snapshot().head;
 assert.equal(app.snapshot().refs['experimento-wording'],experiment);
 await ok(app.advance());await ok(app.execute('git merge experimento-wording'));
 assert.ok(app.snapshot().completed);assert.equal(app.snapshot().commits,'5');
 const merge=app.graph().commits.find(c=>c.hash===app.snapshot().head);assert.deepEqual(merge.parents,[urgent,experiment]);
 return {heroHead,experiment,urgent};
}
function exportRepo(app){const dir=mkdtempSync(join(tmpdir(),'campaign-git-'));for(const [file,data]of Object.entries(app.exportFiles())){const p=join(dir,file);mkdirSync(dirname(p),{recursive:true});writeFileSync(p,Buffer.from(data,'base64'));}return dir;}
test('five chapters share real branches, merge ancestry and a preserving revert',async()=>{
 const app=await setup();const {heroHead,experiment,urgent}=await untilMerge(app);
 const native=exportRepo(app);
 try{
  execFileSync('git',['-c','user.name=QA','-c','user.email=qa@example.invalid','revert','--no-edit',urgent],{cwd:native});
  const nativeTree=execFileSync('git',['rev-parse','HEAD^{tree}'],{cwd:native,encoding:'utf8'}).trim();
  await ok(app.advance());await ok(app.execute(`git revert --no-edit ${urgent}`));
  const s=app.snapshot();assert.ok(s.campaign_completed);assert.equal(s.commits,'6');assert.ok(s.clean);assert.equal(s.preview.button,'Quiero probar');assert.equal(s.preview.color,'#6750a4');
  assert.equal(app.graph().commits.find(c=>c.hash===s.head).tree,nativeTree);
  for(const hash of [heroHead,experiment,urgent])assert.ok(app.graph().commits.some(c=>c.hash===hash));
  const dir=exportRepo(app);try{execFileSync('git',['fsck','--full'],{cwd:dir});assert.equal(execFileSync('git',['status','--porcelain'],{cwd:dir,encoding:'utf8'}),'');assert.equal(execFileSync('git',['rev-list','--count','--all'],{cwd:dir,encoding:'utf8'}).trim(),'6');}finally{rmSync(dir,{recursive:true,force:true});}
 }finally{rmSync(native,{recursive:true,force:true});}
});
test('second choices produce their own preserved final content',async()=>{
 const app=await setup();const {urgent}=await untilMerge(app,'idea_proxima','crear','naranja');
 await ok(app.advance());await ok(app.execute(`git revert ${urgent.slice(0,7)}`));assert.equal(app.snapshot().preview.title,'Tu próxima idea empieza acá');assert.equal(app.snapshot().preview.button,'Ver qué puedo crear');assert.equal(app.snapshot().preview.color,'#6750a4');
});
test('old completed first mission migrates without losing its commit',async()=>{
 const store=storage();const old=await createGitRuntime({storage:store,key:'test',config});await old.choose('idea_vida');await old.execute('git add .');await old.execute('git commit -m "Ya jugué"');const head=old.snapshot().head;
 const app=await setup(store);assert.equal(app.snapshot().head,head);assert.ok(app.snapshot().can_continue);await ok(app.advance());assert.equal(app.snapshot().chapter,1);assert.equal(app.snapshot().head,head);
});
test('reload during experiment preserves branch, index, milestones and chapter',async()=>{
 const store=storage();let app=await setup(store);await ok(app.choose('idea_vida'));await save(app,'Hero');await ok(app.advance());await ok(app.execute('git switch -c experimento-wording'));await ok(app.choose('crear'));await ok(app.execute('git add index.html'));
 const head=app.snapshot().head;app=await setup(store);assert.equal(app.snapshot().chapter,1);assert.equal(app.snapshot().branch,'experimento-wording');assert.ok(app.snapshot().prepared);assert.equal(app.snapshot().head,head);await ok(app.execute('git commit -m "Retomé"'));assert.ok(app.snapshot().completed);
});
test('invalid order, wrong reverts and duplicate advance cannot skip history',async()=>{
 const app=await setup();assert.equal((await app.advance()).exit_code,1);assert.equal((await app.execute('git merge experimento-wording')).exit_code,1);
 await ok(app.choose('idea_vida'));assert.equal((await app.execute('git commit -m "Antes de add"')).exit_code,1);assert.equal(app.snapshot().commits,'1');
 await save(app,'Hero');const results=await Promise.all([app.advance(),app.advance()]);assert.equal(results.filter(r=>r.exit_code===0).length,1);assert.equal(app.snapshot().chapter,1);
 assert.equal((await app.execute('git checkout main')).exit_code,1);
 const fresh=await setup();const {heroHead}=await untilMerge(fresh);await ok(fresh.advance());const head=fresh.snapshot().head;assert.equal((await fresh.execute('git revert '+heroHead)).exit_code,1);assert.equal(fresh.snapshot().head,head);
});
test('persistence failures roll back changes and preserve the prior playable repo',async()=>{
 const store=storage(),app=await setup(store);const before=app.snapshot();store.setItem=()=>{throw Error('Storage full');};assert.equal((await app.choose('idea_vida')).exit_code,1);assert.equal(app.snapshot().phase,'choose');assert.equal(app.snapshot().head,before.head);assert.ok(app.snapshot().clean);
});
test('restart after campaign removes active branches but restores a valid base',async()=>{
 const app=await setup();await untilMerge(app);await ok(app.restart());assert.equal(app.snapshot().chapter,0);assert.equal(app.snapshot().commits,'1');assert.deepEqual(Object.keys(app.snapshot().refs),['main']);assert.ok(app.snapshot().clean);assert.equal(app.snapshot().phase,'choose');
});

test('adding an unchanged file reports that the actual change still needs staging',async()=>{
 const app=await setup();await ok(app.choose('idea_vida'));const result=await ok(app.execute('git add styles.css'));assert.match(result.output,/no tiene cambios/);assert.equal(app.snapshot().prepared,false);assert.equal(app.snapshot().phase,'add');
});
