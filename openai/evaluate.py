import os
import argparse
import json
import openai

RESPONSE_END_TOKEN = '\n'

openai.api_key = os.environ['OPENAI_API_KEY']

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', type=str, required=True, help='File to evaluate')
    parser.add_argument('-o', '--output', type=str, required=False, help='File to write the result, default to the same name as the input file')
    parser.add_argument('--model', type=str, required=True, help='ID of the model')
    args = parser.parse_args()
    
    correct = 0
    total = 0
    with open(args.input, 'r') as fin, open(args.output, 'w') as fout:
        for line in fin:
            example = json.loads(line)
            response = openai.Completion.create(
                model = args.model,
                prompt = example['prompt'],
                stop = RESPONSE_END_TOKEN,
                max_tokens = 100
            )
            print(response)
            example['gold'] = example['completion']
            example['completion'] = response['choices'][0]['text']
            if example['completion'] == example['gold']:
                correct += 1
                break

            total += 1
            fout.write(json.dumps(example) + '\n')
    
    print(correct, total)

