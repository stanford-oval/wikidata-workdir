s3_bucket ?= https://nfs009a5d03c43b4e7e8ec2.blob.core.windows.net/pvc-a8853620-9ac7-4885-a30e-0ec357f17bb6
geniedir ?= $(HOME)/genie-toolkit
qalddir ?= qald
thingpedia_url = https://almond-dev.stanford.edu/thingpedia

-include ./config.mk

s3_metrics_output ?=
metrics_output ?=
artifacts_ver := $(shell date +%s)

memsize := 14000
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

pruning_size ?= 5
maxdepth ?= 8
mindepth ?= 6
maxdepth_count ?= 1
mindepth_count ?= 1

wikidata_cache = $(qalddir)/wikidata_cache.sqlite
bootleg =$(qalddir)/bootleg.sqlite

# ablation settings 
fewshot ?= true
synthetic ?= true
synthetic_size ?=
synthetic_test ?= false
metric ?= query

.PHONY: clean clean-data
.SECONDARY:

$(qalddir):
	./install.sh $(qald_version)

$(wikidata_cache):
	curl https://almond-static.stanford.edu/research/qald/wikidata_cache.sqlite -o $@ 

$(bootleg):
	curl https://almond-static.stanford.edu/research/qald/bootleg.sqlite -o $@

emptydataset.tt:
	echo 'dataset @empty {}' > $@

# prepare raw data for fewshot, eval, and test
$(experiment)/data: $(qalddir)
	mkdir -p $@
	node $(qalddir)/dist/lib/divide.js $(qalddir)/data/$(experiment)/train.json 
	mv xaa $@/fewshot.json
	mv xab $@/eval.json
	cp $(qalddir)/data/$(experiment)/test.json $@/test.json

# generate manifest
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

# synthesize data with depth d
synthetic-d%.tsv: manifest.tt $(dataset_file)
	$(genie) generate \
		--thingpedia manifest.tt --entities entities.json --dataset $(dataset_file) \
		--target-pruning-size $(pruning_size) \
		-o $@.tmp $(generate_flags) --maxdepth $$(echo $* | cut -f1 -d'-') --random-seed $@ --debug 3
	mv $@.tmp $@

# merge synthetic data
synthetic.tsv: $(foreach v,$(shell seq 1 1 $(mindepth_count)),synthetic-d$(mindepth)-$(v).tsv) $(foreach v,$(shell seq 1 1 $(maxdepth_count)),synthetic-d$(maxdepth)-$(v).tsv)
	cat $^ > $@

# augment data 
augmented-%.tsv: $(qalddir) manifest.tt %.tsv
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
		$*.tsv
	node $(qalddir)/dist/lib/post-processor.js \
		--thingpedia manifest.tt \
		--include-entity-value \
		--exclude-entity-display \
		--bootleg-db $(bootleg) \
		--cache $(wikidata_cache) \
		$(normalization_options) \
		-i $@.tmp \
		-o $@.tmp2
	$(genie) typecheck $@.tmp2\
		-o $@ \
		--dropped fewshot-dropped.tsv \
		--thingpedia manifest.tt \
		--include-entity-value \
		--exclude-entity-display 
	rm $@.tmp*

# convert raw data into thingtalk
%-converted.tsv: manifest.tt $(wikidata_cache) $(bootleg) $(experiment)/data
	node $(qalddir)/dist/lib/converter/index.js \
		-i $(experiment)/data/$*.json\
		--manifest manifest.tt \
		--cache $(wikidata_cache) \
		--bootleg-db $(bootleg) \
		--save-cache \
		-d fewshot-dropped.tsv \
		-o $@.tmp \
		$(if $(findstring fewshot,$*),,--exclude-entity-display --include-entity-value)
	node $(qalddir)/dist/lib/post-processor.js \
		--thingpedia manifest.tt \
		--include-entity-value \
		--exclude-entity-display \
		--bootleg-db $(bootleg) \
		--cache $(wikidata_cache) \
		$(normalization_options) \
		-i $@.tmp \
		-o $@.tmp2
	$(genie) typecheck $@.tmp2\
		-o $@ \
		--dropped fewshot-dropped.tsv \
		--thingpedia manifest.tt \
		--include-entity-value \
		--exclude-entity-display 
	rm $@.tmp*

# prepare converted fewshot data
fewshot.tsv: fewshot-converted.tsv
	$(genie) requote fewshot-converted.tsv -o $@ --skip-errors 
	rm fewshot-converted.tsv

# prepare converted eval data
eval/annotated.tsv: eval-converted.tsv
	mkdir -p eval
	mv eval-converted.tsv $@

# prepare converted test data
test/annotated.tsv: test-converted.tsv 
	mkdir -p test
	mv test-converted.tsv $@

eval-synthetic/annotated.tsv: augmented-synthetic-d$(maxdepth)-eval.tsv
	mkdir -p eval-synthetic
	shuf $^ | head -100 > $@

test-synthetic/annotated.tsv: augmented-synthetic-d$(maxdepth)-test.tsv
	mkdir -p test-synthetic
	shuf $^ | head -100 > $@

# augment fewshot and synthetic data
everything.tsv: $(if $(findstring true,$(fewshot)),augmented-fewshot.tsv,) $(if $(findstring true,$(synthetic)),augmented-synthetic.tsv,) 
	if [[ -n "$(synthetic_size)" ]] ; then \
		shuf augmented-synthetic.tsv | head -$(synthetic_size) > augmented-synthetic.tsv.tmp ; \
		mv augmented-synthetic.tsv.tmp augmented-synthetic.tsv ; \
	fi
	cat $^ > $@

# final data directory, putting train, eval and test together 
datadir: $(if $(findstring true,$(synthetic_test)),eval-synthetic/annotated.tsv test-synthetic/annotated.tsv,eval/annotated.tsv test/annotated.tsv) everything.tsv
	mkdir -p $@
	cp manifest.tt $@/manifest.tt
	cp everything.tsv $@/train.tsv
	cp $(if $(findstring true,$(synthetic_test)),eval-synthetic/annotated.tsv,eval/annotated.tsv) $@/eval.tsv
	cp $(if $(findstring true,$(synthetic_test)),test-synthetic/annotated.tsv,test/annotated.tsv) $@/test.tsv 
	touch $@

# download model from azure
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

# save manifest in experiment folder for debugging 
$(experiment)/manifest.tt: manifest.tt
	cp manifest.tt $@

# evaluation
$(eval_set)/%.results: models/%/best.pth $(eval_set)/annotated.tsv $(experiment)/manifest.tt 
	mkdir -p $(eval_set)/$(dir $*)
	if [[ "$(metric)" == "query" ]] ; then \
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
			-o $@.tmp | tee $(eval_set)/$*.debug; \
		mv $@.tmp $@ ; \
	else \
		GENIENLP_NUM_BEAMS=$(beam_size) $(genie) predict $(eval_set)/annotated.tsv \
			--url "file://$(abspath $(dir $<))" \
			--debug \
			--csv \
			-o predictions-thingtalk.tsv | tee $(eval_set)/$*.debug; \
		node $(qalddir)/dist/lib/converter/index.js \
			--direction from-thingtalk \
			-i predictions-thingtalk.tsv \
			--cache $(wikidata_cache) \
			--bootleg-db $(bootleg) \
			-o gold-sparql.tsv \
			--manifest $(experiment)/manifest.tt \
			--domains parameter-datasets/domain.json \
			--include-entity-value \
			--exclude-entity-display ;\
		node $(qalddir)/dist/lib/converter/index.js \
			--direction from-thingtalk \
			-i predictions-thingtalk.tsv \
			-o predictions-sparql.tsv \
			--cache $(wikidata_cache) \
			--bootleg-db $(bootleg) \
			--prediction \
			--manifest $(experiment)/manifest.tt \
			--domains parameter-datasets/domain.json \
			--include-entity-value \
			--exclude-entity-display ;\
		node $(qalddir)/dist/lib/evaluate.js \
			--from-thingtalk \
			--cache $(wikidata_cache) \
			--bootleg-db $(bootleg) \
			--dataset gold-sparql.tsv \
			--prediction predictions-sparql.tsv > $@ ; \
	fi 

evaluate: $(eval_set)/$(model).results
	@for f in $^ ; do echo $$f ; cat $$f ; done

# generate kubeflow visualization
evaluate-output-artifacts:
	mkdir -p `dirname $(s3_metrics_output)`
	mkdir -p $(metrics_output)
	for f in {results,debug} ; do \
		azcopy cp $(eval_set)/$(model).$$f $(s3_bucket)/$(genie_k8s_owner)/workdir/$(genie_k8s_project)/$(eval_set)/$(if $(findstring /,$(model)),$(dir $(model)),)$(artifacts_ver)/ ; \
	done
	echo $(genie_k8s_owner)/workdir/$(genie_k8s_project)/$(eval_set)/$(if $(findstring /,$(model)),$(dir $(model)),)$(artifacts_ver)/ > $(s3_metrics_output)
	cp -r $(eval_set)/$(model)* $(metrics_output)
	if [[ "$(metric)" == "query" ]] ; then \
		python3 write_ui_metrics_outputs.py $(eval_set)/$(model).results ; \
	fi 

# clean up data generated, but keeps manifest
clean-data:
	rm -rf qald7 qald9
	rm -rf datadir eval test eval-synthetic test-synthetic
	rm -rf synthetic* fewshot* augmented* everything.tsv *.tmp*

# clean up workdir entirely, restart
clean:
	rm -rf qald7 qald9
	rm -rf datadir eval test eval-synthetic test-synthetic
	rm -rf synthetic* fewshot* augmented* everything.tsv
	rm -rf parameter-datasets 
	rm -rf *.tt *.json *.tsv *.tmp*
