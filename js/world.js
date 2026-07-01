/*
 * world.js
 * Stores the internal state of one episode.
 */

export class World {
    constructor(config){
        this.config=config;
        this.resetSession();
    }

    resetSession(){
        this.sessionScore=0;
        this.episodeNumber=0;
    }

    startEpisode(imageInstances){
        this.episodeNumber++;
        this.episodeScore=0;
        this.trialNumber=0;
        this.currentActor="human";
        this.startTime=performance.now();

        this.positions=imageInstances.map((imageInstance,positionID)=>({
            positionID,
            imageInstance,
            resolved:false,
            resolvedBy:null,
            reward:null
        }));
    }

    getPosition(id){ return this.positions[id]; }
    isResolved(id){ return this.positions[id].resolved; }

    resolvePosition(id,actor,reward){
        const p=this.positions[id];
        p.resolved=true;
        p.resolvedBy=actor;
        p.reward=reward;
    }

    addReward(points){
        this.episodeScore+=points;
        this.sessionScore+=points;
    }

    nextTrial(){ this.trialNumber++; }

    setActor(actor){ this.currentActor=actor; }

    elapsedTime(){
        return (performance.now()-this.startTime)/1000;
    }

    remainingTime(){
        return Math.max(0,this.config.episodeLength-this.elapsedTime());
    }
}
