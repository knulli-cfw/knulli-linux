#!/usr/bin/env python3
"""Decode the panel init sequences compiled into an Anbernic H700 vendor
u-boot.bin (Thumb-2, linked at 0x4a000000).

The panel driver is straight-line code: `movs r0,#imm ; bl fn` with fn the
3-wire command write, the data write or mdelay.  The lcd_type flag (read
from a gpio, 0 or 1) is kept in r4 and `cmp r4,#1 ; bne` picks the
sequence; where a sequence needs the constant that r4 happens to hold the
compiler emits `mov r0,r4`, so r4 = 1 in the fall-through sequence and 0
in the branch target.  Output: one line per sequence, "cmd data..." items
separated by |, "wait N" for mdelay(N)."""
import struct, sys, collections
d=open(sys.argv[1],'rb').read()
BASE=0x4a000000
def u16(o): return struct.unpack_from('<H',d,o)[0]
def b_target(pc,h1,h2,cond):
    S=(h1>>10)&1; J1=(h2>>13)&1; J2=(h2>>11)&1; imm11=h2&0x7ff
    if cond:
        imm6=h1&0x3f; off=(S<<20)|(J2<<19)|(J1<<18)|(imm6<<12)|(imm11<<1)
        if S: off-=1<<21
    else:
        imm10=h1&0x3ff; I1=~(J1^S)&1; I2=~(J2^S)&1
        off=(S<<24)|(I1<<23)|(I2<<22)|(imm10<<12)|(imm11<<1)
        if S: off-=1<<25
    return pc+4+off
items=[]; i=0
while i<len(d)-6:
    h=u16(i); src=None
    if (h&0xff00)==0x2000: src=('imm',h&0xff)
    elif (h&0xff87)==0x4600: src=('r%d'%((h>>3)&0xf),)
    if src:
        h1,h2=u16(i+2),u16(i+4)
        if (h1&0xf800)==0xf000 and (h2&0xd000)==0xd000:
            items.append((i,src,b_target(i+2,h1,h2,False))); i+=6; continue
    i+=2
cnt=collections.Counter(t for _,_,t in items)
busy=[t for t,_ in cnt.most_common(16)]
# the data write is the target called in runs; the command write precedes those runs
runs=collections.Counter(); prec=collections.Counter()
for a,b in zip(items,items[1:]):
    if a[2]==b[2] and a[2] in busy: runs[a[2]]+=1
    elif b[2] in busy and a[2] in busy: prec[(a[2],b[2])]+=1
pair=max(((a,b) for a in busy for b in busy if a!=b), key=lambda ab: prec[ab]+prec[ab[::-1]])
a,b=pair
if runs[a]!=runs[b]: datafn,cmdfn=(a,b) if runs[a]>runs[b] else (b,a)
else:
    ff30=collections.Counter((x[2],y[2]) for x,y in zip(items,items[1:]) if x[1]==('imm',0xff) and y[1]==('imm',0x30))
    cmdfn,datafn=(a,b) if ff30[(a,b)]>=ff30[(b,a)] else (b,a)
# sequence regions
seqs=[]; cur=None; last=-1000
for a,src,t in items:
    if t in (cmdfn,datafn):
        if a-last>64: cur=[]; seqs.append([a,cur])
        cur.append((a,'C' if t==cmdfn else 'D', src)); last=a
    elif cur is not None and a-last<=24 and src[0]=='imm':
        cur.append((a,'W',src)); last=a
seqs=[s for s in seqs if len(s[1])>=20]
lo=seqs[0][0]-0x400; hi=seqs[-1][1][-1][0]+0x100
# branches on r4 in that range: cmp r4,#N (2c NN) followed by b<cond>.w
splits=[]
for o in range(lo,hi,2):
    h=u16(o)
    if (h&0xf800)==0x2800 and ((h>>8)&7)>=4:   # cmp r4..r7, #imm
        h1,h2=u16(o+2),u16(o+4)
        if (h1&0xf800)==0xf000 and (h2&0xd000)==0x8000:
            cond=(h1>>6)&0xf; tgt=b_target(o+2,h1,h2,True)
            flagreg='r%d'%((h>>8)&7)
            splits.append((o,h&0xff,{0:'beq',1:'bne'}.get(cond,'b?%d'%cond),tgt))
# constants in r4..r7 set before the sequences (movs rN,#imm)
consts={}
for o in range(lo,seqs[0][0],2):
    h=u16(o)
    if (h&0xf800)==0x2000 and ((h>>8)&7)>=4: consts['r%d'%((h>>8)&7)]=h&0xff
flagreg=globals().get('flagreg')
print('# cmd fn %#x data fn %#x  consts %s flag %s' % (cmdfn+BASE, datafn+BASE, consts, flagreg))
for o,n,c,t in splits: print('# %#x: cmp %s,#%d ; %s -> %#x' % (o+BASE,flagreg,n,c,t+BASE))
tgts=sorted(t for _,_,_,t in splits)
for o,n,c,t in splits:
    h1,h2=u16(t),u16(t+2)
    if (h1&0xf800)==0xf000 and (h2&0xd000)==0xd000 and b_target(t,h1,h2,False) in (cmdfn,datafn):
        r0=None; q=o-2
        while q>o-64:
            if (u16(q)&0xff00)==0x2000: r0=u16(q)&0xff; break
            q-=2
        for sq in seqs:
            if sq[0]<=t<=sq[1][-1][0]:
                sq[1].append((t,'C' if b_target(t,h1,h2,False)==cmdfn else 'D',('imm',r0))); sq[1].sort()
def region_r4(addr):
    # sequences reached by bne target: r4 != 1 (0); fall-through after a bne: r4 == 1
    v=1
    for o,n,c,t in splits:
        if c=='bne' and t<=addr: v=0
        if c=='bne' and o<addr<t: v=1
    return v
# split sequences at branch targets and at the end of a display-on
flat=[x for s in seqs for x in s[1]]
out=[]; cur=None; c=None; start=None
def flush():
    global cur,c
    if cur: out.append((start,cur))
    cur=[]; c=None
for a,k,src in flat:
    if a in tgts or cur is None: flush(); start=a
    if src[0]=='imm': v=src[1]
    elif src[0]==flagreg: v='%02x'%region_r4(a)
    elif src[0] in consts: v='%02x'%consts[src[0]]
    else: v=src[0]
    if k=='C': c=[v]; cur.append(c)
    elif k=='D':
        if c is None: c=['?']; cur.append(c)
        c.append(v)
    else: cur.append(['wait',v])
flush()
f=lambda x: ' '.join(v if isinstance(v,str) else '%02x'%v for v in x)
for start,s in out:
    print('== seq at %#x (r4=%d): %d items' % (start+BASE, region_r4(start), len(s)))
    print(' | '.join(f(x) for x in s))
