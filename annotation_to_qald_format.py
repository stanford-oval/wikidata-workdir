import os
import glob
import re
import json
import argparse

PREFIXES = {
    'wd': 'http://www.wikidata.org/entity/',
    'wdt': 'http://www.wikidata.org/prop/direct/',
    'p': 'http://www.wikidata.org/prop/',
    'ps': 'http://www.wikidata.org/prop/statement/',
    'pq': 'http://www.wikidata.org/prop/qualifier/',
    'xsd': 'http://www.w3.org/2001/XMLSchema#',
    'wikibase': 'http://wikiba.se/ontology#',
    'bd': 'http://www.bigdata.com/rdf#',
    'schema': 'http://schema.org/',
    'rdfs': 'http://www.w3.org/2000/01/rdf-schema#'
}

def get_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', type=str, required=True)
    parser.add_argument('-o', '--output', type=str, required=False)
    return parser


def convert_match(match_obj):
    a, b = match_obj.group(0).split(':')
    return '<' + PREFIXES[a] + b + '>'
        

# def sparql_formatter(str_in):
#     for i in PREFIXES.keys():
#         if i in ['wd', 'wdt', 'p', 'ps', 'pq']:
#             pattern_str = i + r":\w[0-9]+[*]?"
#         elif i in ['xsd', 'wikibase', 'bd', 'schema', 'rdfs']:
#             pattern_str = i + r":\w+"
#         str_in = re.sub(pattern_str, convert_match, str_in)
#     return str_in

def sparql_formatter(str_in):
    tmp = []
    for i in PREFIXES.keys():
        if i in str_in:
            tmp.append(f"PREFIX {i}: <{PREFIXES[i]}>")
    tmp.append(str_in)
    return " ".join(tmp)
        

if __name__ == '__main__':
    parser = get_parser()
    args = parser.parse_args()
    data = {}
    if os.path.isdir(args.input):
        files = glob.glob(os.path.join(args.input, '*annotated.json'))
        for f in files:
            id_name = f.split(os.sep)[-1].split('.')[0]
            data[id_name] = json.load(open(f))
    elif os.path.isfile(args.input):
        id_name = args.input.split(os.sep)[-1]
        data[id_name] = json.load(open(args.input))
    f_count = len(data.keys())   
    sample_count = 0
    for n, (k, d) in enumerate(data.items(), 1):
        schema = {
            'dataset': {
                "id": None
            },
            'questions': []
        }
        schema['dataset']['id'] = k
        for i in d:
            temp = {
                'id': i['QuestionId'],
                'question': [
                    {
                        "language": 'en',
                        "string": i['RawQuestion'],
                        "keywords": ''
                    }
                ],
                'query': {
                    'sparql': sparql_formatter(i['Parses'][0]['Sparql'])
                },
            }
            schema['questions'].append(temp)
            sample_count += 1
            
        if args.output:
            if not os.path.exists(args.output):
                os.makedirs(args.output)
            fo_path = os.path.join(args.output, '.'.join([k, 'qald', 'json']))
        else:
            fo_path = os.path.join(args.input, '.'.join([k, 'qald', 'json']))
        print(f'[{n:02d}/{f_count}]\t{k} -> {fo_path}')
        with open(fo_path, 'w') as outfile:
            json.dump(schema, outfile)
    
    print(f'total samples: {sample_count:,}')