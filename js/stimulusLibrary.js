class StimulusLibrary {
  constructor(stimuli = []) {
    this.stimuli = Array.isArray(stimuli) ? stimuli : [];
  }

  getAll() {
    return this.stimuli;
  }

  sample(n) {
    const count = Math.max(0, n);
    if (count === 0) {
      return [];
    }

    const pool = [...this.stimuli];
    const sampled = [];
    while (sampled.length < Math.min(count, pool.length)) {
      const index = Math.floor(Math.random() * pool.length);
      sampled.push(pool.splice(index, 1)[0]);
    }
    return sampled;
  }

  getById(id) {
    return this.stimuli.find(stimulus => stimulus.id === id) || null;
  }
}
