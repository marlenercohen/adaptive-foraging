class BaseRewardStructure {
  constructor(config = {}) {
    this.config = config;
  }

  distributeReward({ actor, reward, gameState } = {}) {
    return {
      actor,
      reward: Boolean(reward),
      allocation: {
        humanDelta: 0,
        agentDelta: 0
      },
      meta: {
        type: 'base',
        config: this.config,
        gameState
      }
    };
  }
}

class IndividualRewardStructure extends BaseRewardStructure {
  constructor(config = {}) {
    super(config);
    const rewardPerHit = Number(config.rewardPerHit);
    this.rewardPerHit = Number.isFinite(rewardPerHit) ? rewardPerHit : 1;
  }

  distributeReward({ actor, reward, gameState } = {}) {
    const isRewarded = Boolean(reward);
    const humanDelta = isRewarded && actor === 'human' ? this.rewardPerHit : 0;
    const agentDelta = isRewarded && actor === 'agent' ? this.rewardPerHit : 0;
    return {
      actor,
      reward: isRewarded,
      allocation: {
        humanDelta,
        agentDelta
      },
      meta: {
        type: 'individual',
        config: this.config,
        gameState
      }
    };
  }
}

class RewardStructureFactory {
  create(config = {}) {
    const type = config?.type || 'individual';
    switch (type) {
      case 'individual':
        return new IndividualRewardStructure(config);
      default:
        return new IndividualRewardStructure(config);
    }
  }
}

window.BaseRewardStructure = BaseRewardStructure;
window.IndividualRewardStructure = IndividualRewardStructure;
window.RewardStructureFactory = RewardStructureFactory;