/* 点击 .more[data-pop="id"] 弹出 <template id="id"> 的内容；Esc / 点遮罩 / 点 ✕ 关闭 */
(function(){
  let mask=null;
  function close(){ if(mask){ mask.remove(); mask=null; } }
  function open(id){
    const t=document.getElementById(id); if(!t) return;
    close();
    mask=document.createElement('div'); mask.className='pop-mask';
    const box=document.createElement('div'); box.className='pop';
    const x=document.createElement('button'); x.className='x'; x.textContent='✕ 关闭'; x.onclick=close;
    box.appendChild(x); box.appendChild(t.content.cloneNode(true));
    mask.appendChild(box);
    mask.addEventListener('click',e=>{ if(e.target===mask) close(); });
    document.body.appendChild(mask);
    box.scrollTop=0;
  }
  document.addEventListener('click',e=>{
    const b=e.target.closest('.more[data-pop]'); if(!b) return;
    e.preventDefault(); e.stopPropagation(); open(b.dataset.pop);
  },true);
  /* 弹窗打开时拦截键盘，避免 Esc 进总览、方向键翻页 */
  document.addEventListener('keydown',e=>{
    if(!mask) return;
    if(e.key==='Escape') close();
    e.stopPropagation();
  },true);
  if(window.Reveal) Reveal.on('slidechanged',close);
})();
