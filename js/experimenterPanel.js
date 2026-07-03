class ExperimenterPanel {
  constructor(containerId) {
    this.el = document.getElementById(containerId);
    if (!this.el) return;
    this.el.classList.add('experimenter-panel');
    this.history = [];
    this.experimentState = {};
    this.agentState = {};
    this.render();
    this.update();
  }

  render() {
    this.el.innerHTML = `
      <div class="ep-header">
        <button type="button" class="expander">Experimenter ▸</button>
      </div>
      <div class="ep-content">
        <section class="ep-section">
          <h3>Experiment</h3>
          <div class="ep-grid">
            <div><strong>Name:</strong> <span data-key="name">-</span></div>
            <div><strong>Episode:</strong> <span data-key="episode">-</span></div>
            <div><strong>Move:</strong> <span data-key="move">-</span></div>
            <div><strong>Rule:</strong> <span data-key="rule">-</span></div>
            <div><strong>Agent:</strong> <span data-key="agent">-</span></div>
            <div><strong>Rewards remaining:</strong> <span data-key="rewards">-</span></div>
            <div><strong>Until switch:</strong> <span data-key="untilSwitch">-</span></div>
          </div>
        </section>
        <section class="ep-section">
          <h3>Agent</h3>
          <div class="ep-grid">
            <div><strong>Last stimulus:</strong> <span data-key="lastStimulus">-</span></div>
            <div><strong>Last rewarded:</strong> <span data-key="lastRewarded">-</span></div>
          </div>
          <div class="ep-table-wrapper">
            <table>
              <thead><tr><th>Feature</th><th>Weight</th></tr></thead>
              <tbody data-key="weights"></tbody>
            </table>
          </div>
        </section>
        <section class="ep-section">
          <h3>Predictions</h3>
          <div class="ep-table-wrapper">
            <table>
              <thead><tr><th>ID</th><th>Icon</th><th>Score</th><th>Rewarded</th><th>Chosen</th></tr></thead>
              <tbody data-key="predictions"></tbody>
            </table>
          </div>
        </section>
        <section class="ep-section">
          <h3>Recent history</h3>
          <div class="ep-table-wrapper">
            <table>
              <thead><tr><th>Episode</th><th>Move</th><th>Stimulus</th><th>Rewarded</th></tr></thead>
              <tbody data-key="history"></tbody>
            </table>
          </div>
        </section>
      </div>`;

    this.expander = this.el.querySelector('.expander');
    this.content = this.el.querySelector('.ep-content');
    this.expander.addEventListener('click', () => this.toggle());
    this.collapsed = true;
    this.content.style.display = 'none';
  }

  toggle() {
    this.collapsed = !this.collapsed;
    this.content.style.display = this.collapsed ? 'none' : 'block';
    this.expander.textContent = this.collapsed ? 'Experimenter ▸' : 'Experimenter ▾';
  }

  updateExperiment(state = {}) {
    this.experimentState = { ...this.experimentState, ...state };
    this.update();
  }

  updateAgent(state = {}) {
    this.agentState = { ...this.agentState, ...state };
    this.update();
  }

  updatePredictions(predictions = []) {
    this.agentState.predictions = predictions;
    this.update();
  }

  pushMove(move) {
    this.history.unshift(move);
    if (this.history.length > 10) this.history.length = 10;
    this.update();
  }

  renderWeights() {
    const tbody = this.el.querySelector('[data-key="weights"]');
    if (!tbody) return;
    tbody.innerHTML = '';
    const entries = Object.entries(this.agentState.weights || {}).sort((a, b) => b[1] - a[1]);
    entries.forEach(([feature, weight]) => {
      const row = document.createElement('tr');
      row.innerHTML = `<td>${feature}</td><td>${weight.toFixed(2)}</td>`;
      tbody.appendChild(row);
    });
  }

  renderPredictions() {
    const tbody = this.el.querySelector('[data-key="predictions"]');
    if (!tbody) return;
    tbody.innerHTML = '';
    const predictions = (this.agentState.predictions || []).slice().sort((a, b) => b.score - a.score);
    predictions.forEach(prediction => {
      const row = document.createElement('tr');
      row.className = prediction.chosen ? 'chosen-row' : '';
      row.innerHTML = `<td>${prediction.id}</td><td>${prediction.icon}</td><td>${prediction.score.toFixed(2)}</td><td>${prediction.rewarded ? 'yes' : 'no'}</td><td>${prediction.chosen ? 'yes' : ''}</td>`;
      tbody.appendChild(row);
    });
  }

  renderHistory() {
    const tbody = this.el.querySelector('[data-key="history"]');
    if (!tbody) return;
    tbody.innerHTML = '';
    this.history.forEach(entry => {
      const row = document.createElement('tr');
      row.innerHTML = `<td>${entry.episode}</td><td>${entry.move}</td><td>${entry.stimulus}</td><td>${entry.rewarded ? 'yes' : 'no'}</td>`;
      tbody.appendChild(row);
    });
  }

  update() {
    if (!this.el) return;
    const set = (key, value) => {
      const el = this.el.querySelector(`[data-key="${key}"]`);
      if (el) el.textContent = value;
    };
    set('name', this.experimentState.name ?? '-');
    set('episode', this.experimentState.episodeNumber ?? '-');
    set('move', this.experimentState.moveNumber ?? '-');
    set('rule', this.experimentState.ruleLabel ?? '-');
    set('agent', this.experimentState.agentType ?? '-');
    set('rewards', this.experimentState.rewardsRemaining ?? '-');
    set('untilSwitch', this.experimentState.episodesUntilNextSwitch ?? '-');
    set('lastStimulus', this.agentState.lastStimulus ?? '-');
    set('lastRewarded', this.agentState.lastRewarded === undefined ? '-' : (this.agentState.lastRewarded ? 'yes' : 'no'));
    this.renderWeights();
    this.renderPredictions();
    this.renderHistory();
  }
}

window.ExperimenterPanel = ExperimenterPanel;
