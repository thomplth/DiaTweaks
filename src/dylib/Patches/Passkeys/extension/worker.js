const refusal = (message) => ({ error: { name: 'NotAllowedError', message } });

// Closing the port closes the host's stdin, which is what stops the request.
chrome.runtime.onConnect.addListener((port) => {
  // sender.origin is the frame's real origin; its URL can claim a site a sandboxed frame doesn't belong to.
  const { id, tab, origin } = port.sender ?? {};
  const secure = id === chrome.runtime.id && tab && typeof origin === 'string' && origin.startsWith('https://');
  port.onMessage.addListener((request) => {
    if (!secure) return port.postMessage(refusal('Passkeys only work on secure sites.'));
    const host = chrome.runtime.connectNative('com.diapatches.passkeys');
    let answered = false;
    host.onMessage.addListener((response) => {
      answered = true;
      port.postMessage(response);
      host.disconnect();
    });
    host.onDisconnect.addListener(() => {
      if (answered) return;
      port.postMessage(refusal(chrome.runtime.lastError?.message ?? 'No reply from diapatch'));
    });
    port.onDisconnect.addListener(() => host.disconnect());
    host.postMessage({ kind: request.kind, options: request.options, origin });
  });
});
