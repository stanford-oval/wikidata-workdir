# Instructions to run GPT-3 experiments

## Installation
To run the experiments, both this workdir and the [qald repository](https://github.com/rayslxu/qald) are required. 
Run the following command to install them (nodejs 12 or 14 is required):

```bash
git clone https://github.com/stanford-oval/wikidata-workdir.git
cd wikidata-workdir
git checkout wip/ablation

git clone https://github.com/rayslxu/qald.git
cd qald
npm ci 
cd ..
```

## Generate manifest 
Under `wikidata-workdir`, run `make manifest.tt`. 
This will generate a `manifest.tt` file containing the schema for Genie toolkit. This step may take a couple of minutes.
After the command is finished, check if the following files have been successfully created: `manifest.tt` `parameter-datasets/domain.json`, `bootleg.sqlite`, and `wikidata_cache.sqlite`. All these files are needed in the next step. 

## Prepare prompt
Run the following command to prepare the prompt:

```bash
cd openai
make everything-<SIZE>.jsonl base_model=<BASE_MODEL> size=<SIZE> lr=<LEARNING_RATE> epochs=<EPOCHS> 
```

Options:
- base_model: base gpt-3 model to be used (ada, babbage, curie, or davinci) 
- size: the size of the synthetic data to include (fewshot data is always included). If no synthetic data is needed, first create an empty file `synthetic-0.jsonl` and then run the above command with size set to 0.
- lr: the learning rate, normally between 0.02 and 0.2
- epochs: the number of epochs, default to 2

This command should generate a prompt file named `everything-<SIZE>.jsonl`. Check your file before moving forward. 

## Finetune
First setup your developer key. Inside `openai` directory, create a `config.mk` files with the following line
```bash
export OPENAI_API_KEY=<YOUR_API_KEY>
```

Then run the following command to start fine tuning. Make sure all parameters are same as last step, they will used as the suffix of the model name. Current, all model name starts with `silei-wikidata`, modify it as needed in the `Makefile`. 

```bash
make finetune base_model=<BASE_MODEL> size=<SIZE> lr=<LEARNING_RATE> epochs=<EPOCHS> 
```

## Evaluate 
Run the following command to evaluate. Replace `.` in the learning rate to `-`, e.g., if your learning rate is set to 0.1,
then in the following command, use `lr=0-1`. 

```bash
make evaluate base_model=<BASE_MODEL> size=<SIZE> lr=<LEARNING_RATE> epochs=<EPOCHS> 
```

This command will produce `dev.results` and `test.results` which have the evaluation results on dev set and test set, respectively. 

## Misc
If you want to finetune a different model run the following command first: 

```bash
# move current result to `results` folder
make archive base_model=<BASE_MODEL> size=<SIZE> lr=<LEARNING_RATE> epochs=<EPOCHS> 

# remove other intermediate files generated
make clean
```
