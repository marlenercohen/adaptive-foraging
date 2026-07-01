/*
 * logger.js
 */

export class Logger{
    constructor(){ this.events=[]; }

    log(type,data={}){
        this.events.push({
            timestamp:performance.now(),
            type,
            ...data
        });
    }

    clear(){ this.events=[]; }

    getEvents(){ return [...this.events]; }
}
