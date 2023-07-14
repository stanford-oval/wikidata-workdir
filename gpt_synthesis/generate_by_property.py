from prompt_continuation import llm_generate
from pymongo import MongoClient
from tqdm import tqdm
from utils import fill_template
import json
import random
import argparse
import multiprocessing
import subprocess


with open('properties-with-aliases.json', 'r') as fd:
    data = json.load(fd)


# time, all replace with 'P585'
# 'P580'
# 'P571'
# 'P575'
# 'P582'

TIME_CONCRETE_PROPERTIES = ['P580', 'P571', 'P575', 'P582']

# location, all replace with P276
# 'P131', // located in the administrative territorial entity
# 'P3842', // located in the present-day administrative territorial entity
# 'P159', // headquarter location
# 'P551', // residence
# 'P17', // country
# 'P27', // country of citizenship
# 'P495', // country of origin
# 'P19', // place of birth
# 'P30', // continent
# 'P625', // coordinate location
LOCATION_CONCRETE_PROPERTIES = ['P131', 'P3842', 'P159', 'P551', 'P17', 'P27', 'P495', 'P19', 'P30', 'P625']


def generate_single_property():
    # populates a DB for generation
    client = MongoClient('localhost', 27017)
    db = client['wikidata_llama']['synthetic_property_alias']
    for domain_name in data:
        for property_name in data[domain_name]["properties"]:
            property_id = data[domain_name]["properties"][property_name]["id"]
            if property_id in TIME_CONCRETE_PROPERTIES + LOCATION_CONCRETE_PROPERTIES:
                continue
                
            alias_list = data[domain_name]["properties"][property_name]["aliases"]
            if len(alias_list) < 5:
                batch = alias_list
            else:
                batch = random.sample(alias_list, 5)
            
            alias_list_display = ", ".join(batch)
            num_question = len(batch)
            if num_question < 5:
                num_question += 1
        
            to_append = {
                "domain_name": domain_name,
                "property_name": property_name.lower().replace(' ', '_').replace('/','_').replace('-', '_'),
                "alias": alias_list_display,
                "num_question": len(batch)
            }
            
            db.insert_one(to_append)
            
def go_through_db(start, end):
    # go through the db to actually generate examples
    # `parallelize` below is a parallel version for this
    client = MongoClient('localhost', 27017)
    db = client['wikidata_llama']['synthetic_property_alias']
    current_j = -1
    for i in db.find().batch_size(500).max_await_time_ms(600000):
        current_j += 1
        if current_j < start:
            continue
        if current_j >= end:
            break
        
        if "results" in i:
            continue
        print("job ({}, {}), currently at {}".format(start, end, current_j))
        
        try:
            continuation = llm_generate('prompts/single_property_alias.prompt', i, max_tokens=400, temperature=0, stop_tokens=["=="], engine="chatGPT", postprocess=False)
            json_repr = '[{"query": "' + continuation
        
            res = json.loads(json_repr)
            db.update_one({
                "_id": i["_id"]
            }, {
                "$set": {
                    "results": res
                }
            })
            
        except Exception as e:
            print(json_repr)
            print("job ({}, {}), errored with {}".format(start, end, e))
    
def parallelize():
    def generate_tuples(start, end, step):
        tuples = []
        for i in range(start, end+1, step):
            t = (i, i+step-1)
            tuples.append(t)
        return tuples
    
    jobs = generate_tuples(0, 4000, 300)

    pool = multiprocessing.Pool(processes=len(jobs))
    pool.starmap(go_through_db, jobs)
    pool.close()
    pool.join()

def collect_all_synthesis():
    client = MongoClient('localhost', 27017)
    db = client['wikidata_llama']['synthetic_property_alias']
    res = []
    for i in db.find():
        if "results" in i and i["results"]:
            for result in i["results"]:
                try:
                    _instruction = fill_template('prompts/property-name-gen.instruction',{})
                    _input = fill_template('prompts/property-name-gen.input',{
                        "query": result["query"],
                        "qid_list_tuples": [(i["name"], i["id"]) for i in result["entities"]]
                    })
                    _output = result["sparql"]
                
                    res.append({
                        "input": _input,
                        "instruction": _instruction,
                        "output": _output
                    })
                except KeyError or ValueError:
                    pass
                
    print(len(res))
    with open("/data0/wikidata-workdir/llama_data/data/alias_synthesis.json", "w") as fd:
        json.dump(res, fd, indent=2)
            
                
if __name__ == "__main__":
    # go_through_db(0, 4000)
    # parser = argparse.ArgumentParser(description='Generate single property at a time')
    # parser.add_argument('-s', '--start', type=int, help='start')
    # parser.add_argument('-e', '--end', type=int, help='end')

    # # Parse the arguments
    # args = parser.parse_args()
    
    generate_single_property()    
    # go_through_db(args.start, args.end)
    # parallelize()
    # collect_all_synthesis()
    
    # for i in db.find({"results": {"$exists": True}}):
    #     del i["_id"]
    #     print(json.dumps(dict(i), indent=2))
        