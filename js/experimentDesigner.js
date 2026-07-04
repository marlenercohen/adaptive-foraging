function loadExperimentDesigner() {
  const root = document.getElementById('experiment-designer');
  const summaryEl = document.getElementById('designer-summary');
  const descriptionEl = document.getElementById('designer-description');
  const listEl = document.getElementById('designer-block-list');
  const detailsEl = document.getElementById('designer-block-details');
  let resolver = null;
  if (!root || !summaryEl || !descriptionEl || !listEl || !detailsEl) return;

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function getDisplayText(value, fallback) {
    if (value === undefined || value === null || value === '') return fallback;
    return String(value);
  }

  function renderSummary(protocol) {
    const name = getDisplayText(protocol?.name, 'Untitled experiment');
    const blockCount = Array.isArray(protocol?.phases) ? protocol.phases.length : 0;
    summaryEl.textContent = `${name} · ${blockCount} block${blockCount === 1 ? '' : 's'}`;

    const description = protocol?.description;
    descriptionEl.textContent = description ? String(description) : '';
    descriptionEl.style.display = description ? 'block' : 'none';
  }

  function formatValue(value) {
    if (value === undefined || value === null) return '-';
    if (typeof value === 'boolean') return value ? 'true' : 'false';
    if (typeof value === 'number') return String(value);
    if (typeof value === 'string') return value || '-';
    return JSON.stringify(value, null, 2);
  }

  function buildRowsFromObject(obj, excludedKeys = []) {
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return [];
    return Object.entries(obj)
      .filter(([key]) => !excludedKeys.includes(key))
      .map(([key, value]) => ({
        label: key,
        value: formatValue(value),
        asCode: typeof value === 'object' && value !== null
      }));
  }

  function renderSection(title, rows) {
    const validRows = rows.filter((row) => row && row.value !== undefined);
    if (!validRows.length) return '';

    const rowsHtml = validRows.map((row) => {
      const valueClass = row.asCode ? 'designer-v designer-v-inline-code' : 'designer-v';
      return `<div class="designer-k">${escapeHtml(row.label)}</div><div class="${valueClass}">${escapeHtml(row.value)}</div>`;
    }).join('');

    return `<section class="designer-section"><h5>${escapeHtml(title)}</h5><div class="designer-kv">${rowsHtml}</div></section>`;
  }

  function renderDetails(block) {
    const ruleName = resolver
      ? resolver.resolveRule(block?.ruleFile).displayName
      : (block?.rule?.displayName || block?.rule?.name || block?.ruleFile || '-');
    const stimulusSetName = resolver
      ? resolver.resolveStimulusSet(block?.stimulusSet).displayName
      : block?.stimulusSet;
    const reward = block?.rewardStructure || {};
    const workingMemory = block?.workingMemory || {};
    const termination = block?.episodeTerminationPolicy || {};
    const agent = block?.agent || {};
    const agentTypeName = resolver
      ? resolver.resolveAgent(agent?.type).displayName
      : agent?.type;
    const rewardTypeName = resolver
      ? resolver.resolveRewardStructure(reward?.type).displayName
      : reward?.type;
    const terminationTypeName = resolver
      ? resolver.resolveEpisodeTerminationPolicy(termination?.type).displayName
      : termination?.type;
    const workingMemoryTypeName = resolver
      ? resolver.resolveWorkingMemoryModel(workingMemory?.type).displayName
      : (workingMemory?.type || 'default');

    const sections = [];
    sections.push(renderSection('General', [
      { label: 'Block name', value: formatValue(block?.name) },
      { label: 'Episodes', value: formatValue(block?.episodeCount) }
    ]));

    sections.push(renderSection('Stimulus', [
      { label: 'Stimulus set', value: formatValue(stimulusSetName) }
    ]));

    sections.push(renderSection('Rule', [
      { label: 'Rule name', value: formatValue(ruleName) }
    ]));

    sections.push(renderSection('Agent', [
      { label: 'Agent type', value: formatValue(agentTypeName) },
      ...buildRowsFromObject(agent, ['type'])
    ]));

    sections.push(renderSection('Reward Structure', [
      { label: 'Type', value: formatValue(rewardTypeName) },
      ...buildRowsFromObject(reward, ['type'])
    ]));

    sections.push(renderSection('Working Memory', [
      { label: 'Type', value: formatValue(workingMemoryTypeName) },
      { label: 'Decay constant', value: formatValue(workingMemory?.decayTimeConstant) },
      ...buildRowsFromObject(workingMemory, ['type', 'decayTimeConstant'])
    ]));

    sections.push(renderSection('Episode Termination', [
      { label: 'Type', value: formatValue(terminationTypeName) },
      { label: 'Max moves', value: formatValue(termination?.maxMoves ?? termination?.maxParticipantSelections) },
      { label: 'End when rewards exhausted', value: formatValue(termination?.endWhenRewardsExhausted ?? termination?.endsOnRewardsExhausted) },
      ...buildRowsFromObject(termination, ['type', 'maxMoves', 'maxParticipantSelections', 'endWhenRewardsExhausted', 'endsOnRewardsExhausted'])
    ]));

    const knownRootKeys = ['name', 'episodeCount', 'stimulusSet', 'ruleFile', 'rule', 'agent', 'rewardStructure', 'workingMemory', 'episodeTerminationPolicy'];
    sections.push(renderSection('Additional Parameters', buildRowsFromObject(block, knownRootKeys)));

    detailsEl.innerHTML = `<div class="designer-sections">${sections.filter(Boolean).join('')}</div>`;
  }

  function buildCard(block, index, onSelect) {
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'designer-block-card';
    const agentType = resolver
      ? resolver.resolveAgent(block?.agent?.type).displayName
      : (block?.agent?.type || '-');
    const stimulusSet = resolver
      ? resolver.resolveStimulusSet(block?.stimulusSet).displayName
      : block?.stimulusSet;
    const ruleName = resolver
      ? resolver.resolveRule(block?.ruleFile).displayName
      : block?.ruleFile;
    card.innerHTML = `
      <h5 class="designer-block-title">${escapeHtml(getDisplayText(block?.name, `Block ${index + 1}`))}</h5>
      <div class="designer-block-meta">
        <div><strong>Episodes:</strong> ${escapeHtml(getDisplayText(block?.episodeCount, '-'))}</div>
        <div><strong>Stimulus set:</strong> ${escapeHtml(getDisplayText(stimulusSet, '-'))}</div>
        <div><strong>Rule:</strong> ${escapeHtml(getDisplayText(ruleName, '-'))}</div>
        <div><strong>Agent:</strong> ${escapeHtml(getDisplayText(agentType, '-'))}</div>
      </div>
    `;
    card.addEventListener('click', () => onSelect(index));
    return card;
  }

  function renderBlocks(protocol) {
    listEl.innerHTML = '';
    const blocks = Array.isArray(protocol?.phases) ? protocol.phases : [];
    if (!blocks.length) {
      summaryEl.textContent = 'No blocks found in protocol.';
      detailsEl.textContent = 'Protocol does not define any blocks.';
      return;
    }

    let selectedIndex = 0;
    const cards = blocks.map((block, index) => buildCard(block, index, (nextIndex) => {
      selectedIndex = nextIndex;
      cards.forEach((node, nodeIndex) => {
        node.classList.toggle('selected', nodeIndex === selectedIndex);
      });
      renderDetails(blocks[selectedIndex]);
    }));

    cards.forEach((card) => listEl.appendChild(card));
    cards[0].classList.add('selected');
    renderDetails(blocks[0]);
  }

  async function init() {
    try {
      const experimentResponse = await fetch('experiment.json');
      if (!experimentResponse.ok) {
        throw new Error(`Failed to load experiment.json (HTTP ${experimentResponse.status})`);
      }
      const experiment = await experimentResponse.json();
      const protocolPath = experiment?.protocolFile || 'protocol.json';

      const protocolResponse = await fetch(protocolPath);
      if (!protocolResponse.ok) {
        throw new Error(`Failed to load ${protocolPath} (HTTP ${protocolResponse.status})`);
      }
      const protocol = await protocolResponse.json();

      if (window.DesignerDefinitionResolver) {
        resolver = new DesignerDefinitionResolver();
        await resolver.initialize(protocol);
      }

      renderSummary(protocol);
      renderBlocks(protocol);
    } catch (error) {
      summaryEl.textContent = 'Unable to load protocol.';
      descriptionEl.style.display = 'none';
      detailsEl.textContent = error?.message || String(error);
    }
  }

  init();
}

loadExperimentDesigner();