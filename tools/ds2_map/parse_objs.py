import re,sys,os,collections
def parse(path):
    txt=open(path,encoding='latin1').read()
    objs=[]
    for m in re.finditer(r'\[t:([^,\]]+),n:(0x[0-9a-fA-F]+)\]\s*\{',txt):
        i=m.end(); depth=1
        while depth and i<len(txt):
            c=txt[i]
            if c=='{': depth+=1
            elif c=='}': depth-=1
            i+=1
        body=txt[m.end():i-1]
        objs.append((m.group(1),m.group(2),body))
    return objs
def field(body,name):
    m=re.search(name+r'\s*=\s*([^;]+);',body)
    return m.group(1).strip() if m else None
if __name__=='__main__':
    base=os.environ.get('DS2_REGIONS_DIR','map/world/maps/ds2_world/regions')
    for r in sys.argv[1:]:
        for fn in ('actor.gas','generator.gas'):
            p=f'{base}/{r}/objects/{fn}'
            if not os.path.exists(p): continue
            objs=parse(p)
            print('==',r,fn,len(objs))
            c=collections.Counter(t for t,_,_ in objs)
            for t,n in c.most_common(): print('   ',n,t)
