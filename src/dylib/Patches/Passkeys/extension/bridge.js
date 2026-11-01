// The page can post requests straight to this listener, skipping page.js, so the checks live here, where it can't reach.
const crossOrigin = () => Array.from(location.ancestorOrigins ?? []).some((origin) => origin !== location.origin);
const feature = (kind) => (kind === 'create' ? 'publickey-credentials-create' : 'publickey-credentials-get');
const allowedHere = (kind) => !document.featurePolicy || document.featurePolicy.allowsFeature(feature(kind));
let unpromptedRequestFailed = false;

window.addEventListener('message', (event) => {
  if (event.source !== window || event.data?.diaTweaksPasskey !== 'request') return;
  const { id, kind, options } = event.data;
  const reply = (response) => window.postMessage({ diaTweaksPasskey: 'response', id, response }, '*');
  const refuse = (message) => reply({ error: { name: 'NotAllowedError', message } });
  if (kind !== 'create' && kind !== 'get') return refuse('That isn’t a passkey request.');
  // The other Dia signs in as the site itself, so a frame from another site would get a sign-in that hides it was framed.
  if (crossOrigin()) return refuse('DiaTweaks only uses passkeys for the site in the address bar.');
  if (!allowedHere(kind)) return refuse('This page doesn’t allow passkeys here.');
  // Each request opens another Dia, so a page that keeps asking unprompted waits for a click.
  const clicked = navigator.userActivation?.isActive ?? false;
  if (!clicked && unpromptedRequestFailed) return refuse('Click the sign-in button again to use your passkey.');
  chrome.runtime.sendMessage({ kind, options }, (response) => {
    if (!clicked && !response?.credential) unpromptedRequestFailed = true;
    reply(response);
  });
});
