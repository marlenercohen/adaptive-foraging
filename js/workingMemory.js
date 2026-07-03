class ExponentialWorkingMemory {
  constructor(config = {}) {
    this.decayTimeConstant = this.parseDecayTimeConstant(config.decayTimeConstant);
    this.memoryStrengths = {};
    this.minStrength = 1e-6;
  }

  parseDecayTimeConstant(value) {
    if (value === undefined || value === null) return 5;
    if (value === Infinity || value === 'Infinity') return Infinity;
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric <= 0) return Number.EPSILON;
    return numeric;
  }

  resetEpisode() {
    this.memoryStrengths = {};
  }

  decayAll() {
    if (this.decayTimeConstant === Infinity) return;
    const decayFactor = Math.exp(-1 / this.decayTimeConstant);
    Object.keys(this.memoryStrengths).forEach((key) => {
      const next = this.memoryStrengths[key] * decayFactor;
      if (next < this.minStrength) {
        delete this.memoryStrengths[key];
      } else {
        this.memoryStrengths[key] = next;
      }
    });
  }

  recordVisit(stimulusId) {
    this.decayAll();
    this.memoryStrengths[stimulusId] = 1.0;
  }

  getStrength(stimulusId) {
    return this.memoryStrengths[stimulusId] || 0;
  }
}

window.ExponentialWorkingMemory = ExponentialWorkingMemory;