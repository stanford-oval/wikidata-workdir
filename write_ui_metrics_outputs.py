import json
import sys
import csv

def write_ui_metadata(nlu_results):
  metadata = {"outputs" : [
    {
      "storage": "inline",
      "source": nlu_results,
      "format": 'csv',
      "type": "table",
      "header": ["Eval Set", "Device", "Example Count", "Accuracy", "W/o params", "Function", "Device", "Num Function", "Syntax", "NED"]
    },
  ]} 
  with open('/tmp/mlpipeline-ui-metadata.json', 'w') as f:
    json.dump(metadata, f)


def write_metrics(nlu_filepath):
  with open(nlu_filepath) as f:
    row1 = next(csv.reader(f))
    accuracy = row1[3]
  metrics = {
    'metrics': [
      { 'name': 'em', 'numberValue':  accuracy, 'format': "PERCENTAGE"},
    ]
  }
  with open('/tmp/mlpipeline-metrics.json', 'w') as f:
    json.dump(metrics, f)


if __name__ == '__main__':
  nlu_results = open(sys.argv[1]).read()
  write_ui_metadata(nlu_results)
  write_metrics(sys.argv[1])
