const refusal = (message) => ({ error: { name: 'NotAllowedError', message } });

chrome.runtime.onMessage.addListener((request, sender, reply) => {
  // sender.origin is the frame's real origin; its URL can claim a site a sandboxed frame doesn't belong to.
  const { origin } = sender;
  if (sender.id !== chrome.runtime.id || !sender.tab || typeof origin !== 'string' || !origin.startsWith('https://')) {
    reply(refusal('Passkeys only work on secure sites.'));
    return false;
  }
  chrome.runtime.sendNativeMessage('com.diapatches.passkeys', { kind: request.kind, options: request.options, origin }, (response) =>
    reply(response ?? refusal(chrome.runtime.lastError?.message ?? 'No reply from diapatch')),
  );
  return true;
});
