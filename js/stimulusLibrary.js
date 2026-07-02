class StimulusLibrary {
  constructor(metadataUrl = null) {
    this.stimuli = [];
    this.metadataUrl = metadataUrl;
    this.ready = this.loadMetadata();
  }

  async loadMetadata() {
    if(!this.metadataUrl){
      this.stimuli = [];
      return;
    }

    const response = await fetch(this.metadataUrl);
    const data = await response.json();
    this.stimuli = Array.isArray(data) ? data : [];
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
