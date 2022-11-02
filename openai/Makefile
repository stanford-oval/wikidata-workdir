# exports OPENAI_API_KEY inside config.mk, required for finetune and evaluation
-include ./config.mk

qalddir=../qald
wikidata_cache = $(qalddir)/wikidata_cache.sqlite
bootleg =$(qalddir)/bootleg.sqlite

base_model=
size=
timestamp=
model=${base_model}:ft-open-virtual-assistant-lab-stanford:silei-wikidata-${size}-${timestamp}

linker=oracle
epochs=2
schema=false

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
		--bootleg $(bootleg) \
		$(if $(findstring true,$(schema)),--schema,) \

everything-%.jsonl: fewshot.jsonl $(if $(findstring 0,$(size)),,synthetic-%.jsonl)
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

evaluate: dev.results test.results
	@for f in $^ ; do echo $$f ; cat $$f ; done

models.json: 
	curl https://api.openai.com/v1/models -H 'Authorization: Bearer $(OPENAI_API_KEY)' > $@

archive:
	mkdir -p ${base_model}-${size}-${timestamp}
	mv *-predictions.tsv ${base_model}-${size}-${timestamp}/
	mv cache.json ${base_model}-${size}-${timestamp}/
	mv *.results ${base_model}-${size}-${timestamp}/ 

clean:
	rm -rf predictions-sparql.tsv gold-sparql.tsv 
	rm -rf *.jsonl