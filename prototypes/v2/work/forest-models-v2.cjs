const fs=require('fs'), path=require('path');
// v2 copy: writes only to ForestStudy-v2. Pass --new-only to build just the jungle additions.
const dir=path.join(__dirname,'../outputs/ForestStudy-v2/models');
const newOnly=process.argv.includes("--new-only");
let seed=173, groups={};
const r=()=>((seed=Math.imul(seed,1664525)+1013904223>>>0)/4294967296), rr=(a,b)=>a+(b-a)*r(), tau=Math.PI*2;
const add=(a,b)=>a.map((x,i)=>x+b[i]), sub=(a,b)=>a.map((x,i)=>x-b[i]), mul=(a,s)=>a.map(x=>x*s), at=(a,b,t)=>add(a,mul(sub(b,a),t));
const len=a=>Math.hypot(...a), unit=a=>mul(a,1/(len(a)||1)), cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]], up=[0,1,0], vec=(ang,l,h=0)=>[Math.cos(ang)*l,h,Math.sin(ang)*l];
function vert(g,p,c){let m=groups[g]??={p:[],n:[],c:[],idx:[]};m.p.push(...p);m.n.push(0,0,0);m.c.push(...c.map(x=>Math.min(1,Math.max(0,x))));return m.p.length/3-1}
function tri(g,a,b,c){let m=groups[g],pos=i=>m.p.slice(i*3,i*3+3),n=cross(sub(pos(b),pos(a)),sub(pos(c),pos(a)));m.idx.push(a,b,c);for(let i of [a,b,c])for(let k=0;k<3;k++)m.n[i*3+k]+=n[k]}
const bark=[.105,.073,.051], moss=[.077,.123,.052],green=[.045,.19,.083],jade=[.058,.25,.19],violet=[.29,.078,.36];
function tube(points,radii,sides=8,color=bark,g='Wood'){
 let last=[],side=unit(cross(unit(sub(points[1],points[0])),[.32,.12,.93])), fl=Array.from({length:sides},()=>rr(.80,1.16));
 points.forEach((p,j)=>{let axis=unit(sub(points[Math.min(points.length-1,j+1)],points[Math.max(0,j-1)])),v=unit(cross(axis,side));side=unit(cross(v,axis));let row=[];
 for(let k=0;k<sides;k++){let a=tau*k/sides,offset=add(mul(side,Math.cos(a)),mul(v,Math.sin(a)));let c=mul(color,(.8+.28*Math.cos(3*a)+.12*r())*(g==='Wood'?(.93+.12*j/points.length):1));row.push(vert(g,add(p,mul(offset,radii[j]*fl[k])),c));if(g==='Wood'){(groups[g].uv??=[]).push(k/sides*3, len(sub(p,points[0]))*.42)}}
 if(j)for(let k=0;k<sides;k++){let l=(k+1)%sides;tri(g,last[k],last[l],row[l]);tri(g,last[k],row[l],row[k])}last=row})
}
function leaf(base,dir,L,W,arch,color,g='Foliage'){
 let side=unit(cross(dir,up)),row;for(let j=0;j<=5;j++){let t=j/5,mid=add(add(base,mul(dir,L*t)),mul(up,arch*Math.sin(Math.PI*t)-L*.13*t*t)),w=W*(.012+Math.pow(Math.sin(Math.PI*t),.8))*(1-.24*t);
 let ids=[-1,0,1].map((k)=>vert(g,add(add(mid,mul(side,k*w)),mul(up,k===0?w*.19:0)),mul(color,(k===0?1.18:k<0?.84:1.01)*(.73+.38*t))));
 if(row)for(let k=0;k<2;k++){tri(g,row[k],ids[k],ids[k+1]);tri(g,row[k],ids[k+1],row[k+1])}row=ids}
}
function spray(p,a,L,fern=false){
 let n=fern?16:8,pts=Array.from({length:n+1},(_,i)=>{let t=i/n;return add(p,vec(a,L*t,L*(.32*Math.sin(t*Math.PI)-.14*t)))});
 tube(pts,pts.map((_,i)=>L*(.012-.009*i/n)),4,moss,'Stems');
 for(let i=1;i<n;i++)for(let sign of [-1,1]){let t=i/n,d=vec(a+sign*(1.16-.39*t),1,rr(-.14,.15)),l=L*(fern?.32:.36)*(.4+.6*Math.sin(Math.PI*t));leaf(pts[i],unit(d),l,l*(fern?.087:.23),l*.13,mul(fern?jade:green,rr(.63,1.34)))}
}
function shelf(p,a,L){let prev;for(let j=0;j<7;j++){let t=j/6,row=[];for(let k=0;k<=16;k++){let angle=a+(k/16-.5)*2.84,w=L*(.92+.08*Math.sin(k*.92));let v=add(p,vec(angle,.025+w*t,L*(.17*Math.sin(t*Math.PI)-.09*t+.034*t*Math.cos(k*1.3))));let col=at([.08,.10,.16],[.37,.20,.43],t);if(j===6)col=[.48,.39,.65];row.push(vert('Shelf',v,mul(col,.80+.2*Math.cos(k*.8))))}if(prev)for(let k=0;k<16;k++){tri('Shelf',prev[k],row[k+1],row[k]);tri('Shelf',prev[k],prev[k+1],row[k+1])}prev=row}}
function barkMap(){
 const z=require('zlib'), W=256,H=512,buf=Buffer.alloc((W*3+1)*H);
 const hash=(x,y)=>{let h=Math.imul(x,1597334677)^Math.imul(y,3812015801);h=Math.imul(h^(h>>>13),2246822519);return (h>>>0)/4294967296};
 function noise(u,v,n,m){let x=u*n,y=v*m,i=Math.floor(x),j=Math.floor(y),f=x-i,g=y-j;f*=f*(3-2*f);g*=g*(3-2*g);let h=(a,b)=>hash((a%n+n)%n,(b%m+m)%m);return (1-g)*((1-f)*h(i,j)+f*h(i+1,j))+g*((1-f)*h(i,j+1)+f*h(i+1,j+1))}
 for(let y=0;y<H;y++)for(let x=0;x<W;x++){let u=x/W,v=y/H,warp=u+.052*noise(u,v,6,5)+.013*noise(u,v,12,14),ridge=noise(warp,v,48,7),fine=noise(warp,v,110,33),lichen=Math.max(0,noise(u,v,5,12)-.53);let k=138+89*ridge+29*fine-66*Math.pow(1-ridge,5)+16*noise(u,v,180,180);let o=y*(W*3+1)+1+3*x;buf[o]=k*(.99-lichen*.75);buf[o+1]=Math.min(255,k+lichen*120);buf[o+2]=k*(.91-lichen*.65)}
 function chunk(name,data){let type=Buffer.from(name),out=Buffer.alloc(data.length+12);out.writeUInt32BE(data.length);type.copy(out,4);data.copy(out,8);let crc=-1;for(let b of Buffer.concat([type,data])){crc^=b;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0)}out.writeUInt32BE((~crc)>>>0,data.length+8);return out}
 let hdr=Buffer.alloc(13);hdr.writeUInt32BE(W);hdr.writeUInt32BE(H,4);hdr[8]=8;hdr[9]=2;return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',hdr),chunk('IDAT',z.deflateSync(buf)),chunk('IEND',Buffer.alloc(0))])
}
// Climbing skeleton: trunk axis and main branches, in the model's own units. Recording consumes no randomness.
let skeleton=null;
function tree(banyan){
 let H=banyan?18:29,R=banyan?1.45:1.85, core=t=>[.9*Math.sin(t*3),H*t,.47*Math.sin(t*5)];
 let pts=Array.from({length:16},(_,j)=>core(j/15));tube(pts,pts.map((_,j)=>R*(1.08-.98*j/15+.65*Math.exp(-j))),22);
 skeleton={height:H,trunk:pts,trunkRadii:pts.map((_,j)=>R*(1.08-.98*j/15+.65*Math.exp(-j))),branches:[]};
  // Keep the buttress tight to the bole. Its outer length is already underground.
 for(let i=0;i<11;i++){
  let a=tau*i/11+rr(-.18,.18), reach=R*rr(1.75,2.23);
  let root=[vec(a,R*.84,1.25),vec(a,R*1.15,.28),vec(a+.09,reach*.83,-.30),vec(a+.14,reach,-.85)];
  tube(root,[.45,.38,.19,.035],9)
 }
 for(let i=0;i<20;i++){let t=.43+.55*i/20,a=i*2.40+rr(-.22,.22),reach=(banyan?10.7:8.2)*(1.23-.62*t)*rr(.82,1.22),base=core(t),p=add(base,vec(a,reach*.36,1.45)),q=add(base,vec(a+.09,reach*.73,2.35)),tip=add(base,vec(a+.16,reach,rr(2.7,3.8)));
 tube([base,p,q,tip],[R*.42,R*.30,R*.155,.06],9);
 skeleton.branches.push({t,points:[base,p,q,tip],radii:[R*.42,R*.30,R*.155,.06]});
 for(let j=0;j<7;j++){let start=at(j<3?p:q,j<3?q:tip,(j%3)/3),az=a+(j%2?1:-1)*rr(.55,1.55),end=add(start,vec(az,rr(1.7,3.0),rr(.5,1.75)));tube([start,at(start,end,.52),end],[.105,.075,.022],5);
 for(let s=0;s<6;s++)spray(at(start,end,.22+.77*s/5),az+(s%2?1:-1)*rr(.68,1.56),rr(1.45,2.5))}
 if(banyan&&i%2===0){let end=[q[0]+rr(-1,1),i%8===0 ? -.85 : Math.max(5.5,q[1]*.57),q[2]+rr(-1,1)];tube([q,add(at(q,end,.32),vec(a,.55)),at(q,end,.67),end],[.17,.12,.115,.26],7,mul(bark,.83))}
 else if(i%2===0){let end=add(q,[.3,-rr(2,5),.1]);tube([q,add(at(q,end,.55),vec(a,.24)),end],[.055,.038,.009],5,moss);for(let k=1;k<10;k++)leaf(at(q,end,k/10),unit(vec(k*2.4,.7,-.6)),.42,.10,.08,jade)}
 }
 if(!banyan)for(let i=0;i<4;i++){let t=.08+.41*i/4,a=i*2.4;shelf(add(core(t),vec(a,R*(1-t)*.9)),a,rr(.8,2.05))}
}
function palm(){for(let i=0;i<3;i++){let a=i*2.4,H=8+i*2.3,pts=Array.from({length:12},(_,j)=>{let t=j/11;return vec(a,.35+2.1*t*t,H*t)});tube(pts,pts.map((_,j)=>.36-.016*j),12,[.14,.115,.08]);for(let k=0;k<17;k++)spray(pts[11],k*2.4,rr(3.1,5.1),true)}}
function rosette(){for(let j=0;j<30;j++){let t=j/30,a=j*2.4;leaf([0,.03,0],unit(vec(a,1-t*.85,.24+t*.9)),2.15-t*.58,.19+.06*(1-t),.52,at([.035,.21,.16],violet,t),j>23?'Petals':'Foliage')}}
function fern(){for(let i=0;i<16;i++){let a=i*2.4;let base=vec(a,.19,rr(.36,.85));tube([[0,0,0],base],[.03,.024],5,moss);spray(base,a,rr(1.4,2.25),true)}}
function fungus(){for(let j=0;j<9;j++){let a=j*2.4,p=vec(a,rr(.18,1.1),0),q=add(p,[.09,rr(.28,1.3),.13]);tube([p,at(p,q,.65),q],[.1,.07,.09],8,[.13,.13,.17]);shelf(q,a,rr(.48,.92))}}
function save(name){
 let buffers=[],offset=0, views=[],access=[],primitives=[],materials=[];
 function append(typed,type,kind,minmax){let bytes=Buffer.from(typed.buffer);let view=views.push({buffer:0,byteOffset:offset,byteLength:bytes.length})-1;buffers.push(bytes);offset+=bytes.length;let n=type==='VEC3'?3:type==='VEC2'?2:1;let obj={bufferView:view,componentType:kind,count:typed.length/n,type};if(minmax){obj.min=[Infinity,Infinity,Infinity];obj.max=[-Infinity,-Infinity,-Infinity];typed.forEach((x,i)=>{let k=i%3;obj.min[k]=Math.min(obj.min[k],x);obj.max[k]=Math.max(obj.max[k],x)})}return access.push(obj)-1}
 for(let [g,m] of Object.entries(groups)){for(let i=0;i<m.n.length;i+=3){let v=unit(m.n.slice(i,i+3));m.n.splice(i,3,...v)}let f=x=>new Float32Array(x);
 let material=materials.push({name:g,doubleSided:true,pbrMetallicRoughness:{metallicFactor:0,roughnessFactor:g==='Wood'?.96:.68},emissiveFactor:g==='Shelf'?[.065,.031,.10]:g==='Petals'?[.075,.026,.10]:[0,0,0]})-1;
 primitives.push({attributes:{...(m.uv?{TEXCOORD_0:append(f(m.uv),'VEC2',5126)}:{}),POSITION:append(f(m.p),'VEC3',5126,true),NORMAL:append(f(m.n),'VEC3',5126),COLOR_0:append(f(m.c),'VEC3',5126)},indices:append(new Uint32Array(m.idx),'SCALAR',5125),material})}
 let imageFields={};if(groups.Wood){let png=barkMap(),idx=views.push({buffer:0,byteOffset:offset,byteLength:png.length})-1,pad=Buffer.alloc((4-png.length%4)%4);buffers.push(png,pad);offset+=png.length+pad.length;materials.find(m=>m.name==='Wood').pbrMetallicRoughness.baseColorTexture={index:0};imageFields={images:[{bufferView:idx,mimeType:'image/png'}],textures:[{source:0}]}}let doc={...imageFields,asset:{version:'2.0',generator:'Lowlight forest study'},scene:0,scenes:[{nodes:[0]}],nodes:[{name,mesh:0}],meshes:[{primitives}],materials,buffers:[{byteLength:offset}],bufferViews:views,accessors:access};let json=Buffer.from(JSON.stringify(doc));let padded=Buffer.alloc((json.length+3)&~3,32);json.copy(padded);let hdr=Buffer.alloc(20);hdr.write('glTF');hdr.writeUInt32LE(2,4);hdr.writeUInt32LE(28+padded.length+offset,8);hdr.writeUInt32LE(padded.length,12);hdr.write('JSON',16);let bin=Buffer.alloc(8);bin.writeUInt32LE(offset);bin.write('BIN\0',4);fs.writeFileSync(path.join(dir,name+'.glb'),Buffer.concat([hdr,padded,bin,...buffers]));groups={};}
// --skeletons: rebuild only the two climbable tree species (same random sequence as a full run, since they
// come first), write their skeleton JSON beside the models, and write the GLBs to a scratch folder so the
// caller can confirm they are byte-identical to the shipped ones.
function buildRiverCollection() {
  const tau = Math.PI*2, origin = [0,0,0];
  const olive = [.14,.29,.052], jade = [.046,.22,.12], lime = [.26,.42,.075];
  const wood = [.31,.24,.15], reed = [.19,.24,.072];
  let route;
  function recordTrunk(points,radii,height,crownReach){
    const trunk=[],trunkRadii=[];
    for(let i=0;i<=30;i++){
      const y=height*i/30;
      let j=1;while(j<points.length-1 && points[j][1]<y)j++;
      const t=(y-points[j-1][1])/(points[j][1]-points[j-1][1]);
      trunk.push(at(points[j-1],points[j],t));trunkRadii.push(radii[j-1]+(radii[j]-radii[j-1])*t);
    }
    route={height,trunk,trunkRadii,crownReach,branches:[]};
  }
  function crown(height, breadth, tiers, branches, lean) {
    const spine = t => [lean*t*t,height*t,.38*Math.sin(t*3)];
    tube([spine(-.03),spine(.1),spine(.38),spine(.7),spine(1)],
      [height*.076,height*.051,height*.037,height*.026,.08],13,wood);
    recordTrunk([spine(-.03),spine(.1),spine(.38),spine(.7),spine(1)],[height*.076,height*.051,height*.037,height*.026,.08],height,breadth);
    for(let i=0;i<7;i++){
      const a=i*2.4;
      tube([spine(.10),vec(a,height*.078,.29),vec(a,height*.19,-.36)],
        [height*.036,height*.025,.08],7,wood);
    }
    for(let i=0;i<tiers*branches;i++){
      const level=Math.floor(i/branches), a=i*2.399+rr(-.17,.17);
      const base=spine(.50+.43*level/Math.max(tiers-1,1));
      const reach=breadth*(1-.25*level)*rr(.81,1.15);
      const elbow=add(base,vec(a,reach*.44,height*.10));
      const tip=add(base,vec(a+.10,reach,height*.14));
      route.branches.push({t:base[1]/height,points:[base,elbow,at(elbow,tip,.55),tip],radii:[height*.023,height*.014,height*.014*.45+.042*.55,.042]});
      tube([base,elbow,tip],[height*.023,height*.014,.042],8,wood);
      for(let j=0;j<6;j++){
        const fork=at(elbow,tip,j/7), bearing=a+(j%2?1:-1)*rr(.48,1.25);
        const end=add(fork,vec(bearing,reach*.43,rr(.3,1.1)));
        tube([fork,end],[.075,.019],5,wood);
        for(let k=0;k<3;k++) spray(at(fork,end,(k+1)/3),bearing+(k-1)*.78,rr(.83,1.35));
      }
    }
  }
  function bamboo(count,height) {
    for(let i=0;i<count;i++){
      const a=i*2.4, h=height*rr(.7,1.12), rad=h*.011;
      const p=t=>add(vec(a,Math.sqrt(i)*.28),vec(a,h*.12*t*t,h*t));
      const tint=i%3===0?[.15,.11,.082]:reed;
      for(let j=0;j<10;j++){
        const start=p(j/10),end=p((j+1)/10),radius=rad*(1-j*.065);
        tube([start,at(start,end,.94),at(start,end,.975),end],
          [radius,radius*.98,radius*1.21,radius*1.09],7,tint,'Culms');
        if(j<4)continue;
        const angle=a+j*2.4, twig=add(end,vec(angle,h*.15,.55));
        tube([end,twig],[rad*.30,.012],5,reed,'Stems');
        for(let k=1;k<=8;k++) leaf(at(end,twig,k/8),unit(vec(angle+(k%2?1:-1)*.8,1,-.2)),h*.064,h*.005,.09,olive);
      }
    }
  }
  function grass(n,h,w,spread,tip,seedheads) {
    for(let i=0;i<n;i++){
      const a=i*2.399, base=vec(a,rr(.025,spread)), H=h*rr(.52,1.16), reach=H*rr(.27,.79);
      let last;
      for(let j=0;j<=6;j++){
        const t=j/6, p=add(base,vec(a,reach*t*t,H*(1.37*t-.53*t*t)));
        const half=w*(1.02-t)*rr(.89,1.08), color=at(olive,tip,t*t);
        const row=[-1,0,1].map(s=>vert('Blades',add(p,vec(a+Math.PI/2,half*s,s===0?half*.45:0)),mul(color,s<0?.82:1)));
        if(last)for(let k=0;k<2;k++){tri('Blades',last[k],row[k],row[k+1]);tri('Blades',last[k],row[k+1],last[k+1]);}
        last=row;
        if(j===6 && seedheads && i%4===0)tube([p,add(p,[0,.08,0]),add(p,[.025,.22,0])],[.016,.035,.003],5,[.32,.23,.10],'Seeds');
      }
    }
  }
  function rosette(n,L,W,stalk,color) {
    for(let i=0;i<n;i++){
      const a=i*2.399,h=stalk*rr(.65,1.3),p=vec(a,h*.37,h);
      tube([origin,at(origin,p,.55),p],[.021,.017,.011],5,jade,'Stems');
      const dir=unit(vec(a,1,rr(-.12,.46))), l=L*rr(.7,1.18), width=W*rr(.85,1.13);
      leaf(p,dir,l,width,l*.25,color);
      for(let k=1;k<=4;k++){
        const t=k/6,mid=add(add(p,mul(dir,l*t)),[0,l*.25*Math.sin(t*Math.PI)-l*.13*t*t+width*.15,0]);
        for(const sign of [-1,1])tube([mid,add(mid,vec(a+sign*1.06,width*Math.sin(t*Math.PI)*.78,-width*.07))],[.007,.002],3,mul(color,1.42),'Veins');
      }
    }
  }
  function fronds(n,l,stalk) {
    for(let i=0;i<n;i++){const a=i*2.4,p=vec(a,stalk*.24,stalk*rr(.72,1.17));
      tube([origin,p],[.023,.012],5,olive,'Stems');spray(p,a,l*rr(.64,1.1),true);}
  }
  function palm(){
    const top=[.85,9,.34];tube([[0,-.25,0],[.08,2,.13],[.47,5.7,.26],top],[.40,.29,.23,.19],12,wood);
    recordTrunk([[0,-.25,0],[.08,2,.13],[.47,5.7,.26],top],[.40,.29,.23,.19],9,4.4);
    for(let i=0;i<14;i++)spray(top,i*2.4,rr(2.3,4.4),true);
  }
  // Uneven rings share a fracture outline. Paired inset rings form recessed bedding seams.
  function stone(cx,cz,rx,rz,h,layers,rounded,mossy,base=0){
    const n=rounded?15:10,outline=Array.from({length:n},(_,k)=>{
      const a=(k+rr(-.21,.21))*tau/n;
      const x=Math.cos(a),z=Math.sin(a),power=rounded?.91:.56;
      return [Math.sign(x)*Math.abs(x)**power*rx*rr(.87,1.08),Math.sign(z)*Math.abs(z)**power*rz*rr(.87,1.08),rr(-.055,.055)];
    });
    let last;
    const ring=(y,scale,color)=>{
      const row=outline.map(([x,z,w])=>vert('Stone',[cx+x*scale,base+h*(y+w*scale),cz+z*scale],mul(color,rr(.84,1.16))));
      if(last)for(let k=0;k<n;k++){const j=(k+1)%n;tri('Stone',last[k],row[k],row[j]);tri('Stone',last[k],row[j],last[j]);}
      last=row;
    };
    const mineral=[.24,.217,.161],shadow=[.11,.112,.093],cap=mossy?[.133,.205,.068]:[.30,.286,.235];
    ring(-.15,.74,shadow);
    if(rounded){ring(.16,.95,mineral);ring(.49,1,mineral);ring(.8,.83,at(mineral,cap,.42));}
    else for(let j=0;j<layers;j++){const y=j/layers,sc=rr(.9,1.05);ring(y,sc,shadow);ring(y+.10/layers,sc+.048,mineral);ring(y+.85/layers,sc+.018,mul(mineral,rr(.85,1.23)));}
    ring(.97,rounded?.53:.88,cap);ring(1.02,rounded?.24:.51,cap);
    const center=vert('Stone',[cx,base+h*1.035,cz],cap);
    for(let i=0;i<n;i++)tri('Stone',last[i],center,last[(i+1)%n]);
    const bottom=outline.map(([x,z,w])=>vert('Stone',[cx+x*.74,base+h*(-.15+w*.74),cz+z*.74],shadow));
    for(let i=1;i<n-1;i++)tri('Stone',bottom[0],bottom[i],bottom[i+1]);
  }
  const models={
    'Umbrella Fig':()=>crown(15,5.2,2,6,.65),'Tiered Copperwood':()=>crown(19,4.1,3,4,-.87),
    'Leaning River Myrtle':()=>crown(8,3.3,2,4,2.1),'Crest Palm':palm,
    'Giant Reed Bamboo':()=>bamboo(5,12),'Brush Bamboo':()=>bamboo(11,4.6),
    'Meadow Hairgrass':()=>grass(86,.47,.016,.36,lime,false),'Rose Plume Grass':()=>grass(53,.91,.033,.35,[.49,.16,.31],false),
    'Bronze Seed Sedge':()=>grass(44,.88,.025,.31,[.37,.32,.105],true),'Marsh Rush':()=>grass(66,1.47,.012,.43,jade,true),
    'Silver Bank Grass':()=>grass(62,.68,.038,.37,[.25,.38,.25],false),'Forest Carpet':()=>grass(120,.19,.023,.52,olive,false),
    'River Elephant Ear':()=>rosette(7,.91,.38,.88,jade),'Copper Bromeliad':()=>rosette(18,.71,.094,.12,[.28,.14,.084]),
    'Violet Shieldleaf':()=>rosette(8,.55,.24,.49,[.19,.105,.22]),'Lime Strapleaf':()=>rosette(15,.92,.067,.10,lime),
    'Blue Ripple Lily':()=>rosette(5,.59,.27,.22,[.049,.235,.211]),'Sword Fern':()=>fronds(11,1.23,.34),
    'Bank Maidenhair':()=>fronds(17,.59,.16),'Tower Fern':()=>fronds(8,1.48,1.30),
    'Bedded Cliff Face':()=>stone(0,0,1.2,.73,1.28,5,false,false),
    'Moss Table Ledge':()=>stone(0,0,1.28,.82,.73,3,false,true),
    'Fractured Twin Block':()=>{stone(-.48,0,.60,.76,1.17,4,false,true);stone(.52,.05,.48,.70,.82,3,false,false);},
    'River Stair Outcrop':()=>{for(let i=0;i<3;i++)stone(i*.57-.57,0,.48,.83,.34+i*.32,2,false,true);},
    'Shale Overhang':()=>{stone(-.22,0,.63,.64,.77,3,false,false);stone(0,0,1.08,.85,.30,2,false,true,.67);},
    'Waterworn Boulder':()=>stone(0,0,1,.79,.72,1,true,false),'Mossback Boulder':()=>stone(0,0,.93,.80,.89,1,true,true),
    'Ford Stepping Slab':()=>stone(0,0,1.13,.72,.34,2,false,false),
    'River Gravel Fan':()=>{for(let i=0;i<21;i++){const p=vec(i*2.4,Math.sqrt(i)*.21),s=rr(.09,.24);stone(p[0],p[2],s,s*.72,s*.62,1,true,false);}},
    'Broken Talus':()=>{for(let i=0;i<8;i++){const p=vec(i*2.4,Math.sqrt(i)*.28),s=rr(.19,.45);stone(p[0],p[2],s,s*.72,s*.88,2,false,false);}}
  };
  for(const [name,buildModel] of Object.entries(models)){route=null;buildModel();save(name);if(route)fs.writeFileSync(path.join(dir,name+".skeleton.json"),JSON.stringify(route));}
  fs.writeFileSync(path.join(dir,'river-collection.json'),JSON.stringify(Object.keys(models)));
  console.log('Wrote '+Object.keys(models).length+' river forest models.');
};

if(process.argv.includes("--river-only")){buildRiverCollection();process.exit(0);}
// --palm-skeleton: replay the --new-only sequence up to the Arch Palm (Young Shelfwood first, same seed)
// and write its trunk skeleton; both GLBs go to the scratch folder for a byte comparison.
if(process.argv.includes("--palm-skeleton")){
 const scratch=path.join(__dirname,'skeleton-check');fs.mkdirSync(scratch,{recursive:true});
 const checked=name=>{const shipped=path.join(dir,name+'.glb'),kept=path.join(scratch,name+'.shipped.glb');
  fs.copyFileSync(shipped,kept);save(name);fs.renameSync(shipped,path.join(scratch,name+'.glb'));fs.copyFileSync(kept,shipped);};
 sapling();checked('Young Shelfwood');
 archPalm();fs.writeFileSync(path.join(dir,'Arch Palm.skeleton.json'),JSON.stringify(skeleton));checked('Arch Palm');
 process.exit(0);
}
if(process.argv.includes("--skeletons")){
 const scratch=path.join(__dirname,'skeleton-check');fs.mkdirSync(scratch,{recursive:true});
 for(let [name,fn] of [['Shelfwood',()=>tree(false)],['Veil Banyan',()=>tree(true)]]){fn();
  fs.writeFileSync(path.join(dir,name+'.skeleton.json'),JSON.stringify(skeleton));
  const shipped=path.join(dir,name+'.glb'),kept=path.join(scratch,name+'.shipped.glb');
  fs.copyFileSync(shipped,kept);save(name);fs.renameSync(shipped,path.join(scratch,name+'.glb'));fs.copyFileSync(kept,shipped);}
 process.exit(0);
}
if(!newOnly&&!process.argv.includes("--grove-only"))for(let [name,fn] of [['Shelfwood',()=>tree(false)],['Veil Banyan',()=>tree(true)],['Crown Fern',palm],['Tide Fern',fern],['Amethyst Rosette',rosette],['Lantern Shelves',fungus]]){fn();save(name)}

function crossing(){
 let pts=[],rad=[];
 for(let i=0;i<=28;i++){let t=i/28;pts.push(bridgePoint(t));rad.push(1.30-.20*Math.sin(Math.PI*t)+.06*Math.sin(t*11))}
 tube(pts,rad,20,[.17,.133,.088]);
 for(let sign of [-1,1])for(let i=0;i<3;i++){
 let t=i*.38+.08, p=bridgePoint(t),q=add(p,[sign*.54,-.36,1.15]),end=add(q,[sign*1.45,-.82,1.64]);tube([p,q,end],[.48,.31,.055],9,bark)}
}
function bridgePoint(t){return [-14+28*t,6.2+0.85*Math.sin(t*Math.PI*2),.55*Math.sin(t*Math.PI*2)]}
function vine(){
 let path=[],n=26;for(let i=0;i<=n;i++){let t=i/n;path.push([t*6, -2.3*Math.sin(Math.PI*t)+.12*Math.sin(3*Math.PI*t),.18*Math.sin(t*8)])}
 tube(path,path.map(()=>.047),7,moss,'Stems');
 for(let i=2;i<n;i+=2){let p=path[i],l=rr(.65,2.2),stem=Array.from({length:8},(_,k)=>add(p,[.12*Math.sin(k*.9),-l*k/7,.12*Math.sin(k*.75)]));tube(stem,stem.map((_,k)=>.028-k*.003),5,moss,'Stems');for(let k=1;k<8;k++)leaf(stem[k],unit(vec(k*2.4,.7,-.55)),rr(.30,.49),.12,.055,jade)}
}
function bloom(){
 for(let i=0;i<9;i++){let a=i*2.4,h=rr(.65,1.35),p=vec(a,rr(.18,.56),h);tube([[0,0,0],mul(p,.48),p],[.027,.022,.014],6,moss,'Stems');
 for(let k=1;k<4;k++)leaf(mul(p,k*.22),unit(vec(a+k*2.4,1,.22)),.38,.096,.08,jade);
 for(let k=0;k<6;k++){let theta=a+tau*k/6;leaf(p,unit(vec(theta,1,.33)),.25,.088,.13,at([.62,.10,.31],[.39,.17,.68],k/6),'Petals')}
 for(let k=0;k<5;k++)leaf(p,unit(vec(k*2.4,.39,1)),.13,.027,.028,[.95,.55,.13],'Petals')}
}
if(!newOnly)for(let [name,fn] of [['Canopy Crossing',crossing],['Curtain Vine',vine],['Lantern Orchid',bloom]]){fn();save(name)}

// ---- Jungle additions (stage 1) ----
const lime=[.085,.22,.06], deep=[.032,.14,.07];

// Broad leaf with a real surface: widest a third of the way out, lighter midrib, drooping edges and tip.
function bigLeaf(base,dir,L,W,color,g='Foliage'){
 let side=unit(cross(dir,up)),n=9,prev;
 // Heart shape: wide at the stalk, basal lobes swept back past the attachment point, tapering to a tip.
 for(let j=0;j<=n;j++){let t=j/n,w=W*Math.pow(Math.sin(Math.PI*(.3+.7*t)),.75)*(1.05-.25*t),lobe=Math.pow(1-t,3)*W*.75;
  let mid=add(add(base,mul(dir,L*t)),mul(up,L*(.16*Math.sin(Math.PI*t*.8)-.32*t*t)));
  let row=[-2,-1,0,1,2].map(k=>{let s=k/2;return vert(g,add(add(add(mid,mul(side,s*w)),mul(dir,-s*s*lobe)),mul(up,-s*s*w*.34+(k===0?w*.05:0))),mul(color,(k===0?1.22:1-.12*Math.abs(s))*(.78+.3*t)))});
  if(prev)for(let k=0;k<4;k++){tri(g,prev[k],row[k],row[k+1]);tri(g,prev[k],row[k+1],prev[k+1])}prev=row}
}
// Young tree: under 5 m so it stays below the climbing threshold; fills gaps between trunks.
function sapling(){
 const H=4.6,core=t=>[.2*Math.sin(t*2.6),H*t,.13*Math.sin(t*3.4)];
 let pts=Array.from({length:10},(_,j)=>core(j/9));tube(pts,pts.map((_,j)=>.13*(1-.78*j/9)+.07*Math.exp(-j*1.4)),9);
 for(let i=0;i<5;i++){let a=i*1.26+rr(-.25,.25);tube([vec(a,.07,.32),vec(a,.27,.04),vec(a+.1,.46,-.24)],[.07,.04,.012],6)}
 for(let i=0;i<10;i++){let t=.38+.58*i/9,a=i*2.4+rr(-.2,.2),base=core(t),tip=add(base,vec(a,rr(.9,1.7)*(1.3-.6*t),rr(.45,1.1)));
  tube([base,at(base,tip,.5),tip],[.045,.028,.008],5);
  for(let s=0;s<4;s++)spray(at(base,tip,.3+.7*s/3),a+(s%2?1:-1)*rr(.5,1.3),rr(.85,1.4))}
 for(let k=0;k<6;k++)spray(core(1),k*2.4,rr(.8,1.3))
}
// Palm frond: arching rachis, leaflets hanging from both sides.
function frond(p,a,L,lift=.36){
 let n=16,pts=Array.from({length:n+1},(_,i)=>{let t=i/n;return add(p,vec(a,L*t,L*(lift*t-.66*t*t)))});
 tube(pts,pts.map((_,i)=>.05*(1-.85*i/n)),4,moss,'Stems');
 for(let i=1;i<n;i++)for(let sign of [-1,1]){let t=i/n,l=L*.29*(.3+.7*Math.sin(Math.PI*Math.pow(t,.8)));
  leaf(pts[i],unit(add(vec(a+sign*1.2,1,0),[0,-.5-.45*t,0])),l,l*.08,l*.03,mul(green,rr(.75,1.25)))}
}
function archPalm(){
 const H=8.4,core=t=>[2.1*t*t,H*t,.45*Math.sin(t*2.2)];
 let pts=Array.from({length:20},(_,j)=>core(j/19));
 tube(pts,pts.map((_,j)=>.27*(1-.3*j/19)+.12*Math.exp(-j*1.2)+(j%2?.012:0)),11,[.15,.12,.085]);
 skeleton={height:H,trunk:pts,trunkRadii:pts.map((_,j)=>.27*(1-.3*j/19)+.12*Math.exp(-j*1.2)),branches:[],crownReach:4.8};
 for(let i=0;i<6;i++){let a=i*1.05+rr(-.2,.2);tube([vec(a,.15,.4),vec(a,.42,.05),vec(a+.08,.62,-.3)],[.09,.05,.015],6)}
 // Three tiers: young fronds rising, a full middle ring, older fronds hanging below.
 let top=core(1);for(let k=0;k<15;k++)frond(top,k*tau/15+rr(-.12,.12),rr(3.6,4.8),rr(.5,.75));
 for(let k=0;k<6;k++)frond(add(top,[0,.15,0]),k*tau/6+.3,rr(2.4,3.0),rr(1.1,1.5));
 for(let k=0;k<5;k++)frond(add(top,[0,-.3,0]),k*tau/5+.6,rr(2.6,3.4),rr(-.1,.1))
}
// Elephant-ear understory: waist-to-head-high stalks carrying big drooping leaves.
function broadLeaf(){
 for(let i=0;i<9;i++){let a=i*2.4+rr(-.25,.25),h=rr(.55,1.65),p=vec(a,rr(.15,.45)*h,h);
  tube([[0,0,0],add(mul(p,.5),[0,.06,0]),p],[.055,.042,.026],6,moss,'Stems');
  let L=rr(.95,1.4);bigLeaf(p,unit(add(vec(a+rr(-.3,.3),1,0),[0,-rr(.1,.5),0])),L,L*.36,mul(i%3?green:deep,rr(.85,1.3)))}
}
// Ground-cover creepers: low runners with small round leaves, so the forest floor is never bare.
function creeper(){
 for(let i=0;i<16;i++){let a=i*2.4+rr(-.3,.3),L=rr(1.1,2.5),wig=rr(-.4,.4),n=8;
  let pts=Array.from({length:n+1},(_,k)=>{let t=k/n;return vec(a+wig*Math.sin(t*3),L*t,.05+.06*Math.sin(t*Math.PI))});
  tube(pts,pts.map(()=>.016),4,moss,'Stems');
  for(let k=1;k<=n;k++)for(let sign of [-1,1]){let l=rr(.15,.27)*(1-.35*k/n);leaf(pts[k],unit(vec(a+sign*rr(.8,1.4),1,rr(.15,.5))),l,l*.42,l*.12,mul(k%3?lime:green,rr(.8,1.25)))}}
 for(let k=0;k<12;k++)leaf([0,.03,0],unit(vec(k*2.4,1,rr(.4,.9))),rr(.25,.4),.11,.06,mul(green,rr(.9,1.2)))
}
for(let [name,fn] of [['Young Shelfwood',sapling],['Arch Palm',archPalm],['Elephant Ear',broadLeaf],['Creeper Mat',creeper]]){fn();save(name)}