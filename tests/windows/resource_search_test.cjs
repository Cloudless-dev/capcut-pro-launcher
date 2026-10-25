const assert=require('node:assert/strict');
const {resourceSearchURL,normalizeResourceSearchBody:normalize}=require('../../scripts/runtime/resource_search.js');
const body='{"query":"%D0%B2%D0%B7%D1%80%D1%8B%D0%B2","id":18446744073709551615,"other":"%D0%B0"}';
assert.equal(normalize(body),'{"query":"взрыв","id":18446744073709551615,"other":"%D0%B0"}');
for(const body of ['{"query":"explosion%20fx"}','{"query":"взрыв"}','{"query":"%ZZ"}','not JSON'])assert.equal(normalize(body),body);
assert.equal(resourceSearchURL('https://api.capcutapi.com/artist/v1/effect/search/'),true);
for(const url of ['https://example.org/artist/v1/effect/search/','https://api.capcutapi.com/passport/search/','https://api.capcutapi.com/artist/v1/effect/search/?signature=abc'])assert.equal(resourceSearchURL(url),false);
console.log('PASS Cyrillic normalization, 64-bit ID preservation, malformed input, endpoint and signed URL exclusions');
