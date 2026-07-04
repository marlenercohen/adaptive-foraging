class DesignerDefinitionResolver {
  constructor(options = {}) {
    this.paths = {
      rules: options.rulesManifestPath || 'designer/definitions/rules.manifest.json',
      agents: options.agentsManifestPath || 'designer/definitions/agents.manifest.json',
      rewardStructures: options.rewardStructuresManifestPath || 'designer/definitions/reward-structures.manifest.json',
      episodeTerminationPolicies: options.episodeTerminationPoliciesManifestPath || 'designer/definitions/episode-termination-policies.manifest.json',
      workingMemoryModels: options.workingMemoryModelsManifestPath || 'designer/definitions/working-memory-models.manifest.json'
    };

    this.catalogs = {
      rules: {},
      agents: {},
      rewardStructures: {},
      episodeTerminationPolicies: {},
      workingMemoryModels: {}
    };

    this.stimulusSets = {};
    this.stimulusRegistry = typeof StimulusRegistry === 'function' ? new StimulusRegistry() : null;
  }

  async loadJson(path, label) {
    const response = await fetch(path);
    if (!response.ok) {
      throw new Error(`Failed to load ${label} from ${path} (HTTP ${response.status}).`);
    }
    return response.json();
  }

  normalizeManifest(manifest, key) {
    const definitions = Array.isArray(manifest?.definitions) ? manifest.definitions : [];
    this.catalogs[key] = definitions.reduce((acc, definition) => {
      if (definition && typeof definition.id === 'string' && definition.id) {
        acc[definition.id] = definition;
      }
      return acc;
    }, {});
  }

  async initialize(protocol) {
    const manifests = await Promise.all([
      this.loadJson(this.paths.rules, 'rule definitions'),
      this.loadJson(this.paths.agents, 'agent definitions'),
      this.loadJson(this.paths.rewardStructures, 'reward structure definitions'),
      this.loadJson(this.paths.episodeTerminationPolicies, 'episode termination policy definitions'),
      this.loadJson(this.paths.workingMemoryModels, 'working memory model definitions')
    ]);

    this.normalizeManifest(manifests[0], 'rules');
    this.normalizeManifest(manifests[1], 'agents');
    this.normalizeManifest(manifests[2], 'rewardStructures');
    this.normalizeManifest(manifests[3], 'episodeTerminationPolicies');
    this.normalizeManifest(manifests[4], 'workingMemoryModels');

    const blocks = Array.isArray(protocol?.phases) ? protocol.phases : [];
    const stimulusSets = [...new Set(blocks.map((block) => block?.stimulusSet).filter(Boolean))];

    if (!this.stimulusRegistry) {
      return;
    }

    await Promise.all(stimulusSets.map(async (setName) => {
      try {
        this.stimulusSets[setName] = await this.stimulusRegistry.resolve(setName);
      } catch (_) {
        this.stimulusSets[setName] = null;
      }
    }));
  }

  resolveFromCatalog(catalogKey, id, fallback = '-') {
    const identifier = id || '';
    const definition = this.catalogs[catalogKey]?.[identifier] || null;
    if (definition && definition.displayName) {
      return {
        id: identifier,
        displayName: definition.displayName,
        description: definition.description || ''
      };
    }
    return {
      id: identifier,
      displayName: identifier || fallback,
      description: ''
    };
  }

  resolveStimulusSet(setName) {
    const definition = this.stimulusSets?.[setName];
    if (definition && definition.displayName) {
      return {
        id: setName,
        displayName: definition.displayName,
        description: definition.description || ''
      };
    }
    return {
      id: setName || '',
      displayName: setName || '-',
      description: ''
    };
  }

  resolveRule(ruleFile) {
    return this.resolveFromCatalog('rules', ruleFile, '-');
  }

  resolveAgent(agentType) {
    return this.resolveFromCatalog('agents', agentType, '-');
  }

  resolveRewardStructure(type) {
    return this.resolveFromCatalog('rewardStructures', type, '-');
  }

  resolveEpisodeTerminationPolicy(type) {
    return this.resolveFromCatalog('episodeTerminationPolicies', type, '-');
  }

  resolveWorkingMemoryModel(type) {
    return this.resolveFromCatalog('workingMemoryModels', type || 'default', '-');
  }
}

window.DesignerDefinitionResolver = DesignerDefinitionResolver;
