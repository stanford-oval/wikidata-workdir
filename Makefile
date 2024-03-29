s3_bucket ?= https://nfs009a5d03c43b4e7e8ec2.blob.core.windows.net/pvc-a8853620-9ac7-4885-a30e-0ec357f17bb6
geniedir ?= $(HOME)/genie-toolkit
qalddir ?= qald

-include ./config.mk

s3_metrics_output ?=
metrics_output ?=
artifacts_ver := $(shell date +%s)

memsize := 14000
genie = node --experimental_worker --max_old_space_size=$(memsize) $(geniedir)/dist/tool/genie.js

owner ?= silei
project = qald
experiment ?= webq
domains ?= all
qald_version ?= main
dataset_file = emptydataset.tt
type_system ?= 'hierarchical'
update_manifest ?= true
exclude_canonical_annotations ?= false
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
ned ?= oracle
synthetic_ned ?= oracle
refined_model ?= questions_model
entity_recovery_mode ?= false
gpt3_rephrase ?= false # requires OPENAI_API_KEY
openai_api_key ?= ${OPENAI_API_KEY}
azure_entity_linker_key = ${AZURE_ENTITY_LINKER_KEY}
abstract_property ?= true

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

models/refined:
	pip install https://github.com/amazon-science/ReFinED/archive/refs/tags/V1.zip 
	mkdir -p $@
	if [[ "$(refined_model)" == "questions_model" ]] ; then \
		python $(qalddir)/python/load_refined_model.py ; \
	else \
		curl https://almond-static.stanford.edu/research/qald/refined-finetune/config.json -o $@/config.json ; \
		curl https://almond-static.stanford.edu/research/qald/refined-finetune/model.pt -o $@/model.pt ; \
		curl https://almond-static.stanford.edu/research/qald/refined-finetune/precomputed_entity_descriptions_emb_wikidata_33831487-300.np -o $@/precomputed_entity_descriptions_emb_wikidata_33831487-300.np ; \
	fi

emptydataset.tt:
	echo 'dataset @empty {}' > $@

# prepare raw data for fewshot, eval, and test
$(experiment)/data: $(qalddir)
	mkdir -p $@
	node $(qalddir)/dist/lib/divide.js \
		$(qalddir)/data/$(experiment)/train.json\
		$(if $(findstring webq,$(experiment)),--size 500,)
	mv xaa $@/fewshot.json
	mv xab $@/eval.json
	cp $(qalddir)/data/$(experiment)/test.json $@/test.json

# generate manifest
manifest.tt: $(qalddir) $(wikidata_cache) $(bootleg)
	if [[ "$(update_manifest)" == "true" ]] ; then \
		mkdir -p parameter-datasets ; \
		node $(qalddir)/dist/lib/manifest-generator.js \
			--experiment $(experiment) \
			--cache $(wikidata_cache) \
			--use-wikidata-alt-labels \
			--save-cache \
			--bootleg-db $(bootleg) \
			--type-system $(type_system) \
			-o $@ \
			$(if $(findstring all,$(domains)),,--domains $(domains)) \
			$(if $(findstring true,$(exclude_canonical_annotations)),--no-canonical-annotations,) ; \
		curl https://almond-static.stanford.edu/research/shared-parameter-datasets/tt:short_free_text.tsv -o parameter-datasets/tt:short_free_text.tsv ; \
		echo "string	en-US	tt:short_free_text	parameter-datasets/tt:short_free_text.tsv" | tee -a parameter-datasets.tsv ; \
	else \
		touch manifest.tt ; \
	fi

# synthesize data with depth d
synthetic-d%.tsv: manifest.tt $(dataset_file)
	$(genie) generate \
		--thingpedia manifest.tt --entities entities.json --dataset $(dataset_file) \
		--target-pruning-size $(pruning_size) \
		-o $@.tmp $(generate_flags) --maxdepth $$(echo $* | cut -f1 -d'-') --random-seed $@ --debug 3 \
		--id-prefix $*-
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
		--skip-errors \
		$*.tsv
	node $(qalddir)/dist/lib/post-processor.js \
		--thingpedia manifest.tt \
		--include-entity-value \
		--bootleg-db $(bootleg) \
		--cache $(wikidata_cache) \
		$(normalization_options) \
		-i $@.tmp \
		-o $@.tmp2
	$(genie) typecheck $@.tmp2\
		-o $@ \
		--dropped $*-augment-dropped.tsv \
		--thingpedia manifest.tt \
		--include-entity-value 
	rm $@.tmp*

# convert raw data into thingtalk
%-converted.tsv: manifest.tt $(wikidata_cache) $(bootleg) $(experiment)/data
	node $(qalddir)/dist/lib/converter/index.js \
		-i $(experiment)/data/$*.json\
		--manifest manifest.tt \
		--cache $(wikidata_cache) \
		--bootleg-db $(bootleg) \
		--save-cache \
		-d $*-convertion-dropped.tsv \
		-o $@.tmp \
		--include-entity-value \
		$(if $(findstring true,$(abstract_property)),,--no-property-abstraction)
	node $(qalddir)/dist/lib/post-processor.js \
		--thingpedia manifest.tt \
		--include-entity-value \
		--bootleg-db $(bootleg) \
		--cache $(wikidata_cache) \
		$(normalization_options) \
		-i $@.tmp \
		-o $@.tmp2
	$(genie) typecheck $@.tmp2\
		-o $@ \
		--dropped $*-typecheck-dropped.tsv \
		--thingpedia manifest.tt \
		--include-entity-value 
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

# append ned information
%-ned.tsv: %.tsv $(if $(or $(findstring refined,$(ned)$(synthetic_ned)), $(findstring ensemble,$(ned)$(synthetic_ned))),models/refined,)
	if [[ -n "$(ned)" ]] ; then \
		export OPENAI_API_KEY=$(openai_api_key) ; \
		export AZURE_ENTITY_LINKER_KEY=$(azure_entity_linker_key) ; \
		split -d -l 10000 $*.tsv $*.tsv-split ; \
		node $(qalddir)/dist/lib/ner/index.js \
			-i $*.tsv \
			-o $*-ned.tsv \
			--wikidata-cache $(wikidata_cache) \
			--bootleg $(bootleg) \
			--module $(if $(findstring everything,$*),$(synthetic_ned),$(ned)) \
			--refined-model $(if $(findstring questions_model,$(refined_model)),$(refined_model),$(realpath $(refined_model))) \
			--include-entity-value \
			--exclude-entity-display \
			$(if $(findstring true,$(entity_recovery_mode)),--entity-recovery-mode,) \
			$(if $(findstring everything,$*),--is-synthetic,) \
			$(if $(or $(findstring false,$(gpt3_rephrase)), $(findstring everything,$*)),,--gpt3-rephrase) ; \
	else \
		cp $*.tsv $*-ned.tsv ; \
	fi


# final data directory, putting train, eval and test together 
datadir: $(if $(findstring true,$(synthetic_test)),eval-synthetic/annotated-ned.tsv test-synthetic/annotated-ned.tsv,eval/annotated-ned.tsv test/annotated-ned.tsv) everything-ned.tsv
	mkdir -p $@
	cp manifest.tt $@/manifest.tt
	cp entities.json $@/entities.json
	cp everything-ned.tsv $@/train.tsv
	cp $(if $(findstring true,$(synthetic_test)),eval-synthetic/annotated-ned.tsv,eval/annotated-ned.tsv) $@/eval.tsv
	cp $(if $(findstring true,$(synthetic_test)),test-synthetic/annotated-ned.tsv,test/annotated-ned.tsv) $@/test.tsv 
	wc -l datadir/*.tsv
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

$(eval_set)/annotated-oracle.tsv: $(eval_set)/annotated.tsv
	node $(qalddir)/dist/lib/ner/index.js \
		-i $< \
		-o $@ \
		--wikidata-cache $(wikidata_cache) \
		--bootleg $(bootleg) \
		--module oracle \
		--include-entity-value \
		--exclude-entity-display 

$(eval_set)/%-predictions.tsv: models/%/best.pth $(eval_set)/annotated-ned.tsv manifest.tt
	mkdir -p $(eval_set)/$(dir $*)
	GENIENLP_NUM_BEAMS=$(beam_size) $(genie) predict $(eval_set)/annotated-ned.tsv \
		--url "file://$(abspath $(dir $<))" \
		--debug \
		--csv \
		-o $@ | tee $(eval_set)/$*.debug

# evaluation
$(eval_set)/%.results: $(eval_set)/%-predictions.tsv manifest.tt $(eval_set)/annotated-oracle.tsv
	mkdir -p $(eval_set)/$(dir $*)
	if [[ "$(metric)" == "query" ]] ; then \
		node $(qalddir)/dist/lib/evaluate-query.js \
			--oracle $(eval_set)/annotated-oracle.tsv \
			--prediction $(eval_set)/$*-predictions.tsv \
			--cache $(wikidata_cache) \
			--save-cache \
			--bootleg-db $(bootleg) \
			-o $(eval_set)/$*.debug  > $@ ; \
	else \
		node $(qalddir)/dist/lib/converter/index.js \
			--direction from-thingtalk \
			-i $(eval_set)/$*-predictions.tsv \
			--cache $(wikidata_cache) \
			--save-cache \
			--bootleg-db $(bootleg) \
			-o $(eval_set)/$*-gold-sparql.tsv \
			--manifest manifest.tt \
			--domains parameter-datasets/domain.json \
			--include-entity-value \
			--exclude-entity-display \
			$(if $(findstring true,$(abstract_property)),,--no-property-abstraction);\
		node $(qalddir)/dist/lib/converter/index.js \
			--direction from-thingtalk \
			-i $(eval_set)/$*-predictions.tsv \
			-o $(eval_set)/$*-prediction-sparql.tsv \
			--cache $(wikidata_cache) \
			--save-cache \
			--bootleg-db $(bootleg) \
			--prediction \
			--manifest manifest.tt \
			--domains parameter-datasets/domain.json \
			--include-entity-value \
			--exclude-entity-display \
			$(if $(findstring true,$(abstract_property)),,--no-property-abstraction) ;\
		node $(qalddir)/dist/lib/evaluate.js \
			--from-thingtalk \
			--cache $(wikidata_cache) \
			--bootleg-db $(bootleg) \
			--dataset $(eval_set)/$*-gold-sparql.tsv \
			--prediction $(eval_set)/$*-prediction-sparql.tsv > $@ ; \
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

safe-clean:
	rm -rf qald7 qald9 webq datadir synthetic* fewshot* augmented* everything* *.tmp* *-dropped.tsv eval/*.tsv test/*.tsv 

# clean up data generated, but keeps manifest
clean-data:
	rm -rf qald7 qald9 webq
	rm -rf datadir eval test eval-synthetic test-synthetic
	rm -rf synthetic* fewshot* augmented* everything* *.tmp* *-dropped.tsv

# clean only the synthetic data generated
clean-synthetic:
	rm -rf datadir eval-synthetic test-synthetic
	rm -rf synthetic* everything* *.tmp* 

# clean up workdir entirely, restart
clean:
	rm -rf qald7 qald9
	rm -rf datadir eval test eval-synthetic test-synthetic
	rm -rf synthetic* fewshot* augmented* everything* *-dropped.tsv
	rm -rf parameter-datasets 
	rm -rf *.tt *.json *.tsv *.tmp*