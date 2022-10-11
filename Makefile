s3_bucket ?= https://nfs009a5d03c43b4e7e8ec2.blob.core.windows.net/pvc-a8853620-9ac7-4885-a30e-0ec357f17bb6
geniedir ?= $(HOME)/genie-toolkit
qalddir ?= qald
thingpedia_url = https://almond-dev.stanford.edu/thingpedia

-include ./config.mk

s3_metrics_output ?=
metrics_output ?=
artifacts_ver := $(shell date +%s)

memsize := 4500
genie = node --experimental_worker --max_old_space_size=$(memsize) $(geniedir)/dist/tool/genie.js

owner ?= silei
project = qald
experiment ?= qald7
domains ?= all
qald_version ?= main
dataset_file = emptydataset.tt
type_system ?= 'hierarchical'
synthetic_flags ?= \
	projection_with_filter \
	projection \
	aggregation \
	filter_join \
	no_soft_match_id \
	no_both \
	notablejoin \
	wikidata 
generate_flags = $(foreach v,$(synthetic_flags),--set-flag $(v))
normalization_options ?= --normalize-domains id-filtered-only --normalize-entity-types

pruning_size ?= 50
maxdepth ?= 8
mindepth ?= 6
maxdepth_count ?= 1
mindepth_count ?= 3

wikidata_cache = $(qalddir)/wikidata_cache.sqlite
bootleg =$(qalddir)/bootleg.sqlite

.PHONY: clean
.SECONDARY:

$(qalddir):
	./install.sh $(qald_version)

$(wikidata_cache):
	curl https://almond-static.stanford.edu/research/qald/wikidata_cache.sqlite -o $@ 

$(bootleg):
	curl https://almond-static.stanford.edu/research/qald/bootleg.sqlite -o $@

emptydataset.tt:
	echo 'dataset @empty {}' > $@

manifest.tt: $(qalddir) $(wikidata_cache) $(bootleg)
	mkdir -p parameter-datasets ; \
	node $(qalddir)/dist/lib/manifest-generator.js \
		--cache $(wikidata_cache) \
		--use-wikidata-alt-labels \
		--save-cache \
		--bootleg-db $(bootleg) \
		--type-system $(type_system) \
		-o $@ \
		$(if $(findstring all,$(domains)),,--domains $(domains)) 
	$(genie) download-string-values \
		--thingpedia-url $(thingpedia_url) \
		--developer-key $(developer_key) \
		--manifest parameter-datasets.tsv \
		--append-manifest \
		--type tt:short_free_text \
		-d parameter-datasets 
	mkdir -p $(experiment) 
	cp entities.json $(experiment)/entities.json

constants.tsv: manifest.tt
	$(genie) sample-constants -o $@ --thingpedia manifest.tt --parameter-datasets parameter-datasets.tsv 
	cat $(geniedir)/data/en-US/constants.tsv >> $@

synthetic-d%.tsv: manifest.tt $(dataset_file)
	$(genie) generate \
		--thingpedia manifest.tt --entities entities.json --dataset $(dataset_file) \
		--target-pruning-size $(pruning_size) \
		-o $@.tmp $(generate_flags) --maxdepth $$(echo $* | cut -f1 -d'-') --random-seed $@ --debug 3
	mv $@.tmp $@

synthetic.tsv : $(foreach v,$(shell seq 1 1 $(mindepth_count)),synthetic-d$(mindepth)-$(v).tsv) $(foreach v,$(shell seq 1 1 $(maxdepth_count)),synthetic-d$(maxdepth)-$(v).tsv)
	cat $^ > $@
	
fewshot.tsv : manifest.tt $(wikidata_cache) $(bootleg)
	node $(qalddir)/dist/lib/converter/index.js \
		-i $(qalddir)/data/$(experiment)/train.json\
		--manifest manifest.tt \
		--cache $(wikidata_cache) \
		--save-cache \
		-d fewshot-dropped.tsv \
		-o $@.tmp \
		--bootleg-db $(bootleg)
	$(genie) typecheck $@.tmp\
		-o $@.tmp2 \
		--dropped fewshot-dropped.tsv \
		--thingpedia manifest.tt \
		--include-entity-value \
		$(if $(findstring true,$(exclude_entity_display)),--exclude-entity-display,) 
	$(genie) requote $@.tmp2 \
		-o $@ \
		--skip-errors 
	rm $@.tmp*

eval/annotated.tsv: manifest.tt $(wikidata_cache) $(bootleg) $(dataset_file)
	mkdir -p eval
	node $(qalddir)/dist/lib/converter/index.js \
		--manifest manifest.tt \
		--cache $(wikidata_cache) \
		--save-cache \
		-i $(qalddir)/data/$(experiment)/test.json \
		-d test-dropped.tsv \
		-o $@.tmp \
		--include-entity-value \
		--exclude-entity-display \
		--bootleg-db $(bootleg)
	node $(qalddir)/dist/lib/post-processor.js \
		--thingpedia manifest.tt \
		--include-entity-value \
		--exclude-entity-display \
		--bootleg-db $(bootleg) \
		--cache $(wikidata_cache) \
		$(normalization_options) \
		-i $@.tmp \
		-o $@
	rm $@.tmp

test/annotated.tsv : eval/annotated.tsv
	mkdir -p test
	cp eval/annotated.tsv $@

everything.tsv: synthetic.tsv fewshot.tsv
	$(genie) augment \
		-o $@.tmp \
		-l en-US \
		--thingpedia manifest.tt \
		--parameter-datasets parameter-datasets.tsv \
		--synthetic-expand-factor 1 \
		--quoted-paraphrasing-expand-factor 60 \
		--no-quote-paraphrasing-expand-factor 20 \
		--quoted-fraction 0.0 \
		--debug \
		--no-requotable \
		--include-entity-value \
		--exclude-entity-display \
		fewshot.tsv synthetic.tsv
	node $(qalddir)/dist/lib/post-processor.js \
		--thingpedia manifest.tt \
		--include-entity-value \
		--exclude-entity-display \
		--bootleg-db $(bootleg) \
		--cache $(wikidata_cache) \
		$(normalization_options) \
		-i $@.tmp \
		-o $@ 
	rm $@.tmp

datadir: eval/annotated.tsv test/annotated.tsv everything.tsv
	mkdir -p $@
	cp eval/annotated.tsv $@/eval.tsv
	cp manifest.tt $@/manifest.tt
	cp everything.tsv $@/train.tsv
	cp test/annotated.tsv $@/test.tsv 
	touch $@

models/%/best.pth:
	mkdir -p models/$*/
	if test -z "$(s3_model_dir)" ; then \
	  echo "s3_model_dir is empty" ; \
	  azcopy sync --recursive --exclude-pattern "*/dataset/*;*/cache/*;iteration_*.pth;*_optim.pth" ${s3_bucket}/$(if $(findstring /,$*),$(dir $*),$(owner)/)models/${project}/$(notdir $*)/ models/$*/ ; \
	else \
	  echo "s3_model_dir is not empty" ; \
	  echo models/$*/ ; \
	  azcopy sync --recursive --exclude-pattern "*/dataset/*;*/cache/*;iteration_*.pth;*_optim.pth" ${s3_bucket}/$(s3_model_dir) models/$*/ ; \
	fi

$(experiment)/manifest.tt: manifest.tt
	cp manifest.tt $@

$(eval_set)/%.results: models/%/best.pth $(eval_set)/annotated.tsv $(experiment)/manifest.tt 
	mkdir -p $(eval_set)/$(dir $*)
	GENIENLP_NUM_BEAMS=$(beam_size) $(genie) evaluate-server $(eval_set)/annotated.tsv \
		--url "file://$(abspath $(dir $<))" \
		--thingpedia $(experiment)/manifest.tt \
		--debug \
		--csv-prefix $(eval_set) \
		--csv $(evalflags) \
		--min-complexity 1 --max-complexity 3 \
		--include-entity-value \
		--exclude-entity-display \
		--ignore-entity-type \
		-o $@.tmp | tee $(eval_set)/$*.debug
	mv $@.tmp $@ 

evaluate: $(eval_set)/$(model).results
	@for f in $^ ; do echo $$f ; cat $$f ; done

evaluate-output-artifacts:
	mkdir -p `dirname $(s3_metrics_output)`
	mkdir -p $(metrics_output)
	for f in {results,debug} ; do \
	  azcopy cp $(eval_set)/$(model).$$f $(s3_bucket)/$(genie_k8s_owner)/workdir/$(genie_k8s_project)/$(eval_set)/$(if $(findstring /,$(model)),$(dir $(model)),)$(artifacts_ver)/ ; \
	done
	echo $(genie_k8s_owner)/workdir/$(genie_k8s_project)/$(eval_set)/$(if $(findstring /,$(model)),$(dir $(model)),)$(artifacts_ver)/ > $(s3_metrics_output)
	cp -r $(eval_set)/$(model)* $(metrics_output)
	python3 write_ui_metrics_outputs.py $(eval_set)/$(model).results 

clean:
	rm -rf *.tmp qald7 qald9
	rm -rf test/annotated.tsv eval/annotated.tsv
	rm -rf datadir synthetic* parameter-datasets parameter-datasets.tsv *.tt *.json *.tsv
