class PlatformBridge {
  constructor(runtime = {}) {
    this.runtime = runtime || {};
    this.sessionId = this.createSessionId();
  }

  createSessionId() {
    if (globalThis.crypto?.randomUUID) {
      return globalThis.crypto.randomUUID();
    }
    return `af-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  getContext() {
    const params = new URLSearchParams(window.location.search);
    return {
      sessionId: this.sessionId,
      hostedInIframe: window.top !== window,
      pageUrl: window.location.href,
      referrer: document.referrer || null,
      prolificPid: params.get('PROLIFIC_PID'),
      prolificStudyId: params.get('STUDY_ID'),
      prolificSessionId: params.get('SESSION_ID')
    };
  }

  postToGorilla(action, payload = undefined) {
    if (window.top === window) return false;
    const message = payload === undefined ? { action } : { action, payload };
    console.log('Sending to Gorilla:', message);
    window.top.postMessage(message, '*');
    return true;
  }

  sendMetric(payload) {
    return this.postToGorilla('metric', payload);
  }

  finishGorilla() {
    return this.postToGorilla('finished');
  }

  async uploadSession(sessionData) {
    const endpoint = this.runtime?.uploadEndpoint;
    if (!endpoint) {
      return {
        skipped: true,
        sessionId: this.sessionId,
        bytes: new Blob([JSON.stringify(sessionData || {})]).size,
        attempts: 0
      };
    }

    const envelope = {
      sessionId: this.sessionId,
      uploadedAt: new Date().toISOString(),
      context: this.getContext(),
      sessionData
    };
    const body = JSON.stringify(envelope);
    const maxAttempts = Math.max(1, Number(this.runtime?.uploadAttempts) || 3);
    let lastError = null;

    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body,
          cache: 'no-store'
        });

        const result = await response.json().catch(() => ({}));
        if (!response.ok) {
          throw new Error(result?.error || `Upload failed with status ${response.status}.`);
        }

        return {
          ...result,
          sessionId: this.sessionId,
          bytes: new Blob([body]).size,
          attempts: attempt
        };
      } catch (error) {
        lastError = error;
        if (attempt < maxAttempts) {
          await new Promise(resolve => setTimeout(resolve, 750 * attempt));
        }
      }
    }

    throw lastError || new Error('Session upload failed.');
  }
}

window.PlatformBridge = PlatformBridge;
