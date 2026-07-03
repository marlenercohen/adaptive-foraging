class EpisodeController {
  constructor(maxParticipantSelections = 0) {
    this.episodeNumber = 0;
    this.participantSelections = 0;
    this.totalSelections = 0;
    this.maxParticipantSelections = maxParticipantSelections;
    this.rewardsRemaining = 0;
  }

  resetEpisode(rewardCount) {
    this.episodeNumber += 1;
    this.participantSelections = 0;
    this.totalSelections = 0;
    this.rewardsRemaining = rewardCount;
  }

  recordSelection() {
    this.totalSelections += 1;
  }

  recordParticipantSelection() {
    this.participantSelections += 1;
  }

  recordRewardCollected() {
    if (this.rewardsRemaining > 0) {
      this.rewardsRemaining -= 1;
    }
  }

  isEpisodeComplete() {
    return this.participantSelections >= this.maxParticipantSelections || this.rewardsRemaining === 0;
  }
}
