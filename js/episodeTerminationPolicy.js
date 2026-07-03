class BaseEpisodeTerminationPolicy {
  constructor(config = {}) {
    this.config = config;
  }

  evaluate() {
    return {
      shouldEnd: false,
      reasons: []
    };
  }
}

class StandardEpisodeTerminationPolicy extends BaseEpisodeTerminationPolicy {
  constructor(config = {}) {
    super(config);
    const configuredMaxMoves = Number(config.maxMoves ?? config.maxParticipantSelections);
    this.maxMoves = Number.isFinite(configuredMaxMoves) && configuredMaxMoves > 0
      ? Math.floor(configuredMaxMoves)
      : Number.MAX_SAFE_INTEGER;

    const rewardsFlag = config.endWhenRewardsExhausted;
    const legacyRewardsFlag = config.endsOnRewardsExhausted;
    this.endWhenRewardsExhausted = rewardsFlag !== undefined
      ? Boolean(rewardsFlag)
      : (legacyRewardsFlag !== undefined ? Boolean(legacyRewardsFlag) : true);
  }

  evaluate({ moveCount = 0, rewardsRemaining = 0 } = {}) {
    const reasons = [];
    if (this.endWhenRewardsExhausted && rewardsRemaining <= 0) {
      reasons.push('rewards_exhausted');
    }
    if (moveCount >= this.maxMoves) {
      reasons.push('move_limit');
    }
    return {
      shouldEnd: reasons.length > 0,
      reasons
    };
  }
}

class EpisodeTerminationPolicyFactory {
  create(config = {}) {
    const type = config?.type || 'standard';
    switch (type) {
      case 'standard':
        return new StandardEpisodeTerminationPolicy(config);
      default:
        return new StandardEpisodeTerminationPolicy(config);
    }
  }
}

window.BaseEpisodeTerminationPolicy = BaseEpisodeTerminationPolicy;
window.StandardEpisodeTerminationPolicy = StandardEpisodeTerminationPolicy;
window.EpisodeTerminationPolicyFactory = EpisodeTerminationPolicyFactory;