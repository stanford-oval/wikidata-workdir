import sys

f1 = sys.argv[1]
f2 = sys.argv[2]

examples1 = {}
with open(f1, 'r') as f:
    for line in f:
        eid = line.split('\t')[0]
        examples1[eid] = line.strip()


examples2 = {}
with open(f2, 'r') as f:
    for line in f:
        eid = line.split('\t')[0]
        examples2[eid] = line.strip()


for eid in examples1:
    if eid not in examples2:
        print(examples1[eid])

