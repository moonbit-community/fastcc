
export async function dump(input, options) {
  const worker = new Worker(`objdump/worker.js`);
  const signal = options.signal;
  if (signal) {
    signal.addEventListener('abort', () => {
      worker.terminate();
    });
  }
  const ready = new Promise((resolve) => {
    const listener = (event) => {
      if (event.data.id === 'ready') {
        resolve();
        worker.removeEventListener('message', listener);
      }
    };
    worker.addEventListener('message', listener);
  });
  await ready;
  worker.postMessage({ id: 'disassemble', cmd: '-d', input });
  const data = await new Promise((resolve) => {
    let output = '';
    let timer;
    const listener = (event) => {
      if (event.data.id === 'output') {
        output += event.data.data + '\n';
        clearTimeout(timer);
        timer = window.setTimeout(() => {
          resolve(output);
          worker.removeEventListener('message', listener);
        }, 50);
      }
    };
    worker.addEventListener('message', listener);
  });
  return data;
}
