class ProtocolEngine {
  constructor(protocolDefinition = {}) {
    this.protocol = this.normalizeProtocol(protocolDefinition);
    this.phases = this.protocol.phases;
    this.loops = this.protocol.loops;
    this.hasLoops = this.loops.length > 0;
    this.repeat = this.protocol.repeat !== false;
    this.repeatFromPhase = this.protocol.repeatFromPhase;

    this.expandedPhaseSchedule = [];
    this.totalEpisodes = 0;
    this.introEpisodes = 0;
    this.totalEpisodesPerCycle = 0;

    if (this.hasLoops) {
      this.expandedPhaseSchedule = this.buildExpandedPhaseSchedule(this.phases, this.loops);
      this.totalEpisodes = this.expandedPhaseSchedule.reduce((sum, scheduledPhase) => {
        const phase = this.phases[scheduledPhase.phaseIndex];
        return sum + (phase?.episodeCount || 0);
      }, 0);
    } else {
      this.totalEpisodes = this.phases.reduce((sum, phase) => sum + phase.episodeCount, 0);
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
        stimulusSet: phase.stimulusSet || null,
        stimulusPopulation: Array.isArray(phase.stimulusPopulation) ? [...phase.stimulusPopulation] : null,
        stimuliPerEpisode: phase.stimuliPerEpisode,
        ruleFile: phase.ruleFile,
        agent: phase.agent || {},
        workingMemory: phase.workingMemory || {},
        rewardStructure: phase.rewardStructure || { rewardPerHit: 1 },
        episodeTerminationPolicy: phase.episodeTerminationPolicy || {}
      };
    });

    const rawLoops = Array.isArray(definition?.loops) ? definition.loops : [];

    const hasLegacyRepeatFields =
      Object.prototype.hasOwnProperty.call(definition || {}, 'repeat')
      || Object.prototype.hasOwnProperty.call(definition || {}, 'repeatFromPhase')
      || Object.prototype.hasOwnProperty.call(definition || {}, 'cycleStartPhaseIndex');

    if (rawLoops.length > 0 && hasLegacyRepeatFields) {
      throw new Error('Protocol cannot define both "loops" and legacy repeat fields ("repeat", "repeatFromPhase", or "cycleStartPhaseIndex"). Use only one repetition mechanism.');
    }

    const normalizedLoops = this.normalizeLoops(rawLoops, normalizedPhases.length);

    const requestedRepeatFrom = definition?.repeatFromPhase ?? definition?.cycleStartPhaseIndex;
    const repeatFromPhase = Number.isInteger(Number(requestedRepeatFrom))
      ? Math.min(Math.max(Number(requestedRepeatFrom), 0), normalizedPhases.length - 1)
      : 0;

    return {
      name: definition?.name || 'Protocol',
      repeat: definition?.repeat !== false,
      repeatFromPhase,
      loops: normalizedLoops,
      phases: normalizedPhases
    };
  }

  normalizeLoops(loops, phaseCount) {
    if (!Array.isArray(loops)) {
      return [];
    }

    const normalizedLoops = loops.map((loop, index) => {
      const startPhase = Number(loop?.startPhase);
      const endPhase = Number(loop?.endPhase);
      const repeatCount = Number(loop?.repeatCount);

      if (!Number.isInteger(startPhase)) {
        throw new Error(`Loop ${index + 1} has invalid "startPhase"; expected an integer phase index.`);
      }
      if (!Number.isInteger(endPhase)) {
        throw new Error(`Loop ${index + 1} has invalid "endPhase"; expected an integer phase index.`);
      }
      if (!Number.isInteger(repeatCount) || repeatCount < 0) {
        throw new Error(`Loop ${index + 1} has invalid "repeatCount"; expected an integer >= 0.`);
      }
      if (startPhase < 0 || startPhase >= phaseCount) {
        throw new Error(`Loop ${index + 1} has "startPhase" ${startPhase} outside valid range 0..${Math.max(phaseCount - 1, 0)}.`);
      }
      if (endPhase < 0 || endPhase >= phaseCount) {
        throw new Error(`Loop ${index + 1} has "endPhase" ${endPhase} outside valid range 0..${Math.max(phaseCount - 1, 0)}.`);
      }
      if (endPhase < startPhase) {
        throw new Error(`Loop ${index + 1} has invalid range: "endPhase" (${endPhase}) must be >= "startPhase" (${startPhase}).`);
      }

      return {
        name: loop?.name || `Loop ${index + 1}`,
        startPhase,
        endPhase,
        repeatCount
      };
    });

    for (let i = 1; i < normalizedLoops.length; i += 1) {
      const previous = normalizedLoops[i - 1];
      const current = normalizedLoops[i];

      if (current.startPhase <= previous.startPhase) {
        throw new Error(
          `Loop "${current.name}" must appear after loop "${previous.name}" in ascending order of "startPhase".`
        );
      }

      if (current.startPhase <= previous.endPhase) {
        throw new Error(
          `Loop "${current.name}" overlaps or nests loop "${previous.name}". Loops must be non-overlapping and non-nested.`
        );
      }
    }

    return normalizedLoops;
  }

  buildExpandedPhaseSchedule(phases, loops) {
    if (!loops.length) {
      return phases.map((_, phaseIndex) => ({
        phaseIndex,
        loopIteration: 0
      }));
    }

    const schedule = [];
    let cursor = 0;

    loops.forEach(loop => {
      for (let phaseIndex = cursor; phaseIndex < loop.startPhase; phaseIndex += 1) {
        schedule.push({ phaseIndex, loopIteration: 0 });
      }

      for (let iteration = 0; iteration <= loop.repeatCount; iteration += 1) {
        for (let phaseIndex = loop.startPhase; phaseIndex <= loop.endPhase; phaseIndex += 1) {
          schedule.push({ phaseIndex, loopIteration: iteration });
        }
      }

      cursor = loop.endPhase + 1;
    });

    for (let phaseIndex = cursor; phaseIndex < phases.length; phaseIndex += 1) {
      schedule.push({ phaseIndex, loopIteration: 0 });
    }

    return schedule;
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

  locatePhaseInExpandedSchedule(episodeNumber) {
    const clampedEpisode = Math.min(Math.max(1, Number(episodeNumber) || 1), this.totalEpisodes);
    let remaining = clampedEpisode;

    for (let scheduleIndex = 0; scheduleIndex < this.expandedPhaseSchedule.length; scheduleIndex += 1) {
      const scheduled = this.expandedPhaseSchedule[scheduleIndex];
      const phase = this.phases[scheduled.phaseIndex];
      if (remaining <= phase.episodeCount) {
        return {
          phase,
          phaseIndex: scheduled.phaseIndex,
          phaseEpisode: remaining,
          blockNumber: scheduleIndex + 1,
          loopIteration: scheduled.loopIteration
        };
      }
      remaining -= phase.episodeCount;
    }

    const fallbackIndex = Math.max(0, this.expandedPhaseSchedule.length - 1);
    const fallbackScheduled = this.expandedPhaseSchedule[fallbackIndex] || { phaseIndex: 0, loopIteration: 0 };
    const fallbackPhase = this.phases[fallbackScheduled.phaseIndex] || this.phases[0];

    return {
      phase: fallbackPhase,
      phaseIndex: fallbackScheduled.phaseIndex,
      phaseEpisode: fallbackPhase?.episodeCount || 1,
      blockNumber: fallbackIndex + 1,
      loopIteration: fallbackScheduled.loopIteration
    };
  }

  getPhaseForEpisode(episodeNumber) {
    if (this.hasLoops) {
      return this.locatePhaseInExpandedSchedule(episodeNumber);
    }

    const ep = Math.max(1, Number(episodeNumber) || 1);

    if (!this.repeat) {
      const allEpisodes = this.phases.reduce((sum, phase) => sum + phase.episodeCount, 0);
      const clamped = Math.min(ep, allEpisodes);
      const located = this.locatePhase(clamped, 0, this.phases.length);
      return {
        ...located,
        blockNumber: located.phaseIndex + 1,
        loopIteration: 0
      };
    }

    if (ep <= this.introEpisodes) {
      const located = this.locatePhase(ep, 0, this.repeatFromPhase);
      return {
        ...located,
        blockNumber: located.phaseIndex + 1,
        loopIteration: 0
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
      blockNumber,
      loopIteration: 0
    };
  }

  episodesUntilNextPhase(episodeNumber) {
    const info = this.getPhaseForEpisode(episodeNumber);
    return Math.max(0, info.phase.episodeCount - info.phaseEpisode);
  }

  getNextEpisodeNumber(completedEpisodeNumber) {
    const completed = Math.max(0, Number(completedEpisodeNumber) || 0);
    if (this.hasLoops) {
      return completed < this.totalEpisodes ? completed + 1 : null;
    }
    if (this.repeat) {
      return completed + 1;
    }
    return completed < this.totalEpisodes ? completed + 1 : null;
  }

  getExecutedProtocol() {
    return JSON.parse(JSON.stringify(this.protocol));
  }
}

window.ProtocolEngine = ProtocolEngine;
