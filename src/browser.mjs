import {createCampaignRuntime} from './campaign-runtime.mjs';

export async function prepareGit(config) {
  const runtime = await createCampaignRuntime({storage: localStorage, key:'oh-my-git-first-mission-web-v1', config});
  let counter = 0;
  const results = new Map();
  window.OMG = {
    snapshot: () => runtime.snapshot(),
    graph: () => runtime.graph(),
    exportFiles: () => runtime.exportFiles(),
    validate: command => runtime.validate(command),
    request(kind, value) {
      const id = ++counter;
      if (!['choose', 'execute', 'restart', 'advance'].includes(kind)) {
        results.set(id, {exit_code:1,output:'Acción no disponible.'});
        return id;
      }
      Promise.resolve().then(() => runtime[kind](value)).then(result => {
        results.set(id, result?.exit_code !== undefined ? result : {exit_code:0,output:''});
      }, error => results.set(id, {exit_code:1,output:error.message || String(error)}));
      return id;
    },
    poll(id) {
      if (!results.has(id)) return '';
      const value = results.get(id);
      results.delete(id);
      return JSON.stringify(value);
    }
  };
  return runtime;
}
