"use strict";

import fs from 'fs';
import * as QALD from 'qald';
import Tp from 'thingpedia';
import ThingTalk from 'thingtalk';
import * as readline from 'readline';

const NLU_SERVER = 'http://127.0.0.1:8400/en-US/query';

async function main() {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const tpClient = new Tp.FileClient({ thingpedia: './manifest.tt', locale: 'en' });
    const schemas = new ThingTalk.SchemaRetriever(tpClient, null, true);
    const classDef = await schemas.getFullMeta('wd');
    const domains = JSON.parse(fs.readFileSync('./domain.json', { encoding: 'utf8' })).data;

    const converter = new QALD.ThingTalkToSPARQLConverter(classDef, domains, {
        locale: 'en',
        timezone: 'utc',
        cache: 'wikidata_cache.sqlite',
        save_cache: true,
        bootleg: 'bootleg.sqlite',
        human_readable_instance_of: false
    });

    const wikidata = new QALD.WikidataUtils('wikidata_cache.sqlite', 'bootleg.sqlite', true);

    rl.prompt();
    rl.on('line', async (line) => {
        let thingtalk = null;
        if (line.startsWith('\t ')) {
            thingtalk = line.slice('\t '.length);
        } else {
            try {
                const nlu_result = await Tp.Helpers.Http.post(NLU_SERVER, JSON.stringify({ q: line }), {
                    dataContentType: 'application/json'
                });
                const parsed = JSON.parse(nlu_result);
                if (parsed && parsed.candidates && parsed.candidates.length > 0) 
                    thingtalk = parsed.candidates[0].code.join(' ');
            } catch (e) {
                console.log(e.message);
            }
        }

        if (!thingtalk) {
            console.log('Failed to parse the question. \n');
            rl.prompt();
            return;
        }
        
        console.log('ThingTalk:', thingtalk);
        try {
            const sparql = await converter.convert(line, thingtalk);
            console.log('SPARQL:', sparql);
            try {
                const answers = await wikidata.query(sparql);
                console.log('Answers:');
                if (answers.length === 0) {
                    console.log('None')
                } else {
                    for (const answer of answers.slice(0, 5)) {
                        if (answer.startsWith('Q')) {
                            const label = await wikidata.getLabel(answer);
                            console.log(`${label} (${answer})`)
                        } else {
                            console.log(answer);
                        }
                    } 
                    if (answers.length > 5)
                        console.log(`and ${answers.length - 5} more ...`)
                }
            } catch (e) {
                console.log('Failed to retrieve answers from Wikidata.')
                console.log(e.message);
            }
        } catch (e) {
            console.log('Failed to convert thingtalk into SPARQL');
        }

        console.log('\n');
        rl.prompt();
    });

    function quit() {
        rl.close();
    }
    rl.on('SIGINT', quit);
}

main();