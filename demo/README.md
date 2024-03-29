# Instructions to run a Wikidata demo

## Start NLU server
The NLU model is set up on Azure. Contact Silei Xu to get access to the VM. 

To start the server, run the following command on the VM as user "oval". 
```bash
# enter a screen session to avoid termination due to connection issue
screen 

# activate python environment 
source ~/.virtualenv/genie/bin/activate

# start the server, use model id 30
cd wikidata-workdir
./run-nlu-server.sh 30
```

Note that the final step will take some time to load. The server is ready when the log shows something like the following:

```bash
[I 221020 21:08:51 server:347] Loading from models/30/best.pth
[I 221020 21:08:51 base:67] Loading the model from models/30/best.pth
[I 221020 21:09:05 numericalizer:141] Loading the accompanying numericalizer from models/30/
[I 221020 21:09:07 util:295] TransformerSeq2Seq has 406,312,960 parameters
```

## Port forward 
Now the server has started in VM, now you can port forward the server locally. On your local machine, run
```bash
ssh oval@wikidata-qa.westus2.cloudapp.azure.com -NfL 8400:localhost:8400
```

## Start Demo
Now you can start the demo locally. 
On your local machine, clone this repository and run the following with node 12 or 14:

```bash
# clone and get to the demo dir
git clone git@github.com:stanford-oval/wikidata-workdir
git checkout wip/ablation
cd demo

# download necessary files 
./sync.sh

# install dependencies
npm ci

# start demo
node index.js 
```

Now you can type your natural language and this tool will return ThingTalk, SPARQL, and answers retrieved from Wikidata.
Note that each of the steps may take some time, wait patiently. If something failed at any step, it will show an error message. 
