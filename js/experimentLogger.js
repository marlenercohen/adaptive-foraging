class ExperimentLogger {
  constructor() {
    this.reset();
  }

  reset() {
    this.sessionMetadata = null;
    this.eventLog = [];
    this.stateSnapshots = [];
    this.sequence = 0;
    this.internalErrors = [];
  }

  nowIso() {
    return new Date().toISOString();
  }

  clone(value) {
    if (value === undefined) return undefined;
    if (typeof structuredClone === 'function') {
      try {
        return structuredClone(value);
      } catch (_) {
        // Fall through to JSON fallback.
      }
    }
    return JSON.parse(JSON.stringify(value));
  }

  captureError(method, error) {
    this.internalErrors.push({
      ts: this.nowIso(),
      method,
      message: error?.message || String(error)
    });
    return null;
  }

  beginSession(metadata = {}) {
    try {
      this.reset();
      this.sessionMetadata = {
        ...this.clone(metadata),
        startedAt: metadata.startedAt || this.nowIso()
      };
      this.logEvent('session_start', { sessionMetadata: this.sessionMetadata });
      return true;
    } catch (error) {
      return this.captureError('beginSession', error);
    }
  }

  endSession(data = {}) {
    try {
      this.logEvent('session_end', this.clone(data));
      if (this.sessionMetadata) {
        this.sessionMetadata.endedAt = this.nowIso();
      }
      return true;
    } catch (error) {
      return this.captureError('endSession', error);
    }
  }

  logEvent(type, data = {}) {
    try {
      const event = {
        seq: ++this.sequence,
        ts: this.nowIso(),
        type,
        data: this.clone(data)
      };
      this.eventLog.push(event);
      return event;
    } catch (error) {
      return this.captureError('logEvent', error);
    }
  }

  recordSnapshot(state = {}, meta = {}) {
    try {
      const snapshot = {
        seq: ++this.sequence,
        ts: this.nowIso(),
        meta: this.clone(meta),
        state: this.clone(state)
      };
      this.stateSnapshots.push(snapshot);
      return snapshot;
    } catch (error) {
      return this.captureError('recordSnapshot', error);
    }
  }

  getSessionData() {
    try {
      return {
        schemaVersion: '1.0.0',
        sessionMetadata: this.clone(this.sessionMetadata),
        eventLog: this.clone(this.eventLog),
        stateSnapshots: this.clone(this.stateSnapshots),
        internalErrors: this.clone(this.internalErrors)
      };
    } catch (error) {
      return {
        schemaVersion: '1.0.0',
        sessionMetadata: this.sessionMetadata,
        eventLog: this.eventLog,
        stateSnapshots: this.stateSnapshots,
        internalErrors: this.internalErrors.concat([{ ts: this.nowIso(), method: 'getSessionData', message: error?.message || String(error) }])
      };
    }
  }

  toJSON(space = 2) {
    return JSON.stringify(this.getSessionData(), null, space);
  }
}

window.ExperimentLogger = ExperimentLogger;