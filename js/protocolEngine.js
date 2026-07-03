class ProtocolEngine {
  constructor(protocolDefinition = {}) {
    this.protocol = this.normalizeProtocol(protocolDefinition);
    this.phases = this.protocol.phases;
    this.repeat = this.protocol.repeat !== false;
    this.totalEpisodesPerCycle = this.phases.reduce((sum, phase) => sum + phase.episodeCount, 0);
  }

  normalizeProtocol(definition) {
    const phases = Array.isArray(definition?.phases) ? definition.phases : [];
    if (!phases.length) {
      throw new Error('Protocol must include at least one phase.');
    }

    const normalizedPhases = phases.map((phase, index) => {
      const episodeCount = Number(phase.episodeCount);
      if (!Number.isFinite(episodeCount) || episodeCount <= 0) {
        throw new Error(`Protocol phase ${index + 1} has invalid episodeCount.`);
      }

      return {
        name: phase.name || `Phase ${index + 1}`,
        episodeCount: Math.floor(episodeCount),
        stimulusMetadataFile: phase.stimulusMetadataFile,
        stimuliPerEpisode: phase.stimuliPerEpisode,
        ruleFile: phase.ruleFile,
        agent: phase.agent || {},
        workingMemory: phase.workingMemory || {},
        rewardStructure: phase.rewardStructure || { rewardPerHit: 1 },
        episodeTerminationPolicy: phase.episodeTerminationPolicy || {}
      };
    });

    return {
      name: definition?.name || 'Protocol',
      repeat: definition?.repeat !== false,
      phases: normalizedPhases
    };
  }

  getPhaseForEpisode(episodeNumber) {
    const ep = Math.max(1, Number(episodeNumber) || 1);
    const cycleEpisode = this.repeat
      ? ((ep - 1) % this.totalEpisodesPerCycle) + 1
      : Math.min(ep, this.totalEpisodesPerCycle);
    let remaining = cycleEpisode;

    for (let i = 0; i < this.phases.length; i += 1) {
      const phase = this.phases[i];
      if (remaining <= phase.episodeCount) {
        const cycleIndex = Math.floor((ep - 1) / this.totalEpisodesPerCycle);
        const blockNumber = this.repeat
          ? (cycleIndex * this.phases.length) + i + 1
          : i + 1;
        return {
          phase,
          phaseIndex: i,
          phaseEpisode: remaining,
          blockNumber
        };
      }
      remaining -= phase.episodeCount;
    }

    const lastIndex = this.phases.length - 1;
    return {
      phase: this.phases[lastIndex],
      phaseIndex: lastIndex,
      phaseEpisode: this.phases[lastIndex].episodeCount,
      blockNumber: lastIndex + 1
    };
  }

  episodesUntilNextPhase(episodeNumber) {
    const info = this.getPhaseForEpisode(episodeNumber);
    return Math.max(0, info.phase.episodeCount - info.phaseEpisode);
  }

  getExecutedProtocol() {
    return JSON.parse(JSON.stringify(this.protocol));
  }
}

window.ProtocolEngine = ProtocolEngine;