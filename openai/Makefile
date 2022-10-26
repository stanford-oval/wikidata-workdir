-include ./config.mk

base_model=davinci
model=davinci:ft-open-virtual-assistant-lab-stanford:silei-wikidata-2022-10-26-09-23-36

linker=oracle
size=1000
epochs=2

.PHONY: clean
.SECONDARY:

synthetic-%.tsv: synthetic.tsv
	shuf $^ | head -$* > $@

%.jsonl: %.tsv
	node ../qald/dist/lib/prompt/index.js \
		-i $^ \
		-o $@ \
		--module $(linker) \
		--ner-cache ../qald/${linker}.sqlite \
		--wikidata-cache ../qald/wikidata_cache.sqlite \
		--bootleg ../qald/bootleg.sqlite 

everything-%.jsonl: fewshot.jsonl synthetic-%.jsonl
	cat $^ > $@

finetune: everything-${size}.jsonl dev.jsonl
	openai \
		-k ${developer_key} \
		api fine_tunes.create \
		-t $< \
		-v dev.jsonl \
		-m $(base_model) \
		--n_epochs ${epochs} \
		--suffix "silei wikidata"

%.results: %.jsonl
	python evaluate.py \
		-i $^ \
		-o $@ \
		--model ${model}

clean:
	rm *.jsonl