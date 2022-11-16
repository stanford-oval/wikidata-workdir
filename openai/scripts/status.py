import os
import time
import argparse
import openai
from openai import cli

openai.api_key = os.environ['OPENAI_API_KEY']
openai.api_base = 'https://ovalopenairesource.openai.azure.com/'
openai.api_type = 'azure'
openai.api_version = '2022-06-01-preview' 

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--id', type=str, required=False, help='Job ID')

    args = parser.parse_args()

    if args.id:
        status = openai.FineTune.retrieve(args.id)['status']
        while status not in ["succeeded", "failed"]:
            print(status)
            time.sleep(5)
            status = openai.FineTune.retrieve(args.id)['status']
        print(openai.FineTune.retrieve(args.id))
    else:
        print(openai.FineTune.list())