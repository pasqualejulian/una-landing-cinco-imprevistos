import * as git from 'isomorphic-git';
import {createTwoFilesPatch,applyPatch} from 'diff';
import {makeFs,allFiles,readText,parsePreview,friendlyError,currentBlob,stagedBlob,commitTreeShape,shortStatusLine} from './git-runtime.mjs';
const DIR='/repo', BASE='refs/guided/checkpoints/stage-0', EXP='experimento-wording';
const AUTHOR={name:'Oh My Git',email:'guided@ohmygit.invalid'};
const WORDINGS={probar:'Quiero probar',crear:'Ver qué puedo crear'};
const COLORS={rojo:'#d94a4a',naranja:'#db6b28'};
const CHAPTERS=[
 {title:'v1_final_ahora_sí',sender:'VOS · LUNES, 09:12',story:'La IA te dio dos heroes. Elegí uno y guardá una versión antes de pedirle «un cambio chiquito».',done:'Primer punto seguro. Tu hero ya tiene un lugar en la timeline.',next:'Llegó un mensaje de Growth →'},
 {title:'¿Y si probamos otro wording?',sender:'GROWTH · MARTES, 11:04',story:'«Empezá ahora» suena a trámite. Probemos otro texto, pero dejemos main como está. Por las dudas.',done:'El experimento tiene su propio commit. main conserva la versión anterior. Mirá dónde se separaron.',next:'Entró un pedido urgente →'},
 {title:'Viernes, 18:57',sender:'STAKEHOLDER · «ES UN MINUTITO»',story:'«¿Podemos hacer el botón más urgente? Rojo. O naranja. Lo necesito para la demo de hoy». Volvé a main.',done:'El pedido quedó en main. El wording sigue a salvo en su rama. Ahora tenés dos caminos reales.',next:'El equipo respondió al experimento →'},
 {title:'El experimento gustó',sender:'EQUIPO · LUNES, 10:06',story:'«Nos quedamos con el nuevo texto». Traelo a main y conservá el color de la demo. Esta vez cambiaste archivos distintos.',done:'Los dos caminos se unieron. Este commit tiene dos padres: el pedido urgente y tu experimento.',next:'El stakeholder volvió a escribir →'},
 {title:'Era para la otra landing',sender:'STAKEHOLDER · «ME CONFUNDÍ DE LINK»',story:'«Lo del color era para otra campaña, ups». Deshacé solo ese pedido. El wording aprobado tiene que quedar.',done:'Sacaste el color urgente y conservaste el wording. El error y su corrección siguen en la timeline: no borraste la historia.',next:''}
];
export async function createCampaignRuntime({storage,key,config}){
 let fs,meta={chapter:0,decisions:{},milestones:{}},feedback='',busy=false,snapshot,graph;
 const opts=()=>({fs,dir:DIR});
 const raw=storage.getItem(key);
 if(raw){
  const saved=JSON.parse(raw);
  ({fs}=makeFs(saved.files));
  await git.resolveRef({...opts(),ref:'HEAD'});
  if(saved.campaign)meta=saved.campaign;
  else {meta.decisions.hero=saved.decision||'';feedback='Tu primera misión sigue acá. Ahora podés continuar la historia.';}
 }
 if(!fs){
  ({fs}=makeFs());await git.init({...opts(),defaultBranch:'main'});
  fs.writeFileSync(DIR+'/index.html',config.baseHtml);fs.writeFileSync(DIR+'/styles.css',config.baseCss);
  await git.add({...opts(),filepath:'index.html'});await git.add({...opts(),filepath:'styles.css'});
  const base=await git.commit({...opts(),message:'Base de la landing',author:AUTHOR});
  await git.writeRef({...opts(),ref:BASE,value:base,force:true});
 }
 const persist=()=>storage.setItem(key,JSON.stringify({version:2,files:allFiles(fs),decision:meta.decisions.hero||'',campaign:meta,feedback}));
 const heroHtml=()=>config.choiceHtml[meta.decisions.hero];
 const wordingHtml=()=>heroHtml()?.replace(/<button>.*?<\/button>/,`<button>${WORDINGS[meta.decisions.wording]}</button>`);
 const urgentCss=()=>config.baseCss.replace(/--cta:\s*[^;]+;/,`--cta: ${COLORS[meta.decisions.urgent]};`);
 async function matches(oid,html,css,parents){
  if(!oid||!html||!css)return false;
  const {commit}=await git.readCommit({...opts(),oid});
  const shape=await commitTreeShape(fs,oid);
  return JSON.stringify(commit.parent)===JSON.stringify(parents)&&commit.message.trim()!==''&&
   JSON.stringify(shape)===JSON.stringify(await commitTreeShape(fs,await git.resolveRef({...opts(),ref:BASE})))&&
   await currentBlob(fs,oid,'index.html')===html&&await currentBlob(fs,oid,'styles.css')===css;
 }
 async function refresh(){
  const head=await git.resolveRef({...opts(),ref:'HEAD'}),base=await git.resolveRef({...opts(),ref:BASE});
  const branch=await git.currentBranch({...opts(),fullname:false}),refs={};
  for(const name of await git.listBranches(opts()))refs[name]=await git.resolveRef({...opts(),ref:name});
  const matrix=await git.statusMatrix(opts());
  const clean=matrix.every(([,h,w,s])=>h===w&&w===s);
  const prepared=!clean&&matrix.some(([,h,,s])=>h!==s)&&matrix.every(([,h,w,s])=>w===s)&&matrix.length===2;
  const m=meta.milestones;
  // Upgrade the prior one-mission save only after checking its real commit.
  if(meta.chapter===0&&!m.hero&&meta.decisions.hero&&clean&&branch==='main'&&await matches(head,heroHtml(),config.baseCss,[base]))m.hero=head;
  const validHero=await matches(m.hero,heroHtml(),config.baseCss,[base]);
  const validExperiment=validHero&&await matches(m.experiment,wordingHtml(),config.baseCss,[m.hero]);
  const validUrgent=validHero&&await matches(m.urgent,heroHtml(),urgentCss(),[m.hero]);
  const validMerge=validExperiment&&validUrgent&&await matches(m.merge,wordingHtml(),urgentCss(),[m.urgent,m.experiment]);
  const validRevert=validMerge&&await matches(m.revert,wordingHtml(),config.baseCss,[m.merge]);
  const validations=[validHero,validExperiment,validUrgent,validMerge,validRevert];
  const currentMilestone=[m.hero,m.experiment,m.urgent,m.merge,m.revert][meta.chapter];
  const expectedBranch=meta.chapter===1?EXP:'main';
  const completed=Boolean(validations[meta.chapter]&&head===currentMilestone&&branch===expectedBranch&&clean);
  let phase,choices=[],cards=[],command='',file='index.html',target='',instruction='',defaultMessage='';
  if(completed){phase='done';instruction=CHAPTERS[meta.chapter].done;}
  else if(meta.chapter===0){
   phase=!meta.decisions.hero?'choose':prepared?'commit':'add';defaultMessage='Elegir hero';
   choices=Object.entries(config.titles).map(([id,label])=>({id,label}));
  }else if(meta.chapter===1){
   phase=!refs[EXP]?'branch':branch!==EXP?'checkout':!meta.decisions.wording?'choose':prepared?'commit':'add';
   command=phase==='branch'?`git branch ${EXP}`:`git checkout ${EXP}`;
   defaultMessage='Probar otro wording';choices=Object.entries(WORDINGS).map(([id,label])=>({id,label}));
  }else if(meta.chapter===2){
   phase=branch!=='main'?'checkout':!meta.decisions.urgent?'choose':prepared?'commit':'add';
   command='git checkout main';file='styles.css';defaultMessage='Cambiar color para la demo';
   choices=[{id:'rojo',label:'Rojo: «que se note urgente»'},{id:'naranja',label:'Naranja: urgente, pero no tanto'}];
  }else if(meta.chapter===3){phase='merge';command=`git merge ${EXP}`;}
  else {phase='revert';command=`git revert --no-edit ${m.urgent}`;}
  if(phase!=='choose')choices=[];
  if(['add','commit'].includes(phase)){
   cards=['add','commit'];target='Guardar versión · soltá commit';
   instruction=phase==='add'?`Cambió ${file}. Preparalo con add.\nLa timeline todavía no suma un commit.`:'El cambio está preparado. Guardalo con commit y un mensaje.';
   command=phase==='add'?`git add ${file}`:`git commit -m "${defaultMessage}"`;
  }else if(phase==='choose')instruction=meta.chapter===0?'Elegí un hero. El juego modifica el archivo por vos.':meta.chapter===1?'Ya estás en tu rama. Elegí el texto que querés probar.':'Estás en main. Elegí el color del pedido urgente.';
  else if(phase==='branch'){cards=['branch'];target='Crear experimento-wording · soltá branch';instruction='Creá una rama desde tu versión guardada. Crear la rama todavía no te cambia de lugar.';}
  else if(phase==='checkout'){cards=['checkout'];target=`Ir a ${expectedBranch} · soltá checkout`;instruction=`Mové HEAD a ${expectedBranch}. La preview va a mostrar los archivos de esa rama.`;}
  else if(phase==='merge'){cards=['merge'];target='Integrar experimento en main · soltá merge';instruction='Uní los caminos. El nuevo texto y el color pueden convivir: están en archivos distintos.';}
  else if(phase==='revert'){cards=['revert'];target='Deshacer solo el color · soltá revert';instruction=`Revertí el commit ${m.urgent.slice(0,7)}. Se agrega una corrección, no se borra el pasado.`;}
  const seen=new Map();
  async function visit(oid){if(seen.has(oid))return;const {commit}=await git.readCommit({...opts(),oid});seen.set(oid,commit);for(const p of commit.parent)await visit(p);}
  for(const oid of Object.values(refs))await visit(oid);
  const order=[],added=new Set();function sort(oid){if(added.has(oid))return;for(const p of seen.get(oid).parent)sort(p);added.add(oid);order.push(oid);}for(const oid of Object.values(refs))sort(oid);
  const captions={[base]:'Base',[m.hero]:'01 · Hero',[m.experiment]:'02 · Wording',[m.urgent]:'03 · Demo',[m.merge]:'04 · Integración',[m.revert]:'05 · Corrección'};
  graph={head,branch,refs,commits:order.map(oid=>({hash:oid,message:seen.get(oid).message.trim(),parents:seen.get(oid).parent,tree:seen.get(oid).tree,caption:captions[oid]||seen.get(oid).message.trim().slice(0,24)}))};
  snapshot={chapter:meta.chapter,chapter_number:meta.chapter+1,chapter_count:5,chapter_title:CHAPTERS[meta.chapter].title,sender:CHAPTERS[meta.chapter].sender,story:CHAPTERS[meta.chapter].story,
   phase,completed,campaign_completed:completed&&meta.chapter===4,can_continue:completed&&meta.chapter<4,next_label:CHAPTERS[meta.chapter].next,
   instruction,choices,cards,command,file,target,default_message:defaultMessage,branch,refs,milestones:{...m},
   preview:parsePreview(readText(fs,'index.html'),readText(fs,'styles.css')),head,clean,prepared,chosen:phase!=='choose',
   commits:String(seen.size),feedback,decision:meta.decisions.hero||'',step:meta.chapter===0?(completed?'stage_0_done':phase==='choose'?'choose_title':prepared?'commit_title':'add_title'):phase};
 }
 function parse(command){
  if(/^git (status(?: --short)?|log(?: --oneline)?|diff(?: --cached)?|show(?: HEAD)?|branch)$/.test(command))return {read:true,verb:command.split(' ')[1]};
  let match=command.match(/^git add (index\.html|styles\.css|\.)$/);if(match)return {verb:'add',file:match[1]};
  match=command.match(/^git commit -m ("([^"$`\\\r\n]+)"|'([^'$`\\\r\n]+)')$/);if(match&&(match[2]??match[3]).trim())return {verb:'commit',message:(match[2]??match[3]).trim()};
  if(command===`git branch ${EXP}`)return {verb:'branch'};
  match=command.match(/^git (?:checkout|switch) (main|experimento-wording)$/);if(match)return {verb:'checkout',ref:match[1]};
  if(command===`git switch -c ${EXP}`||command===`git checkout -b ${EXP}`)return {verb:'branch-switch'};
  if(command===`git merge ${EXP}`||command===`git merge --no-ff ${EXP}`)return {verb:'merge'};
  match=command.match(/^git revert (?:--no-edit )?([a-f0-9]{7,40})$/);if(match)return {verb:'revert',oid:match[1]};
  return null;
 }
 function validate(command){
  const p=parse(command.trim());if(!p)return 'Ese comando no está disponible en este capítulo. Mirá la alternativa debajo del objetivo.';
  if(p.read)return '';
  if(snapshot.completed)return snapshot.can_continue?'Capítulo listo. Abrí el siguiente mensaje para continuar.':'Historia completa. Podés consultar tu timeline o volver a jugar.';
  const allowed={add:['add','commit'],commit:['add','commit'],branch:['branch','branch-switch'],checkout:['checkout'],merge:['merge'],revert:['revert']};
  if(!(allowed[snapshot.phase]||[]).includes(p.verb))return snapshot.phase==='choose'?'Primero elegí una opción del capítulo.':`En este paso: ${snapshot.command}`;
  if(p.verb==='checkout'&&p.ref!==(meta.chapter===1?EXP:'main'))return `En este capítulo tenés que ir a ${meta.chapter===1?EXP:'main'}.`;
  if(p.verb==='revert'&&!meta.milestones.urgent.startsWith(p.oid))return 'Ese no es el pedido del color. Elegí el commit indicado para conservar el wording.';
  return '';
 }
 async function transaction(action,label){
  if(busy)return {exit_code:1,output:'Ya hay una acción en curso.',pretty_command:label};
  busy=true;const backup={files:allFiles(fs),meta:structuredClone(meta)};
  try{const output=await action();await refresh();persist();return {exit_code:0,output:output||'',pretty_command:label};}
  catch(error){({fs}=makeFs(backup.files));meta=backup.meta;feedback=friendlyError(error);await refresh();return {exit_code:1,output:feedback,pretty_command:label};}
  finally{busy=false;}
 }
 async function choose(id){return transaction(async()=>{
  if(snapshot.phase!=='choose')throw Error('Primero completá la acción indicada en el capítulo.');
  if(!snapshot.choices.some(c=>c.id===id))throw Error('Esa opción no está disponible.');
  if(meta.chapter===0){meta.decisions.hero=id;fs.writeFileSync(DIR+'/index.html',heroHtml());}
  else if(meta.chapter===1){meta.decisions.wording=id;fs.writeFileSync(DIR+'/index.html',wordingHtml());}
  else {meta.decisions.urgent=id;fs.writeFileSync(DIR+'/styles.css',urgentCss());}
  feedback='Cambió el archivo. Todavía no hay un nuevo commit.';return feedback;
 },'choose');}
 async function readOutput(command,p){
  if(p.verb==='branch')return Object.keys(snapshot.refs).map(ref=>`${ref===snapshot.branch?'*':' '} ${ref}`).join('\n');
  if(p.verb==='status'){
   const matrix=await git.statusMatrix(opts()),changed=matrix.filter(([,h,w,s])=>h!==w||w!==s);
   return command.endsWith('--short')?changed.map(row=>shortStatusLine(...row)).join('\n'):`En la rama ${snapshot.branch}\n${changed.length?changed.map(row=>shortStatusLine(...row)).join('\n'):'Árbol de trabajo limpio'}`;
  }
  if(p.verb==='log')return (await git.log({...opts(),ref:'HEAD'})).map(e=>`${e.oid.slice(0,7)} ${e.commit.message.trim()}${e.commit.parent.length===2?' [merge · 2 padres]':''}`).join('\n');
  const patches=[];
  if(p.verb==='show'){
   const {commit}=await git.readCommit({...opts(),oid:snapshot.head});
   for(const file of ['index.html','styles.css']){const before=commit.parent.length?await currentBlob(fs,commit.parent[0],file):'',after=await currentBlob(fs,snapshot.head,file);if(before!==after)patches.push(createTwoFilesPatch('a/'+file,'b/'+file,before||'',after||''));}
   return `${snapshot.head}\n${commit.message.trim()}\n\n${patches.join('\n')}`;
  }
  const cached=command.endsWith('--cached');
  for(const file of ['index.html','styles.css']){const before=cached?await currentBlob(fs,snapshot.head,file):await stagedBlob(fs,file),after=cached?await stagedBlob(fs,file):readText(fs,file);if(before!==after)patches.push(createTwoFilesPatch('a/'+file,'b/'+file,before||'',after||''));}
  return patches.join('\n');
 }
 async function execute(input){const command=String(input).trim();return transaction(async()=>{
  const error=validate(command);if(error)throw Error(error);const p=parse(command);
  if(p.read)return await readOutput(command,p);
  let output='';
  if(p.verb==='branch'||p.verb==='branch-switch'){
   await git.branch({...opts(),ref:EXP,checkout:p.verb==='branch-switch'});feedback='Creaste una rama. main sigue en el mismo commit.';
  }else if(p.verb==='checkout'){
   if(!snapshot.clean)throw Error('Guardá tus cambios antes de cambiar de rama.');
   await git.checkout({...opts(),ref:p.ref});feedback=`HEAD ahora está en ${p.ref}. Mirá cómo cambia la preview.`;
  }else if(p.verb==='add'){
   for(const file of p.file==='.'?['index.html','styles.css']:[p.file])await git.add({...opts(),filepath:file});
   const staged=(await git.statusMatrix(opts())).some(([,head,,index])=>head!==index);
   feedback=staged?'Archivo preparado. Ahora creá el commit.':`Ese archivo no tiene cambios. Prepará ${snapshot.file}.`;
  }else if(p.verb==='commit'){
   if(!snapshot.prepared)throw Error('Primero prepará el archivo modificado con add.');
   const parent=snapshot.head;
   const oid=await git.commit({...opts(),message:p.message,author:AUTHOR});
   const html=meta.chapter===1?wordingHtml():heroHtml(),css=meta.chapter===2?urgentCss():config.baseCss;
   if(!await matches(oid,html,css,[parent]))throw Error('El commit no coincide con el objetivo. Se conservó tu estado anterior.');
   meta.milestones[['hero','experiment','urgent'][meta.chapter]]=oid;feedback='Un nuevo punto en tu timeline. El capítulo quedó guardado.';output=`[${snapshot.branch} ${oid.slice(0,7)}] ${p.message}`;
  }else if(p.verb==='merge'){
   if(!snapshot.clean||snapshot.branch!=='main')throw Error('Integrá desde main con los archivos limpios.');
   const result=await git.merge({...opts(),ours:'main',theirs:EXP,fastForward:false,abortOnConflict:true,author:AUTHOR,message:'Integrar el wording aprobado'});
   await git.checkout({...opts(),ref:'main',force:true});
   if(!await matches(result.oid,wordingHtml(),urgentCss(),[meta.milestones.urgent,meta.milestones.experiment]))throw Error('La unión no conservó las dos versiones esperadas.');
   meta.milestones.merge=result.oid;feedback='Merge creado con dos padres. Conservaste el wording y el color.';output=feedback;
  }else if(p.verb==='revert'){
   if(!snapshot.clean||snapshot.branch!=='main')throw Error('Revertí desde main con los archivos limpios.');
   const oid=meta.milestones.urgent,{commit}=await git.readCommit({...opts(),oid});
   // Bounded revert: inverse patch of this scenario's actual commit, then a
   // new Git commit. Later HTML changes are untouched. No reset/checkout back.
   for(const file of ['index.html','styles.css']){
    const before=await currentBlob(fs,commit.parent[0],file),after=await currentBlob(fs,oid,file);
    if(before===after)continue;
    const inverse=createTwoFilesPatch(file,file,after,before);
    const result=applyPatch(readText(fs,file),inverse,{fuzzFactor:0});
    if(result===false)throw Error('El cambio inverso entra en conflicto. Tu estado se conservó.');
    fs.writeFileSync(DIR+'/'+file,result);await git.add({...opts(),filepath:file});
   }
   const newOid=await git.commit({...opts(),message:`Revertir pedido de color\n\nThis reverts commit ${oid}.`,author:AUTHOR});
   if(!await matches(newOid,wordingHtml(),config.baseCss,[meta.milestones.merge]))throw Error('La corrección no conservó el wording. Tu estado se conservó.');
   meta.milestones.revert=newOid;feedback='Corregiste el color sin borrar el commit original ni el wording aprobado.';output=feedback;
  }
  return output||feedback;
 },command);}
 async function advance(){return transaction(async()=>{
  if(!snapshot.can_continue)throw Error('Completá el capítulo antes de abrir el siguiente mensaje.');
  meta.chapter++;feedback='Tu timeline sigue desde donde la dejaste.';return feedback;
 },'advance');}
 async function restart(){return transaction(async()=>{
  const base=await git.resolveRef({...opts(),ref:BASE});
  await git.writeRef({...opts(),ref:'refs/heads/main',value:base,force:true});
  await git.checkout({...opts(),ref:'main',force:true});
  for(const ref of await git.listBranches(opts()))if(ref!=='main')await git.deleteBranch({...opts(),ref});
  meta={chapter:0,decisions:{},milestones:{}};feedback='Nueva historia desde la landing inicial.';return feedback;
 },'restart');}
 await refresh();persist();
 return {choose,execute,advance,restart,validate,snapshot:()=>structuredClone(snapshot),graph:()=>structuredClone(graph),exportFiles:()=>allFiles(fs)};
}
