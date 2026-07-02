
class Logger{
 constructor(){this.events=[];}
 log(type,data){this.events.push({type,...data});console.log("LOG",type,data);}
}
