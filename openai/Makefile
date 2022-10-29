# exports OPENAI_API_KEY inside config.mk, required for finetune and evaluation
-include ./config.mk

qalddir=../qald
wikidata_cache = $(qalddir)/wikidata_cache.sqlite
bootleg =$(qalddir)/bootleg.sqlite

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
	node $(qalddir)/dist/lib/prompt/index.js \
		-i $^ \
		-o $@ \
		--module $(linker) \
		--ner-cache ../qald/${linker}.sqlite \
		--wikidata-cache $(wikidata_cache) \
		--bootleg $(bootleg) 

everything-%.jsonl: fewshot.jsonl synthetic-%.jsonl
	cat $^ > $@

finetune: everything-${size}.jsonl dev.jsonl
	openai \
		api fine_tunes.create \
		-t $< \
		-v dev.jsonl \
		-m $(base_model) \
		--n_epochs ${epochs} \
		--suffix "silei wikidata ${size}"

%-predictions.tsv: %.jsonl
	python evaluate.py \
		-i $^ \
		-o $@ \
		--model ${model}

%.results: %-predictions.tsv
	node $(qalddir)/dist/lib/converter/index.js \
		--direction from-thingtalk \
		-i $^ \
		-o predictions-sparql.tsv \
		--cache $(wikidata_cache) \
		--bootleg-db $(bootleg) \
		--prediction \
		--manifest ../manifest.tt \
		--domains ../parameter-datasets/domain.json \
		--include-entity-value \
		--exclude-entity-display 
	node $(qalddir)/dist/lib/converter/index.js \
		--direction from-thingtalk \
		-i $^ \
		--cache $(wikidata_cache) \
		--bootleg-db $(bootleg) \
		-o gold-sparql.tsv \
		--manifest ../manifest.tt \
		--domains ../parameter-datasets/domain.json \
		--include-entity-value \
		--exclude-entity-display 
	node $(qalddir)/dist/lib/evaluate.js \
		--from-thingtalk \
		--cache $(wikidata_cache) \
		--bootleg-db $(bootleg) \
		--dataset gold-sparql.tsv \
		--prediction predictions-sparql.tsv > $@ 

clean:
	rm *.jsonl