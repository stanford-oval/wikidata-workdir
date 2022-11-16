import os
import argparse
import json
import openai

RESPONSE_END_TOKEN = '\n'

openai.api_key = os.environ['OPENAI_API_KEY']
openai.api_base = 'https://ovalopenairesource.openai.azure.com/'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', type=str, required=True, help='File to evaluate')
    parser.add_argument('-o', '--output', type=str, required=False, help='File to write the result, default to the same name as the input file')
    parser.add_argument('--model', type=str, required=True, help='ID of the model')
    parser.add_argument('--cache', type=str, required=False, default='cache.json', help='Path to the cache file')
    args = parser.parse_args()

    if os.path.exists(args.cache):
        cache = json.load(open(args.cache))
    else:
        cache = dict()

    correct = 0
    total = 0
    with open(args.input, 'r') as fin, open(args.output, 'w') as fout:
        for line in fin:
            example = json.loads(line)
            
            # check cache, if not available, query openai
            if example['prompt'] in cache:
                prediction = cache[example['prompt']]
            else:
                response = openai.Completion.create(
                    model = args.model,
                    prompt = example['prompt'],
                    temperature=0,
                    stop = RESPONSE_END_TOKEN,
                    max_tokens = 100
                )
                prediction = response['choices'][0]['text']
                cache[example['prompt']] = prediction

            # check exact match
            if example['completion'].strip() == prediction.strip():
                correct += 1

            total += 1
            fout.write('{}\t{}\t{}\t{}\n'.format(example['id'], example['utterance'], example['completion'].strip(), prediction.strip()))
    
    with open(args.cache, 'w') as f:
        json.dump(cache, f)
    print(correct, total)


