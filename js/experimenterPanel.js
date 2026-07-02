class ExperimenterPanel{
  constructor(containerId){
    this.el=document.getElementById(containerId);
    if(!this.el) return;
    this.el.classList.add('experimenter-panel');
    this.el.innerHTML = `
      <div class="expander">Experimenter ▸</div>
      <div class="content" style="display:none">
        <div class="row"><strong>Episode:</strong> <span data-key="episode">-</span></div>
        <div class="row"><strong>Rule:</strong> <span data-key="rule">-</span></div>
        <div class="row"><strong>Agent:</strong> <span data-key="agent">-</span></div>
        <div class="row"><strong>Rewards remaining:</strong> <span data-key="rewards">-</span></div>
        <div class="row"><strong>Episodes until switch:</strong> <span data-key="untilSwitch">-</span></div>
      </div>`;
    this.header=this.el.querySelector('.expander');
    this.content=this.el.querySelector('.content');
    this.header.addEventListener('click',()=>this.toggle());
    this.collapsed=true;
  }

  toggle(){
    this.collapsed = !this.collapsed;
    this.content.style.display = this.collapsed ? 'none' : 'block';
    this.header.textContent = this.collapsed ? 'Experimenter ▸' : 'Experimenter ▾';
  }

  update(state={}){
    if(!this.el) return;
    const set = (k,v)=>{ const el=this.el.querySelector(`[data-key="${k}"]`); if(el) el.textContent=v; };
    set('episode', state.episodeNumber ?? '-');
    set('rule', state.currentRule ?? state.ruleIndex ?? '-');
    set('agent', state.agentType ?? '-');
    set('rewards', state.rewardsRemaining ?? '-');
    set('untilSwitch', state.episodesUntilNextSwitch ?? '-');
  }
}

// Expose globally
window.ExperimenterPanel = ExperimenterPanel;
