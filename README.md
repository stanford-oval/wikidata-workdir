# Working directory for Genie Wikidata experiments

This is an _internal_ repository containing the workdirs with project-specific scripts that are called from kubeflow pipelines.


## Local testing setup
Three repositories are required to test run dataset preparation locally:
- [wikidata-workdir](https://github.com/stanford-oval/wikidata-workdir)
- [genie-toolkit](https://github.com/stanford-oval/genie-toolkit)
- [qald](https://github.com/rayslxu/qald)

Install them separately, use `master` branch for `wikidata-workdir`, `wip/entity-recovery-mode` branch for `qald` repository, and `wip/qald` for `genie-toolkit`. Then inside the `wikidata-workdir` directory, create configuration file `config.mk` with the following lines  
```bash
geniedir=<PATH_TO_YOUR_GENIE_INSTALLATION>
qalddir=<PATH_TO_YOUR_QALD_INSTALLATION>
```

To generate a sample dataset, run the following command:
```bash
make datadir
```
This will generate a small sample dataset with oracle NED. If ReFinED entity linker is desired, add the following options to the command:
```
entity_recovery_mode=true
refined_model=models/refined
ned=refined
synthetic_ned=refined
``` 

To evaluate an existing model:

1.  Install [genienlp](https://github.com/stanford-oval/genienlp).

2. Download the model using the following command, where `<path>` is the folder containing the model under azure bucket `pvc-a8853620-9ac7-4885-a30e-0ec357f17bb6`. The model will be downloaded under `models/<model_name>`.
```bash
./sync-models.sh <path> <model_name>
```

3. Run the following command to evaluate, where `<eval_set>` is `eval` for dev set and `test` for test set. 
```bash
make \
  refined_model=models/refined \
  entity_recovery_mode=true \
  ned=refined \
  metric=answer \
  eval_set=<eval_set> \
  <eval_set>/<model_name>.results
```


Note that generating `manifest.tt` file takes very long. Once it's generated and no update is needed, option `update_manifest=false` to all make commands above to save time. 

If some command failed in the middle or there is a dataset update, run `make safe-clean` to clean up the folder before rerun the command. 