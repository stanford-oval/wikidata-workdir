"use strict";

const Tp = require('thingpedia');
const ThingTalk = require('thingtalk');
const QALD = require('qald');

module.exports = class WikidataDevice extends Tp.BaseDevice {
    constructor(engine, state) {
        super(engine, state);
        this.name = "Wikidata";
        this.description = "Question answering on wikdiata";
        this.url = 'https://query.wikidata.org/sparql';
        this.wikidata = new QALD.WikidataUtils('./cache.sqlite', 'bootleg.sqlite', true);
    }

    async _request(sparql) {
        console.log('====');
        console.log('SPARQL query:')
        console.log(sparql);
        console.log('====');
        return Tp.Helpers.Http.get(`${this.url}?query=${encodeURIComponent(sparql)}`, {
            accept: 'application/json'
        }).then((result) => {
            const parsed = JSON.parse(result).results.bindings;
            console.log('Raw result from Wikidata:')
            console.log(parsed);
            const preprocessed = parsed.map((r) => {
                const res = {};
                Object.keys(r).filter((key) => !key.endsWith('Label')).forEach((key) => {
                    let value = r[key].value;
                    if (value.startsWith('http://www.wikidata.org/entity/')) {
                        let id = value.slice('http://www.wikidata.org/entity/'.length);
                        value = r[key + 'Label'] ? r[key + 'Label'].value : null;
                        res[key] = { value: id, display: value };
                    } else {
                        res[key] = value;
                    }
                });
                return res;
            });
            return groupResultById(preprocessed);
        });
    }

    async query(query) {
        return ["LOL"];
    }
};