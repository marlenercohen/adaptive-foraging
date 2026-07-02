class AgentFactory {
  createAgent(config = {}) {
    const type = config?.type || 'random';

    switch(type) {
      case 'random':
        return new RandomAgent();
      case 'feature-learning':
        return new FeatureLearningAgent();
      case 'reinforcement-learning':
        return new RandomAgent();
      case 'imitation':
        return new RandomAgent();
      case 'hybrid':
        return new RandomAgent();
      default:
        return new RandomAgent();
    }
  }
}
