function [participantRewards, agentRewards] = afRewardTotals(rewardEvents)
%AFREWARDTOTALS Sum reward allocation deltas from reward events.

    participantRewards = 0;
    agentRewards = 0;

    for i = 1:numel(rewardEvents)
        data = afField(rewardEvents(i), 'data', struct());
        allocation = afField(data, 'rewardAllocation', struct());
        alloc = afField(allocation, 'allocation', struct());

        participantRewards = participantRewards + afField(alloc, 'humanDelta', 0);
        agentRewards = agentRewards + afField(alloc, 'agentDelta', 0);
    end
end
