# exports OPENAI_API_KEY inside config.mk, required for finetune and evaluation
-include ./config.mk

url=https://ovalopenairesource.openai.azure.com/openai
qalddir=../qald
wikidata_cache = $(qalddir)/wikidata_cache.sqlite
bootleg =$(qalddir)/bootleg.sqlite

base_model=
size=
timestamp=
lr=
epochs=2
model=${base_model}:ft-open-virtual-assistant-lab-stanford:silei-wikidata-${size}-${epochs}-${lr}-${timestamp}
dir=results/${base_model}-${size}-${epochs}-${lr}-${timestamp}/

linker=oracle
schema=false

.PHONY: clean
.SECONDARY:

synthetic-%.tsv: synthetic.tsv
	shuf $^ | head -$* > $@

%.jsonl: %.tsv
	node $(qalddir)/dist/lib/prompt/index.js \
		-i $^ \
		-o $@.tmp \
		--module $(linker) \
		--ner-cache ../qald/${linker}.sqlite \
		--wikidata-cache $(wikidata_cache) \
		--bootleg $(bootleg) \
		$(if $(findstring true,$(schema)),--schema,) 
	mv $@.tmp $@

everything-%.jsonl: fewshot.jsonl synthetic-%.jsonl
	cat $^ > $@

prepared-%.jsonl: %.jsonl
	openai tools fine_tunes.prepare_data -f $^ 
	mv $*_prepared.jsonl $@

finetune: prepared-everything-${size}.jsonl prepared-dev.jsonl
	python scripts/finetune.py \
		--train prepared-everything-${size}.jsonl \
		--validate prepared-dev.jsonl \
		--model $(base_model) \
		--epochs $(epochs) \
		--lr $(lr) \
		--suffix "silei wikidata ${size} ${epochs} ${lr}"

%-predictions.tsv: %.jsonl
	python scripts/evaluate.py \
		-i $^ \
		-o $@.tmp \
		--model ${model}
	mv $@.tmp $@

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

evaluate: dev.results test.results
	@for f in $^ ; do echo $$f ; cat $$f ; done

archive:
	mkdir -p $(dir)
	mv *-predictions.tsv $(dir)
	mv cache.json $(dir)
	mv *.results $(dir)

clean:
	rm -rf predictions-sparql.tsv gold-sparql.tsv 
	rm -rf *.jsonl