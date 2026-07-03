class ProtocolEngine {
  constructor(protocolDefinition = {}) {
    this.protocol = this.normalizeProtocol(protocolDefinition);
    this.phases = this.protocol.phases;
    this.repeat = this.protocol.repeat !== false;
    this.repeatFromPhase = this.protocol.repeatFromPhase;
    this.introEpisodes = this.phases
      .slice(0, this.repeatFromPhase)
      .reduce((sum, phase) => sum + phase.episodeCount, 0);
    this.totalEpisodesPerCycle = this.phases
      .slice(this.repeatFromPhase)
      .reduce((sum, phase) => sum + phase.episodeCount, 0);

    if (this.repeat && this.totalEpisodesPerCycle <= 0) {
      throw new Error('Protocol repeat requires at least one cycling phase.');
    }
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

    const requestedRepeatFrom = definition?.repeatFromPhase ?? definition?.cycleStartPhaseIndex;
    const repeatFromPhase = Number.isInteger(Number(requestedRepeatFrom))
      ? Math.min(Math.max(Number(requestedRepeatFrom), 0), normalizedPhases.length - 1)
      : 0;

    return {
      name: definition?.name || 'Protocol',
      repeat: definition?.repeat !== false,
      repeatFromPhase,
      phases: normalizedPhases
    };
  }

  locatePhase(episodeInWindow, startPhaseIndex, endPhaseIndexExclusive) {
    let remaining = episodeInWindow;
    for (let i = startPhaseIndex; i < endPhaseIndexExclusive; i += 1) {
      const phase = this.phases[i];
      if (remaining <= phase.episodeCount) {
        return {
          phase,
          phaseIndex: i,
          phaseEpisode: remaining
        };
      }
      remaining -= phase.episodeCount;
    }
    const fallbackIndex = Math.max(startPhaseIndex, endPhaseIndexExclusive - 1);
    const fallbackPhase = this.phases[fallbackIndex];
    return {
      phase: fallbackPhase,
      phaseIndex: fallbackIndex,
      phaseEpisode: fallbackPhase?.episodeCount || 1
    };
  }

  getPhaseForEpisode(episodeNumber) {
    const ep = Math.max(1, Number(episodeNumber) || 1);

    if (!this.repeat) {
      const allEpisodes = this.phases.reduce((sum, phase) => sum + phase.episodeCount, 0);
      const clamped = Math.min(ep, allEpisodes);
      const located = this.locatePhase(clamped, 0, this.phases.length);
      return {
        ...located,
        blockNumber: located.phaseIndex + 1
      };
    }

    if (ep <= this.introEpisodes) {
      const located = this.locatePhase(ep, 0, this.repeatFromPhase);
      return {
        ...located,
        blockNumber: located.phaseIndex + 1
      };
    }

    const cycleEpisode = ((ep - this.introEpisodes - 1) % this.totalEpisodesPerCycle) + 1;
    const cycleIndex = Math.floor((ep - this.introEpisodes - 1) / this.totalEpisodesPerCycle);
    const located = this.locatePhase(cycleEpisode, this.repeatFromPhase, this.phases.length);
    const cyclePhaseCount = this.phases.length - this.repeatFromPhase;
    const cyclePhaseOffset = located.phaseIndex - this.repeatFromPhase;
    const blockNumber = this.repeatFromPhase + (cycleIndex * cyclePhaseCount) + cyclePhaseOffset + 1;

    return {
      ...located,
      blockNumber
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
