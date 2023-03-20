# Working directory for Genie Wikidata experiments

This is an _internal_ repository containing the workdirs with project-specific scripts that are called from kubeflow pipelines.


## Local testing setup
Three repositories are required to test run dataset preparation locally:
- [wikidata-workdir](https://github.com/stanford-oval/wikidata-workdir)
- [genie-toolkit](https://github.com/stanford-oval/genie-toolkit)
- [qald](https://github.com/rayslxu/qald)

Install them separatelly, then inside the `wikidata-workdir` directory, create configuration file `config.mk` with the following lines  
```bash
geniedir=<PATH_TO_YOUR_GENIE_INSTALLATION>
qalddir=<PATH_TO_YOUR_QALD_INSTALLATION>
```

To generate a sample dataset, run the following command:
```bash
make datadir
```
